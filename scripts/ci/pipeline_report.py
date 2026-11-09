#!/usr/bin/env python3
"""
Builds the Salesforce pipeline report used by .github/workflows/pipeline.yml.

  python3 scripts/ci/pipeline_report.py analyze   -> writes pipeline-report/failure.md (on failure)
                                                     and prints a readable summary to the log
  python3 scripts/ci/pipeline_report.py comment   -> writes pipeline-report/comment.md
                                                     (includes Claude's suggestions if present)

Inputs come from environment variables set by the workflow (see pipeline.yml).
Standard library only.
"""

import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPORT_DIR = Path("pipeline-report")
PACKAGE_XML = Path("delta/package/package.xml")
DESTRUCTIVE_XML = Path("delta/destructiveChanges/destructiveChanges.xml")
DEPLOY_JSON = REPORT_DIR / "deploy-result.json"
FAILURE_MD = REPORT_DIR / "failure.md"
CLAUDE_MD = REPORT_DIR / "claude-suggestions.md"
COMMENT_MD = REPORT_DIR / "comment.md"
SOURCE_DIR = Path("force-app")

MARKER = "<!-- sf-pipeline-report -->"
NS = {"sf": "http://soap.sforce.com/2006/04/metadata"}
MAX_COMMENT_CHARS = 60000  # GitHub hard limit is 65536

# Configuration / security metadata left out of the component list.
# Edit this set to show or hide types.
CONFIG_TYPES = {
    "Profile", "ProfilePasswordPolicy", "ProfileSessionSetting",
    "PermissionSet", "PermissionSetGroup", "MutingPermissionSet",
    "Settings", "SharingRules", "SharingCriteriaRule", "SharingOwnerRule",
    "SharingGuestRule", "SharingTerritoryRule", "Role", "Group", "Queue",
    "CustomObjectTranslation", "Translations", "StandardValueSetTranslation",
    "GlobalValueSetTranslation", "AppMenu", "IframeWhiteListUrlSettings",
    "TopicsForObjects",
}

# Display name and sort order (code first, then data model, then the rest A-Z)
TYPE_LABELS = {
    "ApexClass": "Apex Classes",
    "ApexTrigger": "Apex Triggers",
    "LightningComponentBundle": "Lightning Web Components",
    "AuraDefinitionBundle": "Aura Components",
    "ApexPage": "Visualforce Pages",
    "ApexComponent": "Visualforce Components",
    "Flow": "Flows",
    "CustomObject": "Custom Objects",
    "CustomField": "Custom Fields",
    "ValidationRule": "Validation Rules",
    "RecordType": "Record Types",
    "BusinessProcess": "Business Processes",
    "ListView": "List Views",
    "WebLink": "Buttons & Links",
    "CompactLayout": "Compact Layouts",
    "FieldSet": "Field Sets",
    "Layout": "Page Layouts",
    "FlexiPage": "Lightning Pages",
    "QuickAction": "Quick Actions",
    "CustomTab": "Tabs",
    "CustomApplication": "Apps",
    "CustomLabels": "Custom Labels",
    "CustomLabel": "Custom Labels",
    "CustomMetadata": "Custom Metadata Records",
    "StaticResource": "Static Resources",
    "EmailTemplate": "Email Templates",
    "Report": "Reports",
    "ReportType": "Report Types",
    "Dashboard": "Dashboards",
    "PlatformEventChannel": "Platform Event Channels",
    "NamedCredential": "Named Credentials",
    "ExternalCredential": "External Credentials",
    "RemoteSiteSetting": "Remote Site Settings",
    "GlobalValueSet": "Global Value Sets",
    "StandardValueSet": "Standard Value Sets",
    "DuplicateRule": "Duplicate Rules",
    "MatchingRules": "Matching Rules",
    "AssignmentRules": "Assignment Rules",
    "AutoResponseRules": "Auto-Response Rules",
    "EscalationRules": "Escalation Rules",
    "PathAssistant": "Path Assistants",
}
TYPE_ORDER = list(TYPE_LABELS)

