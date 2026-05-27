# Release Checks

Use this file when the user asks how a repo is released, whether a change needs a version bump, how changelog updates should work, or what should be checked before cutting or validating a release.

## Start With Repo Evidence

Release behavior is highly repo-specific.

Before answering, check for:
- `CHANGELOG.md`
- version files such as package manifests, image tags, or build metadata
- release workflow files
- docs describing release, publish, package, or deploy flow
- CI or Jenkins jobs that create release artifacts

Do not assume every repo has a formal tagged-release process.

## Common Release Questions

- Does this repo even have releases, or is it just merged and consumed from branch builds?
- Is a version bump required?
- Does the changelog need an entry?
- Which pipeline or workflow actually publishes the artifact?
- How should the change be validated after release?

For many Abilities Center repos, a common pattern is:
- default branch (`main` or `master`) acts like the ongoing pre-release integration branch
- formal release is prepared after merge, often through a dedicated release PR
- downstream image or product build happens from the release

Treat that as a candidate pattern, not a universal rule, until repo-local release evidence confirms it.

## Default Guidance When Repo Rules Are Missing

If the repo does not define release steps clearly:
- say that release behavior is not yet confirmed
- point to the exact artifact or workflow that should confirm it
- avoid inventing a release procedure from another repo

## Changelog Guidance

If `CHANGELOG.md` exists, check whether:
- entries are expected for each merged change
- entries group by version
- entries use repo-specific formatting

If there is no changelog, do not require one unless another repo-local rule says so.

If a repo is using multiple simultaneous PRs and changelog updates are creating approval or merge friction, a separate changelog or release-activity PR may be the cleaner path.

For repos following the Abilities Center-style release flow:
- do not put the final release version header into normal feature/work PRs
- keep the changelog-ready content in both the PR's top description or summary and in `CHANGELOG.md`
- use a pre-release-style section in `CHANGELOG.md` until the release PR converts it into the actual version heading
- it is fine to include the PR link in that changelog-ready content before the release PR
- keep that changelog-ready content aligned with what the release PR should place into `CHANGELOG.md`
- use a later release PR to place that content under the actual release version heading

Historical note:
- some repos may still be following the older habit of leaving `CHANGELOG.md` untouched until release work
- if repo-local guidance still expects that older flow, prefer the repo-local rule over the generic Abilities Center fallback

For Abilities Center repos, prefer the `node-orchestration` changelog style as the fallback pattern when a repo does not define a different one.

Common shapes:

`# <Version>`
`<thing-changing>: <PR link>`
`  * <bullet>`

For more complex PRs:

`PR: <PR link>`
`  * <thing-changing>:`
`    * <bullet>`
`  * <other-thing-changing>:`
`    * <bullet>`

Guidance for `<thing-changing>`:
- keep it very short
- prefer a word or two, or a compact path-like identifier
- reference the thing being changed when possible
- examples: `torq-client`, `DH2 Inventory`, `terraform`, `role/torq-client`

If the repo already has a clear changelog style, follow that instead of forcing the fallback pattern.

For normal work PRs before release:
- keep the same bullet content and short `<thing-changing>` labels in the PR summary or top description and in `CHANGELOG.md`
- include the PR link when it is already available
- make the PR summary or top description section reflect that same changelog-ready content
- keep that same content in the pre-release section of `CHANGELOG.md`
- do not assign the final `# v#.#.#` heading yet
- treat the version heading assignment as release PR work

## Validation After Release

Release-readiness answers should name:
- the artifact that should change
- the workflow or pipeline that produces it
- the place where the result should be verified

## Versioning Pattern

If the repo uses tagged releases in a `v#.#.#` style, treat that as a semver-style release indicator and verify:
- where the version is declared
- whether a changelog update is expected before release
- which pipeline or process builds from the release

Do not assume a release should be cut before the PR is merged unless repo-local docs say so.
If the repo uses a release PR model, expect the version bump and final versioned changelog heading to happen there rather than in the earlier feature PR.

## Output Pattern

When answering a release question:

1. say whether the release flow is confirmed or still inferred
2. name the repo-local file or workflow that supports the answer
3. call out missing release evidence if the process is unclear
