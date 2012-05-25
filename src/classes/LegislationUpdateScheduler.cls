global class LegislationUpdateScheduler implements Schedulable {
	
	global void execute(SchedulableContext sc) {
		// Execute amendment and bill records in separate batches as they call different web services API
		
		// Update active amendments
		LegislationUpdateBatchable legislationUpdate = new LegislationUpdateBatchable(LegislationUpdateBatchable.LegislationType.AMENDMENT);
		Database.executeBatch(legislationUpdate, 50);
		
		// Update active bills
		legislationUpdate = new LegislationUpdateBatchable(LegislationUpdateBatchable.LegislationType.BILL);
		Database.executeBatch(legislationUpdate, 50);
	}
	
}