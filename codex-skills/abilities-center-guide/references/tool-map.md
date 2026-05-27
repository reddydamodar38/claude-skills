# Tool Map

Use this file to orient broad Abilities Center questions before routing into a narrower skill or repo.

## Tool Families

- TORQ test execution
  - Typical need: create or run TORQ testing pipelines, author TORQ config, or troubleshoot TORQ job failures
  - Start with: `torq-toolbelt`
- Data access and DB validation
  - Typical need: run Oracle SQL, inspect schema data, verify records
  - Start with: `sqlplus`
- Remote host access
  - Typical need: inspect logs, check files, verify remote state
  - Start with: `ssh` for Linux or Unix, `ssh-win` for Windows
- Runner readiness
  - Typical need: make Docker or Compose usable on a Linux execution host
  - Start with: `docker-runner-setup`
- Repo contribution workflow
  - Typical need: set up repo access, choose a branch, commit, push, open a PR, or understand release expectations
  - Start with: `repo-workflow-guide`
- Node orchestration
  - Typical need: run TACO, choose inventory, execute Ansible, or handle Terraform-backed node flows
  - Start with: `node-orchestration-runner`
- Gatling performance workflow
  - Typical need: convert, run, fix, or regenerate data for Gatling scenarios
  - Start with: `gatling-converter`, `gatling-runner`, `gatling-fixer`, `gatling-scenario-data-creator`, or `gatling-pipline`
- Eggplant workflow
  - Typical need: clean, convert, or run Eggplant suites used in performance-style flows
  - Start with: `eggplant-script-cleaner`, `eggplant-converter`, or `eggplant-runner`
- Skill maintenance
  - Typical need: refresh installed skills or fix stale local links
  - Start with: `codex-skills-updater`

## Selection Hints

Choose based on the user's actual goal, not just the product name:

- If they need a query result, choose the DB skill.
- If they need to inspect a remote failure, choose an SSH-oriented skill.
- If they need to execute orchestration or infra workflows, choose the node-orchestration skill.
- If they are trying to understand which of several tools applies, stay in the umbrella skill first and narrow the target.

## Unknown Tool Names

If the tool name is unfamiliar:

1. treat the name as a discovery term
2. search local repos and docs for the exact token
3. map it to a tool family
4. then route to the sibling skill or likely repo
