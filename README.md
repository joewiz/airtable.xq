# airtable.xq

[![License][license-img]][license-url]
[![GitHub release][release-img]][release-url]
![exist-db CI](https://github.com/joewiz/airtable.xq/workflows/exist-db%20CI/badge.svg)
[![Coverage percentage][coveralls-image]][coveralls-url]

A library for the Airtable REST API and Metadata API, using XQuery

This library module contains functions for communicating with Airtable’s REST
and Metadata APIs via XQuery.

All functions require an API Key from Airtable. The two functions that access 
Airtable’s Metadata API require an additional token from Airtable.

Rest API functions:

- airtable:create-records()
- airtable:retrieve-record()
- airtable:list-records()
- airtable:update-records()
- airtable:delete-records()

Metadata API functions:

- airtable:list-bases()
- airtable:get-base-tables-schema()

The library sends requests to the Airtable API using the EXPath HTTP Client
library. (See eXist notes below.)

Successful responses (with status 200) are returned with the response body’s 
JSON object parsed as a map. 

When a response indicates an error (a non-200 status), the library’s 
functions all return a map with an "error" entry, with subentries to aid in 
debugging: request, response head and body, rate limit assessments, start and 
end dateTimes, and duration in seconds.

Function documentation is adapted from the Airtable API for XQuery context 
and style (XDM terminology replaces JSON terminology, and parameters are 
kebab case rather than camel case.) 

The library is dependent on eXist in two areas:

1. eXist’s EXPath HTTP Client module returns JSON as xs:base64Binary, so 
util:binary-to-string() is always needed before the JSON can be parsed.

2. To prevent hitting the Airtable API’s rate limits, we use eXist’s 
cache module to store the dateTime of the last request. If a delay is needed
before a request can be submitted, the util:wait() function is used.

Caveats:

- The "typecast" parameter for automatic data conversion for list, create, and 
update actions hasn’t been implemented.
- No special handling for User and Server error codes except rate limits; 
instead, full HTTP response headers are returned.


## Requirements

*   [exist-db](https://exist-db.org/exist/apps/homepage/index.html) version: `5.x` or greater

*   [ant](https://ant.apache.org) version: `1.10.7` \(for building from source\)

*   [node](https://nodejs.org) version: `12.x` \(for building from source\)
    

## Installation

1.  Download  the `airtable.xq-1.0.0.xar` file from GitHub [releases](https://github.com/joewiz/airtable.xq/releases) page.

2.  Open the [dashboard](http://localhost:8080/exist/apps/dashboard/index.html) of your eXist-db instance and click on `package manager`.

    1.  Click on the `add package` symbol in the upper left corner and select the `.xar` file you just downloaded.

3.  You have successfully installed airtable.xq into exist.

### Building from source

1.  Download, fork or clone this GitHub repository
2.  There are two default build targets in `build.xml`:
    *   `dev` including *all* files from the source folder including those with potentially sensitive information.
  
    *   `deploy` is the official release. It excludes files necessary for development but that have no effect upon deployment.
  
3.  Calling `ant`in your CLI will build both files:
  
```bash
cd airtable.xq
ant
```

   1. to only build a specific target call either `dev` or `deploy` like this:
   ```bash   
   ant dev
   ```   

If you see `BUILD SUCCESSFUL` ant has generated a `airtable.xq-1.0.0.xar` file in the `build/` folder. To install it, follow the instructions [above](#installation).



## Running Tests

To run tests locally your app needs to be installed in a running exist-db instance at the default port `8080` and with the default dba user `admin` with the default empty password.

A quick way to set this up for docker users is to simply issue:

```bash
docker run -dit -p 8080:8080 existdb/existdb:release
```

After you finished installing the application, you can run the full testsuite locally.

### Unit-tests

This app uses [mochajs](https://mochajs.org) as a test-runner. To run both xquery and javascript unit-tests type:

```bash
npm test
```

### Integration-tests

This app uses [cypress](https://www.cypress.io) for integration tests, just type:

```bash
npm run cypress
```

Alternatively, use npx:

```bash
npx cypress open
```


## Contributing

You can take a look at the [Contribution guidelines for this project](.github/CONTRIBUTING.md)

## License

AGPL-3.0 © [Joe Wicentowski](https://joewiz.org)

[license-img]: https://img.shields.io/badge/license-AGPL%20v3-blue.svg
[license-url]: https://www.gnu.org/licenses/agpl-3.0
[release-img]: https://img.shields.io/badge/release-1.0.0-green.svg
[release-url]: https://github.com/joewiz/airtable.xq/releases/latest
[coveralls-image]: https://coveralls.io/repos/joewiz/airtable.xq/badge.svg
[coveralls-url]: https://coveralls.io/r/joewiz/airtable.xq
