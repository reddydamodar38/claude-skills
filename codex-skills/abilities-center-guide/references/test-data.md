# Test Data

Use this file when the question is about where test output lives, how test folders are named, what artifacts should exist after a run, or which copy of the data should be treated as authoritative.

## Source of Truth

Treat the test folder itself as the source of truth for a test run.

Some data is parsed and shipped into downstream systems such as OpenSearch for easier browsing, but that data is considered more ephemeral than the original test folder contents.

## Common Share Language

- The shared location is often referred to as `ablpub`.
- The actual share name is commonly `ablpub` or `ABLPUB`, but not always.
- Many environments mount the share so the node path matches the share path, commonly `/ablpub` or `/ABLPUB`.

## Typical Test Folder Path

The usual layout is:

`/ablpub/<org-name>/<subproject-name>/<test-name>/`

Case matters.

For names, special characters are generally avoided except:
- `_`
- `.`

## Test Name Format

The expected test-name pattern is:

`YYYYMMDD_<Subproject>_<UserCount>_R###_<Suffix>`

Notes:
- `UserCount` should be a positive whole number
- `R###` is the run number with zero padding for smaller values
- the run-number portion is at least `R##`, then naturally grows such as `R100`, `R101`, and so on
- `Suffix` is optional but strongly encouraged
- the suffix normally comes from the Jenkins pipeline run field

## Common Contents Inside a Test Folder

A test folder commonly contains:
- one folder per host used in the run, named as the short hostname in uppercase
- `JENKINS` for TORQ or Jenkins-generated support files such as report or injection container output
- `insight` for Insight-related files such as cache or related support data

Metricbeat backup data commonly lives under:

`JENKINS/ELK/backup`

More detailed Elasticsearch or OpenSearch handling belongs in a future dedicated skill.

## Archive and Compression Behavior

There is a tool called `ragnarok` that may later compress a test folder into a zip.

When that happens:
- the zip is typically created inside the test folder
- the zip name typically matches the test name

`ragnarok` may also archive the test into an OCI bucket later.
When that happens, it should leave a text file behind that tells the user where to download it from if needed.

## Mounting Variations

Most environments mount the share path in a way that matches the remote share layout.

There are exceptions:
- some environments mount a remote subfolder as the effective root share
- `ablscale` environments are a known example, where a remote path such as `/ABLPUB/ablscale#` may be mounted on nodes simply as `/ABLPUB`
- some DH2 environments in the `ablcaputil` space may follow a similar pattern

When a folder is not where the user expects, check whether the environment mounts a subfolder as the local share root before assuming the data is missing.

## Response Pattern

When helping with test-data questions:

1. confirm the environment and expected share root
2. normalize the expected test-name format
3. check the test folder first before downstream systems
4. call out mount variations or archive behavior if the folder appears incomplete
