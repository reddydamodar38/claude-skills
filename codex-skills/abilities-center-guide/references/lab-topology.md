# Lab Topology

Use this file when the question depends on Abilities Center or Abilities Lab terminology, environment grouping, network access, or how to reach environment-specific tools such as TORQ.

## Naming

- `Abilities Center`
  - newer name
- `Abilities Lab`
  - older but still commonly used name

Treat both as referring to the same overall area unless the user clearly distinguishes them.

## Environment Groupings

Common environment language includes:

- `DH2`
  - also commonly called `on-prem`
  - original lab footprint before OCI
- `OCI`
  - often discussed in at least two main buckets:
    - `abldev1`
    - `fedscale`
- `EOD`
  - separate hosted environments that often follow OCI-like access patterns more than DH2 VIP-style access

Do not assume the exact environment list is complete in the skill. Ask for the specific environment name or URL when needed.

## DH2 Groupings and Older Team Language

Within DH2, users may still refer to older groupings that came from previously separate teams.
That language still helps narrow where an environment or workflow may belong even though teams merged over time.

- `ABLCERT`
  - often called the `cert` environments
  - environments commonly start with `abl`, such as `abla`, `ablfhir`, or `ablscale#`
  - historically used to help outside product teams stand up production-like performance testing
  - many of these are now part of the main environment pool used today
- `ABLCAPUTIL`
  - sometimes called `caputil` or `cap-util`
  - environments often have more distinct names such as `lin64` or `lntec`
  - historically used more for shared-services, whole-platform scalability, and technology-version testing
  - some environments have since been reclaimed or repurposed
- `CAMM`
  - dedicated CAMM testing footprint
  - `camm7a` is a current example
- `MREV`, `REVCYCLE`, `FINHUB`
  - still useful grouping language
  - may rely on each other operationally
  - exact environment ownership and current boundaries may need local verification

When the user uses one of these group names, treat it as a discovery hint rather than a guarantee of current ownership.

## Inventory Clues

The `node-orchestration/lab_inventory` tree is a good current place to gather an initial environment list for DH2-oriented questions.

Examples currently visible there include:
- ABLCERT-style names such as `abla`, `ablfhir`, `ablscale1` through `ablscale6`
- ABLCAPUTIL-style names such as `lin64` and `lntec`
- CAMM example `camm7a`
- MREV-related entries such as `mrevc`, `mrevd`, `mreve`, and `mrev_shared`

Treat inventory names as current evidence for what exists, while treating historical team labels as guidance for how users may talk about them.

## Access Prerequisites

- To access these environments, users generally need to be on the Abilities Lab VPN.
- To access OCI environments, users typically need to be inside the lab network itself.

When a user cannot reach an environment-specific tool, verify network location before assuming the tool is down.

## Tool URL Patterns

These are useful orientation patterns, not guarantees for every environment.

- DH2 or on-prem commonly exposes shared tools through a VIP-style address
- OCI commonly exposes per-environment tools through direct `ip:port` addresses
- EOD commonly exposes per-environment tools through direct `ip:port` addresses and may omit the usual environment URL prefix

## TORQ-Specific Access Hints

For TORQ:

- DH2 or on-prem environments can often reach the main TORQ instance through:
  - `http://dh2torqvip1.dh2.cerner.com/<env>/`
- OCI environments often use:
  - `http://<ip>:<port>/<env>/`
  - best practice is to ask for the exact URL
- EOD environments often use:
  - `http://<ip>:8081/`
  - typically with no environment prefix in the path

## Response Pattern

When the tool or environment is unknown:

1. normalize the user’s terminology
2. identify whether they mean DH2, OCI, or EOD
3. if DH2 wording is older team language, map it to likely environment families first
4. ask for the exact environment name or URL if the access pattern is not obvious
5. route into the tool-specific skill once the target is known
