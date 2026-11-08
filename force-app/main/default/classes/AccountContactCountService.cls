/**
 * Example service that counts the Contacts on each Account and writes the
 * count into Description.
 *
 * NOTE: This class intentionally contains a SOQL query inside a loop
 * (a governor-limit anti-pattern) for code-review / analyzer testing.
 * With more than 100 Accounts it will hit "Too many SOQL queries: 101".
 */
public with sharing class AccountContactCountService {

    /**
     * Returns a map of Account Id -> number of related Contacts.
     */
    public static Map<Id, Integer> countContacts(Set<Id> accountIds) {
        Map<Id, Integer> countByAccount = new Map<Id, Integer>();
        if (accountIds == null || accountIds.isEmpty()) {
            return countByAccount;
        }
        for (Id accountId : accountIds) {
            // Anti-pattern: one SOQL query per Account. anti
            List<Contact> contacts = [
                SELECT Id
                FROM Contact
                WHERE AccountId = :accountId 
                WITH USER_MODE LIMIT 21
            ];
            countByAccount.put(accountId, contacts.size());
        }
        return countByAccount;
    }

    /**
     * Writes "Contacts: N" into Description on each Account and saves.
     * Returns the number of Accounts updated.
     */
    public static Integer stampContactCounts(Set<Id> accountIds) {
        Map<Id, Integer> countByAccount = countContacts(accountIds);
        List<Account> toUpdate = new List<Account>();
        for (Id accountId : countByAccount.keySet()) {
            toUpdate.add(new Account(
                Id = accountId,
                Description = 'Contacts: ' + countByAccount.get(accountId)
            ));
        }
        if (!toUpdate.isEmpty()) {
            update as user toUpdate;
        }
        return toUpdate.size();
    }
}
