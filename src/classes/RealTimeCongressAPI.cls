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
 * Get information about legislators, bills, amendments and roll call votes using the RESTful JSON Real Time Congress API
 * Real Time Congress API documentation @ http://services.sunlightlabs.com/docs/Real_Time_Congress_API/
 * 
 * getAmendment() gets a single amendment
 * http://api.realtimecongress.org/api/v1/amendments.json?apikey=[APIKEY]&amendment_id=[<prefix><amendment#>-<session#>]&sections=amendment_id,bill_id,purpose,sponsor_id,actions.text,state,offered_at
 *
 * getAmendments() gets a list of amendments by amendment ids
 * http://api.realtimecongress.org/api/v1/amendments.json?apikey=[APIKEY]&amendment_id__in=[id1|id2]&sections=amendment_id,bill_id,purpose,sponsor_id,actions.text,state,offered_at
 * 
 * getBill() gets a single bill
 * http://api.realtimecongress.org/api/v1/bills.json?apikey=[APIKEY]&bill_id=[<prefix><bill#>-<session#>]&sections=bill_id,official_title,short_title,sponsor_id,cosponsors_count,cosponsor_ids,last_action.text,state,summary,introduced_at
 *
 * getBills() gets a list of bills by bill ids
 * http://api.realtimecongress.org/api/v1/bills.json?apikey=[APIKEY]&bill_id__in=[id1|id2]&sections=bill_id,official_title,short_title,sponsor_id,cosponsors_count,cosponsor_ids,last_action.text,state,summary,introduced_at
 *
 * WH, Exponent Partners, 2011
 */
public class RealTimeCongressAPI {
    
    private final String Endpoint;
    private final String APIKey;
    
    private static final String PageSize = '200';
    private static final String AmendmentSectionFilter = 'amendment_id,bill_id,purpose,sponsor_id,actions.text,state,offered_at';
    
    // Include 'summary' in the API callout when a more efficient native JSON parser is available for use
    // In the meantime, bills (e.g. hr3590-111) with long summary can cause this JSON parser to exceed Apex script statement limit
    //private static final String BillSectionFilter = 'bill_id,official_title,short_title,sponsor_id,cosponsors_count,cosponsor_ids,last_action.text,state,summary,introduced_at';
    private static final String BillSectionFilter = 'bill_id,official_title,short_title,sponsor_id,cosponsors_count,cosponsor_ids,last_action.text,state,introduced_at';
    
    private static final String VotesSectionFilter = 'result,roll_type,vote_type,voted_at,roll_id,votes,voter_ids';
    
    
    // Info retrieved for each legislation (amendment, bill)
    // Total number of amendments or bills returned in this API call
    public Integer recordCount;
    // Set of bioguide ids of all legislators who are sponsors or copsonsors of the bills fetched in this API call
    public Set<String> legislators;
    // Map from amendment_id or bill_id to LegInfo containing details of each amendment or bill
    public Map<String, LegInfo> legDetailMap;
    
    public class LegInfo {
        public String amendmentId { get; private set; }     // amendment only
        public String billId { get; private set; }
        public String summary { get; private set; }         // bill only
        public String introducedAt { get; private set; }
        public String sponsorId { get; private set; }
        public Set<String> cosponsorIds { get; set; }       // bill only
        //vote only
        public String roll_id;
        public String result;
        public String roll_type;
        public String voted_at;
        public String vote_type;
        public List<VoteInfo> voteinfo;
        public Map<string,List<VoteInfo>> voterIdMap;
        public Set<String> voterBioguideIds;
        
        private String status;
        private String officialTitle;                       // bill only
        private String shortTitle;                          // bill only
        private String purpose;                             // amendment only
        private String lastAction;
        
        public LegInfo() {
            this.amendmentId = null;
            this.billId = null;
            this.status = null;
            this.officialTitle = null;
            this.shortTitle = null;
            this.purpose = null;
            this.lastAction = null;
            this.summary = null;
            this.introducedAt = null;
            this.sponsorId = null;
            this.cosponsorIds = new Set<String>();
            this.voteInfo = new List<VoteInfo>();
            this.voterIdMap = new Map<string,List<VoteInfo>>();
            this.voterBioguideIds = new Set<String>();
        }
        
        
        
