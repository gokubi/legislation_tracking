/*
 * Fetch details of the legislation with a web services callout and update the Legislation record
 *
 * WH, Exponent Partners, 2011
 */
public class LegislationAction {
       
    public static void getLegislationDetail(Legislation__c leg) {
        if (leg.Bill_Prefix__c != null && leg.Bill_Prefix__c.contains('AMDT')) {
            // amendment - remove 'ADMT' from prefix
            updateAmendmentDetail(leg.Id, leg.Bill_Prefix__c.substring(0,1).toLowerCase(), String.valueOf(leg.Bill_Number__c.setScale(0)), leg.Congressional_Session__c);
        } else {
            // bill
            updateBillDetail(leg.Id, leg.Bill_Prefix__c.toLowerCase(), String.valueOf(leg.Bill_Number__c.setScale(0)), leg.Congressional_Session__c);
            // votes
            updateBillVotes(leg.Id, leg.Bill_Prefix__c.toLowerCase(), String.valueOf(leg.Bill_Number__c.setScale(0)), leg.Congressional_Session__c);
        }
    }
    
    /*
     * Calling RTC amendments API
     */
    
    // Call out to the web services and gather info returned
    @future (callout=true)
    static void updateAmendmentDetail(Id legId, String amendmentPrefix, String amendmentNumber, String session) {
        
        Boolean doUpdate = false;
        String billId, purpose, status, lastAction, introducedAt, sponsorId;
        
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        // Get officalTitle, shortTitle, status, lastAction, sponsorId, and cosponsorIds
        if (api.getAmendment(amendmentPrefix, amendmentNumber, session)) {
            doUpdate = true;
            String amendmentId = amendmentPrefix + amendmentNumber + '-' + session;
            billId = api.legDetailMap.get(amendmentId).billId;
            purpose = api.legDetailMap.get(amendmentId).getPurpose();
            status = api.legDetailMap.get(amendmentId).getStatus();
            lastAction = api.legDetailMap.get(amendmentId).getLastAction();
            introducedAt = api.legDetailMap.get(amendmentId).introducedAt;
            sponsorId = api.legDetailMap.get(amendmentId).sponsorId;
        }
        
        // Update the Legislation record
        if (doUpdate) {
            updateAmendmentRecord(legId, billId, purpose, status, lastAction, introducedAt, sponsorId);
        } else {
            System.debug('>>>>>>>>>> Callout to get amendment detail failed');
        }
    }
    
