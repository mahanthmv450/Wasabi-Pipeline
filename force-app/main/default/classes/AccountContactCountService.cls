public with sharing class AccountContactCountService {

    public static Map<Id, Integer> countContacts(Set<Id> accountIds) {
        Map<Id, Integer> countByAccount = new Map<Id, Integer>();
        if (accountIds == null || accountIds.isEmpty()) {
            return countByAccount;
        }
        for (Id accountId : accountIds) {
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