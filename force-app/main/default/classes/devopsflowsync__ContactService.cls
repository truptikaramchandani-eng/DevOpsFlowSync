public with sharing class ContactService {
    
    @AuraEnabled
    public static Id createContact(String firstName, String lastName, String email, Id accountId) {
        Contact con = new Contact(
            FirstName = firstName,
            LastName  = lastName,
            Email     = email,
            AccountId = accountId
        );
        insert con;
        return con.Id;
    }
}