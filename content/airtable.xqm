xquery version "3.1";

(:~ 
 : This library module contains functions for communicating with Airtable’s Web 
 : API via XQuery.
 : 
 : All functions require a personal access token or OAuth access token from 
 : Airtable. 
 :
 : The library sends requests to the Airtable API using the EXPath HTTP Client
 : library. (See eXist notes below.)
 : 
 : Successful responses (with status 200) are returned with the response body’s 
 : JSON object parsed as a map. 
 : 
 : When a response indicates an error (a non-200 status), the library’s 
 : functions all return a map with an "error" entry, with subentries to aid in 
 : debugging: request, response head and body, rate limit assessments, start and 
 : end dateTimes, and duration in seconds.
 : 
 : Function documentation is adapted to use XQuery conventions (XDM terminology 
 : replaces JSON terminology, and parameters are kebab case rather than camel 
 : case.) 
 : 
 : The library is dependent on eXist in two areas:
 : 
 : 1. eXist’s EXPath HTTP Client module returns JSON as xs:base64Binary, so 
 : util:binary-to-string() is always needed before the JSON can be parsed.
 : 
 : 2. To prevent hitting the Airtable API’s rate limits, we use eXist’s 
 : cache module to store the dateTime of the last request. If a delay is needed
 : before a request can be submitted, the util:wait() function is used. 
 : 
 : Caveats:
 : 
 : - The "typecast" parameter for automatic data conversion for list, create, 
 : and update actions hasn’t been implemented.
 : - No special handling for User and Server error codes except rate limits; 
 : instead, full HTTP response headers are returned.
 : 
 : @author Joe Wicentowski
 : @version 2.0.0
 :
 : @see https://airtable.com/developers/web/api
 :)

module namespace airtable = "http://joewiz.org/ns/xquery/airtable";

(: EXPath :)
declare namespace http = "http://expath.org/ns/http-client";

(: eXist :)
declare namespace cache = "http://exist-db.org/xquery/cache";
declare namespace util = "http://exist-db.org/xquery/util";

(: ======== GLOBAL VARIABLES ======== :)

(:~ The base URL for the Airtable Web API :)
declare variable $airtable:WEB_API_BASE := "https://api.airtable.com/v0/";

(:~ We will cache the time of the last request to avoid exceeding the rate limit :)
declare variable $airtable:RATE_LIMIT_CACHE_NAME := "airtable";

(:~
 : Initialize rate limit cache, with conservative settings:
 : - stale entries expire after 1 minute
 : - max 128 bases at any given time.
 : Why these limits? The cache module documentation states:
 : "eXist-db cannot know how much memory the data you will put in the cache 
 : will take, so it is up to you to manage your own memory needs here."
 :)
declare variable $airtable:INITIALIZE_CACHE := 
    if (cache:names() = $airtable:RATE_LIMIT_CACHE_NAME) then
        ()
    else
        cache:create($airtable:RATE_LIMIT_CACHE_NAME, map { "expireAfterAccess": 60000, "maximumSize": 128 })
;

(:~ 
 : The API is limited to 50 requests per second for all traffic using personal 
 : access tokens from a user or service account. 
 :  
 : 1/50th of a second is equal to .02 seconds.
 :)
declare variable $airtable:MIN_DURATION_BETWEEN_REQUESTS := xs:dayTimeDuration("PT0.02S");

(:~ 
 : If you exceed this rate, you will receive a 429 status code and will need 
 : to wait 30 seconds before subsequent requests will succeed. 
 :)
declare variable $airtable:RATE_LIMIT_COOL_OFF_PERIOD := xs:dayTimeDuration("PT30S");

(:~ The rate limit is 10 records per create request :)
declare variable $airtable:MAX_RECORDS_PER_CREATE_REQUEST := 10;

(:~ The rate limit is 10 records per update request :)
declare variable $airtable:MAX_RECORDS_PER_UPDATE_REQUEST := 10;

(:~ Success code :)
declare variable $airtable:HTTP-OK := "200";

