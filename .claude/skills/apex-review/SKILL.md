---
name: apex-review
description: Pre-pull-request code review for Salesforce Apex classes and triggers in this repo. Reviews the Apex changed on the current branch against develop (or specific files/classes passed as arguments) for governor-limit problems, bulkification, security (sharing, CRUD/FLS, SOQL injection), correctness bugs, hardcoded IDs, and test-class quality, runs Salesforce Code Analyzer, optionally runs the related Apex tests in an org, and writes/maintains a per-class Markdown result file in __review_results__/ with risks, test classes and coverage, test gaps, and an overall score. Use whenever the user wants to review, check, lint, or sanity-check Apex before opening or updating a PR, even if they just say "review my classes" or "is this ready for a PR?".
argument-hint: "[ClassName | path ...] [--all] [--base <branch>] [--run-tests <org-alias>] [--fix]"
---

# Apex pre-PR review

Review Apex before it goes to a pull request (`feature/*` → `develop`). The goal is to catch what the CI
Claude review and the deploy pipeline would catch, earlier, plus anything that would fail deployment or tests.
Report real problems; skip style nits (Prettier with `prettier-plugin-apex` already handles formatting on commit).

## 1. Work out what to review

Parse the arguments:

- **Class names or paths given** → review exactly those (resolve a bare name like `AccountSizeService` to
  `force-app/main/default/classes/AccountSizeService.cls`; include its `-meta.xml`).
- **`--all`** → every `.cls` and `.trigger` under `force-app/`.
- **Nothing given** → the Apex changed on this branch versus the base branch (default `develop`, override with
  `--base`):

  ```bash
  git fetch origin develop --quiet 2>/dev/null
  BASE=$(git merge-base HEAD origin/develop 2>/dev/null || git merge-base HEAD develop)
  { git diff --name-only "$BASE"...HEAD; git diff --name-only; git diff --name-only --cached; git ls-files --others --exclude-standard; } \
    | sort -u | grep -E '\.(cls|trigger)$' | grep '^force-app/'
  ```

  This includes committed, staged, unstaged and untracked work. If the list is empty, say so and stop.

Never review anything under `.sfdx/` (generated stubs).

For each file in scope, also pull in its partner: a class's test (`<Name>Test.cls`, or any test that references
it — `grep -l "<Name>" force-app/**/classes/*Test.cls`) and, for a test class, the class under test. Read the
whole file, not just the diff, but focus findings on changed lines (`git diff "$BASE"...HEAD -- <file>`) unless
the user asked for `--all` or named files.

## 2. Run static analysis

Run Salesforce Code Analyzer on the files in scope (it is installed as `sf code-analyzer`):

```bash
sf code-analyzer run --rule-selector "Recommended:Apex" --rule-selector "Security:Apex" \
  --target <file1> --target <file2> ... \
  --output-file "$SCRATCH/apex-analyzer.json"
```

Write the output to the session scratchpad directory, not the repo. If the command fails or isn't available,
note it in the report and continue with the manual review — don't block on it. Treat analyzer hits as leads:
confirm each one by reading the code, and drop ones that are false positives or pure style.

## 3. Manual review checklist

Go through every file in scope against this list. A finding needs a concrete failure scenario (what input or
org state breaks, and how); if you can't describe one, leave it out.

### Governor limits & bulkification
- SOQL, SOSL or DML inside a loop (including inside methods called from a loop).
- Logic that assumes a single record (`Trigger.new[0]`, `records[0]` with no size check, `LIMIT 1` used to
  fetch "the" related record per parent).
- Queries without selective filters on large objects, or queries that could return >50,000 rows.
- Collections built in loops that should be `Map<Id, SObject>` / `Set<Id>` lookups (nested loops = CPU risk).
- Callouts after uncommitted DML; callouts from triggers without `@future(callout=true)` / Queueable.
- Async chaining or `@future` called from contexts where it can't run (batch, future, >50 enqueues).

### Security
- Class missing an explicit sharing keyword (`with sharing`, `without sharing`, `inherited sharing`).
  `without sharing` needs a comment justifying it.
- `@AuraEnabled`, `@RestResource`, `@InvocableMethod` or `global` entry points without CRUD/FLS enforcement
  (`WITH USER_MODE`, `AccessLevel.USER_MODE`, `Security.stripInaccessible`, or explicit describe checks).
