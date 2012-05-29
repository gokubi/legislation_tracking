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
/*
 * Fetch details of all active legislation with a web services callout and update the Legislation records in batch
 * Handle amendments and bills in separate batches
 *
 * WH, Exponent Partners, 2011
 */
global class LegislationUpdateBatchable implements Database.Batchable<sObject>, Database.AllowsCallouts {
	
	global enum LegislationType { AMENDMENT, BILL }
	
	global final String query;
	global final LegislationType legType;
	
	global LegislationUpdateBatchable() {
		query = 'select Id, Name from Legislation__c where Active__c = true';
	}
	
	global LegislationUpdateBatchable(LegislationType legType) {
		this.legType = legType;
		if (legType == LegislationType.AMENDMENT) {
			query = 'select Id, Name from Legislation__c where Active__c = true and Bill_Prefix__c in (\'HAMDT\', \'SAMDT\')';
		} else {
			// legType == LegislationType.BILL
			query = 'select Id, Name from Legislation__c where Active__c = true and Bill_Prefix__c not in (\'HAMDT\', \'SAMDT\')';
		}
	}
	
	global Database.QueryLocator start(Database.BatchableContext bc) {
		return Database.getQueryLocator(query);
	}
	
	global void execute(Database.BatchableContext bc, List<sObject> scope) {
		if (legType == LegislationType.AMENDMENT) {
			batchUpdateAmendmentRecords(scope, null);
		} else {
			// legType == LegislationType.BILL
			batchUpdateBillRecords(scope, null);
		}
	}
	
	global void finish(Database.BatchableContext bc) {
		// Do nothing
	}
	
	// This method does the heavy lifting for execution of each batch of amendments
	public static void batchUpdateAmendmentRecords(List<sObject> scope, RealTimeCongressAPI api) {
		
		// Map lowercase Legislation name (viz. amendment_id in Real Time Congress API) to Legislation record
		Map<String, Legislation__c> amendmentIdToLegislationMap = new Map<String, Legislation__c>();
		
		// List of amendment_id's to pass to Real Time Congress API
		List<String> amendmentIdList = new List<String>();
		
		// Build legislation map and amendment_id list
		//	- Legislation__c.Name needs to be converted to lowercase with 'AMDT' removed to meet Real Time Congress API syntax for amendment_id
		Legislation__c leg;
		String amendmentId;
		for (sObject s : scope) {
			leg = (Legislation__c)s;
			amendmentId = leg.Name.replace('AMDT', '').toLowerCase();
			amendmentIdToLegislationMap.put(amendmentId, (Legislation__c)s);
			amendmentIdList.add(amendmentId);
		}
		
		// Return if nothing to process
		if (amendmentIdList.size() == 0) { return; }
		
		// Callout to Real Time Congress web services API
		//RealTimeCongressAPI api = new RealTimeCongressAPI();
		
		Boolean doUpdate;
		if (Test.isRunningTest()) {
			// An instance of RealTimeCongressAPI would be passed in for test purposes
			doUpdate = true;
		} else {
			// Callout to Real Time Congress web services API
			api = new RealTimeCongressAPI();
			doUpdate = api.getAmendments(amendmentIdList);
		}
		
		if (doUpdate) {
			
			// Build a map from bioguide_ids to Contact Ids for all legislators who are sponsors of these amendments
			Map<String, Id> bioguideToContactId = new Map<String, Id>();
			for (Contact c : [select Id, Bioguide_ID__c from Contact where Bioguide_ID__c in :api.legislators]) {
				bioguideToContactId.put(c.Bioguide_ID__c, c.Id);
			}
			
			// Update title, status, lastAction, introducedAt, sponsors on legislation
			Legislation__c l;
			RealTimeCongressAPI.LegInfo amendmentInfo;
			String title, status, lastAction, introducedAt, sponsorId;
			
			// List of legislation records to update
			List<Legislation__c> legislationsToUpdate = new List<Legislation__c>();
			// Set of bill_id's for corresponsing bills of this batch of amendments, converted to Legislation naming convention (bill prefix in upper case)
			Set<String> cBillNames = new Set<String>();
			
			// First update title, status, lastAction, introducedAt and sponsors
			for (String aId : amendmentIdList) {
				amendmentInfo = api.legDetailMap.get(aId);
				if (amendmentInfo != null) {
					l = amendmentIdToLegislationMap.get(aId);
					
					if (amendmentInfo.billId != null) {
						// Legislation naming convention in SF uses prefix in upper case vs lower case in RTC API
						cBillNames.add(amendmentInfo.billId.toUpperCase());
					}
					
					title = amendmentInfo.getPurpose();
					l.Bill_Title__c = (title != null  && title.length() > Legislation__c.Bill_Title__c.getDescribe().getLength()) ? title.substring(0, Legislation__c.Bill_Title__c.getDescribe().getLength()) : title;
					
					status = amendmentInfo.getStatus();
					l.Status__c = (status != null  && status.length() > Legislation__c.Status__c.getDescribe().getLength()) ? status.substring(0, Legislation__c.Status__c.getDescribe().getLength()) : status;
					
					lastAction = amendmentInfo.getLastAction();
					l.Latest_Major_Action__c = (lastAction != null  && lastAction.length() > Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) ? lastAction.substring(0, Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) : lastAction;
					
					// Convert date time string like 2011-02-10T12:00:00Z into a Date object
					introducedAt = amendmentInfo.introducedAt;
					l.Introduced_Date__c = (introducedAt != null) ? Date.valueOf(introducedAt.substring(0, introducedAt.indexOf('T'))) : null;
					
					l.Date_Bill_Info_Updated__c = System.now();
					
					sponsorId = amendmentInfo.sponsorId;
					l.Sponsor__c = bioguideToContactId.get(sponsorId);
					l.Sponsor_Info__c = sponsorId;
					
					legislationsToUpdate.add(l);
				}
			}
			
			// Build a map from cBillNames to Legislation Ids for corresponding bills of these amendments
			Map<String, Id> cBillNameToLegislationId = new Map<String, Id>();
			for (Legislation__c cl : [select Id, Name from Legislation__c where Name in :cBillNames]) {
				cBillNameToLegislationId.put(cl.Name, cl.Id);
			}
			
			// Insert junction to corresponding bill if not already there
			
			List<Corresponding_Bill__c> relatedBillJunctionsToInsert = new List<Corresponding_Bill__c>();
			List<Corresponding_Bill__c> relatedBillJunctionsToDelete = new List<Corresponding_Bill__c>();
			
			// Match existing corresponding bill junction records to corresponding bill_id's in Real Time Congress results
			//	- Mark those existing junction records not matched against corresponding bill_id's for removal
			for (Corresponding_Bill__c cb : [select Legislation1__c, Legislation2__r.Name from Corresponding_Bill__c where Legislation2__c in :amendmentIdToLegislationMap.values()]) {
				String aIdKey = cb.Legislation2__r.Name.replace('AMDT', '').toLowerCase();
				amendmentInfo = api.legDetailMap.get(aIdKey);
				if (cb.Legislation1__c == cBillNameToLegislationId.get(amendmentInfo.billId.toUpperCase())) {
					// This Legislation matches the corresponding bill for the amendment in question as returned from RTC API
					//	- Keep this junction, no need to create new corresponding bill junction for this amendment
					amendmentIdToLegislationMap.remove(aIdKey);
				} else {
					// Mark this unmatched corresponding bill junction for removal
					relatedBillJunctionsToDelete.add(cb);
				}
			}
			
			// Create new junction records for those corresponding bills that are not matched to existing junction records
			Id mainLegId;
			for (String aId : amendmentIdToLegislationMap.keySet()) {
				amendmentInfo = api.legDetailMap.get(aId);
				// RTC API is expected to return a corresponding bill_id but that Legislation record may not exist in SF
				if (amendmentInfo.billId != null && (mainLegId = cBillNameToLegislationId.get(amendmentInfo.billId.toUpperCase())) != null) {
					relatedBillJunctionsToInsert.add( new Corresponding_Bill__c(
													Legislation1__c = mainLegId,
													Legislation2__c = amendmentIdToLegislationMap.get(aId).Id) );
				}
			}
			
			// Update legislation and corresponding bill junction records
			if (!legislationsToUpdate.isEmpty())
				update legislationsToUpdate;
			
			if (!relatedBillJunctionsToInsert.isEmpty())
				insert relatedBillJunctionsToInsert;
			
			if (!relatedBillJunctionsToDelete.isEmpty())
				delete relatedBillJunctionsToDelete;
		}
	}
	
	// This method does the heavy lifting for execution of each batch of bills
	public static void batchUpdateBillRecords(List<sObject> scope, RealTimeCongressAPI api) {
		
		// Map lowercase Legislation name (viz. bill_id in Real Time Congress API) to Legislation record
		Map<String, Legislation__c> billIdToLegislationMap = new Map<String, Legislation__c>();
		
		// List of bill_id's to pass to Real Time Congress API
		List<String> billIdList = new List<String>();
		
		// Build legislation map and bill_id list
		//	- Legislation__c.Name needs to be converted to lowercase to meet Real Time Congress API syntax for bill_id
		Legislation__c leg;
		String billId;
		for (sObject s : scope) {
			leg = (Legislation__c)s;
			billId = leg.Name.toLowerCase();
			billIdToLegislationMap.put(billId, (Legislation__c)s);
			billIdList.add(billId);
		}
		
		// Return if nothing to process
		if (billIdList.size() == 0) { return; }
		
		// Callout to Real Time Congress web services API
		//RealTimeCongressAPI api = new RealTimeCongressAPI();
		
		Boolean doUpdate;
		if (Test.isRunningTest()) {
			// An instance of RealTimeCongressAPI would be passed in for test purposes
			doUpdate = true;
		} else {
			// Callout to Real Time Congress web services API
			api = new RealTimeCongressAPI();
			doUpdate = api.getBills(billIdList);
		}
		
		if (doUpdate) {
			
			// Build a map from bioguide_ids to Contact Ids for all legislators who are sponsors or cosponsors of these bills
			Map<String, Id> bioguideToContactId = new Map<String, Id>();
			for (Contact c : [select Id, Bioguide_ID__c from Contact where Bioguide_ID__c in :api.legislators]) {
				bioguideToContactId.put(c.Bioguide_ID__c, c.Id);
			}
			
			// Update title, status, lastAction, summary, introducedAt, sponsors and cosponsors on legislation
			Legislation__c l;
			RealTimeCongressAPI.LegInfo billInfo;
			String title, status, lastAction, introducedAt, sponsorId;
			
			// List of legislation records to update
			List<Legislation__c> legislationsToUpdate = new List<Legislation__c>();
			
			// First update title, status, lastAction, summary, introducedAt and sponsors
			for (String bId : billIdList) {
				billInfo = api.legDetailMap.get(bId);
				if (billInfo != null) {
					l = billIdToLegislationMap.get(bId);
					
					// Use short_title if exists otherwise official_title
					title = (billInfo.getShortTitle() != null) ? billInfo.getShortTitle() : billInfo.getOfficialTitle();
					l.Bill_Title__c = (title != null  && title.length() > Legislation__c.Bill_Title__c.getDescribe().getLength()) ? title.substring(0, Legislation__c.Bill_Title__c.getDescribe().getLength()) : title;
					
					status = billInfo.getStatus();
					l.Status__c = (status != null  && status.length() > Legislation__c.Status__c.getDescribe().getLength()) ? status.substring(0, Legislation__c.Status__c.getDescribe().getLength()) : status;
					
					lastAction = billInfo.getLastAction();
					l.Latest_Major_Action__c = (lastAction != null  && lastAction.length() > Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) ? lastAction.substring(0, Legislation__c.Latest_Major_Action__c.getDescribe().getLength()) : lastAction;
					
					l.Summary__c = billInfo.summary;
					
					// Convert date time string like 2011-02-10T12:00:00Z into a Date object
					introducedAt = billInfo.introducedAt;
					l.Introduced_Date__c = (introducedAt != null) ? Date.valueOf(introducedAt.substring(0, introducedAt.indexOf('T'))) : null;
					
					l.Date_Bill_Info_Updated__c = System.now();
					
					sponsorId = billInfo.sponsorId;
					l.Sponsor__c = bioguideToContactId.get(sponsorId);
					l.Sponsor_Info__c = sponsorId;
					
					// Not necessary to update Legislation__c.Cosponsors__c; for debug purposes only
					if (!billInfo.cosponsorIds.isEmpty()) {
						String cosponsors = '';
						for (String ci : billInfo.cosponsorIds) { cosponsors = cosponsors + ci + ', '; }
						l.Cosponsors__c = (cosponsors != '') ? cosponsors.subString(0, cosponsors.length()-2) : null;
					}
					
					legislationsToUpdate.add(l);
				}
			}
			
			// Update cosponsor junction records
			List<Contact_Leg_junction__c> relatedContactsToInsert = new List<Contact_Leg_junction__c>();
			List<Contact_Leg_junction__c> relatedContactsToDelete = new List<Contact_Leg_junction__c>();
			
			// Match existing junction records to cosponsorIds in Real Time Congress results
			//	- Mark those existing junction records not matched against cosponsorIds for removal
			for (Contact_Leg_junction__c clj : [select Contact__r.Bioguide_ID__c, Legislation__r.Name from Contact_Leg_junction__c where Role__c = 'Co-sponsor' and Legislation__c in :billIdToLegislationMap.values()]) {
				String bIdKey = clj.Legislation__r.Name.toLowerCase();
				billInfo = api.legDetailMap.get(bIdKey);
				if (!billInfo.cosponsorIds.remove(clj.Contact__r.Bioguide_ID__c)) {
					// This bioguide_id is not in the cosponsorIds list for the bill in question
					relatedContactsToDelete.add(clj);
				}
			}
			
			// Create new junction records for those cosponsorIds that are not matched to existing junction records
			for (RealTimeCongressAPI.LegInfo bi : api.legDetailMap.values()) {
				for (String cosponsor : bi.cosponsorIds) {
					// Only create new junction records if cosponsor matches an existing Contact by bioguide_id
					if (bioguideToContactId.get(cosponsor) != null)
						relatedContactsToInsert.add(new Contact_Leg_junction__c(
														Contact__c = bioguideToContactId.get(cosponsor), 
														Legislation__c = billIdToLegislationMap.get(bi.billId).Id, 
														Role__c = 'Co-sponsor'));
				}
			}
			
			// Update legislation and cosponsor junction records
			if (!legislationsToUpdate.isEmpty())
				update legislationsToUpdate;
			
			if (!relatedContactsToInsert.isEmpty())
				insert relatedContactsToInsert;
			
			if (!relatedContactsToDelete.isEmpty())
				delete relatedContactsToDelete;
		}
	}
	
}