    // Update Legislation record with info returned from web services
    private static void updateAmendmentRecord(Id legId, String billId, String purpose, String status, String lastAction, String introducedAt, String sponsorId) {
        try {
            // Select Legislation record to update
            Legislation__c l = [select Id, Name, Bill_Id__c, Sponsor__c, (select Legislation1__c from Corresponding_Bill2__r) from Legislation__c where Id = :legId limit 1];
            
            if(billId!=null){
            	l.Name = billId;
            	l.bill_id__c = billId;
            }
            l.Bill_Title__c = (purpose != null  && purpose.length() > Legislation__c.Bill_Title__c.getDescribe().getLength()) ? purpose.substring(0, Legislation__c.Bill_Title__c.getDescribe().getLength()) : purpose;
            l.Status__c = (status != null  && status.length() > Legislation__c.Status__c.getDescribe().getLength()) ? status.substring(0, Legislation__c.Status__c.getDescribe().getLength()) : status;
            l.Latest_Major_Action__c = (lastAction != null  && lastAction.length() > Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) ? lastAction.substring(0, Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) : lastAction;
            // Convert date time string like 2011-02-10T12:00:00Z into a Date object
            l.Introduced_Date__c = (introducedAt != null) ? Date.valueOf(introducedAt.substring(0, introducedAt.indexOf('T'))) : null;
            l.Date_Bill_Info_Updated__c = System.now();
            
            // Look up sponsor by matching bioguide_id
            if (sponsorId != null) {
                List<Contact> sponsor = [select Id from Contact where Bioguide_ID__c = :sponsorId];
                l.Sponsor__c = (sponsor.size() > 0) ? sponsor[0].Id : null;
                l.Sponsor_Info__c = sponsorId;
            } else {
                l.Sponsor__c = null;
                l.Sponsor_Info__c = null;
            }
            
            // Insert junction to corresponding bill if not already there
            Corresponding_Bill__c relatedBillToInsert;
            
            // Get all existing corresponding bills
            //  Map Bill Id => corresponding bill junction
            Map<Id, Corresponding_Bill__c> relatedBillMap = new Map<Id, Corresponding_Bill__c>();
            for (Corresponding_Bill__c cb : l.Corresponding_Bill2__r) {
                relatedBillMap.put(cb.Legislation1__c, cb);
            }
            
            if (billId != null) {
                // Look up corresponding bill by matching billId
                billId = billId.toUpperCase(); // Legislation naming convention in SF uses prefix in upper case vs lower case in RTC API
                List<Legislation__c> relatedBills = [select Id from Legislation__c where Name = :billId];
                Id relatedBillId = (relatedBills.size() > 0) ? relatedBills[0].Id : null;
                
                if (relatedBillId != null) {
                    if (!relatedBillMap.containsKey(relatedBillId)) {
                        // Create new corresponding bill junction if none exists
                        relatedBillToInsert = new Corresponding_Bill__c(Legislation1__c = relatedBillId, Legislation2__c = legId);
                    } else {
                        // Reuse existing corresponding bill junction
                        relatedBillMap.remove(relatedBillId);
                    }
                }
            }
            
            if (relatedBillToInsert != null)
                insert relatedBillToInsert;
            
            // Corresponding bill junctions remaining in map are not related to the bill returned from web services
            if (!relatedBillMap.isEmpty())
                delete relatedBillMap.values();
        
            update l;
        
        } catch (Exception e) {
            System.debug('>>>>>>>>>> Update legislation failed: ' + e.getMessage());
            return;
        }
        
    }
    
    /*
     * Calling RTC bills API
     */
    
    // Call out to the web services and gather info returned
    @future (callout=true)
    static void updateBillDetail(Id legId, String billPrefix, String billNumber, String session) {
        
        Boolean doUpdate = false;
        String officialTitle, shortTitle, status, lastAction, summary, introducedAt, sponsorId;
        Set<String> cosponsorIds;
        String billId;
        
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        // Get officalTitle, shortTitle, status, lastAction, sponsorId, and cosponsorIds
        if (api.getBill(billPrefix, billNumber, session)) {
            doUpdate = true;
            billId = billPrefix + billNumber + '-' + session;
            officialTitle = api.legDetailMap.get(billId).getOfficialTitle();
            shortTitle = api.legDetailMap.get(billId).getShortTitle();
            status = api.legDetailMap.get(billId).getStatus();
            lastAction = api.legDetailMap.get(billId).getLastAction();
            summary = api.legDetailMap.get(billId).summary;
            introducedAt = api.legDetailMap.get(billId).introducedAt;
            sponsorId = api.legDetailMap.get(billId).sponsorId;
            cosponsorIds = api.legDetailMap.get(billId).cosponsorIds;
        }
        
        // Update the Legislation record
        //  - use shortTitle if exists otherwise officialTitle
        if (doUpdate) {
            updateBillRecord(legId, billId, (shortTitle != null) ? shortTitle : officialTitle, status, lastAction, summary, introducedAt, sponsorId, cosponsorIds);
        } else {
            System.debug('>>>>>>>>>> Callout to get bill detail failed');
        }
    }
    
