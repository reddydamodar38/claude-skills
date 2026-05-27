# Defaults Map

Use this file when the question is "what does TORQ assume by default?" or "where do the default config values come from?"

## Canonical Default Sources

When the `abl_jenkins_lib` repo is available, defaults primarily come from:

- `resources/torq/test_config.yaml`
- `resources/abl_checks/test_config.yaml`
- `resources/alva/test_config.yaml`
- `resources/elk/test_config.yaml`
- `resources/insight/test_config.yaml`
- `resources/k8s/test_config.yaml`
- `resources/rtms/test_config.yaml`
- `resources/scalability/test_config.yaml`
- `resources/scp/test_config.yaml`
- `resources/gatling/load_generator.yaml`
- `resources/eggplant/load_generator.yaml`
- `resources/drones/load_generator.yaml`

## What These Files Mean

- `resources/torq/test_config.yaml`
  - TORQ-specific defaults such as custom script sources and failure email behavior
- `resources/abl_checks/test_config.yaml`
  - preflight validation and pause-or-email behavior before a run proceeds
- `resources/alva/test_config.yaml`
  - Alva deployment and service defaults
- `resources/elk/test_config.yaml`
  - ELK, filebeat, metricbeat, backup, and reporting defaults
- `resources/insight/test_config.yaml`
  - insight reporting defaults
- `resources/k8s/test_config.yaml`
  - Kubernetes-side defaults
- `resources/rtms/test_config.yaml`
  - RTMS defaults
- `resources/scalability/test_config.yaml`
  - multi-run scaling defaults
- `resources/scp/test_config.yaml`
  - SCP override structure
- `resources/gatling/load_generator.yaml`
  - Gatling crank and Gatling Docker defaults
- `resources/eggplant/load_generator.yaml`
  - Eggplant and Eggplant Docker defaults
- `resources/drones/load_generator.yaml`
  - drone replay defaults and single-user related defaults

## Practical Rules

- treat these checked-in resource files as the baseline defaults
- then apply TORQ-global config, subproject config, and Jenkins parameters on top
- do not treat local untracked files or side-project override files as canonical defaults unless the user explicitly says they are in play

## Useful Current Examples

- `resources/torq/test_config.yaml`
  - shows that TORQ custom script sources are now part of `test_config`
- `resources/gatling/load_generator.yaml`
  - shows the real default keys for `gatling_crank` and `gatling_docker`
- `resources/eggplant/load_generator.yaml`
  - shows lead time and helper suite defaults for Eggplant paths
- `resources/abl_checks/test_config.yaml`
  - shows which preflight checks TORQ expects by default and how they can pause or fail a run

## Maintainer Note

Not every load-generator-related path is exposed through one uniform generic reader.

Examples:

- generic merge behavior is centered in `commands.groovy`
- Gatling and Eggplant Docker apply their own per-type defaults after merging
- drones and eggplant-functional paths have additional specialized logic
