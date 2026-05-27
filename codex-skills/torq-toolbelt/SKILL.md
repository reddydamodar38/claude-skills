---
name: torq-toolbelt
description: Answer questions about TORQ (Test Order/Runner/Queuer) jobs, testing pipelines, create-pipeline usage, load_generator_config, test_config, custom scripts, node setup, and troubleshooting TORQ failures. Use when Codex needs to explain how TORQ works, determine which TORQ repo owns a behavior, help author TORQ config YAML, or investigate why a TORQ pipeline or test failed.
---

# TORQ Help

Use this skill for TORQ user and operator questions first, then maintainer diagnosis when the behavior is unclear.
Prefer current behavior from `abl_jenkins_lib` and `torq-image` over narrative docs when they disagree.

## Workflow

1. Classify the question before reading deeply:
- operator usage
- config authoring
- failure or troubleshooting
- repo ownership or maintainer diagnosis
- TORQ boundary vs another tool such as TACO
2. For operator run or config update requests, perform API-write preflight before planning a submit:
- verify whether anonymous read-only access is in effect by checking for login redirects on configure or config endpoints
- assume CSRF crumb is required for POST requests unless proven otherwise
- plan to fetch `<base>/crumbIssuer/api/json` and preserve the same session cookie jar for the submit call
- if authentication is required, surface that early instead of attempting a write first
3. For operator run requests, ask this first:
- "Do you already have a testing pipeline, or is this a new project that still needs `Create Pipeline`?"
- If pipeline exists, route directly to the testing pipeline run path and do not default to `Create Pipeline` steps.
- If pipeline does not exist, route to `Create Pipeline` first.
4. Before triggering a run, show the effective parameters that will be sent:
- Always include `description`, `suffix`, `user_count`, `duration`, `load_generator`, `pause_before_submit`, `test_plan`, `email`.
- Always include `load_generator_config` and `test_config` as either raw YAML (if short) or concise summary.
- If parameter values are generated or inferred, call that out explicitly.
5. For run submissions, treat `description` updates as required:
- Do not submit with placeholder/default text when avoidable.
- If user does not provide wording, set a clear provenance note such as "submitted with torq-toolbelt skill via codex" plus brief intent.
6. For run submissions, treat `suffix` updates as strongly recommended:
- If current suffix is `discard` or empty, replace it with a short meaningful suffix.
- If user gave no suffix, infer one from context and say what was used.
7. Read `references/source-priority.md` first when the user is asking what TORQ does now.
8. Read only one or two additional references that match the question:
- `references/repo-map.md` for repo boundaries and key files
- `references/operator-paths.md` for the standard user path and nonstandard legacy paths
- `references/pipeline-fields.md` for the actual fields in `Create Pipeline` and the generated testing pipeline
- `references/config-authoring.md` for `load_generator_config`, `test_config`, custom scripts, and precedence
- `references/defaults-map.md` for where TORQ and load generator defaults come from in `abl_jenkins_lib/resources`
- `references/troubleshooting.md` for failure investigation and symptom-to-file routing
9. Prefer operator-friendly explanations first. Only dive into Groovy or JCasC internals when the question requires maintainer depth.
10. Route away from TORQ when the question is really about environment provisioning, inventory automation, or runner setup rather than TORQ job behavior.
11. Route back to `abilities-center-guide` when the question is broader than TORQ itself, especially for shared environment terminology, test-folder conventions, repo discovery, or cross-tool process questions.

## Source Handling

- Treat `abl_jenkins_lib` as the strongest source for current execution behavior.
- Treat `torq-image/casc_configs` as the strongest source for Jenkins job definitions, default parameters, views, and the standard `Create Pipeline` path.
- Treat `torq/docs/content` as the main narrative documentation source, but expect some pages to be stale.
- Treat `torq/README.md` and changelogs as setup and orientation aids, not the final word on runtime behavior.
- Use user-provided org knowledge when it clarifies current practice:
  - `Create Pipeline` is the standard path.
  - `AutoCatalog` is effectively deprecated.
  - `State Machine` exists but is not a default recommendation and may be stale.

## Response Style

- Start with the practical answer in TORQ terms, even if the underlying system is Jenkins.
- If the question is configuration-related, explain both where the setting can live and which source wins.
- If the docs and code diverge, say so plainly and explain which source you are trusting.
- If local clones of the TORQ repos are missing, prefer the repo-access workflow from `repo-workflow-guide/references/repo-access.md`: local clone first, then targeted `gh`, then clone if deeper investigation is needed.
- When local `AGENTS.md` guidance exists, use its machine-local repo and auth defaults before rediscovering them.
- If TORQ work keeps rediscovering the same stable machine-local repo or auth facts, suggest capturing them in local `AGENTS.md`.
- If the user is really asking about shared Abilities Center concepts rather than TORQ behavior, say so and route them to `abilities-center-guide`.
- If the user is primarily asking how to commit, push, open a PR, or release a repo change, route them to `repo-workflow-guide`.

## Reference Loading Guide

- Need current-source rules or stale-doc handling: read `references/source-priority.md`
- Need to know which TORQ repo or file owns behavior: read `references/repo-map.md`
- Need the standard operator path or TORQ vs TACO boundary: read `references/operator-paths.md`
- Need the current job field meanings: read `references/pipeline-fields.md`
- Need config precedence or YAML authoring guidance: read `references/config-authoring.md`
- Need to know where defaults actually come from: read `references/defaults-map.md`
- Need failure triage or maintainer diagnosis hints: read `references/troubleshooting.md`
