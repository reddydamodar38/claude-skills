# Troubleshooting

Use this file when a TORQ job failed, paused unexpectedly, created the wrong behavior, or seems to disagree with the docs.

## First Triage Questions

Identify:

- which TORQ URL is being used
  - if unknown, ask for the exact URL first
- which job failed
  - `Create Pipeline` or a testing pipeline
- which phase failed
  - create, verify, prep, submit, run, collect, or post
- whether the issue is config, node, load generator, or share-related

## URL-First Triage

Before troubleshooting deeply, anchor on the TORQ instance.

Common URL patterns:

- DH2 or on-prem:
  - often `http://dh2torqvip1.dh2.cerner.com/<env>/`
- OCI:
  - often `http://<ip>:<port>/<env>/`
  - best to ask for the exact URL
- EOD:
  - often `http://<ip>:8081/`
  - usually no environment path prefix

Network prerequisites:

- Abilities Lab VPN is generally required
- OCI usually also requires being inside the lab network

Anonymous read access should generally be available, so once the exact URL is known, Jenkins APIs can often be used for read-only job discovery.

Useful Jenkins API patterns after the base URL is known:

- `<base>/api/json`
- `<base>/job/<pipeline>/api/json`
- `<base>/crumbIssuer/api/json`
- `<base>/job/<pipeline>/buildWithParameters` (POST)

Use API inspection when it is faster than clicking through pages and the question is about listing jobs, reading parameters, or confirming pipeline existence.

## Triggering A Run By API

When the user asks to kick off a run, this sequence is the safest default:

1. verify the job exists:
   - `GET <base>/job/<pipeline>/api/json`
2. get current parameter defaults:
   - read `actions[].parameterDefinitions[]` from job API
   - if possible, build a pre-submit parameter preview for the user
3. update metadata before submit:
   - set a non-placeholder `description` (required unless user explicitly says keep default)
   - if `suffix` is `discard` or blank, set a meaningful suffix
4. fetch a CSRF crumb:
   - `GET <base>/crumbIssuer/api/json`
5. trigger:
   - defaults-only: `POST <base>/job/<pipeline>/buildWithParameters` with empty form data
   - preferred in practice: submit `buildWithParameters` including updated `description` and `suffix`
6. confirm queue item and build number:
   - read `Location` header (queue URL), then `GET <queue>/api/json`

Practical notes:

- many TORQ jobs are parameterized; `buildWithParameters` is usually safer than `build`
- Jenkins crumb validation often requires using the same session cookie jar for crumb fetch and POST
- if response is `201 Created`, trigger was accepted
- include a pre-submit parameter display in the response when possible
- always show `load_generator_config` and `test_config` as raw YAML or concise summary

## Parameter Preview Guidance

Before submitting, present the effective parameters, especially when using defaults.

Minimum fields to display:

- `description`
- `suffix`
- `user_count`
- `duration`
- `load_generator`
- `pause_before_submit`
- `test_plan`
- `email`

Config fields to always include:

- `load_generator_config`
- `test_config`

Summary rules:

- if config YAML is short, show it directly
- if config YAML is long, summarize key sections and values that affect behavior
- explicitly state which values were inherited defaults vs agent-updated overrides

## Symptom Routing

### `Create Pipeline` is wrong or fails

Inspect first:

- `torq-image/casc_configs/create-pipeline.yaml`

Use this when:

- parameter defaults are wrong
- dynamic UI content is wrong
- created pipelines look malformed
- operator behavior differs before the actual test run starts

### API trigger returns 403 or 400

Common causes:

- `403 No valid crumb was included in the request`
  - fetch crumb from `<base>/crumbIssuer/api/json`
  - include crumb header and preserve session cookies between crumb request and POST
- `400 Nothing is submitted`
  - use `buildWithParameters` and send empty form data for a defaults-only run

Quick verification path:

- check queue item URL from `Location` header
- confirm `executable.number` and `executable.url` on queue item API

### YAML is invalid or config is not being accepted

Inspect first:

- `abl_jenkins_lib/vars/abl_checks.groovy`
- `abl_jenkins_lib/vars/context.groovy`
- `abl_jenkins_lib/vars/commands.groovy`

Likely causes:

- invalid YAML in Jenkins parameters
- invalid YAML in subproject `code` files
- misunderstanding of precedence between TORQ-global, subproject, git-backed, and Jenkins config

### Test pauses before submit or prep

Common causes:

- `pause_before_submit` was intentionally set
- ABL checks found a red condition and paused for human input
- the job is waiting on manual correction of invalid YAML or another input gate

Inspect:

- `torq/docs/content/doc/abl_scripts.md`
- `abl_jenkins_lib/vars/abl_checks.groovy`

### Test behavior does not match authored config

Check in this order:

1. selected `load_generator` types
2. final source precedence
3. generated `<test folder>/JENKINS/load_generator.yaml`
4. load-generator-specific code paths in `abl_jenkins_lib`

Remember:

- unused sections can exist in config and still not run if the load generator type was not selected
- Jenkins config wins last

### Collect fails

Inspect first:

- `abl_jenkins_lib/vars/abl.groovy`

Useful current hint from the code:

- collect failures are often treated as share-space problems first

Also check:

- share availability
- test data paths
- node disk space
- whether earlier stages left the environment in a bad state

### Node or agent behavior is wrong

Inspect:

- node configuration in TORQ JCasC files and `casc_custom`
- `torq/docs/content/doc/node_setup/setup_node.md`
- label-driven behavior in load generator config

### Docs say one thing, jobs do another

Default to:

- `abl_jenkins_lib` for runtime behavior
- `torq-image` for Jenkins job behavior

Treat older operator docs as helpful context, not final proof.

## Maintainer Escalation Hints

When the answer needs code-level diagnosis:

- use `torq-image` for job-definition bugs
- use `abl_jenkins_lib` for execution or merge bugs
- use `torq` docs for user-facing wording and examples

If the issue appears tied to deprecated paths:

- do not default to `AutoCatalog`
- verify whether `State Machine` is even intended to be used before debugging it deeply
