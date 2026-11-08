@IsTest
private class AccountContactCountServiceTest {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Three Contacts'),
            new Account(Name = 'No Contacts'),
            new Account(Name = 'Many Contacts')
        };
        insert accounts;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 3; i++) {
            contacts.add(new Contact(LastName = 'Three ' + i, AccountId = accounts[0].Id));
        }
        for (Integer i = 0; i < 25; i++) {
            contacts.add(new Contact(LastName = 'Many ' + i, AccountId = accounts[2].Id));
        }
        insert contacts;
    }

    private static Map<String, Id> idsByName() {
        Map<String, Id> result = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account]) {
            result.put(a.Name, a.Id);
        }
        return result;
    }

    @IsTest
    static void countContacts_returnsEmptyForNull() {
        Map<Id, Integer> result = AccountContactCountService.countContacts(null);
        Assert.isTrue(result.isEmpty(), 'Null input should return an empty map');
    }

    @IsTest
    static void countContacts_returnsEmptyForEmptySet() {
        Map<Id, Integer> result = AccountContactCountService.countContacts(new Set<Id>());
        Assert.isTrue(result.isEmpty(), 'Empty input should return an empty map');
    }

    @IsTest
    static void countContacts_countsPerAccount() {
        Map<String, Id> ids = idsByName();

        Test.startTest();
        Map<Id, Integer> result = AccountContactCountService.countContacts(new Set<Id>(ids.values()));
        Test.stopTest();

        Assert.areEqual(3, result.size());
        Assert.areEqual(3, result.get(ids.get('Three Contacts')));
        Assert.areEqual(0, result.get(ids.get('No Contacts')));
        Assert.areEqual(21, result.get(ids.get('Many Contacts')), 'Count is capped by the query LIMIT');
    }

    @IsTest
    static void stampContactCounts_updatesDescriptions() {
        Map<String, Id> ids = idsByName();

        Test.startTest();
        Integer updated = AccountContactCountService.stampContactCounts(new Set<Id>(ids.values()));
        Test.stopTest();

        Assert.areEqual(3, updated);
        Map<String, String> descByName = new Map<String, String>();
        for (Account a : [SELECT Name, Description FROM Account]) {
            descByName.put(a.Name, a.Description);
        }
        Assert.areEqual('Contacts: 3', descByName.get('Three Contacts'));
        Assert.areEqual('Contacts: 0', descByName.get('No Contacts'));
        Assert.areEqual('Contacts: 21', descByName.get('Many Contacts'));
    }

    @IsTest
    static void stampContactCounts_returnsZeroForEmptyInput() {
        Assert.areEqual(0, AccountContactCountService.stampContactCounts(null));
        Assert.areEqual(0, AccountContactCountService.stampContactCounts(new Set<Id>()));
    }
}