(:~ Rate limit exceeded code :)
declare variable $airtable:HTTP_RATE_LIMIT_EXCEEDED := "429";


(: ======== MAIN FUNCTIONS ======== :)

(:~ 
 : Get user info
 : 
 : Retrieve the user's ID associated with the provided token. For OAuth access 
 : tokens, the scopes associated with the token used are also returned. For 
 : tokens with the `user.email:read` scope, the user's email is also returned.
 :
 : @param $access-token Airtable personal access token or OAuth access token
 : 
 : @return The user's ID
 : 
 : @see https://airtable.com/developers/web/api/get-user-id-scopes
 :)
declare function airtable:get-user-info(
    $access-token as xs:string
) as map(*) {
    airtable:send-request(
        $access-token, 
        "GET", 
        airtable:generate-href(("meta", "whoami"))
    )
};

(:~ 
 : Return the list of bases the API key can access in the order they appear on 
 : the user’s home screen. The result will be truncated to only include the 
 : first 1,000 bases.
 :
 : TODO: Add support for offset to handle >1,000 bases.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : 
 : @return A map containing a "bases" entry, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/list-bases
 :)
declare function airtable:list-bases(
    $access-token as xs:string
) as map(*) {
    airtable:send-request(
        $access-token, 
        "GET", 
        airtable:generate-href(("meta", "bases"))
    )
};

(:~ 
 : Get base schema
 : 
 : Returns the schema of the tables in the specified base.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : 
 : @return A map containing a "tables" entry, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/get-base-schema
 :)
declare function airtable:get-base-schema(
    $access-token as xs:string, 
    $base-id as xs:string
) as map(*) {
    airtable:send-request(
        $access-token, 
        "GET", 
        airtable:generate-href(("meta", "bases", $base-id, "tables"))
    )
};

(:~ 
 : Create records
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : @param $records A sequence of maps, each containing a "fields" entry
 : 
 : @return A map containing an "records" entry with an array of the new record entries created if the call succeeded, including record IDs that uniquely identify the records, or a map with an "error" entry containing information about the request
 :
 : https://airtable.com/developers/web/api/create-records
 :)
declare function airtable:create-records(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string, 
    $records as map(*)*
) as map(*)+ {
    let $records-for-this-request := 
        map { 
            "records": 
                array {
                    if (count($records) gt $airtable:MAX_RECORDS_PER_CREATE_REQUEST) then
                        subsequence($records, 1, $airtable:MAX_RECORDS_PER_CREATE_REQUEST)
                    else
                        $records
                }
        }
    let $records-for-next-request := subsequence($records, $airtable:MAX_RECORDS_PER_CREATE_REQUEST + 1)
    let $response := 
        airtable:send-request(
            $access-token, 
            "POST", 
            airtable:generate-href(($base-id, $table-id-or-name)), 
            $records-for-this-request
        )
    return
        (
            $response,
            (: create the rest of the records if the first attempt was successful :)
            if (exists($records-for-next-request) and map:contains($response, "records")) then
                airtable:create-records($access-token, $base-id, $table-id-or-name, $records-for-next-request)
            else
                ()
        )
};

(:~ 
 : Get record
 : 
 : Retrieve a single record. Any "empty" fields (e.g. "", [], or false) in the 
 : record will not be returned.
 : 
 : In attachment objects included in the retrieved record, only id, url, and 
 : filename are always returned. Other attachment properties may not be 
 : included.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : @param $record-id A record ID
 : 
 : @return A map containing the record if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/get-record
 :)
declare function airtable:get-record(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string, 
    $record-id as xs:string
) as map(*) {
    airtable:send-request(
        $access-token, 
        "GET", 
        airtable:generate-href(($base-id, $table-id-or-name, $record-id))
    )
};

(:~ 
 : List records
 : 
 : List records in a table. Note that table names and table ids can be used interchangeably. 
 :
 : Any "empty" fields (e.g. "", [], or false) in the record will not be returned.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : 
 : @return A map containing a "records" entry if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/list-records
 :)
