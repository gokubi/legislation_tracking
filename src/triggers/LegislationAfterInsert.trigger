/*
 * Fetch details of the legislation with a web services callout and update the Legislation record
 *
 * WH, Exponent Partners, 2011
 */
trigger LegislationAfterInsert on Legislation__c (after insert) {
	// Do not apply to bulk insert because of governor limit on web services callout
	if (Trigger.size == 1) {
		LegislationAction.getLegislationDetail(Trigger.new[0]);
	}
}