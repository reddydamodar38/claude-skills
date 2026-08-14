# ABLFEDA / INJABLFEDA001 Migration

## Scope

Replace the Gatling Docker Test Runner's fixed EPINJCERNABL000/ABLFHIR profile with a fixed INJABLFEDA001/ABLFEDA profile. This is a replacement, not a selectable multi-environment runner.

## Fixed execution contract

- SSH target: `opc@10.44.121.15`.
- Expected short hostname: `INJABLFEDA001`, compared case-insensitively.
- Default SSH key: `~/.ssh/id_ed25519_injablfeda001`.
- Allowed remote test root: `/ablpub/OCI/Torq/Gatling`; supplied test folders must be absolute descendants of this directory.
- YAML authority: `ablfeda` in `config.yaml` and in every `globalDataSets` entry in `scenario-data.yaml`.
- Load profile: `startUsers: 1`, `endUsers: 10`, `durationSeconds: 600`, and `rampDurationSeconds: 0`.
- DNS container and Docker network: `gatling_dns_mappcernabl010`.
- Expected DNS address: resolve dynamically from the approved network and require `172.25.0.2`.
- Execution-container suffix: `mappcernabl010`.
- Docker commands run as `sudo -n docker`; inability to use passwordless sudo is a stop condition.
- Docker image remains `iad.ocir.io/idxlj5etbfyf/gatling_docker:gatling_oci_test`.

## Components and data flow

`run_gatling_docker_test.sh` remains the single execution entry point. It validates the absolute folder prefix, pinned SSH access, user and hostname, stages read-only copies of the three YAML files locally, invokes `validate_test_folder.rb`, checks Docker prerequisites remotely, and either stops after prepare-only or runs the foreground execution workflow.

The validator keeps the ten-user dataset gate, placeholder rejection, identity-field checks, and explicit shared-data approval. Its fixed authority and load expectations change to the FEDA contract.

Remote execution starts the approved DNS container only if needed, confirms its address on the approved network, rejects an existing execution-container name, creates timestamped output and report paths, runs Docker through passwordless sudo, and derives the final result from exit code, Gatling completion evidence, report creation, and KO count.

## Safety and error handling

- Never edit or upload the three YAML source files.
- Never weaken SSH host-key checking or print keys/passwords.
- Stop on user, hostname, path-root, configuration, dataset, Docker, DNS-address, image, network, sudo, or container-name mismatches.
- Never delete an unexpected container or force a PASS result.
- Keep execution attached to the invoking runner and preserve the existing interruption/status behavior.

## Documentation changes

Update `SKILL.md`, `references/sop.md`, and `agents/openai.yaml` so all examples and defaults describe INJABLFEDA001, ABLFEDA, the `/ablpub/OCI/Torq/Gatling` root, zero-second ramp, passwordless sudo Docker, and the `mappcernabl010` DNS/network profile. Remove obsolete EPINJCERNABL000/ABLFHIR references.

## Testing

Update `tests/test_skill.sh` before implementation so the existing code fails against the new contract. Cover:

- FEDA authority and zero-ramp validation;
- rejection of old/wrong authority and nonzero ramp;
- fixed target IP, hostname, key name, test-root, DNS/network, DNS IP, and container suffix;
- passwordless `sudo -n docker` usage;
- case-insensitive hostname validation;
- ten-user dedicated and explicitly approved shared-data modes;
- required prepare-only markers and security signatures;
- absence of obsolete EPINJCERNABL000/ABLFHIR defaults.

Run shell syntax checks, Ruby syntax checks, and the complete skill test suite before reporting completion.
