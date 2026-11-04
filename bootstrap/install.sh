#!/usr/bin/env bash
# DigitalHouses Ansible-3: fresh PVE -> Debian LXC -> Ansible -> Semaphore -> task 00.
set -Eeuo pipefail
umask 077
export LANG=C.UTF-8 LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive

[[ $# -eq 0 && ${EUID} -eq 0 && -f /etc/pve/user.cfg ]] || {
  echo "ERROR: run without arguments as root on Proxmox VE" >&2
  exit 2
}

read -r -p "Site ID (<owner>-<type>): " SITE
[[ ${#SITE} -le 31 && $SITE =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+$ ]] || {
  echo "ERROR: invalid Site ID" >&2
  exit 2
}
read -r -p "Confirm site $SITE (y/n): " CONFIRM
[[ $CONFIRM == y || $CONFIRM == Y ]] || {
  echo "CANCELLED" >&2
  exit 2
}

CTID="${DH_BOOTSTRAP_CTID:-1231}"
GIT_REF="${DH_BOOTSTRAP_GIT_REF:-main}"
GIT_URL="https://github.com/DigitalHouses/Ansible-3.git"
[[ $CTID =~ ^[1-9][0-9]*$ && $GIT_REF =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || {
  echo "ERROR: invalid bootstrap override" >&2
  exit 2
}

# Both defaults match the former bootstrap, without using project Python.
HOST_CIDR="$(ip -4 -o addr show dev vmbr0 | awk '$3 == "inet" {print $4; exit}')"
HOST_GW="$(ip -4 route show default | awk '$1 == "default" && $2 == "via" {print $3; exit}')"
[[ $HOST_CIDR == */24 && -n $HOST_GW ]] || {
  echo "ERROR: vmbr0 must have IPv4 /24 and a default gateway" >&2
  exit 2
}
NETWORK="${HOST_CIDR%/*}"
PREFIX="${NETWORK%.*}"
RUNNER_IP="${DH_BOOTSTRAP_IP:-$PREFIX.231}"
[[ $RUNNER_IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && $RUNNER_IP == "$PREFIX".* &&
   $RUNNER_IP != "$NETWORK" && $RUNNER_IP != "$HOST_GW" ]] || {
  echo "ERROR: runner IPv4 must be a distinct address on vmbr0 /24" >&2
  exit 2
}
RUNNER_CIDR="$RUNNER_IP/24"

if pct config "$CTID" >/dev/null 2>&1 || qm config "$CTID" >/dev/null 2>&1; then
  echo "ERROR: CT/VM $CTID already exists; bootstrap never overwrites guests" >&2
  exit 2
fi
pvesm status | grep -Eq '^local-lvm[[:space:]]+lvmthin[[:space:]]+active' || {
  echo "ERROR: required storage local-lvm is unavailable" >&2
  exit 2
}

echo "Creating CT$CTID (ansible-$SITE, $RUNNER_CIDR)"
pveam update
TEMPLATE="$(pveam available --section system |
  awk '$2 ~ /^debian-13-standard_[[:alnum:].+-]+_amd64\.tar\.zst$/ {print $2}' |
  sort -V | tail -n 1)"
[[ -n $TEMPLATE ]] || {
  echo "ERROR: official Debian 13 template unavailable" >&2
  exit 2
}
pveam list local | grep -Fq "local:vztmpl/$TEMPLATE" ||
  pveam download local "$TEMPLATE"

(umask 022; pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname "ansible-$SITE" --ostype debian \
  --cores 1 --memory 1024 --swap 512 --rootfs local-lvm:16 \
  --unprivileged 1 --features nesting=1 \
  --net0 "name=eth0,bridge=vmbr0,ip=$RUNNER_CIDR,gw=$HOST_GW" \
  --onboot 1 --startup "order=2" --protection 1 --start 0)
pct start "$CTID"

pct exec "$CTID" -- apt-get update -o APT::Update::Error-Mode=any
pct exec "$CTID" -- apt-get install -y --no-install-recommends \
  git python3 ansible-core ca-certificates
pct exec "$CTID" -- git clone --depth 1 --branch "$GIT_REF" \
  "$GIT_URL" /opt/ansible-3

CODE_SHA="$(pct exec "$CTID" -- git -C /opt/ansible-3 rev-parse HEAD)"
pct exec "$CTID" -- git -C /opt/ansible-3 checkout --detach "$CODE_SHA"
echo "CODE_SHA=$CODE_SHA"

pct exec "$CTID" -- ansible-playbook \
  -i localhost, -c local \
  /opt/ansible-3/playbooks/bootstrap-runner.yml \
  -e "dh_site_id=$SITE" -e "dh_runner_ip=$RUNNER_IP" \
  -e "dh_git_ref=$GIT_REF"

echo "BOOTSTRAP=SUCCESS CTID=$CTID SITE=$SITE CODE_SHA=$CODE_SHA"
echo "SEMAPHORE_URL=https://$RUNNER_IP:3000/"
echo "ADMIN_PASSWORD: pct exec $CTID -- cat /root/dh-semaphore-admin-password"
echo "FIRST_TEMPLATE=00-Обновить список задач"
echo "DEV_API_TOKEN: root SSH to $RUNNER_IP, read /etc/semaphore/dev-automation-token"
