#!/usr/bin/env bash
set -euo pipefail

XUI_VERSION=${XUI_VERSION:-v3.7.0}
INSTALLER_URL=https://raw.githubusercontent.com/MHSanaei/3x-ui/main/install.sh
RESULT_FILE=/etc/x-ui/install-result.env
DATABASE=/etc/x-ui/x-ui.db
GUARD_TABLE=xui_install_guard
installer=
hardened=0

die() {
  printf 'install-3x-ui-private: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"
[[ "$XUI_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid XUI_VERSION"
command -v apt-get >/dev/null 2>&1 || die "this installer expects Debian or Ubuntu"
[[ ! -e "$DATABASE" ]] || die "an existing 3x-ui database was found; refusing to overwrite it"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl sqlite3 iproute2 nftables

installer=$(mktemp)
cleanup() {
  rm -f "$installer"
  nft delete table inet "$GUARD_TABLE" 2>/dev/null || true
  if [[ "$hardened" -ne 1 ]] && systemctl list-unit-files x-ui.service >/dev/null 2>&1; then
    systemctl stop x-ui 2>/dev/null || true
  fi
}
trap cleanup EXIT

ssh_port=${XUI_SSH_PORT:-22}
if [[ -z ${XUI_SSH_PORT:-} && -n ${SSH_CONNECTION:-} ]]; then
  read -r _ _ _ ssh_port <<<"$SSH_CONNECTION"
fi
[[ "$ssh_port" =~ ^[0-9]+$ ]] || die "cannot determine the SSH server port"
(( ssh_port >= 1 && ssh_port <= 65535 )) || die "invalid SSH server port"

# Prevent the upstream installer from briefly publishing its random panel port.
# Existing connections survive; new TCP is accepted only on loopback and SSH.
nft delete table inet "$GUARD_TABLE" 2>/dev/null || true
nft -f - <<EOF
table inet $GUARD_TABLE {
  chain input {
    type filter hook input priority -200; policy accept;
    ct state established,related accept
    iifname "lo" accept
    tcp dport $ssh_port accept
    tcp flags syn drop
  }
}
EOF

curl --fail --silent --show-error --location "$INSTALLER_URL" -o "$installer"

# The upstream installer verifies a published release checksum when available.
XUI_NONINTERACTIVE=1 bash "$installer" "$XUI_VERSION"

[[ -f "$DATABASE" ]] || die "3x-ui database was not created"
systemctl stop x-ui

sqlite3 "$DATABASE" <<'SQL'
BEGIN IMMEDIATE;
DELETE FROM settings WHERE key IN ('webListen', 'subListen', 'subEnable');
INSERT INTO settings(key, value) VALUES('webListen', '127.0.0.1');
INSERT INTO settings(key, value) VALUES('subListen', '127.0.0.1');
INSERT INTO settings(key, value) VALUES('subEnable', 'false');
COMMIT;
SQL

chmod 600 "$DATABASE"
systemctl start x-ui
sleep 2

panel_port=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='webPort' LIMIT 1;")
[[ "$panel_port" =~ ^[0-9]+$ ]] || die "cannot determine panel port"

if ss -H -lnt | awk -v port=":$panel_port" '$4 ~ port "$" && $4 !~ /^(127\.0\.0\.1|\[::1\]):/ { found=1 } END { exit !found }'; then
  systemctl stop x-ui
  die "panel is listening on a non-loopback address; service stopped"
fi
hardened=1

printf '\n3x-ui %s installed with private-only panel access.\n' "$XUI_VERSION"
printf 'Panel port: %s\n' "$panel_port"
printf 'Credentials: %s\n' "$RESULT_FILE"
printf 'Tunnel: ssh -N -L 127.0.0.1:12053:127.0.0.1:%s root@RU_SERVER_IP\n' "$panel_port"