declare function airtable:list-records(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string
) as map(*)+ {
    airtable:list-records(
        $access-token, 
        $base-id, 
        $table-id-or-name, 
        (),
        (),
        (),
        (),
        (),
        (),
        ()
    )
};

(:~ 
 : List records
 : 
 : List records in a table. Note that table names and table ids can be used 
 : interchangeably. 
 :
 : Any "empty" fields (e.g. "", [], or false) in the record will not be returned.
 : 
 : The server returns one page of records at a time. Each page will contain 
 : $page-size records, which is 100 by default. If there are more records, the 
 : response will contain an offset. Pagination will stop when you’ve reached 
 : the end of the table. If the $max-records parameter is passed, pagination 
 : will stop once you’ve reached this maximum.

 : You can filter, sort, and format the results by supplying parameters. 
 : 
 : The only standard parameters that aren’t supported are cellFormat and the
 : associated timeZone and userLocale. Besides cellFormat’s default value of 
 : "json", the only other value is "string"; the documentation warns: "You 
 : should not rely on the format of these strings, as it is subject to change."
 : The timeZone and userLocale parameters are only relevant when cellFormat is
 : set to "string."
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : @param $fields Only data for fields whose names are in this list will be included in the result. If you don’t need every field, you can use this parameter to reduce the amount of data transferred.
 : @param $filter-by-formula An Airtable formula used to filter records. The formula will be evaluated for each record, and if the result is not 0, false, "", NaN, [], or #Error! the record will be included in the response.
 : @param $max-records The maximum total number of records that will be returned in your requests. If this value is larger than page-size (which is 100 by default), you may have to load multiple pages to reach this total.
 : @param $page-size The number of records returned in each request. Must be less than or equal to 100. Default is 100.
 : @param $sort A list of sort objects that specifies how the records will be ordered. Each sort entry must have a "field" key specifying the name of the field to sort on, and an optional "direction" key that is either "asc" or "desc". The default direction is "asc".
 : @param $view The name or ID of a view in the requested table. If set, only the records in that view will be returned. The records will be sorted according to the order of the view unless the sort parameter is included, which overrides that order. Fields hidden in this view will be returned in the results. To only return a subset of fields, use the $fields parameter.
 : @param $offset An offset ID supplied by the API needed to load the next page of results
 : 
 : @return A map containing a "records" entry if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/list-records
 :)
declare function airtable:list-records(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string, 
    $fields as xs:string*,
    $filter-by-formula as xs:string?,
    $max-records as xs:integer?,
    $page-size as xs:integer?,
    $sort as map(*)*,
    $view as xs:string?,
    $offset as xs:string?
) as map(*)+ {
    (: prepare parameters map :)
    let $parameters :=
        map:merge((
            if (exists($fields)) then 
                map:entry("fields[]", $fields) 
            else 
                (),
            if (exists($filter-by-formula)) then 
                map:entry("filterByFormula", $filter-by-formula) 
            else 
                (),
            if (exists($max-records)) then 
                map:entry("maxRecords", $max-records) 
            else 
                (),
            if (exists($page-size)) then 
                map:entry("pageSize", $page-size) 
            else 
                (),
            (: to prepare the "sort" parameter correctly, take a sequence of 
             : maps like:
             :     { "field" : "Status", "direction" : "desc" }
             : and transform it into 
             :     sort[0][field]=Status 
             :     sort[0][direction]=desc
             :)
            if (exists($sort)) then 
                for $s at $n in $sort 
                return 
                    map:for-each(
                        $s,
                        function($key, $value) {
                            map:entry("sort[" || $n || "][" || $key || "]", $value)
                        }
                    )
            else
                (),
            if (exists($view)) then 
                map:entry("view", $view) 
            else 
                (),
            if (exists($offset)) then 
                map:entry("offset", $offset) 
            else 
                ()
        ))
    let $request := 
        airtable:send-request(
            $access-token, 
            "GET", 
            airtable:generate-href(($base-id, $table-id-or-name), $parameters)
        )
    return
        (
            $request,
            if (exists($request?offset)) then
                airtable:list-records(
                    $access-token,
                    $base-id, 
                    $table-id-or-name, 
                    $fields,
                    $filter-by-formula,
                    $max-records,
                    $page-size,
                    $sort,
                    $view,
                    $request?offset
                )
            else
                ()
        )
};

