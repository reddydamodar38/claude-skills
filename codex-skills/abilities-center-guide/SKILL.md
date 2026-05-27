---
name: abilities-center-guide
description: Answer questions about Abilities Center tools, processes, documentation, ownership, expected behavior, and where information is likely located. Use when Codex needs help finding the right repo, doc, runner, environment, workflow, or sibling skill for Abilities Center work, especially for prompts like "where is this documented?", "how is this supposed to work?", "what tool should I use?", or "who/what/where should I check next?"
---

# Abilities Center Guide

Use this skill as a lightweight router for Abilities Center knowledge.
Keep the main flow small. Load only the reference file needed for the current question.

## Workflow

1. Classify the question before reading deeply:
- tool selection or tool behavior
- process or workflow guidance
- "where is this documented?" discovery
- ownership or source-of-truth uncertainty
- handoff to a more specific sibling skill
2. Read `references/source-priority.md` first whenever the answer depends on trust, freshness, or conflicting docs.
3. Read only one or two additional reference files that match the question:
- `references/skill-routing.md` for matching the request to a sibling skill in this repo
- `references/where-to-look.md` for likely locations of docs, repos, configs, and operational notes
- `references/lab-topology.md` for shared Abilities Center or Abilities Lab terminology, environment groupings, and access patterns
- `references/local-agents-guidance.md` for what belongs in machine-local `AGENTS.md` defaults versus skill or repo-level guidance
- `references/test-data.md` for shared test-folder naming, path, artifact, and archive conventions
- `references/doc-sources.md` for shared documentation locations, including `abilities-center/.github-private`
- `references/tool-map.md` for tool families and what each one is generally for
- `references/process-map.md` for common process-style questions and the usual evidence to gather
- `references/gap-capture.md` when the answer is incomplete and you need to ask for durable source material
4. Prefer the narrowest reliable answer. If the source is weak, say so plainly and separate confirmed facts from likely leads.
5. If a sibling skill clearly fits, use that skill next instead of trying to answer from this skill alone.

## Source Handling

- Treat chat snippets, copied notes, and memory as discovery aids unless they are explicitly confirmed as maintained sources of truth.
- Prefer active code, current automation, maintained runbooks, current team-owned docs, and shared documentation repos over historical notes.
- Treat `abilities-center/.github-private` as a strong candidate location for shared Abilities Center documentation, but still verify execution details in active code and automation when the answer depends on current behavior.
- When sources disagree, call out the conflict and explain which source you trust more and why.
- When no trustworthy source is available, say what you checked and ask for the smallest missing artifact needed to continue.

## Response Style

- Start with the direct answer if one is available.
- Then give the best next place to verify or continue.
- If the request is ambiguous, ask one short clarifying question instead of a broad questionnaire.
- When appropriate, suggest the next sibling skill to use by name.

## Reference Loading Guide

- Need source trust rules or stale-doc handling: read `references/source-priority.md`
- Need to route into another local skill: read `references/skill-routing.md`
- Need likely locations for docs, repos, configs, logs, or inventories: read `references/where-to-look.md`
- Need environment terminology or access-pattern context: read `references/lab-topology.md`
- Need guidance on what local `AGENTS.md` should contain: read `references/local-agents-guidance.md`
- Need shared test-folder or artifact-location conventions: read `references/test-data.md`
- Need shared documentation repo guidance: read `references/doc-sources.md`
- Need a tool-family overview: read `references/tool-map.md`
- Need a process/workflow troubleshooting frame: read `references/process-map.md`
- Need to capture missing knowledge cleanly for future reuse: read `references/gap-capture.md`
