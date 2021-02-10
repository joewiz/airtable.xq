xquery version "3.1";

(:~ 
 : This library module contains functions for communicating with Airtable’s REST
 : and Metadata APIs via XQuery.
 : 
 : All functions require an API Key from Airtable. The two functions that access 
 : Airtable’s Metadata API require an additional token from Airtable.
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
 : Function documentation is adapted from the Airtable API for XQuery context 
 : and style (XDM terminology replaces JSON terminology, and parameters are 
 : kebab case rather than camel case.) 
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
 : - The "typecast" parameter for automatic data conversion for list, create, and 
 : update actions hasn’t been implemented.
 : - No special handling for User and Server error codes except rate limits; 
 : instead, full HTTP response headers are returned.
 : 
 : @author Joe Wicentowski
 : @version 1.0.0
 :
 : @see https://airtable.com/api
 : @see https://airtable.com/api/meta
 :)

module namespace airtable = "http://joewiz.org/ns/xquery/airtable";

(: EXPath :)
declare namespace http = "http://expath.org/ns/http-client";

(: eXist :)
declare namespace cache = "http://exist-db.org/xquery/cache";
declare namespace util = "http://exist-db.org/xquery/util";

(: ======== GLOBAL VARIABLES ======== :)

(:~ The base URL for the Airtable REST API :)
declare variable $airtable:REST_API := "https://api.airtable.com/v0/";

(:~ The base URL for the Airtable Metadata API :)
declare variable $airtable:METADATA_API := "https://api.airtable.com/v0/meta/";

(:~ We will cache the time of the last request to avoid exceeding the rate limit :)
declare variable $airtable:RATE_LIMIT_CACHE_NAME := "airtable";

(: Initialize rate limit cache, with stale entries expiring after 5 minutes :)
declare variable $airtable:INITIALIZE_CACHE := 
    if (cache:names() = "airtable") then
        ()
    else
        cache:create($airtable:RATE_LIMIT_CACHE_NAME, map { "expireAfterAccess": 1000 });

(:~ The API is limited to 5 requests per second per base. :)
declare variable $airtable:MIN_DURATION_BETWEEN_REQUESTS := xs:dayTimeDuration("PT0.2S");

(:~ If you exceed this rate, you will receive a 429 status code and will need to wait 30 seconds before subsequent requests will succeed. :)
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
 : Return the list of bases the API key can access in the order they appear on 
 : the user’s home screen. The result will be truncated to only include the 
 : first 1000 bases.
 : 
 : Developers must request an Airtable Metadata Client Secret token.
 : 
 : @param $api-key Airtable API Key
 : @param $client-secret Airtable Metadata API Client Secret token
 : 
 : @return A map containing a "bases" entry, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api/meta
 :)
declare function airtable:list-bases(
    $api-key as xs:string, 
    $client-secret as xs:string
) as map(*) {
    airtable:send-request($api-key, $client-secret, "GET", (), (), (), (), (), ())
};

(:~ 
 : Return the schema of the tables in the specified base.
 : 
 : Developers must request an Airtable Metadata Client Secret token.
 : 
 : @param $api-key Airtable API Key
 : @param $client-secret Airtable Metadata API Client Secret token
 : @param $base-id The ID of the base
 : 
 : @return A map containing a "tables" entry, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api
 :)
declare function airtable:get-base-tables-schema(
    $api-key as xs:string, 
    $client-secret as xs:string, 
    $base-id as xs:string
) as map(*) {
    airtable:send-request($api-key, $client-secret, "GET", $base-id, (), (), (), (), ())
};

(:~ 
 : Create records
 : 
 : @param $api-key Airtable API Key
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $records A sequence of maps, each containing a "fields" entry
 : 
 : @return An array of the new record entries created if the call succeeded, including record IDs that uniquely identify the records, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api
 :)
declare function airtable:create-records(
    $api-key as xs:string, 
    $base-id as xs:string, 
    $table-name as xs:string, 
    $records as map(*)*
) as item()+ {
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
    let $response := airtable:send-request($api-key, (), "POST", $base-id, $table-name, (), (), (), $records-for-this-request)
    return
        (
            $response,
            (: keep creating records if the first attempt was successful :)
            if (exists($records-for-next-request) and $response instance of array(*)) then
                airtable:create-records($api-key, $base-id, $table-name, $records-for-next-request)
            else
                ()
        )
};

