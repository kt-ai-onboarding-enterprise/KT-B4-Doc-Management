@IsTest
private class KT_DocumentVaultAccessServiceTest {
    @TestSetup
    static void setupUsers() {
        Profile profileRecord = [
            SELECT Id
            FROM Profile
            WHERE UserType = 'Standard'
            LIMIT 1
        ];

        insert new List<User>{
            buildUser(profileRecord.Id, 'mgrone'),
            buildUser(profileRecord.Id, 'mgrtwo'),
            buildUser(profileRecord.Id, 'peerusr')
        };
    }

    @IsTest
    static void createsManagerShareWhenOnboardingAssigned() {
        User managerUser = getUser('mgrone');

        Test.startTest();
        KT_Onboarding__c onboarding = new KT_Onboarding__c(Hiring_Manager__c = managerUser.Id);
        insert onboarding;
        Test.stopTest();

        List<SObject> shares = queryManagerShares(onboarding.Id);
        System.assertEquals(1, shares.size(), 'One manager share should be created.');
        System.assertEquals(managerUser.Id, (Id) shares[0].get('UserOrGroupId'));
        System.assertEquals('Read', (String) shares[0].get('AccessLevel'));
    }

    @IsTest
    static void replacesShareWhenManagerChanges() {
        User firstManager = getUser('mgrone');
        User secondManager = getUser('mgrtwo');
        KT_Onboarding__c onboarding = new KT_Onboarding__c(Hiring_Manager__c = firstManager.Id);
        insert onboarding;

        Test.startTest();
        onboarding.Hiring_Manager__c = secondManager.Id;
        update onboarding;
        Test.stopTest();

        List<SObject> shares = queryManagerShares(onboarding.Id);
        System.assertEquals(1, shares.size(), 'Only the current manager share should remain.');
        System.assertEquals(secondManager.Id, (Id) shares[0].get('UserOrGroupId'));
    }

    @IsTest
    static void removesShareWhenManagerCleared() {
        User managerUser = getUser('mgrone');
        KT_Onboarding__c onboarding = new KT_Onboarding__c(Hiring_Manager__c = managerUser.Id);
        insert onboarding;

        Test.startTest();
        onboarding.Hiring_Manager__c = null;
        update onboarding;
        Test.stopTest();

        System.assertEquals(0, queryManagerShares(onboarding.Id).size(), 'Manager share should be removed.');
    }

    @IsTest
    static void accessCheckHonorsRecordSharing() {
        User managerUser = getUser('mgrone');
        User peerUser = getUser('peerusr');
        KT_Onboarding__c onboarding = new KT_Onboarding__c(Hiring_Manager__c = managerUser.Id);
        insert onboarding;

        System.runAs(managerUser) {
            System.assertEquals(true, KT_DocumentVaultAccessService.hasCurrentUserVaultAccess(onboarding.Id));
        }

        System.runAs(peerUser) {
            System.assertEquals(false, KT_DocumentVaultAccessService.hasCurrentUserVaultAccess(onboarding.Id));
        }
    }

    private static User buildUser(Id profileId, String aliasPrefix) {
        String uniqueValue = aliasPrefix + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            Alias = aliasPrefix.left(8),
            Email = uniqueValue + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = aliasPrefix,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueValue + '@example.com'
        );
    }

    private static User getUser(String aliasPrefix) {
        return [
            SELECT Id
            FROM User
            WHERE Alias = :aliasPrefix.left(8)
            LIMIT 1
        ];
    }

    private static List<SObject> queryManagerShares(Id onboardingId) {
        String managerRowCause = KT_DocumentVaultAccessService.MANAGER_ROW_CAUSE;
        return Database.query(
            'SELECT Id, ParentId, UserOrGroupId, AccessLevel ' +
            'FROM KT_Onboarding__Share ' +
            'WHERE ParentId = :onboardingId ' +
            'AND RowCause = :managerRowCause'
        );
    }
}
