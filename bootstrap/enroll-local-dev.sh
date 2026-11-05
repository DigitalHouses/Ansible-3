#!/usr/bin/env bash
# Enroll local central DEV via native Ansible on Runner. Run as root on PVE.
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 && -f /etc/pve/user.cfg && ( $# -eq 2 || $# -eq 3 ) ]] || {
  echo 'Usage (PVE root): enroll-local-dev.sh SITE RUNNER_IP [--check]' >&2; exit 2;
}
SITE=$1
RUNNER_IP=$2
REF=${DH_DEV_ACCESS_REF:-main}
[[ $SITE =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+$ &&
   $RUNNER_IP =~ ^192\.168\.11\.([0-9]{1,3})$ &&
   $REF =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]{0,80}$ &&
   $REF != *..* && ${3:-} =~ ^(--check)?$ ]] || exit 2

[[ $(pct status 1231) == 'status: running' &&
   $(pct status 1254) == 'status: running' ]] || exit 2
RUNNER_CONFIG=$(pct config 1231)
DEV_CONFIG=$(pct config 1254)
[[ $RUNNER_CONFIG == *"hostname: ansible-$SITE"$'\n'* ||
   $RUNNER_CONFIG == *"hostname: ansible-$SITE" ]] || exit 2
[[ $RUNNER_CONFIG == *"ip=$RUNNER_IP/24"* &&
   $DEV_CONFIG == *'ip=192.168.11.254/24'* ]] || exit 2
[[ $(pct exec 1231 -- hostname) == "ansible-$SITE" ]] || exit 2
DEV_HOSTNAME=$(printf '%s\n' "$DEV_CONFIG" | sed -n 's/^hostname: //p')
[[ -n $DEV_HOSTNAME && $(pct exec 1254 -- hostname) == "$DEV_HOSTNAME" ]] || exit 2
pct exec 1254 -- ip -4 -o addr show dev eth0 | grep -Fq 'inet 192.168.11.254/24 ' || exit 2
pct exec 1231 -- ip -4 -o addr show dev eth0 | grep -Fq "inet $RUNNER_IP/24 " || exit 2
[[ $(pct exec 1254 -- getent passwd dev) == dev:*:/home/dev:* ]] || exit 2
pct exec 1254 -- test -d /home/dev/work/dev-infra/.git
[[ ${3:-} != --check ]] || exit 0

# Existing Runner is pinned to an older Git commit. Stage only two approved
# Ansible files; never update /opt/ansible-3 or execute guest code as PVE root.
TMP=$(mktemp -d /run/ansible-3-dev.XXXXXXXX)
trap 'rm -f -- "$TMP/enroll-dev.yml" "$TMP/dev-access.yml" "$TMP/access.curl" "$TMP/semaphore.crt"; rmdir -- "$TMP"' EXIT
REPO=https://raw.githubusercontent.com/DigitalHouses/Ansible-3
curl --fail --silent --show-error --location --proto '=https' \
  "$REPO/$REF/bootstrap/enroll-dev.yml" -o "$TMP/enroll-dev.yml"
curl --fail --silent --show-error --location --proto '=https' \
  "$REPO/$REF/bootstrap/tasks/dev-access.yml" -o "$TMP/dev-access.yml"
pct exec 1231 -- install -d -m 0700 /root/dh-dev-access/tasks
pct push 1231 "$TMP/enroll-dev.yml" /root/dh-dev-access/enroll-dev.yml \
  --user root --group root --perms 0600
pct push 1231 "$TMP/dev-access.yml" /root/dh-dev-access/tasks/dev-access.yml \
  --user root --group root --perms 0600
pct exec 1231 -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  /opt/ansible/venv/bin/ansible-playbook -i localhost, -c local \
  -e "site_id=$SITE" /root/dh-dev-access/enroll-dev.yml

# No secret value is printed, passed as argv, or stored in Git.
pct pull 1231 /etc/semaphore/dev-automation.curl "$TMP/access.curl"
pct pull 1231 /etc/semaphore/tls.crt "$TMP/semaphore.crt"
chmod 0600 "$TMP/access.curl" "$TMP/semaphore.crt"
pct exec 1254 -- sh -eu -c '
  site=$1
  for p in /home /home/dev /home/dev/.config /home/dev/.config/ansible-3 \
    "/home/dev/.config/ansible-3/$site.curl" \
    "/home/dev/.config/ansible-3/$site.crt"; do
    test ! -L "$p" || exit 2
  done
  install -d -m 0700 -o dev -g dev /home/dev/.config/ansible-3
' sh "$SITE"
pct push 1254 "$TMP/semaphore.crt" "/home/dev/.config/ansible-3/$SITE.crt" \
  --user dev --group dev --perms 0600
pct push 1254 "$TMP/access.curl" "/home/dev/.config/ansible-3/$SITE.curl" \
  --user dev --group dev --perms 0600
pct exec 1254 -- runuser -u dev -- sh -eu -c '
  curl -q --config "/home/dev/.config/ansible-3/$1.curl" \
    "https://$2:3000/api/user/" | jq -e '\''.username == "dev-automation"'\'' >/dev/null
' sh "$SITE" "$RUNNER_IP"
echo "DEV enrolled: site=$SITE; API=https://$RUNNER_IP:3000/api; user=dev-automation"
