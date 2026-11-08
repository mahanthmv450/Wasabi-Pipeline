@IsTest
private class AccountContactCountServiceTest {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Two Contacts'),
            new Account(Name = 'One Contact'),
            new Account(Name = 'No Contacts')
        };
        insert accounts;
        insert new List<Contact>{
            new Contact(LastName = 'A1', AccountId = accounts[0].Id),
            new Contact(LastName = 'A2', AccountId = accounts[0].Id),
            new Contact(LastName = 'B1', AccountId = accounts[1].Id)
        };
    }

    private static Map<String, Id> idsByName() {
        Map<String, Id> result = new Map<String, Id>();
        for (Account a : [SELECT Id, Name FROM Account]) {
            result.put(a.Name, a.Id);
        }
        return result;
    }

    @IsTest
    static void countContacts_returnsCountPerAccount() {
        Map<String, Id> ids = idsByName();

        Test.startTest();
        Map<Id, Integer> counts = AccountContactCountService.countContacts(new Set<Id>(ids.values()));
        Test.stopTest();

        Assert.areEqual(3, counts.size());
        Assert.areEqual(2, counts.get(ids.get('Two Contacts')));
        Assert.areEqual(1, counts.get(ids.get('One Contact')));
        Assert.areEqual(0, counts.get(ids.get('No Contacts')));
    }

    @IsTest
    static void countContacts_handlesNullAndEmpty() {
        Assert.isTrue(AccountContactCountService.countContacts(null).isEmpty());
        Assert.isTrue(AccountContactCountService.countContacts(new Set<Id>()).isEmpty());
    }

    @IsTest
    static void stampContactCounts_updatesDescription() {
        Map<String, Id> ids = idsByName();

        Test.startTest();
        Integer updated = AccountContactCountService.stampContactCounts(new Set<Id>(ids.values()));
        Test.stopTest();

        Assert.areEqual(3, updated);
        Map<String, String> descByName = new Map<String, String>();
        for (Account a : [SELECT Name, Description FROM Account]) {
            descByName.put(a.Name, a.Description);
        }
        Assert.areEqual('Contacts: 2', descByName.get('Two Contacts'));
        Assert.areEqual('Contacts: 1', descByName.get('One Contact'));
        Assert.areEqual('Contacts: 0', descByName.get('No Contacts'));
    }

    @IsTest
    static void stampContactCounts_noIdsUpdatesNothing() {
        Assert.areEqual(0, AccountContactCountService.stampContactCounts(new Set<Id>()));
    }
}