# Source file location per type, used to link components to the commit
SOURCE_PATTERNS = {
    "ApexClass": "**/classes/{name}.cls",
    "ApexTrigger": "**/triggers/{name}.trigger",
    "LightningComponentBundle": "**/lwc/{name}",
    "AuraDefinitionBundle": "**/aura/{name}",
    "ApexPage": "**/pages/{name}.page",
    "ApexComponent": "**/components/{name}.component",
    "Flow": "**/flows/{name}.flow-meta.xml",
    "CustomObject": "**/objects/{name}/{name}.object-meta.xml",
    "FlexiPage": "**/flexipages/{name}.flexipage-meta.xml",
}

OPERATION_STEPS = [
    ("checkout", "Checkout"),
    ("install_cli", "Install Salesforce CLI"),
    ("install_sgd", "Install sfdx-git-delta"),
    ("auth", "Authenticate to Salesforce"),
    ("delta_range", "Determine Delta Range"),
    ("delta", "Generate Delta Package"),
    ("build_args", "Build Deploy Arguments"),
    ("sfdeploy", "Validate / Deploy"),
]

STEP_HINTS = {
    "auth": "Check that the `SALESFORCE_AUTH_URL_{env}` secret exists and holds a current "
            "SFDX auth URL (`sf org display --verbose --target-org <alias>`). Refresh it after "
            "a sandbox refresh or password/token reset.",
    "delta_range": "The previous commit could not be resolved. Re-run the job; if it was a "
                   "force-push, push a normal commit on top.",
    "delta": "sfdx-git-delta could not build the package. Check `sfdx-project.json` and that the "
             "changed files are valid source-format metadata.",
    "install_cli": "npm could not install the Salesforce CLI. Usually transient: re-run the job, "
                   "or check that `SF_CLI_VERSION` exists on npm.",
    "install_sgd": "The sfdx-git-delta plugin failed to install. Re-run, or check that "
                   "`SGD_VERSION` exists on npm.",
}


# ----------------------------------------------------------------- helpers
def env(name, default=""):
    return os.environ.get(name, default) or default


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def label_for(type_name):
    if type_name in TYPE_LABELS:
        return TYPE_LABELS[type_name]
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", type_name)


def sort_key(type_name):
    try:
        return (0, TYPE_ORDER.index(type_name), "")
    except ValueError:
        return (1, 0, label_for(type_name))


def md_escape(text):
    text = str(text if text is not None else "")
    return text.replace("|", "\\|").replace("\r", "").replace("\n", "<br>")


def truncate(text, limit):
    text = str(text or "")
    return text if len(text) <= limit else text[: limit - 1] + "…"


def parse_manifest(path):
    """Return {type: [members]} from a package.xml, or {} if missing/empty."""
    if not path.is_file():
        return {}
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError:
        return {}
    result = {}
    for types in root.findall("sf:types", NS):
        name = types.findtext("sf:name", default="", namespaces=NS)
        members = [m.text for m in types.findall("sf:members", NS) if m.text]
        if name and members:
            result.setdefault(name, []).extend(members)
    return result


def split_config(manifest):
    components, config_counts = {}, {}
    for type_name, members in manifest.items():
        if type_name in CONFIG_TYPES:
            config_counts[type_name] = len(members)
        else:
            components[type_name] = sorted(set(members))
    return components, config_counts


def find_source(type_name, member):
    pattern = SOURCE_PATTERNS.get(type_name)
    if not pattern or not SOURCE_DIR.is_dir():
        return None
    matches = sorted(SOURCE_DIR.glob(pattern.format(name=member)))
    return matches[0] if matches else None


def is_test_class(path):
    try:
        return bool(re.search(r"@\s*isTest", path.read_text(errors="ignore"), re.I))
    except OSError:
        return False


