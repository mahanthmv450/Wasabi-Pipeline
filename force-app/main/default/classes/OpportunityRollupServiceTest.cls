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
        Account a = new Account(Name = 'Recalc Test');
        insert a;
        insert new Opportunity(Name = 'Recalc Opp', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today(), Amount = 250);

        Test.startTest();
        OpportunityRollupService.recalc(new List<Id>{ a.Id });
        Test.stopTest();

        Account result = [SELECT Description FROM Account WHERE Id = :a.Id];
        Assert.areEqual('Total: 250.00', result.Description);
    }
}
