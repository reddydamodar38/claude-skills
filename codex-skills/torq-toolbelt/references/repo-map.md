# Repo Map

Use this file when you need to decide which TORQ repo owns a behavior or where to inspect next.

## TORQ Repo Roles

- `torq`
  - TORQ container runtime, `.env` settings, `docker-compose.yml`, and the Hugo docs under `docs/content`
- `torq-image`
  - TORQ image build, Jenkins Configuration as Code, built-in pipeline jobs, theming, and startup migration behavior
- `abl_jenkins_lib`
  - actual Jenkins shared library and orchestration logic used by TORQ jobs

## High-Value Files

### `torq`

- `README.md`
  - environment variables and runtime intent
- `docker-compose.yml`
  - container launch behavior and TORQ env var wiring
- `docs/content/doc/run_a_test.md`
  - operator build-with-parameters guidance
- `docs/content/doc/order_of_execute/order_of_execute.md`
  - historical but still useful execution flow map
- `docs/content/doc/load_generaotr_config.md`
  - load generator config authoring
- `docs/content/doc/test_config.md`
  - test config authoring
- `docs/content/doc/custom_scripts.md`
  - custom scripts behavior and locations
- `docs/content/doc/abl_scripts.md`
  - ABL checks behavior

### `torq-image`

- `casc_configs/create-pipeline.yaml`
  - standard `Create Pipeline` job definition
- `casc_configs/jenkins.yaml`
  - global Jenkins configuration, views, shared library linkage, and built-in tools
- `entrypoint.sh`
  - startup behavior and deprecation of older job names
- other `casc_configs/*.yaml`
  - specialized built-in jobs such as ABL checks, firewall management, and Eggplant-to-Gatling helpers

### `abl_jenkins_lib`

- `vars/context.groovy`
  - builds the TORQ execution context and merges config sources
- `vars/commands.groovy`
  - merge logic, test config setup, and load generator config reading
- `vars/abl_checks.groovy`
  - YAML validation and ABL checks behavior
- `vars/abl.groovy`
  - core prep, submit, run, collect, and post behavior
- `vars/statemachine.groovy`
  - automated pipeline creation path that is not the standard operator recommendation

## Ownership Hints

If the problem is:

- Jenkins job shape, parameter UI, or generated pipeline creation
  - inspect `torq-image` first
- how a test actually executes or merges config
  - inspect `abl_jenkins_lib` first
- install, runtime env vars, or operator docs
  - inspect `torq` first

## TORQ vs TACO Boundary

Use TORQ for:
- creating and running test pipelines
- authoring TORQ config
- troubleshooting TORQ job behavior

Leave TORQ for TACO or node-orchestration concerns when the question is mainly about:
- provisioning nodes
- inventory selection
- Terraform or Ansible flows
- runner setup outside Jenkins job behavior