def load_deploy_json():
    if not DEPLOY_JSON.is_file():
        return None
    raw = DEPLOY_JSON.read_text(errors="ignore")
    start = raw.find("{")
    if start < 0:
        return {"_raw": raw.strip()}
    try:
        return json.loads(raw[start:])
    except json.JSONDecodeError:
        return {"_raw": raw.strip()}


def deploy_result(payload):
    """The DeployResult object, wherever the CLI put it."""
    if not isinstance(payload, dict):
        return {}
    for key in ("result", "data"):
        value = payload.get(key)
        if isinstance(value, dict) and ("details" in value or "status" in value):
            return value
    return {}


def failed_step():
    """First workflow step whose outcome is failure, as (id, label)."""
    for step_id, label in OPERATION_STEPS:
        if env(f"OUTCOME_{step_id.upper()}") == "failure":
            return step_id, label
    if env("DEPLOY_EXIT_CODE", "0") not in ("", "0"):
        return "sfdeploy", "Validate / Deploy"
    return None


# ----------------------------------------------------------- failure model
def collect_failures():
    payload = load_deploy_json()
    result = deploy_result(payload)
    details = result.get("details") or {}
    tests = details.get("runTestResult") or {}

    component_failures = [
        f for f in as_list(details.get("componentFailures"))
        if isinstance(f, dict)
    ]
    test_failures = [f for f in as_list(tests.get("failures")) if isinstance(f, dict)]
    coverage_warnings = [
        w for w in as_list(tests.get("codeCoverageWarnings")) if isinstance(w, dict)
    ]

    cli_error = ""
    if isinstance(payload, dict):
        if payload.get("_raw"):
            cli_error = payload["_raw"]
        elif payload.get("status", 0) != 0 and not result:
            cli_error = f"{payload.get('name', 'Error')}: {payload.get('message', '')}".strip()
        elif result.get("errorMessage"):
            cli_error = result["errorMessage"]

    return {
        "result": result,
        "component_failures": component_failures,
        "test_failures": test_failures,
        "coverage_warnings": coverage_warnings,
        "cli_error": cli_error,
    }


def failure_markdown(f, step):
    """Failure section (shared by the PR comment and Claude's input)."""
    lines = []
    step_id, step_label = step

    if step_id != "sfdeploy":
        lines.append(f"The **{step_label}** step failed before anything was sent to Salesforce.")
        hint = STEP_HINTS.get(step_id)
        if hint:
            lines += ["", f"**How to fix:** {hint.format(env=env('ENV_NAME', '<ENV>'))}"]
        lines += ["", f"See the [job log]({env('RUN_URL')}) for the full error."]
        return "\n".join(lines)

    if f["cli_error"]:
        lines += ["**Salesforce CLI error**", "", "```", truncate(f["cli_error"], 3000), "```", ""]

    if f["component_failures"]:
        lines += [f"**Component errors ({len(f['component_failures'])})**", "",
                  "| Type | Component | File | Line | Problem |",
                  "|---|---|---|---|---|"]
        for c in f["component_failures"][:50]:
            line = c.get("lineNumber") or ""
            col = c.get("columnNumber")
            if line and col:
                line = f"{line}:{col}"
            lines.append("| {} | `{}` | {} | {} | {} |".format(
                md_escape(c.get("componentType", "")),
                md_escape(c.get("fullName", "")),
                md_escape(c.get("fileName", "")),
                md_escape(line),
                md_escape(truncate(c.get("problem", ""), 500)),
            ))
        if len(f["component_failures"]) > 50:
            lines.append(f"\n_…and {len(f['component_failures']) - 50} more._")
        lines.append("")

    if f["test_failures"]:
        lines += [f"**Apex test failures ({len(f['test_failures'])})**", "",
                  "| Test class | Method | Message |", "|---|---|---|"]
        for t in f["test_failures"][:30]:
            lines.append("| `{}` | `{}` | {} |".format(
                md_escape(t.get("name", "")),
                md_escape(t.get("methodName", "")),
                md_escape(truncate(t.get("message", ""), 500)),
            ))
        traces = [t for t in f["test_failures"][:30] if t.get("stackTrace")]
        if traces:
            lines += ["", "<details><summary>Stack traces</summary>", ""]
            for t in traces:
                lines += [f"`{t.get('name')}.{t.get('methodName')}`", "```",
                          truncate(t.get("stackTrace"), 1500), "```"]
            lines += ["</details>"]
        lines.append("")

    if f["coverage_warnings"]:
        lines += ["**Code coverage warnings**", ""]
        for w in f["coverage_warnings"]:
            name = w.get("name")
            prefix = f"`{name}`: " if isinstance(name, str) and name else ""
            lines.append(f"- {prefix}{md_escape(w.get('message', ''))}")
        lines.append("")

    if not lines:
        status = f["result"].get("status") or "Failed"
        lines.append(f"Salesforce reported status **{status}** without component or test "
                     f"details. See the [job log]({env('RUN_URL')}).")
    return "\n".join(lines).rstrip()


