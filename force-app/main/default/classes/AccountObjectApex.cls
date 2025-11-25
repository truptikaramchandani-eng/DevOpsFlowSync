public with sharing class AccountObjectApex {

    // ===================================================================
    // 1. INSERT ACCOUNTS
    // ===================================================================
    public static List<Database.SaveResult> insertAccounts(List<Account> accountsToInsert) {
        if (accountsToInsert == null || accountsToInsert.isEmpty()) {
            return new List<Database.SaveResult>();
        }

        // Using allOrNone = false to get partial success
        return Database.insert(accountsToInsert, false);
    }
    }