(:~ 
 : Retrieve a record
 : 
 : Any "empty" fields (e.g. "", [], or false) in the record will not be returned.
 : 
 : In attachment objects included in the retrieved record, only id, url, and 
 : filename are always returned. Other attachment properties may not be included.
 : 
 : @param $api-key Airtable API Key
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $record-id A record ID
 : 
 : @return A map containing the record if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api
 :)
declare function airtable:retrieve-record(
    $api-key as xs:string, 
    $base-id as xs:string, 
    $table-name as xs:string, 
    $record-id as xs:string
) as map(*) {
    airtable:send-request($api-key, (), "GET", $base-id, $table-name, $record-id, (), (), ())
};

(:~ 
 : List a table’s records
 : 
 : Any "empty" fields (e.g. "", [], or false) in the record will not be returned.
 : 
 : You can filter, sort, and format the results by supplying parameters. 
 : 
 : The server returns one page of records at a time. Each page will contain 
 : $page-size records, which is 100 by default. If there are more records, the 
 : response will contain an offset. To continue loading all pages automatically, 
 : set $load-multiple-pages to true(). Pagination will stop when you’ve reached 
 : the end of the table. If the $max-records parameter is passed, pagination 
 : will stop once you’ve reached this maximum.

 : The only standard parameters that aren’t supported are cellFormat and the
 : associated timeZone and userLocale. Besides cellFormat’s default value of 
 : "json", the only other value is "string"; the documentation warns: "You 
 : should not rely on the format of these strings, as it is subject to change."
 : The timeZone and userLocale parameters are only relevant when cellFormat is
 : set to "string."
 : 
 : @param $api-key Airtable API Key
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $load-multiple-pages Whether or not to load pages until the entire table has been loaded
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
 : @see https://airtable.com/api
 :)