# ------------------------------------------------------------ components
def components_markdown(components, destructive, config_counts):
    repo, sha = env("REPO"), env("HEAD_SHA")
    lines = []

    def table(manifest):
        out = []
        for type_name in sorted(manifest, key=sort_key):
            members = manifest[type_name]
            out += [f"<details open><summary><b>{label_for(type_name)}</b> ({len(members)})</summary>", "",
                    "| Component | Notes |", "|---|---|"]
            for m in members:
                path = find_source(type_name, m)
                name = f"`{m}`"
                if path and repo and sha:
                    name = f"[`{m}`](https://github.com/{repo}/blob/{sha}/{path.as_posix()})"
                note = ""
                if type_name == "ApexClass" and path and is_test_class(path):
                    note = "🧪 Test class"
                out.append(f"| {name} | {note} |")
            out += ["", "</details>", ""]
        return out

    total = sum(len(v) for v in components.values())
    lines += [f"### 📦 Components in this change ({total})", ""]
    if components:
        lines += table(components)
    else:
        lines += ["_No code or functional components changed._", ""]

    if destructive:
        dtotal = sum(len(v) for v in destructive.values())
        lines += [f"### 🗑️ Components to be deleted ({dtotal})", ""]
        lines += table(destructive)

    if config_counts:
        summary = ", ".join(f"{label_for(t)}: {n}" for t, n in sorted(config_counts.items()))
        lines += [f"<sub>Configuration metadata not listed above: {summary}.</sub>", ""]
    return "\n".join(lines).rstrip()


# --------------------------------------------------------------- commands
def cmd_analyze():
    REPORT_DIR.mkdir(exist_ok=True)
    step = failed_step()
    f = collect_failures()

    r = f["result"]
    if r:
        print("====== Salesforce result ======")
        print(f"Status:      {r.get('status')}")
        print(f"Components:  {r.get('numberComponentsDeployed', 0)} deployed, "
              f"{r.get('numberComponentErrors', 0)} errors")
        print(f"Apex tests:  {r.get('numberTestsCompleted', 0)} passed, "
              f"{r.get('numberTestErrors', 0)} failed")

    if step:
        FAILURE_MD.write_text(
            f"# Pipeline failure ({env('OPERATION')} → {env('ENV_NAME')})\n\n"
            + failure_markdown(f, step) + "\n"
        )
        print("\n====== Failure ======")
        print(FAILURE_MD.read_text())
    elif FAILURE_MD.exists():
        FAILURE_MD.unlink()


