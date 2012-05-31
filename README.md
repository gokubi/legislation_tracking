legislation-tracking
====================

This package allows for easy tracking of legislation in Salesforce.com. It consists of a collection of custom objects and REST callouts to the Sunlight Labs Real Time Congress API.

Setup
-----

1. deploy code
2. override new button for legislation: newLegislation visualforce page
3. assign Legislation Admin permission set to desired users


Real Time Congress API
----------------------

Sunlight labs has a no-cost API that provides access to a wealth of congressional information. Bills, amendments, votes, etc. It's all accessible through an easy to use API.

http://services.sunlightlabs.com/docs/Real_Time_Congress_API/

This package takes your sunlight API key and communicates automatically with the API to keep your Salesforce information up to date.

Congresperson Data
------------------

Tracking bills is helpful, and connecting those bills to congresspeople is where real engagement can take place. Cosponsors, voters, influencers, all can be tracked through use of the bioguide id that each congressperson has. This data is freely available from govtrak:

Listing of all members of the 112th session: http://govtrack.us/data/us/112/people.xml
Schema: http://www.govtrack.us/developers/people_xml

KnowWho has an excellent Appexchange product that gives you access to all congresspeople, staffers, and a ton more directly in your Salesforce instance:

http://appexchange.salesforce.com/listingDetail?listingId=a0N30000001tHWDEA2

Credits
-------
Code contributed by Iraq and Afghanistan Veterans of America. Originally written by Exponent Partners. Modified by Salesforce.com Foundation. 