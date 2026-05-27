# Source Priority

Use this file when the question is about what is correct, current, supported, or official.

## Priority Order

Prefer sources in roughly this order:

1. Current code and automation that is actively used
2. Current repo-local configuration, examples, templates, and tests
3. Current team-maintained operational docs or runbooks
4. Shared documentation repos such as `abilities-center/.github-private`
5. Recent issue discussions or PRs that explain an intentional change
6. Human memory, assumptions, or patterns carried over from similar systems

## How to Treat Shared Docs Repos

Shared documentation repos can be strong sources for maintained process guidance, links, and ownership context.
Do not treat any doc repo as automatic source of truth for live behavior when active code or automation says otherwise.

Use shared docs repos to find:
- likely repo names
- tool names
- environment names
- supported process names
- likely owners or teams
- links to deeper docs or runbooks

Verify doc-derived claims against stronger sources before stating:
- current run commands
- current environment expectations
- authentication details
- support boundaries
- exact workflow steps
- ownership claims

## Trust Heuristics

Prefer a source more when it:
- is closer to execution
- is updated recently
- is owned by the team operating the tool
- matches current filenames, paths, and commands seen locally
- is consistent with current automation behavior

Trust a source less when it:
- uses old naming
- references retired hosts or environments
- describes manual steps that newer automation replaced
- conflicts with current repo structure
- has no owner or update history

## Answer Framing

When confidence is high:
- answer directly
- cite the stronger source category you used

When confidence is medium:
- answer with a confidence qualifier
- name the likely verification point

When confidence is low:
- do not present guesses as settled facts
- provide the best next place to check
- ask for the smallest missing artifact needed to verify

## Conflict Template

Use a short structure like:

- `What looks current:` source closest to execution
- `What conflicts:` older or weaker source
- `Recommendation:` what to trust next and what to verify
