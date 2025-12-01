public with sharing class AccountDataController {
    public static List<Account> getAccounts(String accId){
        return [Select Id from Account where Id =: accId];
    }

}