        // This is for use in amendment unit tests
        public LegInfo(String amendmentId, String billId, String status, String purpose, String lastAction, String introducedAt, String sponsorId) {
            this.amendmentId = amendmentId;
            this.billId = billId;
            this.status = status;
            this.purpose = purpose;
            this.lastAction = lastAction;
            this.introducedAt = introducedAt;
            this.sponsorId = sponsorId;
        }
        
        // This is for use in bill unit tests
        public LegInfo(String billId, String status, String officialTitle, String shortTitle, String lastAction, String summary, String introducedAt, String sponsorId, Set<String> cosponsorIds) {
            this.billId = billId;
            this.status = status;
            this.officialTitle = officialTitle;
            this.shortTitle = shortTitle;
            this.lastAction = lastAction;
            this.summary = summary;
            this.introducedAt = introducedAt;
            this.sponsorId = sponsorId;
            this.cosponsorIds = (cosponsorIds != null) ? cosponsorIds : new Set<String>();
        }
        
        // These getters return strings that can be manipulated by the caller, e.g. truncated to fit field sizes on sObjects
        public String getOfficialTitle() { return this.officialTitle; }
        public String getShortTitle() { return this.shortTitle; }
        public String getStatus() { return this.status; }
        public String getPurpose() { return this.purpose; }
        public String getLastAction() { return this.lastAction; }       
    }

    
    public RealTimeCongressAPI() {
        RealTimeCongress_Settings__c rs = RealTimeCongress_Settings__c.getInstance('RealTimeCongress');
        if (rs != null) {
            Endpoint = rs.Endpoint__c;
            APIKey = rs.APIKey__c;
        } else {
            // defaults
            Endpoint = 'http://api.realtimecongress.org/api/v1';
            APIKey = 'e875910d16c32457b55036aeaa2194f1';
        }
        
        recordCount = 0;
        legislators = new Set<String>();
        legDetailMap = new Map<String, LegInfo>();
    }
    
        
   public class VoteInfo {
        public String roll_id;
        public String bioguide;
        public String vote;
        
        public VoteInfo (String ri, String bg, String vt){
            roll_id = ri;
            bioguide = bg;
            vote = vt;
        }
   }
    
    // Get info for a single amendment
    // Returns true if successful, false otherwise
    public Boolean getAmendment(String amendmentPrefix, String amendmentNumber, String session) {
        
        Http h = new Http();
        HttpResponse res = new HttpResponse();
        
        List<String> keys = new List<String>{'amendment_id', 'sections'};
        List<String> vals = new List<String>{amendmentPrefix + amendmentNumber + '-' + session, AmendmentSectionFilter};
        HttpRequest req = buildRequest('amendments', keys, vals);
        
        if (!Test.isRunningTest()) {
            res = invokeWebService(h, req);
            System.debug('>>>>>>>>>> Result: ' + res.getBody());
        }
        
        return handleResponse(res);
        
    }
    
    // Get info for amendments specified by a list of amendment Ids in format: <prefix><amendment#>-<session#>
    // Returns true if successful, false otherwise
    public Boolean getAmendments(List<String> amendmentIdList) {
        
        Http h = new Http();
        HttpResponse res = new HttpResponse();
        
        // Format amendment ids
        String amendmentIds = '';
        for (String b : amendmentIdList) {
            amendmentIds += b + '|';
        }
        amendmentIds = amendmentIds.substring(0, amendmentIds.length()-1);
        
        List<String> keys = new List<String>{'amendment_id__in', 'per_page', 'sections'};
        List<String> vals = new List<String>{amendmentIds, PageSize, AmendmentSectionFilter};
        HttpRequest req = buildRequest('amendments', keys, vals);
        
        if (!Test.isRunningTest()) {
            res = invokeWebService(h, req);
            System.debug('>>>>>>>>>> Result: ' + res.getBody());
        }
        
        return handleResponse(res);
        
    }
    
    // Get info for a single legislation (bill)
    // Returns true if successful, false otherwise
    public Boolean getBill(String billPrefix, String billNumber, String session) {
        
        Http h = new Http();
        HttpResponse res = new HttpResponse();
        
        List<String> keys = new List<String>{'bill_id', 'sections'};
        List<String> vals = new List<String>{billPrefix + billNumber + '-' + session, BillSectionFilter};
        HttpRequest req = buildRequest('bills', keys, vals);
        
        if (!Test.isRunningTest()) {
            res = invokeWebService(h, req);
            System.debug('>>>>>>>>>> Result: ' + res.getBody());
        }
        
        return handleResponse(res);
        
    }
    
