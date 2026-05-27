# Config Authoring

Use this file when the user is writing or debugging `load_generator_config`, `test_config`, custom scripts, or YAML precedence.

## Mental Model

There are two main config surfaces:

- `load_generator_config`
  - controls the load generators and their data or workflow inputs
- `test_config`
  - controls TORQ behavior and environment-related settings such as custom scripts, ABL checks, SCP, and some platform-specific behavior

For the actual current job fields, read `references/pipeline-fields.md`.
For the default source files, read `references/defaults-map.md`.

## `test_config` Precedence

Current code builds `test_config` in this order:

1. default section resources from `abl_jenkins_lib`
2. TORQ-global `/code/test_config.yaml`
3. subproject `code/test_config.yaml`
4. Jenkins `test_config` parameter

Practical rule:
- Jenkins wins last
- subproject code wins over TORQ-global defaults
- library defaults fill in anything not provided

Special case:
- `abl_checks` has custom merge behavior for the `checks` list in `vars/abl_checks.groovy`, because normal map merge logic does not merge lists intelligently

## `load_generator_config` Precedence

Current code reads and merges load config in this order:

1. TORQ-global `/code/load_generator.yaml`
2. optional git-backed load config referenced from `test_config.torq.load_generator_config.git`
3. subproject `code/load_generator.yaml`
4. Jenkins `load_generator_config` parameter

Then the per-load-generator readers apply defaults and calculated fields from `abl_jenkins_lib`.

Practical rule:
- Jenkins wins last
- subproject code wins over TORQ-global and git-backed base config
- git-backed config can act like a shared base layer

## What Current Code Actually Supports

`commands.generate_test_config()` currently builds these sections:

- `alva`
- `elk`
- `scalability`
- `torq`
- `k8s`
- `rtms`
- `scp`
- `insight`

`abl_checks` is also supported, but handled through separate merge logic in `abl_checks.groovy`.

Important drift note:

- older wording in TORQ docs may say `test_config` is only for Alva
- current library code supports many more sections than that

## Maintainer Note

If the merge behavior looks strange in code:

- `commands.groovy` rewrites top-level `gatling_docker` and `gatling_crank` keys under a `gatling` map before final merging
- generated config behavior ultimately comes from `generate_load_generator_config()` and the per-type readers

## Common `test_config` Areas

- `torq.failure_email`
  - targeted failure recipients
- `torq.resume`
  - only meaningful when the previous attempt failed during prep
- `torq.load_generator_config.git`
  - points TORQ at an external repo for base load generator config
- `torq.custom_scripts`
  - subproject, folder, and GitHub-based custom script sources
- `abl_scripts`
  - checks that can warn, email, or pause before prep continues
- `scp`
  - hierarchical SCP settings by global, label, or node
- `insight`
  - report-generation and parsing containers
- `elk`
  - filebeat, metricbeat, ELK injection, summary email, backup, and related behavior
- `k8s`
  - Kubernetes-side operations when enabled
- `rtms`
  - RTMS collector settings
- `scalability`
  - automated multi-run scaling behavior

## Custom Scripts

Custom scripts can come from:

- subproject `code` folder
- shared folder locations
- GitHub repos

Important behavior:

- TORQ copies them to the nodes under `test_data`
- logs go to `custom_scripts_output`
- non-`user_def` scripts run as the Jenkins agent user
- file endings matter by OS

Important current note:

- current generated testing pipelines do not expose a separate `custom_scripts` parameter
- custom script behavior now lives under `test_config`

## Validation and Syntax Errors

`abl_checks.groovy` validates YAML in:

- Jenkins `load_generator_config`
- Jenkins `test_config`
- subproject `code/load_generator.yaml`
- subproject `code/test_config.yaml`

If YAML is invalid, TORQ can pause and ask for corrected input before proceeding.

## Useful Output

- final merged load generator config is written to `<test folder>/JENKINS/load_generator.yaml`

When debugging authored config, prefer checking the generated artifact and Jenkins console output instead of trusting only the input text boxes.