    // Call out to the web services and gather info returned
    @future (callout=true)
    static void updateBillVotes(Id legId, String billPrefix, String billNumber, String session) {
        
        Boolean doUpdate = false;
        String rollId, voteDate, result, voteType;
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        List<Roll_Vote__c> rollVotes = new List<Roll_Vote__c>();
        // Get officalTitle, shortTitle, status, lastAction, sponsorId, and cosponsorIds
        if (api.getVotes(billPrefix, billNumber, session)) {
            doUpdate = true;
            for(String thisRollId : api.legDetailMap.keySet()){
                //Date dateVoted = date.newInstance(Integer.valueOf(api.legDetailMap.get(thisRollId).voted_at.substring(0,4)),Integer.valueOf(api.legDetailMap.get(thisRollId).voted_at.substring(5,2)),Integer.valueOf(api.legDetailMap.get(thisRollId).voted_at.substring(8,2)));
                Roll_Vote__c thisRollVote = new Roll_Vote__c(Legislation__c=legId, Name=api.legDetailMap.get(thisRollId).roll_id, Roll_Type__c=api.legDetailMap.get(thisRollId).roll_type,Roll_Id__c=api.legDetailMap.get(thisRollId).roll_id,Result__c=api.legDetailMap.get(thisRollId).result);
                rollVotes.add(thisRollVote);
                
            }

        }
        
        // Update the Legislation record
        //  - use shortTitle if exists otherwise officialTitle
        if (doUpdate) {
            upsert rollVotes Roll_Id__c;
            
            
            //soql the ids or the roll votes
            List<Roll_Vote__c> rollVotesAfterUpsert = [select id, roll_id__c from Roll_Vote__c where id IN :rollVotes];
            
            Map<String,Roll_Vote__c> rollIdToIdMap = new Map<String,Roll_Vote__c>();
            //put roll votes in a map of roll_id to id
            for(Roll_Vote__c thisRV : rollVotesAfterUpsert){
                rollIdToIdMap.put(thisRV.roll_id__c,thisRV);
            }
            
            //get the keyset of all the bioguide voter ids for this roll id
            
            Set<String> bioGuides = new Set<String>();
            for(String thisRollId : api.legDetailMap.keySet()){
                
                for(RealTimeCongressAPI.VoteInfo thisVoteInfo :api.legDetailMap.get(thisRollId).voterIdMap.get(thisRollId)){
                
                        bioGuides.add(thisVoteInfo.bioguide);
                }
                //voterIdMap.get(thisRollId);
            }
            //soql the contacts that are in that set
            List<Contact> legislators = [select id, Bioguide_ID__c from Contact where Bioguide_ID__c IN :bioGuides];
            Map<String, Contact> bioGuideContactMap = new Map<String, Contact>();
            
            for(Contact thisLeg : legislators){
                bioGuideContactMap.put(thisLeg.Bioguide_ID__c,thisLeg);
            }
            //put contacts in a map of roll_id to contact id
            
            List<Legislator_Vote__c> legVotes = new List<Legislator_Vote__c>();
            for(String thisRollId : api.legDetailMap.keySet()){
                for(RealTimeCongressAPI.VoteInfo thisVoteIfnfo: api.legDetailMap.get(thisRollId).voterIdMap.get(thisRollId)){
                    if(bioGuideContactMap.get(thisVoteIfnfo.bioguide)!=null){
                        String legVoteId = thisRollId+thisVoteIfnfo.bioguide;
                        Legislator_Vote__c thisLegVote = new Legislator_Vote__c();
                        
                        thisLegVote.Legislator__c=bioGuideContactMap.get(thisVoteIfnfo.bioguide).id;
                        thisLegVote.Roll_Vote__c=rollIdToIdMap.get(thisRollId).id;
                        thisLegVote.Vote__c=thisVoteIfnfo.vote;
                        thisLegVote.LegVoteId__c=legVoteId;
                        legVotes.add(thisLegVote);    
                    }
                }
                
            }
            
            upsert legVotes LegVoteId__c;
            
           // updateBillVotes(legId, (shortTitle != null) ? shortTitle : officialTitle, status, lastAction, summary, introducedAt, sponsorId, cosponsorIds);
        } else {
            System.debug('>>>>>>>>>> Callout to get bill detail failed');
        }
    }
    
