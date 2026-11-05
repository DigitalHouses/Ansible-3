#!/usr/bin/env bash
# Local PVE only: fixed Runner CT1231 and known DEV CT1254.
set -Eeuo pipefail
umask 077
[[ $EUID -eq 0 && -f /etc/pve/user.cfg && ( $# -eq 2 || $# -eq 3 ) ]] || {
  echo 'Usage (root on local PVE): enroll-local-dev.sh SITE RUNNER_IP [--check]' >&2; exit 2;
}
SITE=$1
RUNNER_IP=$2
[[ $SITE =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)+$ &&
   $RUNNER_IP =~ ^192\.168\.11\.([0-9]{1,3})$ &&
   ${3:-} =~ ^(--check)?$ ]] || exit 2
[[ $(pct status 1231) == 'status: running' && $(pct status 1254) == 'status: running' ]] || exit 2
RUNNER_CONFIG=$(pct config 1231)
DEV_CONFIG=$(pct config 1254)
[[ $RUNNER_CONFIG == *"hostname: ansible-$SITE"$'\n'* || $RUNNER_CONFIG == *"hostname: ansible-$SITE" ]] || exit 2
[[ $RUNNER_CONFIG == *"ip=$RUNNER_IP/24"* && $DEV_CONFIG == *'ip=192.168.11.254/24'* ]] || exit 2
[[ $(pct exec 1231 -- hostname) == "ansible-$SITE" ]] || exit 2
DEV_HOSTNAME=$(printf '%s\n' "$DEV_CONFIG" | sed -n 's/^hostname: //p')
[[ -n $DEV_HOSTNAME && $(pct exec 1254 -- hostname) == "$DEV_HOSTNAME" ]] || exit 2
pct exec 1254 -- ip -4 -o addr show dev eth0 | grep -Fq 'inet 192.168.11.254/24 ' || exit 2
pct exec 1231 -- ip -4 -o addr show dev eth0 | grep -Fq "inet $RUNNER_IP/24 " || exit 2
[[ $(pct exec 1254 -- getent passwd dev) == dev:*:/home/dev:* ]] || exit 2
pct exec 1254 -- test -d /home/dev/work/dev-infra/.git
[[ ${3:-} != --check ]] || exit 0

pct exec 1231 -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  /opt/ansible/venv/bin/ansible-playbook -i localhost, -c local \
  -e "site_id=$SITE" /opt/ansible-3/bootstrap/enroll-dev.yml
TRANSFER_DIR=$(mktemp -d /tmp/ansible-3-dev.XXXXXXXX)
trap 'rm -f -- "$TRANSFER_DIR/access.curl" "$TRANSFER_DIR/semaphore.crt"; rmdir -- "$TRANSFER_DIR"' EXIT
chmod 0700 "$TRANSFER_DIR"
pct pull 1231 /etc/semaphore/dev-automation.curl "$TRANSFER_DIR/access.curl"
pct pull 1231 /etc/semaphore/tls.crt "$TRANSFER_DIR/semaphore.crt"
chmod 0600 "$TRANSFER_DIR/access.curl" "$TRANSFER_DIR/semaphore.crt"
# Reject symlinks before writing credentials, including parent directories.
pct exec 1254 -- sh -eu -c '
  for p in /home /home/dev /home/dev/.config /home/dev/.config/ansible-3 /home/dev/.config/ansible-3/${SITE}.curl /home/dev/.config/ansible-3/${SITE}.crt; do
    test ! -L "$p" || exit 2
  done
  install -d -m 0700 -o dev -g dev /home/dev/.config/ansible-3
'
pct push 1254 "$TRANSFER_DIR/semaphore.crt" /home/dev/.config/ansible-3/${SITE}.crt \
  --user dev --group dev --perms 0600
pct push 1254 "$TRANSFER_DIR/access.curl" /home/dev/.config/ansible-3/${SITE}.curl \
  --user dev --group dev --perms 0600
echo "DEV enrolled: CT1254; site=$SITE; API=https://$RUNNER_IP:3000/api"
