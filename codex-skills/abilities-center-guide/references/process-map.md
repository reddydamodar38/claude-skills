# Process Map

Use this file when the user is asking how something is supposed to work rather than asking to run a specific command.

## Common Question Shapes

- "What is the right process for this?"
- "What order do these steps usually happen in?"
- "What should I check before I run this?"
- "Why would someone use tool A instead of tool B?"
- "What is the source of truth for this workflow?"

## Process Answer Pattern

Answer in this order:

1. state the likely process or decision path
2. name the key artifact that should confirm it
3. call out any assumptions or stale-doc risk
4. route to the exact tool or repo that carries out the work

## Evidence to Gather

For process questions, look for:
- entrypoint commands
- runner prerequisites
- required inventories or environment selectors
- data or credential dependencies
- validation or output artifacts
- cleanup or follow-up steps
- shared test-folder conventions when the output of the process matters

## Useful Distinctions

Separate these clearly when answering:

- discovery vs execution
- supported process vs historical process
- shared pattern vs tool-specific requirement
- current automation vs manual fallback

## When to Ask a Clarifying Question

Ask one short question when the answer changes materially based on:
- tool family
- target environment
- operating system
- runner location
- read-only vs apply intent

Do not ask broad questions if you can first narrow the domain from local artifacts.
