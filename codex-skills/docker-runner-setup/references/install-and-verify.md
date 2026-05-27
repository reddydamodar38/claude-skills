# Docker Install And Verify

Run commands on the target Linux runner unless noted.

## 1) Baseline Checks

```bash
uname -s
cat /etc/os-release
id -un
id -nG
docker --version
docker compose version || docker-compose version
docker ps
```

Interpretation:
- If `docker` command is missing, install Docker.
- If `docker ps` fails with permission denied, use `sudo` or add user to `docker` group.
- If daemon is not running, start/enable Docker service.

## 2) Install Or Repair (By Distro)

RHEL / Oracle Linux / Rocky / Alma (dnf):

```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Legacy RHEL/CentOS variants (yum):

```bash
sudo yum -y install yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

Ubuntu / Debian (apt):

```bash
sudo apt-get update
sudo apt-get -y install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```

## 3) Operator Access

Option A (immediate, low risk): run Docker commands with `sudo`.

Option B (persistent user access):

```bash
sudo groupadd -f docker
sudo usermod -aG docker "$USER"
newgrp docker
```

If group change does not apply in current session, reconnect.

## 4) TACO Runtime Checks

From TACO repo root:

```bash
test -f docker-compose.yml
docker compose version || docker-compose version
docker ps
docker-compose run --rm taco bash -lc 'pwd && whoami'
```

For OCI-based inventories:

```bash
test -d oci_api
test -f oci_api/config
```

## 5) Safety Checks

- Confirm host is user-owned (not shared jump host) before storing auth.
- If currently on Windows, SSH to Linux runner first, then execute this checklist.