(:~ 
 : Update record or multiple records
 : 
 : Each of the $records maps should have an "id" entry containing the record ID 
 : and a "fields" entry, containing an array all of the record’s cell values by 
 : field name. You can include all, some, or none of the field values.
 : 
 : To add to an attachments field, include "attachment" entries for the 
 : respective field. Be sure to include all existing attachment objects that 
 : you wish to retain. For the new attachments being added, "url" is required, 
 : and "filename" is optional. To remove attachments, include the existing array 
 : of attachment entry, excluding any that you wish to remove.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : @param $records A sequence of maps containing "id" and "fields" entries
 : @param $destroy-existing Whether to perform a destructive update and clear all unspecified fields' values
 : 
 : @return A map containing an "records" entry with an array of the updated record entries created if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/update-record
 : @see https://airtable.com/developers/web/api/update-multiple-records
 :)
declare function airtable:update-records(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string, 
    $records as map(*)+,
    $destroy-existing as xs:boolean?
) as map(*)+ {
    let $method := 
        if ($destroy-existing) then 
            "PUT" 
        else 
            "PATCH"
    let $records-for-this-request := 
        map { 
            "records": 
                array {
                    if (count($records) gt $airtable:MAX_RECORDS_PER_UPDATE_REQUEST) then
                        subsequence($records, 1, $airtable:MAX_RECORDS_PER_UPDATE_REQUEST)
                    else
                        $records
                }
        }
    let $records-for-next-request := subsequence($records, $airtable:MAX_RECORDS_PER_UPDATE_REQUEST + 1)
    let $response := 
        airtable:send-request(
            $access-token, 
            $method, 
            airtable:generate-href(($base-id, $table-id-or-name)), 
            $records-for-this-request
        )
    return
        (
            $response,
            (: keep creating records if the first attempt was successful :)
            if (exists($records-for-next-request) and map:contains($response, "records")) then
                airtable:update-records($access-token, $base-id, $table-id-or-name, $records-for-next-request, $destroy-existing)
            else
                ()
        )
};

(:~ 
 : Delete record or multiple records
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $base-id The ID of the base
 : @param $table-id-or-name The ID or name of the table where the records should be added
 : @param $record-ids The IDs of records to delete
 : 
 : @return A map containing a "records" entry listing the deleted record IDs if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/developers/web/api/delete-record
 : @see https://airtable.com/developers/web/api/delete-multiple-records
 :)
declare function airtable:delete-records(
    $access-token as xs:string, 
    $base-id as xs:string, 
    $table-id-or-name as xs:string, 
    $record-ids as xs:string+
) as map(*) {
    let $parameters := map { "records": $record-ids }
    return
        airtable:send-request(
            $access-token, 
            "DELETE", 
            airtable:generate-href(($base-id, $table-id-or-name), $parameters)
        )
};


(: ======== HELPER FUNCTIONS ======== :)

(:~ 
 : Assembles EXPath HTTP Client request element, sending the request to Airtable
 : as soon as the API’s rate limit allows, processing status codes to handle
 : errors.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $method The HTTP method to use for the request
 : @param $href The API endpoint URL, including optional query string
 : 
 : @return The response body if the call succeeded, or a map with an "error" entry containing information about the request
 :)
declare 
    %private
function airtable:send-request(
    $access-token as xs:string, 
    $method as xs:string,
    $href as xs:string 
) {
    airtable:send-request(
        $access-token, 
        $method, 
        $href, 
        (), 
        ()
    )
};

(:~ 
 : Assembles EXPath HTTP Client request element, sending the request to Airtable
 : as soon as the API’s rate limit allows, processing status codes to handle
 : errors.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $method The HTTP method to use for the request
 : @param $href The API endpoint URL, including optional query string
 : @param $body Request body
 : 
 : @return The response body if the call succeeded, or a map with an "error" entry containing information about the request
 :)
