# Skill Routing

Use this file to decide whether the question should hand off to a more specific local skill in this repo.

## Routing Rule

If the user wants execution, validation, troubleshooting, or concrete steps for a specific tool family, prefer the corresponding sibling skill after using this umbrella skill to orient.

## Local Skill Map

- `torq-toolbelt`
  - Use for TORQ or Jenkins-based test pipeline questions, especially config authoring, create-pipeline usage, or troubleshooting TORQ failures.
- `sqlplus`
  - Use for Oracle SQL, schema checks, and pulling result sets from FPABL, ABLFHIR, or FPSG.
- `ssh`
  - Use for SSH access to Linux or Unix hosts and remote log inspection.
- `ssh-win`
  - Use for Windows remote access, RDP launch, and Windows-side remote troubleshooting.
- `docker-runner-setup`
  - Use for installing, repairing, or validating Docker and Compose on a Linux runner.
- `repo-workflow-guide`
  - Use for repo setup, git or gh access checks, branch hygiene, commit and push flow, PR creation, or release-oriented repo questions.
- `node-orchestration-runner`
  - Use for TACO or node-orchestration commands, inventory selection, Ansible, or Terraform flows.
- `gatling-runner`
  - Use for running Gatling scenarios on a remote Linux host.
- `gatling-converter`
  - Use for converting Eggplant recordings into Gatling scenarios.
- `gatling-fixer`
  - Use for stabilizing failing Gatling scenarios and KO remediation.
- `gatling-scenario-data-creator`
  - Use for generating or refreshing Gatling `scenario-data.yaml`.
- `gatling-annotation-report`
  - Use for generating annotation resolution reports from scenario and replies YAML.
- `gatling-pipline`
  - Use for end-to-end converter, runner, fixer, and scenario-data flows.
- `eggplant-runner`
  - Use for running Eggplant workflows remotely through Docker.
- `eggplant-converter`
  - Use for converting functional Eggplant scripts into perf-style scripts.
- `eggplant-script-cleaner`
  - Use for cleaning up legacy Eggplant workflows and aligning data/resources.
- `codex-skills-updater`
  - Use for refreshing installed skill copies and syncing symlinks.

## Routing Examples

- "How does TORQ create or run a testing pipeline?" -> route to `torq-toolbelt`
- "Why is my TORQ `load_generator_config` not behaving as expected?" -> route to `torq-toolbelt`
- "Which runner should I use for node-orchestration on Linux?" -> start here, then move to `node-orchestration-runner`
- "How do I commit, push, or open a PR for this repo?" -> route to `repo-workflow-guide`
- "How is this repo released?" -> route to `repo-workflow-guide`
- "How do I access or clone this repo?" -> route to `repo-workflow-guide`
- "How do I query ABLFHIR?" -> route to `sqlplus`
- "Where do I troubleshoot a remote Linux run log?" -> route to `ssh` or a tool-specific runner skill
- "I only know the tool name and need the repo or docs" -> stay in this umbrella skill first

## If No Skill Fits

Stay in this skill when the request is mostly about:
- discovery
- terminology
- ownership ambiguity
- document hunting
- process orientation
- comparing several possible tools before choosing one
