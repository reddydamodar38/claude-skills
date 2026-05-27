# Source Priority

Use this file when the question is about what TORQ currently does, which docs are stale, or which repo should win when sources disagree.

## Priority Order

Prefer sources in roughly this order:

1. Current behavior in `abl_jenkins_lib`
2. Current job and Jenkins definitions in `torq-image/casc_configs`
3. Current operator docs in `torq/docs/content`
4. `torq/README.md` and repo changelogs
5. Historical notes, memory, or screenshots

## Source Roles

- `abl_jenkins_lib`
  - strongest source for orchestration behavior, stage order, config precedence, and failure handling
- `torq-image/casc_configs`
  - strongest source for `Create Pipeline`, Jenkins views, global libraries, built-in job definitions, and default parameter shapes
- `torq/docs/content`
  - strongest narrative source for operator instructions and examples
- `torq/README.md`
  - strongest high-level source for install intent, environment variables, and repo purpose

## Current Practice Overrides

Use these as current working assumptions unless stronger local evidence contradicts them:

- `Create Pipeline` is the standard path for creating testing pipelines.
- `AutoCatalog` is deprecated and should not be the default recommendation.
- `State Machine` exists in the library but is not a standard operator path. Verify before recommending it.

## Stale-Doc Heuristics

Trust a TORQ doc less when it:
- points to the old wiki
- calls out `1.X` or another clearly historical version scope
- describes a path the team says is deprecated
- conflicts with current Groovy or JCasC definitions
- mentions a testing-pipeline field that no longer exists
- understates `test_config` as only an Alva concern when current code supports more sections

When docs conflict with code:
- treat code as the source of truth for current behavior
- use the doc only for operator wording, examples, or background

Known current examples of likely doc drift:

- older operator docs may mention a `custom_scripts` Jenkins parameter, but current generated testing pipelines move that behavior into `test_config`
- older wording may say `test_config` is only for Alva, but current library code builds multiple sections from defaults under `abl_jenkins_lib/resources`

## Answer Framing

When confidence is high:
- answer directly
- name the repo or file class you trusted

When confidence is medium:
- answer with a short qualifier
- point to the repo or file that should verify it

When confidence is low:
- explain what looks stale
- ask for the smallest missing artifact such as a pipeline link, failing stage, or repo path
