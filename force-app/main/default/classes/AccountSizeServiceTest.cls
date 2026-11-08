@IsTest
private class AccountSizeServiceTest {

    @TestSetup
    static void setup() {
        insert new List<Account>{
            new Account(Name = 'Big Co',   NumberOfEmployees = 5000),
            new Account(Name = 'Mid Co',   NumberOfEmployees = 250),
            new Account(Name = 'Small Co', NumberOfEmployees = 10),
            new Account(Name = 'Null Co',  NumberOfEmployees = null)
        };
    }

    @IsTest
    static void getSegment_coversAllBranches() {
        Assert.areEqual(AccountSizeService.SMALL_BUSINESS, AccountSizeService.getSegment(null));
        Assert.areEqual(AccountSizeService.ENTERPRISE, AccountSizeService.getSegment(AccountSizeService.ENTERPRISE_MIN));
        Assert.areEqual(AccountSizeService.MID_MARKET, AccountSizeService.getSegment(AccountSizeService.MID_MARKET_MIN));
        Assert.areEqual(AccountSizeService.SMALL_BUSINESS, AccountSizeService.getSegment(99));
    }

    @IsTest
    static void applySegments_handlesNullAndEmpty() {
        AccountSizeService.applySegments(null);
        List<Account> empty = new List<Account>();
        AccountSizeService.applySegments(empty);
        Assert.isTrue(empty.isEmpty(), 'Empty list should stay empty');
    }

    @IsTest
    static void applySegments_setsDescriptionInMemory() {
        Account acc = new Account(Name = 'Mem', NumberOfEmployees = 2000);
        AccountSizeService.applySegments(new List<Account>{ acc });
        Assert.areEqual(AccountSizeService.ENTERPRISE, acc.Description);
    }

    @IsTest
    static void segmentAndSave_updatesAccounts() {
        Map<Id, Account> accounts = new Map<Id, Account>([SELECT Id FROM Account]);

        Test.startTest();
        Integer updated = AccountSizeService.segmentAndSave(accounts.keySet());
        Test.stopTest();

        Assert.areEqual(4, updated);
        Map<String, String> segmentByName = new Map<String, String>();
        for (Account a : [SELECT Name, Description FROM Account]) {
            segmentByName.put(a.Name, a.Description);
        }
        Assert.areEqual(AccountSizeService.ENTERPRISE, segmentByName.get('Big Co'));
        Assert.areEqual(AccountSizeService.MID_MARKET, segmentByName.get('Mid Co'));
        Assert.areEqual(AccountSizeService.SMALL_BUSINESS, segmentByName.get('Small Co'));
        Assert.areEqual(AccountSizeService.SMALL_BUSINESS, segmentByName.get('Null Co'));
    }

    @IsTest
    static void segmentAndSave_throwsOnNullIds() {
        try {
            AccountSizeService.segmentAndSave(null);
            Assert.fail('Expected AccountSizeException');
        } catch (AccountSizeService.AccountSizeException e) {
            Assert.isTrue(e.getMessage().contains('must not be empty'));
        }
    }

    @IsTest
    static void segmentAndSave_throwsOnEmptyIds() {
        try {
            AccountSizeService.segmentAndSave(new Set<Id>());
            Assert.fail('Expected AccountSizeException');
        } catch (AccountSizeService.AccountSizeException e) {
            Assert.isTrue(e.getMessage().contains('must not be empty'));
        }
    }
}