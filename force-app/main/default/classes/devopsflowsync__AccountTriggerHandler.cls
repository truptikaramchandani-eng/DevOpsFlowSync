public class AccountTriggerHandler {

    public static void beforeInsert(List<Account> newList) {
        for (Account acc : newList) {
            acc.Description = 'Created on ' + Date.today();
        }
    }

    public static void beforeUpdate(List<Account> newList, Map<Id, Account> oldMap) {
        for (Account acc : newList) {
            Account oldAcc = oldMap.get(acc.Id);

            if (acc.Name != oldAcc.Name) {
                acc.Description = 'Name changed from ' + oldAcc.Name + ' to ' + acc.Name;
            }
        }
    }

    public static void afterInsert(List<Account> newList) {
        System.debug('Accounts inserted: ' + newList.size());
    }

    public static void afterUpdate(List<Account> newList, Map<Id, Account> oldMap) {
        System.debug('Accounts updated: ' + newList.size());
    }
}