declare function airtable:list-records(
    $api-key as xs:string, 
    $base-id as xs:string, 
    $table-name as xs:string, 
    $load-multiple-pages as xs:boolean?,
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
    let $request := airtable:send-request($api-key, (), "GET", $base-id, $table-name, (), $parameters, (), ())
    return
        (
            $request,
            if ($load-multiple-pages and exists($request?offset)) then
                airtable:list-records(
                    $api-key,
                    $base-id, 
                    $table-name, 
                    $load-multiple-pages,
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
 : Update records
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
 : @param $api-key Airtable API Key
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $records A sequence of maps containing "id" and "fields" entries
 : @param $destroy-existing Whether to perform a destructive update and clear all unspecified cell values
 : 
 : @return An array of the updated record entries created if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api
 :)
declare function airtable:update-records(
    $api-key as xs:string, 
    $base-id as xs:string, 
    $table-name as xs:string, 
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
    let $response := airtable:send-request($api-key, (), $method, $base-id, $table-name, (), (), (), $records-for-this-request)
    return
        (
            $response,
            (: keep creating records if the first attempt was successful :)
            if (exists($records-for-next-request) and $response instance of array(*)) then
                airtable:update-records($api-key, $base-id, $table-name, $records-for-next-request, $destroy-existing)
            else
                ()
        )
};

(:~ 
 : Delete records
 : 
 : @param $api-key Airtable API Key
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $record-ids The IDs of records to delete
 : 
 : @return A map containing a "records" entry listing the deleted record IDs if the call succeeded, or a map with an "error" entry containing information about the request
 : 
 : @see https://airtable.com/api
 :)
declare function airtable:delete-records(
    $api-key as xs:string, 
    $base-id as xs:string, 
    $table-name as xs:string, 
    $record-ids as xs:string+
) as map(*) {
    let $parameters := map:entry("records[]", $record-ids)
    return
        airtable:send-request($api-key, (), "DELETE", $base-id, $table-name, (), $parameters, (), ())
};


(: ======== HELPER FUNCTIONS ======== :)

(:~ 
 : Assembles EXPath HTTP Client request element, sending the request to Airtable
 : as soon as the API’s rate limit allows, processing status codes to handle
 : errors.
 : 
 : @param $api-key Airtable API Key
 : @param $metadata-api-client-secret Airtable Metadata API Client Secret token
 : @param $method The HTTP method to use for the request
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $record-id The ID of the record
 : @param $parameters Request parameters
 : @param $headers Request headers
 : @param $body Request body
 : 
 : @return The response body if the call succeeded, or a map with an "error" entry containing information about the request
 :)
declare 
    %private
function airtable:send-request(
    $api-key as xs:string, 
    $metadata-api-client-secret as xs:string?, 
    $method as xs:string,
    $base-id as xs:string?, 
    $table-name as xs:string?, 
    $record-id as xs:string?, 
    $parameters as map(*)?, 
    $headers as map(*)?, 
    $body as map(*)?
) {
    let $request := 
        element http:request {
            attribute href { 
                if (exists($metadata-api-client-secret)) then
                    airtable:build-metadata-api-url($base-id)
                else
                    airtable:build-rest-api-url($base-id, $table-name, $record-id, $parameters) 
            },
            attribute method { $method },
            element http:header {
                attribute name { "Authorization" },
                attribute value { "Bearer " || $api-key }
            },
            if (exists($metadata-api-client-secret)) then
                element http:header {
                    attribute name { "X-Airtable-Client-Secret" },
                    attribute value { $metadata-api-client-secret }
                }
            else
                (),
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
            if (exists($body)) then
                element http:body { 
                    attribute media-type { "application/json" },
                    attribute method { "text" },
                    serialize($body, map { "method": "json" })
                }
            else
                ()
        }
    (: Use the Base ID as the cache key; the Metadata API doesn't appear to be per-base :)
    let $rate-limit-cache-key := ($base-id, "metadata-api")[1]
    let $response := airtable:send-request-when-rate-limit-ok($request, $rate-limit-cache-key)
    return
        if ($response?status eq $airtable:HTTP-OK) then
            $response?body
        else
            map { "error": $response }
};

(:~ 
 : Sends requests, waiting until the rate limit expires if necessary. 
 : 
 : @param $request EXPath HTTP Request element
 : @param $cache-key The key for looking up when the current base’s rate limits will allow the request to be sent
 : 
 : @return A map containing a reflection of the request, the response status code, the response head and body, the status of rate limit before the request was sent
 :)
declare
    %private
function airtable:send-request-when-rate-limit-ok(
    $request as element(http:request), 
    $cache-key as xs:string?
) as map(*) {
    let $start-dateTime := util:system-dateTime()
    let $wait-until := cache:get($airtable:RATE_LIMIT_CACHE_NAME, $cache-key)
    let $rate-limit-info := 
        if (empty($wait-until)) then
            map { 
                "assessment": "send request, since no rate limit expiration had"
                    || " been set",
                "can-send-request-immediately": true()
            }
        else
            let $ok := $wait-until le $start-dateTime
            return
                if ($ok) then
                    map {
                        "assessment": "send request, since rate limit already"
                            || " expired at " || $wait-until,
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
            $cache-key, 
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
    $duration as xs:dayTimeDuration, 
    $function as function(*), 
    $arguments as array(*)
) {
    util:wait($duration),
    apply($function, $arguments)
};

(:~ 
 : Construct the REST API URL for a request, applying URL encoding to table name
 : and all parameter names & values. 
 : 
 : @param $base-id The ID of the base
 : @param $table-name The name of the table where the records should be added
 : @param $record-id The ID of the record
 : @param $parameters Request parameters
 : 
 : @return The REST API URL
 :)
declare 
    %private
function airtable:build-rest-api-url(
    $base-id as xs:string?, 
    $table-name as xs:string?, 
    $record-id as xs:string?,
    $parameters as map(*)?
) as xs:string {
    let $fragments :=
        (
            $airtable:REST_API,
            $base-id,
            "/",
            encode-for-uri($table-name),
            if (exists($record-id)) then
                (
                    "/",
                    $record-id
                )
            else
                (),
            if (exists($parameters)) then
                (
                    "?",
                    string-join(
                        map:for-each(
                            $parameters, 
                            function($key, $values) { 
                                for $value in $values
                                return
                                    encode-for-uri($key) || "=" || encode-for-uri($value)
                            }
                        ),
                        "&amp;"
                    )
                )
            else
                ()
        )
    return
        string-join($fragments)
};

(:~ 
 : Construct the Metadata API URL for a request, applying URL encoding to table name
 : and all parameter names & values. 
 : 
 : @param $base-id The ID of the base
 : 
 : @return The Metadata API URL
 :)
declare 
    %private
function airtable:build-metadata-api-url(
    $base-id as xs:string?
) as xs:string {
    let $fragments := 
        (
            $airtable:METADATA_API,
            "bases",
            if (exists($base-id)) then
                (
                    "/",
                    $base-id,
                    "/tables"
                )
            else
                ()
        )
    return
        string-join($fragments)
};
