#!/usr/bin/env bash
# DigitalHouses Ansible-3: fresh PVE bootstrap; no custom Python.
set -Eeuo pipefail
umask 077
export LANG=C.UTF-8 LC_ALL=C.UTF-8
unset LANGUAGE

[[ $EUID -eq 0 && -f /etc/pve/user.cfg && $# -eq 0 ]] || {
  echo 'BLOCKED: launch as root on Proxmox VE, without arguments' >&2; exit 2;
}
read -r -p 'Site ID (<owner>-<type>): ' SITE
SITE="${SITE%$'\r'}"
[[ ${#SITE} -le 31 && $SITE =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+$ ]] || {
  echo 'BLOCKED: invalid Site ID' >&2; exit 2;
}
read -r -p "Confirm site $SITE (y/n): " YES
[[ $YES == y || $YES == Y ]] || { echo 'Cancelled'; exit 2; }

CTID="${DH_BOOTSTRAP_CTID:-1231}"
GIT_REF="${DH_BOOTSTRAP_REF:-main}"
RUNNER_HOSTNAME="${DH_BOOTSTRAP_HOSTNAME:-ansible-$SITE}"
PROTECTION="${DH_BOOTSTRAP_PROTECTION:-1}"
[[ $CTID =~ ^[1-9][0-9]{2,5}$ && $GIT_REF =~ ^[a-zA-Z0-9._/-]+$ &&
   $RUNNER_HOSTNAME =~ ^[a-z0-9][a-z0-9-]{0,62}$ &&
   $PROTECTION =~ ^[01]$ ]] || {
  echo 'BLOCKED: invalid CTID, Git ref or hostname' >&2; exit 2;
}

HOST_CIDR="$(ip -4 -o addr show dev vmbr0 | awk '$3 == "inet" {print $4; exit}')"
HOST_GW="$(ip -4 route show default | awk '$1 == "default" && $2 == "via" {print $3; exit}')"
[[ $HOST_CIDR == */24 && $HOST_GW =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo 'BLOCKED: expected PVE vmbr0 with /24 and default gateway' >&2; exit 2;
}
HOST_IPV4="${HOST_CIDR%/*}"
PVE_NODE="$(hostname -s)"
PVE_HOSTNAME="$(hostname -f)"
PVE_ROOT_CA=/etc/pve/pve-root-ca.pem
[[ -n $PVE_NODE && -n $PVE_HOSTNAME && -s $PVE_ROOT_CA ]] || {
  echo 'BLOCKED: missing PVE identity or cluster CA certificate' >&2; exit 2;
}
# An unauthenticated HTTP 401 is fine; the TLS verification must succeed.
curl --silent --show-error --cacert "$PVE_ROOT_CA" --connect-timeout 5 --max-time 10 \
  -o /dev/null "https://$HOST_IPV4:8006/api2/json/version" || {
    echo 'BLOCKED: PVE API certificate is not trusted for vmbr0 IP' >&2; exit 2;
  }
IFS=. read -r A B C D <<< "$HOST_IPV4"
NETWORK="${A}.${B}.${C}"
RUNNER_IP="${DH_BOOTSTRAP_IP:-$NETWORK.231}"
[[ $HOST_GW == "$NETWORK."* && $RUNNER_IP == "$NETWORK."* ]] || {
  echo 'BLOCKED: PVE, gateway and Runner must share vmbr0 /24' >&2; exit 2;
}
LAST_OCTET="${RUNNER_IP##*.}"
[[ $LAST_OCTET =~ ^[0-9]{1,3}$ ]] && (( 10#$LAST_OCTET >= 1 && 10#$LAST_OCTET <= 254 )) &&
  [[ $RUNNER_IP != "$HOST_IPV4" && $RUNNER_IP != "$HOST_GW" ]] || {
  echo 'BLOCKED: invalid or conflicting Runner IP' >&2; exit 2;
}

if pct config "$CTID" >/dev/null 2>&1 || qm config "$CTID" >/dev/null 2>&1; then
  echo "BLOCKED: guest $CTID already exists. Use a separate test CTID/IP, or an empty PVE." >&2
  exit 2
fi
LOG_DIR=/var/log/digitalhouses/ansible-3
install -d -m 0700 "$LOG_DIR"
LOG="$(mktemp "$LOG_DIR/bootstrap-$(date -u +%Y%m%dT%H%M%SZ).XXXXXXXX.log")"
chmod 0600 "$LOG"
MOUNTED=0
on_exit() {
  rc=$?
  trap - EXIT
  if (( MOUNTED )); then pct unmount "$CTID" || true; fi
  echo "RESULT_RC=$rc"
  echo "LOG_FILE=$LOG"
  echo 'Failed partial CTs are NOT removed automatically.'
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1

printf 'SITE=%s PVE=%s RUNNER=CT%s/%s/%s REF=%s\n' \
  "$SITE" "$HOST_CIDR" "$CTID" "$RUNNER_HOSTNAME" "$RUNNER_IP" "$GIT_REF"

echo '=== 1/5 Debian 13 LXC ==='
pveam update
TEMPLATE="$(pveam available --section system |
  awk '$2 ~ /^debian-13-standard_[[:alnum:].+-]+_amd64\.tar\.zst$/ {print $2}' |
  sort -V | tail -n 1)"
[[ -n $TEMPLATE ]] || { echo 'BLOCKED: Debian 13 template unavailable' >&2; exit 2; }
if ! pveam list local | grep -Fq "local:vztmpl/$TEMPLATE"; then
  pveam download local "$TEMPLATE"
fi
(umask 022; pct create "$CTID" "local:vztmpl/$TEMPLATE" \
  --hostname "$RUNNER_HOSTNAME" --ostype debian \
  --cores 1 --memory 1024 --swap 512 --rootfs local-lvm:16 \
  --unprivileged 1 --features nesting=1 \
  --net0 "name=eth0,bridge=vmbr0,ip=$RUNNER_IP/24,gw=$HOST_GW" \
  --onboot 1 --startup order=2 --protection "$PROTECTION" --start 0)
pct mount "$CTID"
MOUNTED=1
ETC="/var/lib/lxc/$CTID/rootfs/etc"
[[ -d $ETC && ! -L $ETC ]] || { echo 'BLOCKED: unexpected guest /etc' >&2; exit 2; }
case "$(stat -c %a "$ETC")" in
  700) chmod 0755 "$ETC" ;;
  755) ;;
  *) echo 'BLOCKED: unexpected guest /etc mode' >&2; exit 2 ;;
esac
pct unmount "$CTID"
MOUNTED=0
pct start "$CTID"
[[ $(pct exec "$CTID" -- hostname) == "$RUNNER_HOSTNAME" ]] || {
  echo 'BLOCKED: guest hostname differs' >&2; exit 2;
}

echo '=== 2/5 Ansible and Ansible-3 sources ==='
pct exec "$CTID" -- apt-get update -o APT::Update::Error-Mode=any
pct exec "$CTID" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  --no-install-recommends git python3 python3-venv python3-pip ca-certificates
pct exec "$CTID" -- python3 -m venv /opt/ansible/venv
pct exec "$CTID" -- /opt/ansible/venv/bin/pip install \
  --disable-pip-version-check ansible-core==2.21.4
pct exec "$CTID" -- git clone -q --depth 1 --single-branch \
  --branch "$GIT_REF" https://github.com/DigitalHouses/Ansible-3.git /opt/ansible-3
CODE_RELEASE="$(pct exec "$CTID" -- git -C /opt/ansible-3 rev-parse HEAD)"
[[ $CODE_RELEASE =~ ^[0-9a-f]{40}$ ]] || { echo 'BLOCKED: invalid Git SHA' >&2; exit 2; }
pct exec "$CTID" -- git -C /opt/ansible-3 checkout -q --detach "$CODE_RELEASE"

# Only a public trust certificate is copied; no private PVE key.
pct exec "$CTID" -- install -d -m 0755 /etc/digitalhouses
pct push "$CTID" "$PVE_ROOT_CA" /etc/digitalhouses/pve-root-ca.pem \
  --user root --group root --perms 0644

echo '=== 3/5 Semaphore through Ansible ==='
pct exec "$CTID" -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  /opt/ansible/venv/bin/ansible-playbook -i localhost, -c local \
  -e "site_id=$SITE runner_ip=$RUNNER_IP runner_hostname=$RUNNER_HOSTNAME code_branch=$GIT_REF pve_ipv4=$HOST_IPV4 pve_node=$PVE_NODE pve_hostname=$PVE_HOSTNAME" \
  /opt/ansible-3/bootstrap/runner.yml

echo '=== 4/5 Pin host SSH and enroll the Semaphore runner ==='
# Only the runner's PUBLIC key is added to the PVE host. The private key
# remains inside the site LXC; the PVE SSH host key is pinned at bootstrap.
[[ -s /etc/ssh/ssh_host_ed25519_key.pub ]] || {
  echo 'BLOCKED: PVE ed25519 SSH host key is missing' >&2; exit 2;
}
pct exec "$CTID" -- install -d -m 0700 -o semaphore -g semaphore /var/lib/semaphore/.ssh
if ! pct exec "$CTID" -- test -s /var/lib/semaphore/.ssh/id_ed25519; then
  pct exec "$CTID" -- runuser -u semaphore -- ssh-keygen -q -t ed25519 -N '' \
    -f /var/lib/semaphore/.ssh/id_ed25519
fi
RUNNER_SSH_PUB="$(pct exec "$CTID" -- cat /var/lib/semaphore/.ssh/id_ed25519.pub)"
[[ $RUNNER_SSH_PUB == ssh-ed25519\ * ]] || {
  echo 'BLOCKED: invalid Semaphore runner SSH public key' >&2; exit 2;
}
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
AUTHORIZED_LINE="restrict,from=\"$RUNNER_IP\" $RUNNER_SSH_PUB"
if ! grep -Fqx -- "$AUTHORIZED_LINE" /root/.ssh/authorized_keys; then
  printf '%s\n' "$AUTHORIZED_LINE" >> /root/.ssh/authorized_keys
fi
PVE_SSH_HOST_PUB="$(awk '{print $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub)"
[[ $PVE_SSH_HOST_PUB == ssh-ed25519\ * ]] || {
  echo 'BLOCKED: invalid PVE host SSH public key' >&2; exit 2;
}
PINNED_HOSTS="$(mktemp)"
printf '%s %s\n' "$HOST_IPV4" "$PVE_SSH_HOST_PUB" > "$PINNED_HOSTS"
pct push "$CTID" "$PINNED_HOSTS" /var/lib/semaphore/.ssh/known_hosts \
  --user semaphore --group semaphore --perms 0600
rm -f "$PINNED_HOSTS"
pct exec "$CTID" -- runuser -u semaphore -- ssh -n \
  -i /var/lib/semaphore/.ssh/id_ed25519 \
  -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
  -o UserKnownHostsFile=/var/lib/semaphore/.ssh/known_hosts \
  "root@$HOST_IPV4" /usr/bin/true || {
    echo 'BLOCKED: Semaphore-to-PVE pinned root SSH verification failed' >&2; exit 2;
  }

# Fresh bootstrap uses the same native Ansible playbook as task 08.
# Do not add any other Semaphore task during bootstrap; no task is autorun.
if [[ $CTID == 1231 ]] && [[ $(pct status 1254 2>/dev/null) == 'status: running' ]]; then
  echo '=== DEV enrollment through Ansible task 08 playbook ==='
  pct exec "$CTID" -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    /opt/ansible/venv/bin/ansible-playbook -i /opt/ansible-3/inventory/bootstrap.yml \
    /opt/ansible-3/playbooks/configure-dev-semaphore.yml || {
      echo 'BLOCKED: native DEV enrollment failed' >&2
      exit 2
    }
else
  echo 'DEV enrollment skipped: no running local DEV CT1254 for Runner CT1231.'
fi

echo '=== 5/5 Ready ==='
echo "BOOTSTRAP_FRESH_DONE=PASS commit=$CODE_RELEASE"
echo "SEMAPHORE_URL=https://$RUNNER_IP:3000/"
echo "GET_SEMAPHORE_ADMIN_PASSWORD: pct exec $CTID -- cat /root/dh-semaphore-initial-admin-password"
echo 'ONLY_TASK=00-Обновить список задач'
