# Node Types Quick Reference

Use this to map user language to TACO groups/playbooks and to identify when clarification is required.

## Common Roles

Use this compact map to translate user intent into likely playbooks/roles quickly.
Keep details (vars, defaults, dependencies, caveats) in each role's own README.

- `torq-client`: node labeling and TORQ client setup.
- `torq-server`: central TORQ service stack host setup.
- `metricbeat` / `filebeat` (`beats`): baseline observability/log shipping.
- `perf_proc`: performance collection tooling on target hosts.
- `samba-client`: SMB client/share access on workload nodes.
- `samba-server`: SMB share host setup (`ablpub` patterns).
- `guacamole-host`: endpoint preparation for guacamole access.
- `guacamole-server`: guacamole service server stack.
- `opensearch-server`: opensearch service node setup.
- `gatling`: Gatling injector dependencies and runtime.
- `eggplant-controller`: Eggplant controller host setup (Windows path).
- `eggplant-injector`: Eggplant injector host setup (Linux path).
- `eggplant-sut`: Eggplant SUT endpoint preparation (Windows path).
- `citrix-vda`: common Citrix VDA setup target.

If user request names only a broad bucket (`citrix`, `eggplant`, `injector`, `generic`), ask one targeted clarification before execution.

## Orchestrator

Common meaning:
- Central abilities-lab utility node.

Common workloads in repo:
- `torq-server`
- `opensearch-server`
- `guacamole-server`
- `samba-server` (`ablpub` share)
- `abl_ragnarok`
- `metricbeat` and `filebeat` (via beats setup)
- often `traefik`, `filebrowser-server`, `ablweb-server`

Where this is defined:
- `abldev1_inventory/abldev1_groups.yml`
- `oci_inventory/oci_groups.yml`
- `playbooks/torq-server.yml`
- `playbooks/opensearch.yml`
- `playbooks/guacamole-server.yml`
- `playbooks/samba-server.yml`
- `playbooks/abl_ragnarok.yml`
- `playbooks/beats.yml`

## Injector

Common meaning is ambiguous and should be clarified.

Possible meanings:
- `gatling` injector host
- `eggplant-injector` (Linux GUI based injector)
- `eggplant-docker` host (newer containerized path)

Clarify with one question:
- "Do you mean `gatling`, `eggplant-injector`, or `eggplant-docker`?"

Repo signals:
- `playbooks/gatling.yml`
- `playbooks/eggplant-injector.yml`
- `playbooks/eggplant-docker.yml`
- group mappings in `abldev1_inventory/abldev1_groups.yml` and `lab_inventory/lab_groups.yml`

## Gatling

Current practical meaning:
- Mostly `gatling_docker` usage operationally; legacy Maven/Java Gatling setup still exists in automation.

Repo behavior:
- `playbooks/gatling.yml` applies roles `docker`, `abl_java`, and `gatling`.
- `gatling_dns` is a separate playbook/group (`playbooks/gatling_dns.yml`) and is commonly paired with gatling.
- In `abldev1_inventory/playbook.yml`, gatling_dns block is currently commented out.

Operational note:
- If user says "run gatling", confirm whether they also want `gatling_dns`.

## Eggplant

Three primary node types:
- `eggplant-controller`: Windows host for Eggplant Functional/Performance controller role.
- `eggplant-injector`: Linux injector role for official execution paths.
- `eggplant-sut`: Windows SUT endpoint for remote-user style interaction.

Additional variant:
- `eggplant-docker`: containerized injector-style path in newer flows.

Role intent and terminology:
- Historically, `eggplant-injector` referred to the Linux GUI-based injector host used by Eggplant controller workflows.
- `eggplant-docker` is the newer, preferred path for Eggplant Performance execution going forward.
- In current setup/TACO practice, `eggplant-injector` targets are typically expected to resolve as both `eggplant-injector` and `eggplant-docker`.
- This is a present-day convention, not a hard requirement, and may change over time.
- Users may still say "eggplant-injector node" generically even when they mean workload placement that could be docker-based.
- Treat "injector" wording as intent context, then clarify whether they want classic injector setup, docker path, or both.

Repo behavior worth noting:
- `playbooks/eggplant-controller.yml` gathers facts on controller and injector, then applies controller role to controller host.
- `playbooks/eggplant-injector.yml` applies injector role.
- `playbooks/eggplant-sut.yml` applies SUT role.

Clarify when user says only "eggplant":
- ask whether they mean `controller`, `injector`/`eggplant-docker`, or `sut`.

## Citrix

Common meaning:
- Often `citrix-vda` in day-to-day requests.

Repo nuance:
- `citrix` umbrella can include additional roles in some inventories (for example delivery controller, storefront, management, datastore).
- `torq-client` label mappings include broader citrix groups in `abldev1_inventory/group_vars/torq-client.yml`.

Clarify when needed:
- if user says only "citrix", ask whether they mean `citrix-vda` specifically or another citrix role.

## Generic

Common meaning:
- catch-all host outside predefined specialty buckets.

Repo nuance:
- explicit `generic_nodes` grouping appears primarily in `lab_inventory/lab_groups.yml`.
- typically paired with baseline tooling like `perf_proc`, `metricbeat`, `samba-client`, and sometimes `torq-client` depending on environment intent.

Clarify when needed:
- ask what baseline they want (`perf_proc`, `metricbeat`, `samba-client`, `torq-client`, or full system-prep).

## Suggested Clarification Prompts

- Injector ambiguity:
  - "Do you want `gatling`, `eggplant-injector`, or `eggplant-docker`?"
- Eggplant ambiguity:
  - "Should I target `eggplant-controller`, `eggplant-injector`/`eggplant-docker`, or `eggplant-sut`?"
- Citrix ambiguity:
  - "Do you mean `citrix-vda` only, or another citrix role (storefront/delivery-controller/management)?"
- Generic ambiguity:
  - "For `generic`, should I run baseline only (`perf_proc`, `metricbeat`, `samba-client`) or full scoped playbook?"

## Common Node Actions

These are frequent requests and safe clarifications to use before execution.

Setup `torq-client`:
- intent: connect nodes to TORQ services/UI labeling workflows
- playbook mapping: `playbooks/torq-client.yml`
- typical tag(s): `torq`, `torq-client`

Setup abilities-lab baseline tools:
- common bundle: `torq-client`, `metricbeat`/`filebeat`, `perf_proc`, share connectivity (`samba-client`), and guacamole access path (`guacamole-host`/`guacamole-server`)
- playbook mapping:
  - `playbooks/torq-client.yml`
  - `playbooks/beats.yml`
  - `playbooks/perf_proc.yml`
  - `playbooks/samba-client.yml`
  - `playbooks/guacamole-host.yml` and `playbooks/guacamole-server.yml`

Clarify target scope before running baseline bundle:
- "Should I run the full baseline bundle (`torq-client`, beats, `perf_proc`, samba-client, guacamole) or only specific pieces?"