declare 
    %private
function airtable:send-request(
    $access-token as xs:string, 
    $method as xs:string,
    $href as xs:string, 
    $records as map(*)?
) {
    airtable:send-request(
        $access-token, 
        $method, 
        $href, 
        $records, 
        ()
    )
};

    (:~ 
 : Assembles EXPath HTTP Client request element, sending the request to Airtable
 : as soon as the API’s rate limit allows, processing status codes to handle
 : errors.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : @param $method The HTTP method to use for the request
 : @param $href The API endpoint URL, including optional query string
 : @param $body Request body
 : @param $headers Request headers
 : 
 : @return The response body if the call succeeded, or a map with an "error" entry containing information about the request
 :)
declare 
    %private
function airtable:send-request(
    $access-token as xs:string, 
    $method as xs:string,
    $href as xs:string, 
    $records as map(*)?,
    $headers as map(*)? 
) {
    let $initialize-cache-if-needed := $airtable:INITIALIZE_CACHE
    let $user-id := airtable:get-user-id($access-token)
    let $request := 
        element http:request {
            attribute href { $href },
            attribute method { $method },
            element http:header {
                attribute name { "Authorization" },
                attribute value { "Bearer " || $access-token }
            },
            if (exists($headers)) then
                map:for-each(
                    $headers,
                    function($key, $value) {
                        element http:header {
                            attribute name { $key },
                            attribute value { $value }
                        }
                    }
                )
            else
                (),
            if (exists($records)) then
                element http:body { 
                    attribute media-type { "application/json" },
                    attribute method { "text" },
                    serialize($records, map { "method": "json" })
                }
            else
                ()
        }
    let $response := airtable:send-request-when-rate-limit-ok($user-id, $request)
    return
        if ($response?status eq $airtable:HTTP-OK) then
            $response?body
        else
            map { "error": $response }
};

(:~ 
 : Looks up the user ID for the username corresponding to the personal access 
 : token or service account access token. Needed as a cache key since rate 
 : limiting is against the user, not the access token.
 : 
 : @param $access-token Airtable personal access token or OAuth access token
 : 
 : @return The user ID
 :)
declare
    %private
