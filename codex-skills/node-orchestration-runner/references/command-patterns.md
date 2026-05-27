# Command Patterns

Use these patterns from repo root.
Use `references/node-types.md` when user terminology is ambiguous (`injector`, `eggplant`, `citrix`, `generic`).

## Git Sync And PR Flow

Verify branch status and sync before automation runs:

```bash
git status -sb
git remote -v
git fetch --all --prune
git branch -vv
```

If branch is behind upstream, sync (choose one):

```bash
git pull --rebase
```

or

```bash
git pull
```

If work changes repo files, use a dedicated branch:

```bash
git switch -c <user-or-ticket>/<short-change-name>
```

Commit and push:

```bash
git add <files>
git commit -m "<clear summary>"
git push -u origin <branch-name>
```

Create PR (preferred with `gh`):

```bash
gh pr create --fill
```

If `gh` is unavailable, push branch and provide compare URL/manual PR instructions.

## Host and Docker Preflight

Run these checks before any TACO action:

```bash
uname -s
hostname
id -un
```

Use decision rules:
- Prefer user-owned Linux secondary runners.
- If current session is Windows, SSH to user-owned Linux runner and execute from there.
- Refuse to run from shared hosts/jump boxes where `oci_api` auth would be shared.

Check Docker availability:

```bash
docker compose version || docker-compose version
docker ps
```

If Docker is unavailable or permission is denied, stop and report setup requirement.
Then use `docker-runner-setup` skill to install/fix Docker and validate runner safety.

## Container Entry

Single command in container:

```bash
docker-compose run --rm taco <command>
```

Interactive shell only when requested:

```bash
docker-compose run --rm taco bash
```

## Ansible: lab_inventory

Resolved inventory set for this family:

```bash
-i lab_inventory/<env>/ -i lab_inventory/lab_groups.yml
```

Full run:

```bash
docker-compose run --rm taco ansible-playbook -i lab_inventory/<env>/ -i lab_inventory/lab_groups.yml --ask-vault-pass lab_inventory/playbook.yml
```

Scoped run:

```bash
docker-compose run --rm taco ansible-playbook -i lab_inventory/<env>/ -i lab_inventory/lab_groups.yml --ask-vault-pass lab_inventory/playbook.yml -l <host-or-group>
```

## Ansible: oci_inventory

Resolved inventory set for this family:

```bash
-i oci_inventory/<env>.yml -i oci_inventory/<env>.oci.yml -i oci_inventory/oci_groups.yml
```

Full run:

```bash
docker-compose run --rm taco ansible-playbook -i oci_inventory/<env>.yml -i oci_inventory/<env>.oci.yml -i oci_inventory/oci_groups.yml --ask-vault-pass oci_inventory/playbook.yml
```

Scoped run:

```bash
docker-compose run --rm taco ansible-playbook -i oci_inventory/<env>.yml -i oci_inventory/<env>.oci.yml -i oci_inventory/oci_groups.yml --ask-vault-pass oci_inventory/playbook.yml -l <host-or-group>
```

Task-tag run (only when requested):

```bash
docker-compose run --rm taco ansible-playbook -i oci_inventory/<env>.yml -i oci_inventory/<env>.oci.yml -i oci_inventory/oci_groups.yml --ask-vault-pass oci_inventory/playbook.yml -l <host-or-group> -t <tag1,tag2>
```

## Ansible: abldev1_inventory

Resolved inventory set for this family:

```bash
-i abldev1_inventory/<env>.yml -i abldev1_inventory/<env>.oci.yml -i abldev1_inventory/abldev1_groups.yml
```

Full run:

```bash
docker-compose run --rm taco ansible-playbook -i abldev1_inventory/<env>.yml -i abldev1_inventory/<env>.oci.yml -i abldev1_inventory/abldev1_groups.yml --ask-vault-pass abldev1_inventory/playbook.yml
```

Scoped run:

```bash
docker-compose run --rm taco ansible-playbook -i abldev1_inventory/<env>.yml -i abldev1_inventory/<env>.oci.yml -i abldev1_inventory/abldev1_groups.yml --ask-vault-pass abldev1_inventory/playbook.yml -l <host-or-group>
```

Scoped tag run (only when requested):

```bash
docker-compose run --rm taco ansible-playbook -i abldev1_inventory/<env>.yml -i abldev1_inventory/<env>.oci.yml -i abldev1_inventory/abldev1_groups.yml --ask-vault-pass abldev1_inventory/playbook.yml -l <host-or-group> -t <tag1,tag2>
```

## Ansible Quick Connectivity Tests

Use ad-hoc module tests for fast debug checks before a full playbook run.
Do not mix Linux and Windows hosts in one quick test command.

Treat `<inventory>` as the full resolved inventory argument list (`-i ... -i ...`) for the target env/family.

Examples:

