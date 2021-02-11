xquery version "3.1";

(:~ This library module contains XQSuite tests for the airtable.xq app.
 :
 : @author Joe Wicentowski
 : @version 1.0.0
 : @see https://joewiz.org
 :)

module namespace tests = "http://joewiz.org/ns/xquery/airtable/tests";

declare namespace test="http://exist-db.org/xquery/xqsuite";



declare
    %test:name('one-is-one')
    %test:assertTrue
    function tests:tautology() {
        1 = 1
};
