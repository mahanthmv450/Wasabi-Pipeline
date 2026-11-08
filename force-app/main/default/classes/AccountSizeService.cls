/**
 * Example service that classifies Accounts by NumberOfEmployees and
 * writes the size segment into Description.
 */
public with sharing class AccountSizeService {

    public static final Integer ENTERPRISE_MIN = 1000;
    public static final Integer MID_MARKET_MIN = 100;

    public static final String ENTERPRISE     = 'Enterprise';
    public static final String MID_MARKET     = 'Mid-Market';
    public static final String SMALL_BUSINESS = 'Small Business';

    /**
     * Returns the size segment for a given employee count.
     */
    public static String getSegment(Integer employees) {
        if (employees == null) {
            return SMALL_BUSINESS;
        }
        if (employees >= ENTERPRISE_MIN) {
            return ENTERPRISE;
        }
        if (employees >= MID_MARKET_MIN) {
            return MID_MARKET;
        }
        return SMALL_BUSINESS;
    }

    /**
     * Sets Description on each Account in memory (no DML).
     */
    public static void applySegments(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        for (Account acc : accounts) {
            acc.Description = getSegment(acc.NumberOfEmployees);
        }
    }

    /**
     * Queries the given Accounts, classifies them and saves the result.
     * Returns the number of Accounts updated.
     */
    public static Integer segmentAndSave(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new AccountSizeException('accountIds must not be empty.');
        }
        List<Account> accounts = [
            SELECT Id, NumberOfEmployees, Description
            FROM Account
            WHERE Id IN :accountIds
            WITH USER_MODE
        ];
        applySegments(accounts);
        update as user accounts;
        return accounts.size();
    }

    public class AccountSizeException extends Exception {}

}