    // Get info for legislations (bills) specified by a list of bill Ids in format: <prefix><bill#>-<session#>
    // Returns true if successful, false otherwise
    public Boolean getBills(List<String> billIdList) {
        
        Http h = new Http();
        HttpResponse res = new HttpResponse();
        
        // Format bill ids
        String billIds = '';
        for (String b : billIdList) {
            billIds += b + '|';
        }
        billIds = billIds.substring(0, billIds.length()-1);
        
        List<String> keys = new List<String>{'bill_id__in', 'per_page', 'sections'};
        List<String> vals = new List<String>{billIds, PageSize, BillSectionFilter};
        HttpRequest req = buildRequest('bills', keys, vals);
        
        if (!Test.isRunningTest()) {
            res = invokeWebService(h, req);
            System.debug('>>>>>>>>>> Result: ' + res.getBody());
        }
        
        return handleResponse(res);
        
    }
 
 //Steve Andersen
    // Get info for legislations (bills) specified by a list of bill Ids in format: <prefix><bill#>-<session#>
    // Returns true if successful, false otherwise
    public Boolean getVotes(String billPrefix, String billNumber, String session) {
        
        Http h = new Http();
        HttpResponse res = new HttpResponse();
        
        List<String> keys = new List<String>{'bill_id',  'sections'};
        List<String> vals = new List<String>{billPrefix + billNumber + '-' + session, VotesSectionFilter};
        HttpRequest req = buildRequest('votes', keys, vals);
        
        if (!Test.isRunningTest()) {
            res = invokeWebService(h, req);
            System.debug('>>>>>>>>>> Result: ' + res.getBody());
        }
        
        return handleResponse(res);
        
    }
 //Steve Andersen
    
    // Build the Web Service request, packing a list of key-value pairs in query string
    private HttpRequest buildRequest(String method, List<String> keys, List<String> values) {
        
        // Build query string parameters
        Integer i = 0;
        String params = '';
        for (String k : keys) {
            params = params + '&' + k + '=' + EncodingUtil.urlEncode(values.get(i), 'UTF-8');
            i++;
        }
        
        // Compose the URL
        String url = Endpoint + '/' + method + '.json?apikey=' + APIKey + params;
        
        // Instantiate a new HTTP request, GET method, set endpoint
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        
        return req;
    }
    
    // Invoke the Web Service
    private HttpResponse invokeWebService(Http h, HttpRequest req) {
        HttpResponse res = new HttpResponse();
        try {
            res = h.send(req);
        } catch(System.CalloutException e) {
            System.debug('>>>>>>>>>> Callout error: '+ e);
            System.debug('>>>>>>>>>> ' + res.toString());
        }
        return res;
    }
    
    // Process the Web Service response
    private Boolean handleResponse(HttpResponse res) {
        String resBody = res.getBody();
        
        If (res.getStatusCode() != 200 || resBody == null || resBody == '') {
            System.debug('>>>>>>>>>> HTTP Status Code: ' + res.getStatusCode());
            return false;
        }
        
        // JSON parser does not handle line breaks well
        resBody = resBody.replace('\n', '');
        
        return parseResult(resBody);
    }
    
