/**
 * Example service that normalizes Contact emails (trim + lowercase)
 * and reports the email domain.
 */
public with sharing class ContactEmailService {

    /**
     * Returns the email trimmed and lowercased, or null if blank.
     */
    public static String normalize(String email) {
        if (String.isBlank(email)) {
            return null;
        }
        return email.trim().toLowerCase();
    }

    /**
     * Returns the lowercase domain part of an email, or null if there is none.
     */
    public static String getDomain(String email) {
        String normalized = normalize(email);
        if (normalized == null || !normalized.contains('@')) {
            return null;
        }
        String domain = normalized.substringAfterLast('@');
        return String.isBlank(domain) ? null : domain;
    }

    /**
     * Normalizes Email on each Contact in memory (no DML).
     * Returns the Contacts whose Email actually changed.
     */
    public static List<Contact> applyNormalization(List<Contact> contacts) {
        List<Contact> changed = new List<Contact>();
        if (contacts == null || contacts.isEmpty()) {
            return changed;
        }
        for (Contact c : contacts) {
            String normalized = normalize(c.Email);
            // Apex '!=' on Strings is case-insensitive; equals() is case-sensitive.
            if (!String.valueOf(normalized).equals(String.valueOf(c.Email))) {
                c.Email = normalized;
                changed.add(c);
            }
        }
        return changed;
    }

    /**
     * Queries the given Contacts, normalizes their emails and saves only
     * the ones that changed. Returns the number of Contacts updated.
     */
    public static Integer normalizeAndSave(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            throw new ContactEmailException('contactIds must not be empty.');
        }
        List<Contact> contacts = [
            SELECT Id, Email
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ];
        List<Contact> changed = applyNormalization(contacts);
        if (!changed.isEmpty()) {
            update as user changed;
        }
        return changed.size();
    }

    public class ContactEmailException extends Exception {}
}
