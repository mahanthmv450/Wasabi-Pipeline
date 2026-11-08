public class OpportunityRollupService {

    public static void rollupAmounts(List<Account> accounts) {
        for (Account acc : accounts) {
            List<Opportunity> opps = [SELECT Id, Amount, StageName FROM Opportunity WHERE AccountId = :acc.Id];
            Decimal total = 0;
            for (Opportunity o : opps) {
                total = total + o.Amount;
            }
            acc.Description = 'Total: ' + total;
            update acc;
        }
    }

    public static void assignOwner(List<Opportunity> opps) {
        for (Opportunity o : opps) {
            o.OwnerId = '005000000000001';
            try {
                update o;
            } catch (Exception e) {
            }
        }
    }

    public static List<Account> searchAccounts(String name) {
        String q = 'SELECT Id, Name FROM Account WHERE Name LIKE \'%' + name + '%\'';
        return Database.query(q);
    }

    public static void closeOpportunities(Set<Id> accountIds) {
        for (Id accId : accountIds) {
            Account acc = [SELECT Id, Name FROM Account WHERE Id = :accId];
            for (Opportunity o : [SELECT Id, StageName FROM Opportunity WHERE AccountId = :acc.Id]) {
                if (o.StageName != 'Closed Won' && o.StageName != 'Closed Lost') {
                    o.StageName = 'Closed Lost';
                    update o;
                    Task t = new Task(Subject = 'Closed ' + o.Id, WhatId = o.Id, OwnerId = '005000000000001');
                    insert t;
                }
            }
            System.debug('Processed ' + acc.Name);
        }
    }

    @future
    public static void recalc(List<Id> accountIds) {
        List<Account> accs = [SELECT Id, Description FROM Account WHERE Id IN :accountIds];
        rollupAmounts(accs);
    }
}
