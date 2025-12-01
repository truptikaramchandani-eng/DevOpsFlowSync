public with sharing class AccountController {

    // --- Fetch All Accounts ---
    @AuraEnabled(cacheable=true)
    public static List<Account> getAllAccounts() {
        return [
            SELECT Id, Name, Phone, Industry, Rating, Type, BillingCity, BillingState, BillingCountry
            FROM Account
            ORDER BY Name
        ];
    }
}