    // Parse JSON response from the Web Service and store info in legDetailMap
    private Boolean parseResult(String result) {
        
        // Reset data
        recordCount = 0;
        legislators = new Set<String>();
        legDetailMap = new Map<String, LegInfo>();
        
        try {
            // Parse the JSON result
            JSONObject json = new JSONObject(result);
            
            // Get number of amendments or bills in current page
            JSONObject page;
            if (json != null && json.getValue('page') != null) {
                page = json.getValue('page').obj;
                recordCount = (page.getValue('count') != null) ? page.getValue('count').num : 0;
                
                // Handle amendments
                if (recordCount > 0 && json.getValue('amendments') != null) {
                    
                    //{"count":1,"page":{"per_page":20,"count":1,"page":1},
                    //  "amendments":[
                    //      {"sponsor_id":"R000361",
                    //          "actions":[{"text":"Amendment SA 4843 proposed by Senator Bingaman for Senator Rockefeller."},{"text":"Amendment SA 4843 agreed to in Senate by Unanimous Consent."}],
                    //          "amendment_id":"s4843-111","offered_at":"2010-12-17T12:00:00Z","bill_id":"hr5116-111","state":"pass",
                    //          "purpose":"To invest in innovation through research and development, to improve competitiveness of the United States, and for other purposes."}
                    //      ]}
                    
                    // Get each amendment in the array
                    JSONObject amendment;
                    LegInfo amendmentDetail;
                    Integer actions_count;
                    
                    for (Integer i = 0; i < recordCount; i++) {
                        if (json.getValue('amendments').values[i] != null) {
                            amendment = json.getValue('amendments').values[i].obj;
                            amendmentDetail = new LegInfo();
                            
                            amendmentDetail.amendmentId = (amendment.getValue('amendment_id') != null) ? amendment.getValue('amendment_id').str : null;
                            
                            amendmentDetail.billId = (amendment.getValue('bill_id') != null) ? amendment.getValue('bill_id').str : null;
                            
                            amendmentDetail.status = (amendment.getValue('state') != null) ? amendment.getValue('state').str : null;
                            
                            amendmentDetail.purpose = (amendment.getValue('purpose') != null) ? amendment.getValue('purpose').str : null;
                            
                            amendmentDetail.introducedAt = (amendment.getValue('offered_at') != null) ? amendment.getValue('offered_at').str : null;
                            
                            amendmentDetail.sponsorId = (amendment.getValue('sponsor_id') != null) ? amendment.getValue('sponsor_id').str : null;
                            if (amendmentDetail.sponsorId != null) { legislators.add(amendmentDetail.sponsorId); }
                            
                            actions_count = (amendment.getValue('actions') != null) ? amendment.getValue('actions').values.size() : 0;
                            // Get last (latest) action text
                            if (actions_count > 0 && amendment.getValue('actions') != null) {
                                JSONObject last_action = (amendment.getValue('actions').values[actions_count-1] != null) ? amendment.getValue('actions').values[actions_count-1].obj : null;
                                amendmentDetail.lastAction = (last_action != null && last_action.getValue('text') != null) ? last_action.getValue('text').str : null;
                            }
                            
                            legDetailMap.put(amendmentDetail.amendmentId, amendmentDetail);
                        }
                    }
                    
                    return true;
                    
                // Handle bills
                } else if (recordCount > 0 && json.getValue('bills') != null) {
                    
                    //{"page":{"per_page":20,"page":1,"count":20},"count":3417,
                    //  "bills":[
                    //      {"bill_id":"<billId>", "sponsor_id":"<sponsorId>","last_action":{"text":"<lastAction>"},"official_title":"<officialTitle>","short_title":"<shortTitle>","summary":"<summary>","introduced_at":"<introducedAt>",
                    //          "cosponsors_count":21,"cosponsor_ids":["B001245",...],
                    //          "state":"REFERRED"},...
                    //      ]}
                    
                    // Get each bill in the array
                    JSONObject bill;
                    LegInfo billDetail;
                    Integer cosponsors_count;
                    
                    for (Integer i = 0; i < recordCount; i++) {
                        if (json.getValue('bills').values[i] != null) {
                            bill = json.getValue('bills').values[i].obj;
                            billDetail = new LegInfo();
                            
                            billDetail.billId = (bill.getValue('bill_id') != null) ? bill.getValue('bill_id').str : null;
                            
                            billDetail.status = (bill.getValue('state') != null) ? bill.getValue('state').str : null;
                            
                            billDetail.officialTitle = (bill.getValue('official_title') != null) ? bill.getValue('official_title').str : null;
                            
                            billDetail.shortTitle = (bill.getValue('short_title') != null) ? bill.getValue('short_title').str : null;
                            
                            billDetail.summary = (bill.getValue('summary') != null) ? bill.getValue('summary').str : null;
                            
                            billDetail.introducedAt = (bill.getValue('introduced_at') != null) ? bill.getValue('introduced_at').str : null;
                            
                            billDetail.sponsorId = (bill.getValue('sponsor_id') != null) ? bill.getValue('sponsor_id').str : null;
                            if (billDetail.sponsorId != null) { legislators.add(billDetail.sponsorId); }
                            
                            cosponsors_count = (bill.getValue('cosponsors_count') != null) ? bill.getValue('cosponsors_count').num : 0;
                            if (cosponsors_count > 0 && bill.getValue('cosponsor_ids') != null) {
                                for (Integer j = 0; j < cosponsors_count; j++)
                                    billDetail.cosponsorIds.add(bill.getValue('cosponsor_ids').values[j].str);
                            }
                            legislators.addAll(billDetail.cosponsorIds);
                            
                            JSONObject last_action = (bill.getValue('last_action') != null) ? bill.getValue('last_action').obj : null;
                            billDetail.lastAction = (last_action != null && last_action.getValue('text') != null) ? last_action.getValue('text').str : null;
                            
                            legDetailMap.put(billDetail.billId, billDetail);
                        }
                        
                        }
                        return true;
                    } else if (recordCount > 0 && json.getValue('votes') != null) {
                        // Get each bill in the array
                        JSONObject vote;
                        
                        LegInfo voteDetail;
                        Integer vote_count;
                        Integer voter_ids_count;
                        String rollId;
                        
                        system.debug('got into votes json parse');
                        
                        for (Integer i = 0; i < recordCount; i++) {
                            if (json.getValue('votes').values[i] != null) {
                
                                vote = json.getValue('votes').values[i].obj;
                                voteDetail = new LegInfo();
                                system.debug('vote!!!: ' + vote);
                                voteDetail.billId = (vote.getValue('bill_id') != null) ? vote.getValue('bill_id').str : null;
                                
                                voteDetail.roll_id = (vote.getValue('roll_id') != null) ? vote.getValue('roll_id').str : null;
                                voteDetail.result = (vote.getValue('result') != null) ? vote.getValue('result').str : null;
                                voteDetail.roll_type = (vote.getValue('roll_type') != null) ? vote.getValue('roll_type').str : null;
                                voteDetail.vote_type = (vote.getValue('vote_type') != null) ? vote.getValue('vote_type').str : null;
                                voteDetail.voted_at = (vote.getValue('voted_at') != null) ? vote.getValue('voted_at').str : null;
                                                  
                               JSONObject voter_ids = (vote.getValue('voter_ids') != null) ? vote.getValue('voter_ids').obj : null;
                               if(voter_ids!=null){
                                    system.debug('voter_ids object:' + voter_ids);
                                    voteDetail.voterBioguideIds = voter_ids.keys();
                                    
                                    List<VoteInfo> thisVoteVoterIds = new List<VoteInfo>();
                                    for(String thisKey : voteDetail.voterBioguideIds){
                                         VoteInfo thisVoterInfo = new VoteInfo(voteDetail.roll_id,thisKey,voter_ids.getValue(thisKey).str);
                                         thisVoteVoterIds.add(thisVoterInfo);
                                    }
                                    voteDetail.voterIdMap.put(voteDetail.roll_id,thisVoteVoterIds);
                                    /*
                                        List<VoteInfo> thisVoteVoterIds = new List<VoteInfo>();
                                        for (Integer j = 0; j < voter_ids.length(); j++) {
                                              
                                            VoteInfo thisVoterInfo = new VoteInfo(voteDetail.roll_id,vote.getValue('voter_ids').values[j].str,vote.getValue('voter_ids').values[j].str);
                                            thisVoteVoterIds.add(thisVoterInfo);
                                          
                                         
                                        }
                                        voteDetail.voterIdMap.put(voteDetail.roll_id,thisVoteVoterIds);
                                    */
                                  
                                   legDetailMap.put(voteDetail.roll_id, voteDetail); 
                               }
                            }
                        }
                        
                        
                        
                        return true;
                } else {
                    System.debug('>>>>>>>>>> No amendment or bill information returned: ' + result);
                    return false;
                }
                
            } else {
                System.debug('>>>>>>>>>> No pagination information returned: ' + result);
                return false;
            }
            
        } catch (JSONObject.JSONException e) {
            System.debug('>>>>>>>>>> Error parsing JSON response from RealTimeCongress API: ' + e);
            return false;
        }
    }
    
