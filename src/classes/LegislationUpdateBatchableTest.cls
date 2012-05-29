/*
    Copyright (c) 2009, Salesforce.com Foundation
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the Salesforce.com Foundation nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
 * Test LegislationUpdateBatchable.cls
 */
@isTest
private class LegislationUpdateBatchableTest {

	static testMethod void testBatchUpdateAmendmentRecords() {
		
		// Set up legislator contacts and legislation
		List<Contact> reps = new List<Contact> {
			new Contact(FirstName = 'Test', LastName = 'Legislator 0', Bioguide_ID__c = 'H0001'),	// Sponsor for 's246-112'
			new Contact(FirstName = 'Test', LastName = 'Legislator 1', Bioguide_ID__c = 'H0002'),	// Sponsor for 'h468-112'
			new Contact(FirstName = 'Test', LastName = 'Legislator 2', Bioguide_ID__c = 'S0003'),
			new Contact(FirstName = 'Test', LastName = 'Legislator 3')
		};
		insert reps;
		
		// Active bill #1
		Legislation__c bill1 = new Legislation__c(Active__c = true, Name = 'S123-112', Bill_Prefix__c = 'S', Bill_Number__c = 123, Congressional_Session__c = '112');
		insert bill1;
		
		// Active bill #2
		Legislation__c bill2 = new Legislation__c(Active__c = true, Name = 'HR234-112', Bill_Prefix__c = 'HR', Bill_Number__c = 234, Congressional_Session__c = '112');
		insert bill2;
		
		// Active amendment #1 (related to bill #1) that will be updated - update Sponsor to reps[0], delete corresponding bill junction cbs[1] to bill2
		Legislation__c amend1 = new Legislation__c(Active__c = true, Name = 'SAMDT246-112', Bill_Prefix__c = 'SAMDT', Bill_Number__c = 246, Congressional_Session__c = '112', Sponsor__c = reps[3].Id);
		insert amend1;
		
		// Active amendment #2 (related to bill #2) that will be updated - update Sponsor to reps[1], insert corresponding bill junction to bill2
		Legislation__c amend2 = new Legislation__c(Active__c = true, Name = 'HAMDT468-112', Bill_Prefix__c = 'HAMDT', Bill_Number__c = 468, Congressional_Session__c = '112');
		insert amend2;
		
		// Pre-existing corresponding bill junction records
		List<Corresponding_Bill__c> cbs = new List<Corresponding_Bill__c> {
			new Corresponding_Bill__c(Legislation1__c = bill1.Id, Legislation2__c = amend1.Id),		// keep this matched bill junction
			new Corresponding_Bill__c(Legislation1__c = bill2.Id, Legislation2__c = amend1.Id)		// remove this unmatched bill junction
		};
		insert cbs;
		
		// Set up fake Real Time Congress API response for bills
		RealTimeCongressAPI api = new RealTimeCongressAPI();
		api.recordCount = 2;
		api.legislators = new Set<String> { 'H0001', 'H0002' };
		RealTimeCongressAPI.LegInfo amendmentInfo1 = new RealTimeCongressAPI.LegInfo('s246-112', 's123-112', 'Status 1', 'Purpose 1', 'Last action 1', '2011-12-01T14:00:00Z', 'H0001');
		RealTimeCongressAPI.LegInfo amendmentInfo2 = new RealTimeCongressAPI.LegInfo('h468-112', 'hr234-112', 'Status 2', 'Purpose 2', null, null, 'H0002');
		api.legDetailMap = new Map<String, RealTimeCongressAPI.LegInfo> { 's246-112' => amendmentInfo1, 'h468-112' => amendmentInfo2 };
		
		// Test batchUpdateAmendmentRecords()
		Test.startTest();
		LegislationUpdateBatchable.batchUpdateAmendmentRecords(new List<sObject> { amend1, amend2 }, api);
		Test.stopTest();
		
		Legislation__c leg = [select Bill_Title__c, Status__c, Latest_Major_Action__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c from Legislation__c where Id = :amend1.Id];
		
		System.assertEquals('Purpose 1', leg.Bill_Title__c);
		System.assertEquals('Status 1', leg.Status__c);
		System.assertEquals('Last action 1', leg.Latest_Major_Action__c);
		System.assertEquals('2011-12-01', String.valueOf(leg.Introduced_Date__c));
		System.assertEquals(System.today().format(), leg.Date_Bill_Info_Updated__c.date().format());
		System.assertEquals(reps[0].Id, leg.Sponsor__c);
		
		// 1 matched junction kept, 1 unmatched junction deleted
		List<Corresponding_Bill__c> cbjunctions = [select Id, Legislation1__c from Corresponding_Bill__c where Legislation2__c = :amend1.Id];
		
		System.assertEquals(1, cbjunctions.size());
		System.assertEquals(cbs[0].Id, cbjunctions[0].Id);				// matched junction kept
		System.assertEquals(bill1.Id, cbjunctions[0].Legislation1__c);	// kept junction unchanged
		
		leg = [select Bill_Title__c, Status__c, Latest_Major_Action__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c from Legislation__c where Id = :amend2.Id];
		
		System.assertEquals('Purpose 2', leg.Bill_Title__c);
		System.assertEquals('Status 2', leg.Status__c);
		System.assertEquals(null, leg.Latest_Major_Action__c);
		System.assertEquals(null, String.valueOf(leg.Introduced_Date__c));
		System.assertEquals(System.today().format(), leg.Date_Bill_Info_Updated__c.date().format());
		System.assertEquals(reps[1].Id, leg.Sponsor__c);
		
		// 1 new junction inserted
		cbjunctions = [select Id, Legislation1__c from Corresponding_Bill__c where Legislation2__c = :amend2.Id];
		
		System.assertEquals(1, cbjunctions.size());
		System.assertEquals(bill2.Id, cbjunctions[0].Legislation1__c);
	}
	