- Dynamic SOQL built by string concatenation of user input → SOQL injection. Expect bind variables,
  `Database.queryWithBinds`, or `String.escapeSingleQuotes`.
- Secrets, tokens, passwords or endpoints in code instead of Named Credentials / custom metadata.

### Correctness
- Null dereferences: map `.get()` results, query results assigned to a single SObject (throws on 0 rows),
  relationship fields not queried, `Trigger.oldMap` in insert context.
- Fields used but not in the SELECT (runtime `SObjectException`).
- Wrong trigger context handling (before vs after, recursion with no guard, update logic firing on unchanged
  fields — compare with `Trigger.oldMap`).
- Swallowed exceptions (`catch (Exception e) {}` or catch-and-`System.debug`) that hide failures.
- Partial-success DML (`Database.insert(list, false)`) whose `SaveResult` errors are ignored.
- Hardcoded record IDs, Record Type IDs, profile/user names or org URLs — use `Schema` describes,
  `DeveloperName` lookups or custom metadata.
- String comparisons that should be case-insensitive, Decimal/Integer division surprises, date/time zone bugs.

### Test classes
- `@isTest(SeeAllData=true)` — flag it.
- Tests with no assertions, or only `System.assert(true)` / asserting what was just set. Prefer the
  `Assert` class (`Assert.areEqual`, etc.) with a message.
- No bulk test (≥200 records through a trigger/service), no negative/exception path test, no test for
  restricted-user behaviour (`System.runAs`) when the code enforces sharing/FLS.
- Missing `Test.startTest()` / `Test.stopTest()` around async code, or callouts with no `HttpCalloutMock`.
- Test data created inline everywhere instead of in `@TestSetup` / a factory (mention once, not per test).
- Every new non-test class should have a test class; coverage under 75% fails deploy.

### Metadata
- `-meta.xml` missing for a new class, or `apiVersion` different from `sourceApiVersion` in
  `sfdx-project.json` (currently 68.0) without a reason.
- Class name and file name must match.

## 4. Optional: run the tests

Only when the user passes `--run-tests <org-alias>` (or asks), run the test classes related to the files in
scope against that org. This deploys nothing; it runs tests already in the org, so first tell the user the
org must have the current code deployed, or offer a check-only deploy instead:

```bash
# Check-only deploy of the changed source, running only the related tests
sf project deploy validate --source-dir <file1> --source-dir <file2> ... \
  --test-level RunSpecifiedTests --tests <TestClass1> --tests <TestClass2> \
  --target-org <org-alias> --wait 30 --json
```

Confirm the target org with the user before running if it looks like production. Report failures with the
test method, message and stack trace line, and per-class coverage from the result.

## 5. Report

Lead with a one-line verdict: **Ready for PR**, **Ready after minor fixes**, or **Not ready**.

Then list findings, most severe first, grouped by severity:

- **Blocker** — will fail deploy/tests, data-loss/security hole, or governor-limit failure under normal volume.
- **Should fix** — real bug or risk under realistic conditions.
- **Consider** — worthwhile improvement with a concrete benefit (keep these few).

Each finding: `[File.cls:line](force-app/main/default/classes/File.cls#Lline)` — what's wrong, the concrete
failure scenario, and the fix (a short code snippet when it helps). Then a short line on Code Analyzer
results (how many hits, how many confirmed) and test results if run.

If nothing survives verification, say it's ready and mention what you checked — don't invent findings.

End the chat report with a list of the result files written or updated (step 6), as clickable links.

## 6. Result files (`__review_results__/`)

