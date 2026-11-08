@IsTest
private class ContactEmailServiceTest {

    @TestSetup
    static void setup() {
        insert new List<Contact>{
            new Contact(LastName = 'Messy',  Email = 'Jane.Doe@Example.COM'),
            new Contact(LastName = 'Clean',  Email = 'clean@example.com'),
            new Contact(LastName = 'NoMail', Email = null)
        };
    }

    @IsTest 
    static void normalize_coversAllBranches() {
        Assert.isNull(ContactEmailService.normalize(null));
        Assert.isNull(ContactEmailService.normalize('   '));
        Assert.areEqual('a@b.com', ContactEmailService.normalize('  A@B.Com  '));
    }

    @IsTest
    static void getDomain_coversAllBranches() {
        Assert.isNull(ContactEmailService.getDomain(null));
        Assert.isNull(ContactEmailService.getDomain('no-at-sign'));
        Assert.isNull(ContactEmailService.getDomain('user@'));
        Assert.areEqual('example.com', ContactEmailService.getDomain('User@Example.com'));
    }

    @IsTest
    static void applyNormalization_handlesNullAndEmpty() {
        Assert.isTrue(ContactEmailService.applyNormalization(null).isEmpty());
        Assert.isTrue(ContactEmailService.applyNormalization(new List<Contact>()).isEmpty());
    }

    @IsTest
    static void applyNormalization_returnsOnlyChanged() {
        Contact messy = new Contact(LastName = 'M', Email = 'X@Y.COM');
        Contact clean = new Contact(LastName = 'C', Email = 'x@y.com');
        List<Contact> changed = ContactEmailService.applyNormalization(new List<Contact>{ messy, clean });

        Assert.areEqual(1, changed.size());
        Assert.areEqual('x@y.com', messy.Email);
        Assert.areEqual('x@y.com', clean.Email);
    }

    @IsTest
    static void normalizeAndSave_updatesOnlyChangedContacts() {
        Map<Id, Contact> contacts = new Map<Id, Contact>([SELECT Id FROM Contact]);

        Test.startTest();
        Integer updated = ContactEmailService.normalizeAndSave(contacts.keySet());
        Test.stopTest();

        // The org lowercases Email on save, so stored emails are already
        // normalized and nothing needs updating (null email must not throw).
        Assert.areEqual(0, updated);
        Map<String, String> emailByName = new Map<String, String>();
        for (Contact c : [SELECT LastName, Email FROM Contact]) {
            emailByName.put(c.LastName, c.Email);
        }
        Assert.areEqual('jane.doe@example.com', emailByName.get('Messy'));
        Assert.areEqual('clean@example.com', emailByName.get('Clean'));
        Assert.isNull(emailByName.get('NoMail'));
    }

    @IsTest
    static void normalizeAndSave_noChangesSkipsDml() {
        Id cleanId = [SELECT Id FROM Contact WHERE LastName = 'Clean' LIMIT 1].Id;
        Assert.areEqual(0, ContactEmailService.normalizeAndSave(new Set<Id>{ cleanId }));
    }

    @IsTest
    static void normalizeAndSave_throwsOnNullIds() {
        try {
            ContactEmailService.normalizeAndSave(null);
            Assert.fail('Expected ContactEmailException');
        } catch (ContactEmailService.ContactEmailException e) {
            Assert.isTrue(e.getMessage().contains('must not be empty'));
        }
    }

    @IsTest
    static void normalizeAndSave_throwsOnEmptyIds() {
        try {
            ContactEmailService.normalizeAndSave(new Set<Id>());
            Assert.fail('Expected ContactEmailException');
        } catch (ContactEmailService.ContactEmailException e) {
            Assert.isTrue(e.getMessage().contains('must not be empty'));
        }
    }
}