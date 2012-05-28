public class LegislationUpdateControllerExt {
	
	private static Legislation__c legislation;
	
	public LegislationUpdateControllerExt(ApexPages.StandardController controller) {
		legislation = (Legislation__c)controller.getRecord();
	}
	
	public PageReference refresh() {
		if (legislation.Active__c)
			LegislationAction.getLegislationDetail(legislation);
		return new PageReference('/' + legislation.Id);
		//return new PageReference('/a0y/o');
	}
}