```bash
# abldev1 env ablfeda
-i abldev1_inventory/ablfeda.yml -i abldev1_inventory/ablfeda.oci.yml -i abldev1_inventory/abldev1_groups.yml

# oci env oci006
-i oci_inventory/oci006.yml -i oci_inventory/oci006.oci.yml -i oci_inventory/oci_groups.yml
```

Linux-only target set:

```bash
ansible <host-or-group> <inventory> -m ping
```

Windows-only target set:

```bash
ansible <host-or-group> <inventory> -m win_ping
```

## Terraform

Terraform is only supported for `abldev1` flows.
If inventory family is `lab_inventory` or `oci_inventory`, skip Terraform.

### Profile-based OCI auth (preferred)

Use env vars with mounted `oci_api/config`:

```bash
docker-compose run --rm \
  -e OCI_CLI_PROFILE=<profile> \
  -e OCI_CLI_CONFIG_FILE=/root/.oci/config \
  -e OCI_CONFIG_FILE=/root/.oci/config \
  taco terraform -chdir=terraform/envs/<env> <terraform-subcommand>
```

### Node existence checks

Inventory check:

```bash
rg -n "^\s*<node-name>\b" abldev1_inventory/<env>.yml abldev1_inventory/<env>.oci.yml
```

State check:

```bash
docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> state list | rg -i "<node-name>|<resource-fragment>"
```

### Plan / apply / destroy

Plan:

```bash
docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> plan -var-file=../../../oci_api/secrets.tfvars -var-file=terraform.tfvars
```

Apply (explicit request only):

```bash
docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> apply -var-file=../../../oci_api/secrets.tfvars -var-file=terraform.tfvars
```

Destroy workflow (explicit request only):

```bash
docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> plan -destroy -var-file=../../../oci_api/secrets.tfvars -var-file=terraform.tfvars

docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> destroy -auto-approve -var-file=../../../oci_api/secrets.tfvars -var-file=terraform.tfvars
```

Run `init` only if Terraform says initialization is required or backend/provider config changed.

First-time init in this repo commonly needs backend config from repo secrets:
```bash
docker-compose run --rm -e OCI_CLI_PROFILE=<profile> -e OCI_CLI_CONFIG_FILE=/root/.oci/config -e OCI_CONFIG_FILE=/root/.oci/config taco terraform -chdir=terraform/envs/<env> init -backend-config=../../../oci_api/secrets.tfvars
```

If `plan` reports lock-file or provider selection mismatch, run `init` then retry `plan`.

For contribution/PR workflow guidance, consult `CONTRIBUTING.md` at repo root when available.

## OCI Auth Preflight (abldev1 and fedscale)

Run these checks from repo root before `abldev1_inventory` or `oci_inventory` actions.

Validate expected auth folder/files:

```bash
test -d oci_api && test -f oci_api/config
ls -1 oci_api/*.pem
```

Validate compose mount in current standard mode (`oci_api` -> `/root/.oci`):

```bash
rg -n "oci_api|/root/\\.oci" docker-compose.yml
```

Extract abldev1 expected profile name:

```bash
awk -F': *' '/^config_profile_name:/{print $2}' abldev1_inventory/group_vars/all.yml
```

Inspect available OCI config profiles:

```bash
rg -n "^\\[(abldev1|fedscale|DEFAULT)\\]$" oci_api/config
```

Inspect profile/key mapping in config:

```bash
awk '/^\\[/{p=$0} /^key_file=/{print p \" \" $0}' oci_api/config
```

Inspect profile used by inventory plugins:

```bash
rg -n "^config_profile:" abldev1_inventory/*.oci.yml oci_inventory/*.oci.yml
```

Decision rules:
- For `abldev1_inventory`, require profile `abldev1` (or the value from `abldev1_inventory/group_vars/all.yml`) in `oci_api/config`.
- For `oci_inventory` (fedscale), require profile `fedscale` and run OCI API access with `OCI_CLI_PROFILE=fedscale` by default.
- Keep the user's `DEFAULT` profile as user-managed state; do not rewrite it and do not select it unless explicitly requested.
- If future mode uses `$HOME/.oci/config` instead of repo `oci_api`, validate that location and avoid forcing repo-local migration.

## Preflight Checks

1. Verify repo root contains `docker-compose.yml`.
2. Verify local branch is up to date with origin.
3. Verify run location is user-owned and not a shared host.
4. Verify Docker/Compose is installed and usable.
5. Verify inventory files referenced in command exist.
6. Confirm scope (`-l` and optional `-t`).
7. Confirm interactive prompt expectations (`--ask-vault-pass`).
8. For Terraform, confirm plan vs apply/destroy intent.
9. For Terraform destroy, verify plan output is scoped to requested node/resources.
10. For non-`abldev1` inventories, do not run Terraform.
11. For `abldev1_inventory` and `oci_inventory`, verify OCI auth/profile checks pass before command execution.
12. If files changed, use dedicated branch, push, and create PR.