    ////////// Unit Tests //////////
    
    static testMethod void testBuildRequest() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        List<String> keys = new List<String>{'key1', 'key2'};
        List<String> vals = new List<String>{'value1', 'value2'};
        HttpRequest req = api.buildRequest('method', keys, vals);
        
        System.assertNotEquals(null, req);
        System.assertEquals(api.Endpoint + '/method.json?apikey=' + api.APIKey + '&key1=value1&key2=value2', req.getEndpoint());
        System.assertEquals('GET', req.getMethod());
        //System.assertEquals(null, req.getBody());
    }
    
    static testMethod void testHandleResponse() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        System.assertEquals(false, api.handleResponse(new HttpResponse()));
    }
    
    static testMethod void testParseAmendmentResult() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        // Results contain everything we are looking for in an amendment
        String result = '{"count":1,"page":{"per_page":20,"count":1,"page":1},"amendments":[{"sponsor_id":"R000361","actions":[{"text":"Amendment SA 4843 proposed by Senator Bingaman for Senator Rockefeller."},{"text":"Amendment SA 4843 agreed to in Senate by Unanimous Consent."}],"amendment_id":"s4843-111","offered_at":"2010-12-17T12:00:00Z","bill_id":"hr5116-111","state":"pass","purpose":"To invest in innovation through research and development, to improve competitiveness of the United States, and for other purposes."}]}';
        System.assertEquals(true, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals('s4843-111', api.legDetailMap.get('s4843-111').amendmentId);
        System.assertEquals('hr5116-111', api.legDetailMap.get('s4843-111').billId);
        System.assertEquals('pass', api.legDetailMap.get('s4843-111').getStatus());
        System.assertEquals('To invest in innovation through research and development, to improve competitiveness of the United States, and for other purposes.', api.legDetailMap.get('s4843-111').getPurpose());
        System.assertEquals('Amendment SA 4843 agreed to in Senate by Unanimous Consent.', api.legDetailMap.get('s4843-111').getLastAction());
        System.assertEquals('2010-12-17T12:00:00Z', api.legDetailMap.get('s4843-111').introducedAt);
        System.assertEquals('R000361', api.legDetailMap.get('s4843-111').sponsorId);
        System.assertEquals(1, api.legislators.size());
        System.assertEquals(true, api.legislators.contains('R000361'));
        
        // Results contain partial information for an amendment
        result = '{"count":1,"page":{"per_page":20,"count":1,"page":1},"amendments":[{"sponsor_id":"R000361","amendment_id":"s4843-111","offered_at":"2010-12-17T12:00:00Z","bill_id":"hr5116-111","state":"pass"}]}';
        System.assertEquals(true, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals('s4843-111', api.legDetailMap.get('s4843-111').amendmentId);
        System.assertEquals('hr5116-111', api.legDetailMap.get('s4843-111').billId);
        System.assertEquals('pass', api.legDetailMap.get('s4843-111').getStatus());
        System.assertEquals(null, api.legDetailMap.get('s4843-111').getPurpose());
        System.assertEquals(null, api.legDetailMap.get('s4843-111').getLastAction());
        System.assertEquals('2010-12-17T12:00:00Z', api.legDetailMap.get('s4843-111').introducedAt);
        System.assertEquals('R000361', api.legDetailMap.get('s4843-111').sponsorId);
        System.assertEquals(1, api.legislators.size());
        System.assertEquals(true, api.legislators.contains('R000361'));
        
        
        // No information for amendment
        result = '{"page":{"per_page":20,"page":1,"count":1},"count":1,"funny":{"pretty":"much"}}';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
        
        // No pagination information
        result = '{"funny":{"pretty":"much"}}';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(0, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
        
        // Bad JSON result
        result = 'Bad JSON';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(0, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
    }
    
    static testMethod void testParseBillResult() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        // Results contain everything we are looking for in a bill
        String result = '{"page":{"per_page":20,"page":1,"count":1},"count":1,"bills":[{"bill_id":"s888-112","cosponsor_ids":["K000369","S000810"],"cosponsors_count":2,"last_action":{"text":"Referred to XYZ."},"official_title":"To change the world forever!","short_title":"To change the world","summary":"Peace and clean energy for all.","introduced_at":"2011-02-10T12:00:00Z","sponsor_id":"M001160","state":"REFERRED"}]}';
        System.assertEquals(true, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals('s888-112', api.legDetailMap.get('s888-112').billId);
        System.assertEquals('REFERRED', api.legDetailMap.get('s888-112').getStatus());
        System.assertEquals('To change the world forever!', api.legDetailMap.get('s888-112').getOfficialTitle());
        System.assertEquals('To change the world', api.legDetailMap.get('s888-112').getShortTitle());
        System.assertEquals('Referred to XYZ.', api.legDetailMap.get('s888-112').getLastAction());
        System.assertEquals('Peace and clean energy for all.', api.legDetailMap.get('s888-112').summary);
        System.assertEquals('2011-02-10T12:00:00Z', api.legDetailMap.get('s888-112').introducedAt);
        System.assertEquals('M001160', api.legDetailMap.get('s888-112').sponsorId);
        //System.assertEquals(new String[] {'K000369', 'S000810'}, api.legDetailMap.get('s888-112').cosponsorIds);
        System.assertEquals(2, api.legDetailMap.get('s888-112').cosponsorIds.size());
        System.assertEquals(true, api.legDetailMap.get('s888-112').cosponsorIds.contains('K000369'));
        System.assertEquals(true, api.legDetailMap.get('s888-112').cosponsorIds.contains('S000810'));
        System.assertEquals(3, api.legislators.size());
        System.assertEquals(true, api.legislators.contains('M001160'));
        System.assertEquals(true, api.legislators.contains('K000369'));
        System.assertEquals(true, api.legislators.contains('S000810'));
        
        // Results contain partial information for a bill
        result = '{"page":{"per_page":20,"page":1,"count":1},"count":1,"bills":[{"bill_id":"s999-111","cosponsor_ids":["K000369","S000810"],"cosponsors_count":2}]}';
        System.assertEquals(true, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals('s999-111', api.legDetailMap.get('s999-111').billId);
        System.assertEquals(null, api.legDetailMap.get('s999-111').getStatus());
        System.assertEquals(null, api.legDetailMap.get('s999-111').getOfficialTitle());
        System.assertEquals(null, api.legDetailMap.get('s999-111').getShortTitle());
        System.assertEquals(null, api.legDetailMap.get('s999-111').getLastAction());
        System.assertEquals(null, api.legDetailMap.get('s999-111').summary);
        System.assertEquals(null, api.legDetailMap.get('s999-111').introducedAt);
        System.assertEquals(null, api.legDetailMap.get('s999-111').sponsorId);
        //System.assertEquals(new String[] {'K000369', 'S000810'}, api.legDetailMap.get('s999-111').cosponsorIds);
        System.assertEquals(2, api.legDetailMap.get('s999-111').cosponsorIds.size());
        System.assertEquals(true, api.legDetailMap.get('s999-111').cosponsorIds.contains('K000369'));
        System.assertEquals(true, api.legDetailMap.get('s999-111').cosponsorIds.contains('S000810'));
        System.assertEquals(2, api.legislators.size());
        System.assertEquals(true, api.legislators.contains('K000369'));
        System.assertEquals(true, api.legislators.contains('S000810'));
        
        // No information for bill
        result = '{"page":{"per_page":20,"page":1,"count":1},"count":1,"funny":{"pretty":"much"}}';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(1, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
        
        // No pagination information
        result = '{"funny":{"pretty":"much"}}';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(0, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
        
        // Bad JSON result
        result = 'Bad JSON';
        System.assertEquals(false, api.parseResult(result));
        System.assertEquals(0, api.recordCount);
        System.assertEquals(0, api.legDetailMap.size());
    }
    
    static testMethod void testGetAmendment() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        Boolean result = api.getAmendment('s', '555', '112');
        System.assertEquals(false, result);
    }
    
    static testMethod void testGetAmendments() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        Boolean result = api.getAmendments(new List<String> { 'h123-112', 's567-111'});
        System.assertEquals(false, result);
    }
    
    static testMethod void testGetBill() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        Boolean result = api.getBill('s', '888', '112');
        System.assertEquals(false, result);
    }
    
    static testMethod void testGetBills() {
        RealTimeCongressAPI api = new RealTimeCongressAPI();
        
        Boolean result = api.getBills(new List<String> { 'hr614-112', 's888-111'});
        System.assertEquals(false, result);
    }
    
}