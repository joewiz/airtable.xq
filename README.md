# airtable.xq

[![License][license-img]][license-url]
[![GitHub release][release-img]][release-url]
![exist-db CI](https://github.com/joewiz/airtable.xq/workflows/exist-db%20CI/badge.svg)
[![Coverage percentage][coveralls-image]][coveralls-url]

<img src="icon.png" align="left" width="25%"/>

A library for the Airtable Web API, using XQuery

## Overview

The library module in the `content` directory contains functions for 
communicating with [Airtable’s Web API](https://airtable.com/developers/web/api/introduction) 
via XQuery. To use the library module, either import it directly from the 
content directory, or [install](#requirements) or [build](#building-from-source) 
the package and import the library module with:

```xquery
import module namespace airtable="http://joewiz.org/ns/xquery/airtable";
```

The library contains the following functions, all of which require a personal
access token or a service account access token from Airtable.

### Web API functions

#### General

- `airtable:get-user-info()`

#### Base Data

##### Bases

- `airtable:list-bases()`
- `airtable:get-base-schema()`

##### Records

- `airtable:create-records()`
- `airtable:retrieve-record()`
- `airtable:list-records()`
- `airtable:update-records()`
- `airtable:delete-records()`

### How it works

The library sends requests to the Airtable API using the EXPath HTTP Client
library. (See eXist notes below.)

Successful responses (with status 200) are returned with the response body’s 
JSON object parsed as a map. 

When a response indicates an error (a non-200 status), the library’s 
functions all return a map with an "error" entry, with subentries to aid in 
debugging: request, response head and body, rate limit assessments, start and 
end dateTimes, and duration in seconds.

Function documentation is adapted from the Airtable API to conform to XQuery 
style conventions. XDM terminology replaces JSON terminology, and parameters 
are kebab case rather than camel case. 

### XQuery compatibility

The library uses standard XQuery 3.1, but is dependent on eXist in two areas:

1. eXist’s EXPath HTTP Client module returns JSON as xs:base64Binary, so 
`util:binary-to-string()` is always needed before the JSON can be parsed.

2. To prevent hitting the Airtable API’s rate limits, we use eXist’s 
`cache` module to store the dateTime of the last request. If a delay is needed 
before a request can be submitted, the `util:wait()` function is used.

To adapt the library to another processor, you may adapt these `util` and 
`cache` functions to those of your processor. 

### Caveats

- The "typecast" parameter for automatic data conversion for list, create, and 
update actions hasn’t been implemented.
- No special handling for User and Server error codes except rate limits; 
instead, full HTTP response headers are returned.

### About this repository

Thanks to @duncdrum for his contributions to [generator-exist](https://github.com/eXist-db/generator-exist)
tool, which generated all of the scaffolding for this app—EXPath package 
descriptors, GitHub templates, and GitHub Actions actions. I used the "blank" 
template. I've made only minimal changes to the assets generated by this tool.

More recently, I've adopted the CI approach used by @duncdrum in [aws.xq](https://github.com/HistoryAtState/aws.xq).

## Requirements

*   [eXist-db](https://exist-db.org) version: `5.0.0` or greater

*   [ant](https://ant.apache.org) version: `1.10.7` \(for building from source\)

*   [node](https://nodejs.org) version: `12.x` \(for building from source\)
    

## Installation

1.  Download the `airtable.xar` file from GitHub [releases](https://github.com/joewiz/airtable.xq/releases) page.

2.  Open the [Dashboard](http://localhost:8080/exist/apps/dashboard/index.html) on your eXist-db instance and click on `Package Manager`.

    1.  Click on the `Upload` button in the upper left corner and select the `.xar` file you just downloaded.

3.  You have successfully installed airtable.xq into eXist.

### Building from source

1.  Download, fork or clone this GitHub repository
2.  The default build target in `build.xml` is `xar`
3.  Calling `ant`in your CLI will build both files:
  
```bash
cd airtable.xq
ant
```

Since releases have been automated when building locally you might want to supply your own version number (e.g. `X.X.X`) like this:

```shell
ant -Dapp.version=X.X.X
```

If you see `BUILD SUCCESSFUL` ant has generated a `airtable.xar` file in the `build/` folder. To install it, follow the instructions [above](#installation).

## Contributing

You can take a look at the [Contribution guidelines for this project](.github/CONTRIBUTING.md)

## Release

Releases for this data package are automated. Any commit to the `main` branch will trigger the release automation.

All commit message must conform to [Conventional Commit Messages](https://www.conventionalcommits.org/en/v1.0.0/) to determine semantic versioning of releases, please adhere to these conventions, like so:

| Commit message  | Release type |
|-----------------|--------------|
| `fix(pencil): stop graphite breaking when too much pressure applied` | Patch Release |
| `feat(pencil): add 'graphiteWidth' option` | ~~Minor~~ Feature Release |
| `perf(pencil): remove graphiteWidth option`<br/><br/>`BREAKING CHANGE: The graphiteWidth option has been removed.`<br/>`The default graphite width of 10mm is always used for performance reasons.` | ~~Major~~ Breaking Release |

When opening PRs commit messages are checked using commitlint.

## License

AGPL-3.0 © [Joe Wicentowski](https://joewiz.org)

[license-img]: https://img.shields.io/badge/license-AGPL%20v3-blue.svg
[license-url]: https://www.gnu.org/licenses/agpl-3.0
[release-img]: https://img.shields.io/github/v/release/joewiz/airtable.xq?sort=semver
[release-url]: https://github.com/joewiz/airtable.xq/releases/latest
[coveralls-image]: https://coveralls.io/repos/joewiz/airtable.xq/badge.svg
[coveralls-url]: https://coveralls.io/r/joewiz/airtable.xq
