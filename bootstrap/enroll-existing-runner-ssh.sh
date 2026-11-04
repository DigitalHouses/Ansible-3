#!/usr/bin/env bash
# One-time, non-destructive SSH enrollment for an EXISTING Ansible-3 runner.
# Run locally as root on the expected PVE host, not over a restricted DEV SSH.
set -Eeuo pipefail
umask 077

CTID="${1:-1231}"
[[ "${EUID}" -eq 0 && -f /etc/pve/user.cfg && "${CTID}" =~ ^[1-9][0-9]{2,5}$ ]] || {
  echo 'BLOCKED: run as root on PVE, with optional numeric CTID' >&2; exit 2;
}
pct status "$CTID" | grep -q 'status: running' || {
  echo "BLOCKED: runner CT$CTID is not running" >&2; exit 2;
}
RUNNER_NAME="$(pct exec "$CTID" -- hostname -s)"
[[ "$RUNNER_NAME" == ansible-* ]] || {
  echo "BLOCKED: CT$CTID is not an Ansible-3 runner" >&2; exit 2;
}
pct exec "$CTID" -- id semaphore >/dev/null || {
  echo "BLOCKED: runner does not contain the Semaphore user" >&2; exit 2;
}
NET0="$(pct config "$CTID" | sed -n 's/^net0: //p')"
[[ "$NET0" == *"bridge=vmbr0"* && "$NET0" == *"ip="* ]] || {
  echo "BLOCKED: runner is not on vmbr0 with static IPv4" >&2; exit 2;
}
RUNNER_CIDR="$(printf '%s\n' "$NET0" | sed -nE 's/.*(^|,)ip=([0-9.]+\/[0-9]+)(,|$).*/\2/p')"
RUNNER_IP="${RUNNER_CIDR%/*}"
PVE_IP="$(ip -4 -o addr show dev vmbr0 | awk '$3 == "inet" {split($4,x,"/"); print x[1]; exit}')"
[[ "$RUNNER_CIDR" == */24 && "$RUNNER_IP" =~ ^[0-9.]+$ && "$PVE_IP" =~ ^[0-9.]+$ ]] || {
  echo 'BLOCKED: unexpected vmbr0 addressing' >&2; exit 2;
}
[[ -r /etc/ssh/ssh_host_ed25519_key.pub ]] || {
  echo 'BLOCKED: host ED25519 SSH identity missing' >&2; exit 2;
}

pct exec "$CTID" -- install -d -m 0700 -o semaphore -g semaphore /var/lib/semaphore/.ssh
if ! pct exec "$CTID" -- test -s /var/lib/semaphore/.ssh/id_ed25519; then
  pct exec "$CTID" -- runuser -u semaphore -- ssh-keygen -q -t ed25519 -N '' \
    -f /var/lib/semaphore/.ssh/id_ed25519
fi
RUNNER_PUB="$(pct exec "$CTID" -- cat /var/lib/semaphore/.ssh/id_ed25519.pub)"
[[ "$RUNNER_PUB" == ssh-ed25519\ * ]] || {
  echo 'BLOCKED: runner SSH public key invalid' >&2; exit 2;
}
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
KEY_LINE="restrict,from=\"$RUNNER_IP\" $RUNNER_PUB"
grep -Fqx -- "$KEY_LINE" /root/.ssh/authorized_keys || \
  printf '%s\n' "$KEY_LINE" >> /root/.ssh/authorized_keys

HOST_PUB="$(awk '{print $1 " " $2}' /etc/ssh/ssh_host_ed25519_key.pub)"
KNOWN_HOSTS=/var/lib/semaphore/.ssh/known_hosts
if pct exec "$CTID" -- test -f "$KNOWN_HOSTS"; then
  PINNED="$(pct exec "$CTID" -- runuser -u semaphore -- ssh-keygen -F "$PVE_IP" -f "$KNOWN_HOSTS" || true)"
  if [[ -n "$PINNED" ]]; then
    printf '%s\n' "$PINNED" | grep -Fqx -- "$PVE_IP $HOST_PUB" || {
      echo "BLOCKED: existing PVE SSH key differs from host key" >&2; exit 2;
    }
  fi
fi
if ! pct exec "$CTID" -- runuser -u semaphore -- ssh-keygen -F "$PVE_IP" -f "$KNOWN_HOSTS" >/dev/null 2>&1; then
  PIN_FILE="$(mktemp)"
  printf '%s %s\n' "$PVE_IP" "$HOST_PUB" > "$PIN_FILE"
  pct push "$CTID" "$PIN_FILE" /tmp/dh-pve-ssh-host-key --user semaphore --group semaphore --perms 0600
  rm -f "$PIN_FILE"
  pct exec "$CTID" -- bash -c \
    "cat /tmp/dh-pve-ssh-host-key >> '$KNOWN_HOSTS' && chown semaphore:semaphore '$KNOWN_HOSTS' && chmod 0600 '$KNOWN_HOSTS' && rm -f /tmp/dh-pve-ssh-host-key"
fi
pct exec "$CTID" -- runuser -u semaphore -- ssh -n \
  -i /var/lib/semaphore/.ssh/id_ed25519 \
  -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 \
  -o UserKnownHostsFile="$KNOWN_HOSTS" \
  "root@$PVE_IP" /usr/bin/true || {
    echo 'BLOCKED: PVE root SSH smoke test failed; verify PermitRootLogin prohibit-password' >&2; exit 2;
  }
printf 'ENROLL_EXISTING_RUNNER_SSH=PASS CT%s %s -> PVE %s\n' "$CTID" "$RUNNER_IP" "$PVE_IP"