Keep one Markdown result file per reviewed class or trigger at `__review_results__/<Name>.md` in the repo root
(e.g. `__review_results__/AccountSizeService.md`). Create the folder if it doesn't exist. Test classes don't get
their own file — they're covered inside the file for the class they test. A test class reviewed on its own
(its class under test isn't in scope) updates the class-under-test's file.

**Maintain, don't overwrite blindly.** If the file already exists, read it first, then:
- Replace the "Current review" sections with this review's results.
- Mark findings from the previous review that are now gone as **Resolved** in the Findings table (keep them,
  with the date resolved) rather than deleting them; carry still-present findings forward with their original
  "first seen" date.
- Prepend one row to the Review history table. Never delete history rows.
- If the class was deleted from `force-app`, keep the file and add a note at the top: `> Class removed on <date>`.

### Scoring

Score the class out of 100, starting at 100 and deducting per open finding and gap:

| Item | Deduction |
|---|---|
| Blocker finding | −20 each |
| Should-fix finding | −8 each |
| Consider finding | −2 each (max −10 total) |
| No test class | −30 |
| Coverage < 75% (measured) | −20 · 75–89% −8 · ≥ 90% −0 |
| Coverage unmeasured | −0, but state the estimate is unverified |
| No bulk test / no negative-path test / no `runAs` test where sharing/FLS is enforced | −5 each |

Floor at 0. Grade: **A** 90–100 · **B** 75–89 · **C** 60–74 · **D** 40–59 · **F** < 40. Any open Blocker
caps the grade at **D** regardless of points.

### Coverage

Use measured coverage when tests were run this review (`--run-tests`), and say which org and when. Otherwise,
keep the last measured figure from the existing file if the class hasn't changed since (check
`git log -1 --format=%cs -- <file>` against that date); if it has changed, or nothing was ever measured, give an
**estimate** from reading which methods and branches the tests exercise, clearly labelled "Estimated (not run)".

### File template

```markdown
# <ClassName> — Review Results

| | |
|---|---|
| **Score** | 78 / 100 (B) |
| **Verdict** | Ready after minor fixes |
| **Last reviewed** | 2026-11-08 on branch `feature/xyz` @ `<short-sha>` |
| **File** | [force-app/main/default/classes/<ClassName>.cls](../force-app/main/default/classes/<ClassName>.cls) |
| **Sharing** | with sharing |
| **API version** | 68.0 |

## Summary
Two or three sentences: what the class does and the overall state of its quality.

## Risks
Open findings, most severe first. One subsection per finding:

### 🔴 Blocker — SOQL inside loop (line 42)
- **What:** ...
- **Failure scenario:** ...
- **Fix:** ... (short snippet if useful)
- **First seen:** 2026-11-08

(🔴 Blocker · 🟠 Should fix · 🔵 Consider. Write "No open risks." if there are none.)

## Test classes & coverage
| Test class | Methods | Bulk test | Negative test | runAs | Assertions quality |
|---|---|---|---|---|---|
| <ClassName>Test | 4 | ✅ | ❌ | n/a | Good — uses Assert.areEqual with messages |

**Coverage:** 82% — measured in `<org-alias>` on 2026-11-08  *(or: ~70% — Estimated (not run))*

## Misses
What the tests don't cover — the specific gaps, each tied to code:
- `calculateSize()` branch where `NumberOfEmployees` is null (line 31) is never exercised.
- No test asserts the exception path in `updateAccounts()` (line 55).
- No test with 200+ records through the trigger.

## Static analysis
Code Analyzer: N hits, M confirmed (confirmed ones are listed under Risks), rest dismissed as false positives/style.

## Findings log
| # | Severity | Finding | Line | First seen | Status |
|---|---|---|---|---|---|
| 1 | Blocker | SOQL inside loop | 42 | 2026-11-08 | Open |
| 2 | Should fix | Missing null check on map get | 18 | 2026-11-01 | Resolved 2026-11-08 |

## Review history
| Date | Branch @ commit | Score | Grade | Coverage | Blockers / Should fix / Consider |
|---|---|---|---|---|---|
| 2026-11-08 | feature/xyz @ abc1234 | 78 | B | 82% (measured) | 0 / 2 / 1 |
```

Keep line references current — line numbers in Risks and Misses must match the file as reviewed today.
Write result files even when the verdict is "Ready for PR" (score, coverage and history still matter).

## 7. Fixing

If the user passed `--fix`, or says yes when you offer, apply fixes for Blocker and Should-fix findings,
then re-run Code Analyzer on the touched files and update each affected result file: mark fixed findings
Resolved, recompute the score, and add a history row noting "after --fix". Don't commit or push — the user
does that when they open the PR (the `__review_results__/` files go in with it). Don't refactor beyond the
findings.