function airtable:get-user-id($access-token) as xs:string {
    let $access-token-hash := util:hash($access-token, "SHA-256")
    return
        (: we store the user ID in a cache whose key is a hash of the access token :)
        if (cache:keys($airtable:RATE_LIMIT_CACHE_NAME) = $access-token-hash) then
            cache:get($airtable:RATE_LIMIT_CACHE_NAME, $access-token-hash)
        (: if it's not present, look it up from Airtable :)
        else
            let $href := airtable:generate-href(("meta", "whoami"))
            let $method := "GET"
            let $request := 
                element http:request {
                    attribute href { $href },
                    attribute method { $method },
                    element http:header {
                        attribute name { "Authorization" },
                        attribute value { "Bearer " || $access-token }
                    }
                }
            let $response := http:send-request($request)
            let $response-head := $response[1]
            let $user-id :=
                if ($response-head/@status eq $airtable:HTTP-OK) then
                    let $response-body := $response[2] ! (util:binary-to-string(.) => parse-json())
                    return
                        $response-body?id
                else
                    (: fall back on a harmless value; the underlying cause of 
                     : the error will be apparent with request to the actual API 
                     :)
                    let $_log := util:log("INFO", "attempt to look up Airtable user ID failed with a status code of " || $response-head/@status)
                    return
                        "unknown-user"
            let $cache-put := cache:put($airtable:RATE_LIMIT_CACHE_NAME, $access-token-hash, $user-id)
            return
                $user-id
};

(:~ 
 : Sends requests, waiting until the rate limit expires if necessary. 
 : 
 : @param $user-id User ID of the account that owns the access token
 : @param $request EXPath HTTP Request element
 : 
 : @return A map containing a reflection of the request, the response status code, the response head and body, the status of rate limit before the request was sent
 :)
declare
    %private
function airtable:send-request-when-rate-limit-ok(
    $user-id as xs:string, 
    $request as element(http:request)
) as map(*) {
    let $start-dateTime := util:system-dateTime()
    let $wait-until := cache:get($airtable:RATE_LIMIT_CACHE_NAME, $user-id)
    let $rate-limit-info := 
        if (empty($wait-until)) then
            map { 
                "assessment": "send request, since no rate limit expiration had been set",
                "can-send-request-immediately": true()
            }
        else
            let $ok := $wait-until le $start-dateTime
            return
                if ($ok) then
                    map {
                        "assessment": "send request, since rate limit already expired at " || $wait-until,
                        "can-send-request-immediately": true()
                    }
                else
                    map {
                        "assessment": "wait to send request until " || $wait-until,
                        "can-send-request-immediately": false()
                    }
    let $response :=
        if ($rate-limit-info?can-send-request-immediately) then
            http:send-request($request)
        else
            let $wait-duration := $wait-until - $start-dateTime
            let $milliseconds-to-wait := 
                seconds-from-duration($wait-duration) * 1000
            return
                airtable:wait(
                    $milliseconds-to-wait, 
                    http:send-request#1, 
                    array { $request }
                )
    let $end-dateTime := util:system-dateTime()
    let $set-next-expiration := 
        cache:put(
            $airtable:RATE_LIMIT_CACHE_NAME, 
            $user-id, 
            (: "If you exceed this rate, you will receive a 429 status code and 
             : will need to wait 30 seconds before subsequent requests will 
             : succeed." :)
            if ($response[1]/@status eq $airtable:HTTP_RATE_LIMIT_EXCEEDED) then
                $end-dateTime + $airtable:RATE_LIMIT_COOL_OFF_PERIOD
            else
                $end-dateTime + $airtable:MIN_DURATION_BETWEEN_REQUESTS
        )
    return
        map {
            "request": $request,
            "head": $response[1],
            "status": $response[1]/@status/string(),
            "body": $response[2] ! (util:binary-to-string(.) => parse-json()),
            "rate-limit-info": $rate-limit-info,
            "start-dateTime": $start-dateTime,
            "end-dateTime": $end-dateTime,
            "duration": seconds-from-duration($end-dateTime - $start-dateTime) || "s"
        }
};

(:~ 
 : Wait a specified duration before applying a function. 
 : 
 : @param $duration Duration to wait
 : @param $function Function to apply
 : @param $arguments Arguments for the function
 : 
 : @return The results of the applied function
 :)
declare
    %private
function airtable:wait(
    $milliseconds-to-wait as xs:integer, 
    $function as function(*), 
    $arguments as array(*)
) {
    util:wait($milliseconds-to-wait),
    apply($function, $arguments)
};

(:~ 
 : Construct the Airtable Web API URL for a request from path segments. 
 : 
 : @param $path-segments Segments of the path
 : 
 : @return The Airtable Web API URL
 :)
declare 
(:    %private:)
function airtable:generate-href(
    $path-segments as xs:string+
) as xs:string {
    airtable:generate-href($path-segments, ())
};

(:~ 
 : Construct the Airtable Web API URL for a request from path segments and 
 : parameter names & values. 
 : 
 : @param $path-segments Segments of the path
 : @param $parameters Request parameters
 : 
 : @return The Airtable Web API URL
 :)
declare 
(:    %private:)
function airtable:generate-href(
    $path-segments as xs:string+,
    $parameters as map(*)?
) as xs:string {
    let $path :=
        $path-segments
        => for-each(encode-for-uri#1)
        => string-join("/")
    let $query-string :=
        if (exists($parameters)) then
            $parameters
            => map:for-each(
                function($key, $values) { 
                    for $value in $values
                    return
                        encode-for-uri($key) || "=" || encode-for-uri($value)
                }
            )
            => string-join("&amp;")
        else
            ()
    return
        concat(
            $airtable:WEB_API_BASE,
            string-join(($path, $query-string), "?")
        )
};
