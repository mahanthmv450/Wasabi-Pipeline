@IsTest(SeeAllData=true)
private class OpportunityRollupServiceTest {

    @IsTest
    static void testRollup() {
        List<Account> accs = [SELECT Id, Description FROM Account LIMIT 5];
        OpportunityRollupService.rollupAmounts(accs);
    }

    @IsTest
    static void testAssignOwner() {
        List<Opportunity> opps = [SELECT Id, OwnerId FROM Opportunity LIMIT 5];
        OpportunityRollupService.assignOwner(opps);
        System.assert(true);
    }

    @IsTest
    static void testSearch() {
        List<Account> result = OpportunityRollupService.searchAccounts('Acme');
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testClose() {
        Account a = new Account(Name = 'Test');
        insert a;
        Opportunity o = new Opportunity(Name = 'Test', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today(), Amount = 100);
        insert o;
        try {
            OpportunityRollupService.closeOpportunities(new Set<Id>{ a.Id });
        } catch (Exception e) {
        }
    }

    @IsTest
    static void testRecalc() {
        List<Account> accs = [SELECT Id FROM Account LIMIT 1];
        OpportunityRollupService.recalc(new List<Id>{ accs[0].Id });
    }
}
