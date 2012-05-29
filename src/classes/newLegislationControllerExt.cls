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
public with sharing class newLegislationControllerExt {

	public Legislation__c legislation {get;set;}
	public String thomasURL {get;set;}
	public String legislationInsertErrorText {get;set;}
	public String URLParseErrorText {get;set;}
	public Boolean legislationInsertError {get;set;}
	public Boolean URLParseError {get;set;}

	public newLegislationControllerExt (ApexPages.StandardController controller) {
		legislation = (Legislation__c)controller.getRecord();
		legislation.bill_Number__c=0;
		thomasURL = ApexPages.currentPage().getParameters().get('thomas');
		URLParseErrorText = null;
		legislationInsertErrorText = null;
		legislationInsertError = false;
		URLParseError = false;
		
	}
	//http://thomas.loc.gov/cgi-bin/bdquery/z?d112:h.r.05326:
	private String thomasBillPrefix (String thomasURL) {
		return  thomasURL.subString(41,3);
	}
	
	//http://thomas.loc.gov/cgi-bin/bdquery/z?d112:h.r.05326:
	private String thomasBillNumber (String thomasURL) {
		return  thomasURL.subString(thomasURL.length()-5,5);
	}
	
	private String thomasCongressionalSession;
	private Integer thomasBillNumber;
	private String thomasBillPrefix;
	
	//http://thomas.loc.gov/cgi-bin/bdquery/z?d112:h.r.05326:
	private boolean parseThomas (String thomasURL) {
		try{
			thomasURL = thomasURL.replace('?',':');
			List<String> URLParts = thomasURL.Split(':',0);
			system.debug(URLParts);
			thomasCongressionalSession = URLParts[2].subString(1,4);
			system.debug(thomasCongressionalSession);
			
			String prefixNumberString = URLParts[3].replaceFirst('0',':');
			List<String> prefixNumber = prefixNumberString.split(':', 0);
			system.debug(prefixNumber);
			thomasBillPrefix = prefixNumber[0].replace('.','').toUpperCase();
			thomasBillNumber = Integer.valueOf(prefixNumber[1]);
			URLParseErrorText = null;
			URLParseError = false;
		//	system.debug('session:' + thomasCongressionalSession + ': prefix :' + thomasBillPrefix + ': number: ' + thomasBillNumber);
			return true;
		} catch(Exception e) {
			URLParseErrorText = 'Cannot Parse Thomas URL. Please enter by hand.';
			legislationInsertErrorText = null;
			legislationInsertError = false;
			URLParseError = true;
            return false;
		}
	} 
	
	public PageReference autoParseThomas(){
		if(thomasURL!=null){
			try{
				return insertLegislation();
			} catch (Exception e){
				URLParseErrorText = 'Cannot Parse Thomas URL. Please enter by hand.';
			legislationInsertErrorText = null;
			legislationInsertError = false;
			URLParseError = true;
				return null;
			}
		} else {
			return null;
		}
	}
	
	public PageReference insertLegislation (){
		//Active__c
		//name
		legislation.Active__c = true;
		legislation.Name = '-';
		
		//parse ThomasURL
		if(thomasURL!=null&&thomasURL!=''){ 
			Boolean successfulParse = parseThomas(thomasURL);
			if (successfulParse){
				legislation.Bill_Prefix__c = thomasBillPrefix;
				legislation.Bill_Number__c = thomasBillNumber;
				legislation.Congressional_Session__c = thomasCongressionalSession;
				
			} else {
				return null;
			}
		}
		if(legislation.Bill_Prefix__c!=null){
			try {
				insert legislation;
				legislationInsertErrorText = null;
				return new PageReference('/' + legislation.id);	
			} catch (Exception e) {
				legislationInsertErrorText = 'There is a duplicate record!';	
				 URLParseErrorText = null;
				 legislationInsertError = true;
				URLParseError = false;	
				 return null;
			}	
			
		} else {
			return null;
		}
	}
}