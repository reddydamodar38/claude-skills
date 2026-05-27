# Operator Paths

Use this file when the user is asking how to use TORQ as an operator or which TORQ path is standard.

## Standard Path

The normal operator flow is:

1. identify the correct TORQ URL for the environment
2. determine whether a testing pipeline already exists for the requested work
3. if it exists, open that testing pipeline directly
4. otherwise use `Create Pipeline` to create or update the testing pipeline
5. open the created testing pipeline
6. click `Build with Parameters`
7. fill in the test parameters and start the run

## First Operator Question

Before explaining steps, ask:

- "Do you already have a testing pipeline, or is this a new project?"

Use this rule:

- existing pipeline
  - do not force `Create Pipeline`; go straight to running the existing job
- new project
  - guide through `Create Pipeline` first, then run the created job

When the user asks to "run now" or use "current defaults", also ask whether they want metadata overrides (`description` and `suffix`) before submit.

## Key Distinction

- `Create Pipeline`
  - standard path for creating testing pipelines
- testing pipeline created by `Create Pipeline`
  - standard path for actually running a test

This matches both current repo structure and current team guidance.

For run requests that mention "current defaults" or "run now", prefer the existing testing pipeline path unless the user says no pipeline exists.

## Run Submit Checklist

Before pressing Build (UI or API), show the run inputs that will be used:

- `description`
- `suffix`
- `user_count`
- `duration`
- `load_generator`
- `load_generator_config`
- `test_config`
- `pause_before_submit`
- `test_plan`
- `email`

For API submit paths, do auth and crumb preflight first:

- verify whether the instance is read-only for anonymous users (`/configure` or `/config.xml` redirect to login is a strong signal)
- fetch crumb from `<base>/crumbIssuer/api/json`
- preserve the same session cookie jar from crumb fetch through `buildWithParameters` POST
- if auth is required, state that before attempting a write

Operator guidance:

- update `description` for almost every run; avoid placeholders like `Change Me`
- if `suffix` is `discard` or blank, replace it with something meaningful
- for `load_generator_config` and `test_config`, provide either:
  - full YAML if short
  - concise summary of key sections/overrides if long

## Common Operator Questions

- "What TORQ URL should I use?"
- "Which TORQ job do I open?"
- "Do I run `Create Pipeline` or the test job?"
- "What does each field in the testing pipeline mean?"
- "Where do I put `load_generator_config`?"
- "Where do I put `test_config`?"
- "Why did my test pause or fail before running?"

## Finding the Right TORQ

For operator help, first anchor on the exact TORQ URL.

Common patterns:

- DH2 or on-prem:
  - often reachable through `http://dh2torqvip1.dh2.cerner.com/<env>/`
- OCI:
  - often uses `http://<ip>:<port>/<env>/`
  - best practice is to ask for the exact URL
- EOD:
  - often uses `http://<ip>:8081/`
  - usually without an environment path prefix

Access assumptions:

- anonymous read access should generally exist for troubleshooting and job discovery
- users still need the right network location
- Abilities Lab VPN is typically required
- OCI access typically requires being inside the lab network

Once the URL is known, TORQ can usually be treated as Jenkins for read-only inspection and job discovery.

For exact current field meanings, read `references/pipeline-fields.md`.

## Important Parameters

Users commonly need help with:

- `organization`
- `subproject`
- `test_type`
- `automation`
- `automation_config`
- `environment_name`
- `dns_suffix`
- `load_generator_config`
- `test_config`
- `pause_before_submit`
- `custom_scripts`
- `custom_variables`

## High-Value Operator Docs

When the docs repo is available, start with:

- `torq/docs/content/doc/run_a_test.md`
- `torq/docs/content/doc/load_generaotr_config.md`
- `torq/docs/content/doc/test_config.md`
- `torq/docs/content/doc/custom_scripts.md`
- `torq/docs/content/doc/abl_scripts.md`

Then verify field-level details against `torq-image/casc_configs/create-pipeline.yaml` if the docs and UI wording differ.

## Current Caution

Do not assume every field named in older docs still exists in the generated testing pipeline.

Current example:

- `custom_scripts`
  - older docs may mention this as a pipeline field
  - current generated testing pipelines moved this behavior into `test_config`

## Nonstandard or Legacy Paths

- `AutoCatalog`
  - treat as deprecated unless the user explicitly says their team still uses it
- `State Machine`
  - exists in the library but is not the default operator recommendation
  - verify before recommending it

## TORQ vs TACO

Explain the boundary this way when helpful:

- TORQ is the user-facing front door for creating and running tests.
- TACO is more about environment setup and automation around the infrastructure.

If the user is really asking about provisioning or inventory automation, route away from this skill.