    // Update Legislation record with info returned from web services
    private static void updateBillRecord(Id legId, String billId, String title, String status, String lastAction, String summary, String introducedAt, String sponsorId, Set<String> cosponsorIds) {
        try {
            // Select Legislation record to update
            Legislation__c l = [select Id, Name, bill_id__c,Sponsor__c, (select Contact__c, Role__c from Contact_Leg__r where Role__c = 'Co-sponsor') from Legislation__c where Id = :legId limit 1];
            if(billId!=null){
            	l.Name = billId;
            	l.bill_id__c = billId;
            }
            l.Bill_Title__c = (title != null  && title.length() > Legislation__c.Bill_Title__c.getDescribe().getLength()) ? title.substring(0, Legislation__c.Bill_Title__c.getDescribe().getLength()) : title;
            l.Status__c = (status != null  && status.length() > Legislation__c.Status__c.getDescribe().getLength()) ? status.substring(0, Legislation__c.Status__c.getDescribe().getLength()) : status;
            l.Latest_Major_Action__c = (lastAction != null  && lastAction.length() > Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) ? lastAction.substring(0, Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) : lastAction;
            l.Summary__c = summary;
            // Convert date time string like 2011-02-10T12:00:00Z into a Date object
            l.Introduced_Date__c = (introducedAt != null) ? Date.valueOf(introducedAt.substring(0, introducedAt.indexOf('T'))) : null;
            l.Date_Bill_Info_Updated__c = System.now();
            
            // Look up sponsor by matching bioguide_id
            if (sponsorId != null) {
                List<Contact> sponsor = [select Id from Contact where Bioguide_ID__c = :sponsorId];
                //if (sponsor.size() > 0) { l.Sponsor__c = sponsor[0].Id; } // Should be at most 1 contact
                l.Sponsor__c = (sponsor.size() > 0) ? sponsor[0].Id : null;
                l.Sponsor_Info__c = sponsorId;
            } else {
                l.Sponsor__c = null;
                l.Sponsor_Info__c = null;
            }
            
            // Look up cosponsors by matching bioguide_id
            List<Contact_Leg_junction__c> relatedContactsToInsert = new List<Contact_Leg_junction__c>();
            
            // Get all existing related Co-sponsor contacts
            Map<Id, Contact_Leg_junction__c> cosponsorMap = new Map<Id, Contact_Leg_junction__c>();
            for (Contact_Leg_junction__c clj : l.Contact_Leg__r) {
                cosponsorMap.put(clj.Contact__c, clj);
            }
            
            if (!cosponsorIds.isEmpty()) {
                for (Contact c: [select Id from Contact where Bioguide_ID__c in :cosponsorIds]) {
                    if (!cosponsorMap.containsKey(c.Id)) {
                        // Create new related contact if none exists
                        relatedContactsToInsert.add(new Contact_Leg_junction__c(Contact__c = c.Id, Legislation__c = legId, Role__c = 'Co-sponsor'));
                    } else {
                        // Reuse existing related contact
                        cosponsorMap.remove(c.Id);
                    }
                }
                
                String cosponsors = '';
                for (String ci : cosponsorIds) { cosponsors = cosponsors + ci + ', '; }
                l.Cosponsors__c = (cosponsors != '') ? cosponsors.subString(0, cosponsors.length()-2) : null;
            }
            
            if (!relatedContactsToInsert.isEmpty())
                insert relatedContactsToInsert;
            
            // Related contacts remaining in map are not in list of cosponsors returned from web services
            if (!cosponsorMap.isEmpty())
                delete cosponsorMap.values();
        
            // For debug purposes
            //l.Summary__c = Limits.getScriptStatements() + ' statements.';
            
            update l;
        
        } catch (Exception e) {
            System.debug('>>>>>>>>>> Update legislation failed: ' + e.getMessage());
            return;
        }
        
    }
    
   
    
    ////////// Unit Tests //////////
    
    static testMethod void testGetLegislationDetail() {
        Test.startTest();
        Legislation__c testBill = new Legislation__c(Bill_Prefix__c = 'S', Bill_Number__c = 614, Congressional_Session__c = '112');
        insert testBill;
        Test.stopTest();
        
        // Web services callout not executed in test
        Legislation__c insertedBill = [select Bill_Title__c, Cosponsors__c, Latest_Major_Action__c, Sponsor__c, Status__c from Legislation__c where Id = :testBill.Id limit 1];
        System.assertEquals(null, insertedBill.Bill_Title__c);
        System.assertEquals(null, insertedBill.Status__c);
        System.assertEquals(null, insertedBill.Latest_Major_Action__c);
        System.assertEquals(null, insertedBill.Sponsor__c);
        System.assertEquals(null, insertedBill.Cosponsors__c);
    }
    