def cmd_comment():
    REPORT_DIR.mkdir(exist_ok=True)
    operation = env("OPERATION", "Deploy")          # Validate | Deploy
    env_name = env("ENV_NAME", "?")
    step = failed_step()
    f = collect_failures()
    r = f["result"]

    components, config_counts = split_config(parse_manifest(PACKAGE_XML))
    destructive, _ = split_config(parse_manifest(DESTRUCTIVE_XML))
    no_changes = env("HAS_CHANGES") != "true" and env("HAS_DESTRUCTIVE") != "true"

    past = "Validation" if operation == "Validate" else "Deployment"
    if step:
        title = f"## ❌ {past} failed → {env_name}"
        status = "❌ **Failed**" + (f" at step _{step[1]}_" if step[0] != "sfdeploy" else "")
    elif no_changes and env("OUTCOME_DELTA") == "success":
        title = f"## ⏭️ {past} skipped → {env_name}"
        status = "⏭️ **Skipped**: no Salesforce metadata changes"
    else:
        title = f"## ✅ {past} succeeded → {env_name}"
        status = "✅ **Succeeded**"

    sha = env("HEAD_SHA")
    from_sha = env("FROM_SHA")
    def branch(name):
        return f"`{md_escape(name.replace('`', ''))}`"

    target_branch = env("TARGET_BRANCH")
    source_branch = env("SOURCE_BRANCH")
    if source_branch and target_branch:
        branches = f"{branch(source_branch)} → {branch(target_branch)}"
    elif target_branch:
        branches = branch(target_branch)
    else:
        branches = "-"

    rows = [
        ("Status", status),
        ("Branch", branches),
        ("Target org", f"`{env_name}`"),
        ("Operation", "Validate (check-only, nothing saved)" if operation == "Validate" else "Deploy"),
        ("Test level", f"`{env('TEST_LEVEL_USED', '-')}`"),
        ("Commit", f"`{sha[:7]}`" + (f" (delta from `{from_sha[:7]}`)" if from_sha else "")),
    ]
    if r:
        rows.append(("Components", f"{r.get('numberComponentsDeployed', 0)} deployed · "
                                   f"{r.get('numberComponentErrors', 0)} errors"))
        if r.get("numberTestsTotal"):
            rows.append(("Apex tests", f"{r.get('numberTestsCompleted', 0)} passed · "
                                       f"{r.get('numberTestErrors', 0)} failed · "
                                       f"{r.get('numberTestsTotal', 0)} total"))
        if r.get("id"):
            rows.append(("Deploy ID", f"`{r['id']}`"))
    rows.append(("Run", f"[View job log]({env('RUN_URL')})"))

    parts = [MARKER, title, "", "| | |", "|---|---|"]
    parts += [f"| **{k}** | {v} |" for k, v in rows]
    parts += [""]

    if env("OUTCOME_DELTA") == "success":
        parts += [components_markdown(components, destructive, config_counts), ""]

    if step:
        parts += ["### 🔍 Why it failed", "", failure_markdown(f, step), ""]
        if CLAUDE_MD.is_file() and CLAUDE_MD.read_text().strip():
            parts += ["### 🤖 Suggested fix (Claude)", "",
                      CLAUDE_MD.read_text().strip(), "",
                      "<sub>AI-generated suggestions. Review before applying.</sub>", ""]
        elif step[0] == "sfdeploy":
            parts += ["<sub>Claude fix suggestions unavailable for this run "
                      "(check the `CLAUDE_CODE_OAUTH_TOKEN` secret and the Claude step log).</sub>", ""]

    body = "\n".join(parts).rstrip() + "\n"
    if len(body) > MAX_COMMENT_CHARS:
        body = body[:MAX_COMMENT_CHARS] + f"\n\n_…truncated. See the [job log]({env('RUN_URL')})._\n"
    COMMENT_MD.write_text(body)
    print(body)


if __name__ == "__main__":
    commands = {"analyze": cmd_analyze, "comment": cmd_comment}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(f"usage: {sys.argv[0]} {{{'|'.join(commands)}}}")
    commands[sys.argv[1]]()