	static testMethod void testBatchUpdateBillRecords() {
		
		// Set up legislator contacts and legislation
		List<Contact> reps = new List<Contact> {
			new Contact(FirstName = 'Test', LastName = 'Legislator 0', Bioguide_ID__c = 'H0001'),	// Sponsor for 'hr123-112'
			new Contact(FirstName = 'Test', LastName = 'Legislator 1', Bioguide_ID__c = 'H0002'),	// Co-sponsor for 'hr123-112'
			new Contact(FirstName = 'Test', LastName = 'Legislator 2', Bioguide_ID__c = 'S0003'),	// Co-sponsor for 'hr123-112'
			new Contact(FirstName = 'Test', LastName = 'Legislator 3')
		};
		insert reps;
		
		// Active bill that will be updated - update Sponsor to reps[0], add missing co-sponsor reps[1], delete co-sponsor junction cljs[0]
		Legislation__c bill1 = new Legislation__c(Active__c = true, Name = 'HR123-112', Bill_Prefix__c = 'HR', Bill_Number__c = 123, Congressional_Session__c = '112', Sponsor__c = reps[3].Id);
		insert bill1;
		
		// Pre-existing contact legislation junction records
		List<Contact_Leg_junction__c> cljs = new List<Contact_Leg_junction__c> {
			new Contact_Leg_junction__c(Contact__c = reps[0].Id, Legislation__c = bill1.Id, Role__c = 'Co-sponsor'),		// remove this co-sponsor
			new Contact_Leg_junction__c(Contact__c = reps[2].Id, Legislation__c = bill1.Id, Role__c = 'Co-sponsor'),		// keep this co-sponsor
			new Contact_Leg_junction__c(Contact__c = reps[3].Id, Legislation__c = bill1.Id, Role__c = 'Other')			// keep this non-cosponsor
		};
		insert cljs;
		
		// Active bill that will be updated - use official title when there is no short title
		Legislation__c bill2 = new Legislation__c(Active__c = true, Name = 'S456-112', Bill_Prefix__c = 'S', Bill_Number__c = 456, Congressional_Session__c = '112');
		insert bill2;
		
		// Set up fake Real Time Congress API response for bills
		RealTimeCongressAPI api = new RealTimeCongressAPI();
		api.recordCount = 2;
		api.legislators = new Set<String> { 'H0001', 'H0002', 'S0003' };
		RealTimeCongressAPI.LegInfo billInfo1 = new RealTimeCongressAPI.LegInfo('hr123-112', 'Passed in House', 'Test House Bill Official', 'Test House Bill Short', 'Sent to Senate', 'Great summary', '2011-02-10T12:00:00Z', 
			'H0001', new Set<String> { 'H0002', 'S0003' });
		RealTimeCongressAPI.LegInfo billInfo2 = new RealTimeCongressAPI.LegInfo('s456-112', 'Voted in Senate', 'Test Senate Bill Official', null, null, null, null, null, null);
		api.legDetailMap = new Map<String, RealTimeCongressAPI.LegInfo> { 'hr123-112' => billInfo1, 's456-112' => billInfo2 };
		
		// Test batchUpdateBillRecords()
		Test.startTest();
		LegislationUpdateBatchable.batchUpdateBillRecords(new List<sObject> { bill1, bill2 }, api);
		Test.stopTest();
		
		Legislation__c leg = [select Bill_Title__c, Status__c, Latest_Major_Action__c, Summary__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c from Legislation__c where Id = :bill1.Id];
		
		System.assertEquals('Test House Bill Short', leg.Bill_Title__c);
		System.assertEquals('Passed in House', leg.Status__c);
		System.assertEquals('Sent to Senate', leg.Latest_Major_Action__c);
		System.assertEquals('Great summary', leg.Summary__c);
		System.assertEquals('2011-02-10', String.valueOf(leg.Introduced_Date__c));
		System.assertEquals(System.today().format(), leg.Date_Bill_Info_Updated__c.date().format());
		System.assertEquals(reps[0].Id, leg.Sponsor__c);
		
		List<Contact_Leg_junction__c> cljunctions = [select Contact__c, Role__c from Contact_Leg_junction__c where Legislation__c = :bill1.Id];
		
		System.assertEquals(3, cljunctions.size());
		for (Contact_Leg_junction__c cj : cljunctions) {
			if (cj.Role__c == 'Co-sponsor') {
				// New junction for reps[1] inserted'; existing junction cljs[1] for reps[2] kept; old junction cljs[0] for reps[0] removed
				if (cj.Id != cljs[1].Id) {
					System.assertNotEquals(cljs[0].Id, cj.Id);
					System.assertEquals(reps[1].Id, cj.Contact__c);
				}
			} else {
				// 'Other' junction kept intact
				System.assertEquals(reps[3].Id, cj.Contact__c);
				System.assertEquals('Other', cj.Role__c);
			}
		}
		
		leg = [select Bill_Title__c, Status__c, Latest_Major_Action__c, Summary__c, Introduced_Date__c, Date_Bill_Info_Updated__c, Sponsor__c from Legislation__c where Id = :bill2.Id];
		
		System.assertEquals('Test Senate Bill Official', leg.Bill_Title__c);
		System.assertEquals('Voted in Senate', leg.Status__c);
		System.assertEquals(null, leg.Latest_Major_Action__c);
		System.assertEquals(null, leg.Summary__c);
		System.assertEquals(null, String.valueOf(leg.Introduced_Date__c));
		System.assertEquals(System.today().format(), leg.Date_Bill_Info_Updated__c.date().format());
		System.assertEquals(null, leg.Sponsor__c);
		
		cljunctions = [select Contact__c, Role__c from Contact_Leg_junction__c where Legislation__c = :bill2.Id];
		
		System.assertEquals(0, cljunctions.size());
	}
}