    static testMethod void testUpdateAmendmentRecord() {
        Legislation__c testBill = new Legislation__c(Bill_Prefix__c = 'S', Bill_Number__c = 614, Congressional_Session__c = '112');
        insert testBill;
        
        Legislation__c testAnotherBill = new Legislation__c(Bill_Prefix__c = 'H', Bill_Number__c = 789, Congressional_Session__c = '112');
        insert testAnotherBill;
        
        Legislation__c testAmendment = new Legislation__c(Bill_Prefix__c = 'SAMDT', Bill_Number__c = 123, Congressional_Session__c = '112');
        insert testAmendment;
        
        Contact sponsor = new Contact(FirstName = 'Test', LastName = 'Sponsor', Bioguide_ID__c = 'S00001');
        insert sponsor;
        
        Corresponding_Bill__c cbjunction1 = new Corresponding_Bill__c(Legislation1__c = testBill.Id, Legislation2__c = testAmendment.Id);
        insert cbjunction1;
        
        Corresponding_Bill__c cbjunction2 = new Corresponding_Bill__c(Legislation1__c = testAnotherBill.Id, Legislation2__c = testAmendment.Id);
        insert cbjunction2;
        
        // Amendment related to testBill
        LegislationAction.updateAmendmentRecord(testAmendment.Id, 's614-112', 'To make it better', 'Passed', 'Amendment made to s614-112', '2011-12-01T14:00:00Z', 'S00001');
        
        Legislation__c updatedAmendment = [select Bill_Title__c, Latest_Major_Action__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c, Sponsor_Info__c, Status__c from Legislation__c where Id = :testAmendment.Id limit 1];
        System.assertEquals('To make it better', updatedAmendment.Bill_Title__c);
        System.assertEquals('Passed', updatedAmendment.Status__c);
        System.assertEquals('Amendment made to s614-112', updatedAmendment.Latest_Major_Action__c);
        System.assertEquals('2011-12-01', String.valueOf(updatedAmendment.Introduced_Date__c));
        System.assertEquals(System.today().format(), updatedAmendment.Date_Bill_Info_Updated__c.date().format());
        System.assertEquals(sponsor.Id, updatedAmendment.Sponsor__c);
        System.assertEquals('S00001', updatedAmendment.Sponsor_Info__c);
        
        List<Corresponding_Bill__c> cbjuncts = [select Legislation1__c from Corresponding_Bill__c where Legislation2__c = :testAmendment.Id];
        // Old junction for testAnotherBill deleted, old junction for testBill kept
        System.assertEquals(1, cbjuncts.size());
        System.assertEquals(cbjunction1.Id, cbjuncts[0].Id);
        
        // Amendment related to testAnotherBill
        LegislationAction.updateAmendmentRecord(testAmendment.Id, 'h789-112', 'To make it even better', 'Passed', null, '2011-12-01T16:00:00Z', 'S00001');
        
        updatedAmendment = [select Bill_Title__c, Latest_Major_Action__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c, Sponsor_Info__c, Status__c from Legislation__c where Id = :testAmendment.Id limit 1];
        System.assertEquals('To make it even better', updatedAmendment.Bill_Title__c);
        System.assertEquals('Passed', updatedAmendment.Status__c);
        System.assertEquals(null, updatedAmendment.Latest_Major_Action__c);
        System.assertEquals('2011-12-01', String.valueOf(updatedAmendment.Introduced_Date__c));
        System.assertEquals(System.today().format(), updatedAmendment.Date_Bill_Info_Updated__c.date().format());
        System.assertEquals(sponsor.Id, updatedAmendment.Sponsor__c);
        System.assertEquals('S00001', updatedAmendment.Sponsor_Info__c);
        
        cbjuncts = [select Legislation1__c from Corresponding_Bill__c where Legislation2__c = :testAmendment.Id];
        // Old junction for testBill deleted, new junction for testAnotherBill created
        System.assertEquals(1, cbjuncts.size());
        System.assertEquals(testAnotherBill.Id, cbjuncts[0].Legislation1__c);
    }
    
    static testMethod void testUpdateBillRecord() {
        Legislation__c testBill = new Legislation__c(Bill_Prefix__c = 'S', Bill_Number__c = 614, Congressional_Session__c = '112');
        insert testBill;
        
        Contact sponsor = new Contact(FirstName = 'Test', LastName = 'Sponsor', Bioguide_ID__c = 'S00001');
        insert sponsor;
        
        Contact[] cosponsors = new Contact[] {
            new Contact(FirstName = 'Test', LastName = 'Cosponsor 1', Bioguide_ID__c = 'CS00001'), 
            new Contact(FirstName = 'Test', LastName = 'Cosponsor 2', Bioguide_ID__c = 'CS00077'), 
            new Contact(FirstName = 'Test', LastName = 'Cosponsor 3', Bioguide_ID__c = 'CS00099')
        };
        insert cosponsors;
        
        Contact_Leg_junction__c csjunction1 = new Contact_Leg_junction__c(Contact__c = cosponsors[0].Id, Legislation__c = testBill.Id, Role__c = 'Co-sponsor');
        insert csjunction1;
        
        Contact_Leg_junction__c csjunction2 = new Contact_Leg_junction__c(Contact__c = cosponsors[1].Id, Legislation__c = testBill.Id, Role__c = 'Co-sponsor');
        insert csjunction2;
        
        Contact_Leg_junction__c otherjunction = new Contact_Leg_junction__c(Contact__c = cosponsors[0].Id, Legislation__c = testBill.Id, Role__c = 'Other');
        insert otherjunction;
        
        LegislationAction.updateBillRecord(testBill.Id, 'H.R.5652-112','Test title', 'Pending President signature', 'Passed in Senate', 'Great summary', '2011-02-10T12:00:00Z', 'S00001', new Set<String> { 'CS00077', 'CS00099' });
        
        Legislation__c updatedBill = [select Bill_Title__c, Cosponsors__c, Latest_Major_Action__c, Summary__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c, Sponsor_Info__c, Status__c from Legislation__c where Id = :testBill.Id limit 1];
        System.assertEquals('Test title', updatedBill.Bill_Title__c);
        System.assertEquals('Pending President signature', updatedBill.Status__c);
        System.assertEquals('Passed in Senate', updatedBill.Latest_Major_Action__c);
        System.assertEquals('Great summary', updatedBill.Summary__c);
        System.assertEquals('2011-02-10', String.valueOf(updatedBill.Introduced_Date__c));
        System.assertEquals(System.today().format(), updatedBill.Date_Bill_Info_Updated__c.date().format());
        System.assertEquals(sponsor.Id, updatedBill.Sponsor__c);
        System.assertEquals('S00001', updatedBill.Sponsor_Info__c);
        System.assertEquals(true, updatedBill.Cosponsors__c.contains('CS00077'));
        System.assertEquals(true, updatedBill.Cosponsors__c.contains('CS00099'));
        
        List<Contact_Leg_junction__c> csjuncts = new List<Contact_Leg_junction__c>();
        List<Contact_Leg_junction__c> otherjuncts = new List<Contact_Leg_junction__c>();
        for (Contact_Leg_junction__c clj : [select Contact__c, Role__c from Contact_Leg_junction__c where Legislation__c = :testBill.Id]) {
            if (clj.Role__c == 'Co-sponsor')
                csjuncts.add(clj);
            else
                otherjuncts.add(clj);
        }
        // Old cosponsor junction for cosponsors[0] deleted, old junction for cosponsors[1] kept, 1 new junction for cosponsors[2] inserted
        System.assertEquals(2, csjuncts.size());
        if (csjuncts[0].Contact__c == cosponsors[1].Id) {
            System.assertEquals(csjunction2.Id, csjuncts[0].Id);    // old junction for cosponsors[1]
            System.assertEquals(cosponsors[2].Id, csjuncts[1].Contact__c);
        } else {
            System.assertEquals(cosponsors[2].Id, csjuncts[0].Contact__c);
            System.assertEquals(csjunction2.Id, csjuncts[1].Id);    // old junction for cosponsors[1]
            System.assertEquals(cosponsors[1].Id, csjuncts[1].Contact__c);
        }
        // Other junction unchanged
        System.assertEquals(1, otherjuncts.size());
        System.assertEquals(otherjunction.Id, otherjuncts[0].Id);
    }
    
}