#!/usr/bin/env bash
set -euo pipefail

DATABASE=/etc/x-ui/x-ui.db

die() {
  printf 'verify-3x-ui-private: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "run as root"
[[ -r "$DATABASE" ]] || die "cannot read $DATABASE"
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is not installed"
command -v ss >/dev/null 2>&1 || die "ss is not installed"

web_listen=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='webListen' LIMIT 1;")
sub_listen=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='subListen' LIMIT 1;")
sub_enable=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='subEnable' LIMIT 1;")
panel_port=$(sqlite3 "$DATABASE" "SELECT value FROM settings WHERE key='webPort' LIMIT 1;")

[[ "$web_listen" == 127.0.0.1 ]] || die "webListen is '$web_listen', expected 127.0.0.1"
[[ "$sub_listen" == 127.0.0.1 ]] || die "subListen is '$sub_listen', expected 127.0.0.1"
[[ "$sub_enable" == false ]] || die "subscriptions are enabled"
[[ "$panel_port" =~ ^[0-9]+$ ]] || die "invalid panel port: $panel_port"
systemctl is-active --quiet x-ui || die "x-ui service is not active"

listeners=$(ss -H -lnt | awk -v port=":$panel_port" '$4 ~ port "$" { print $4 }')
[[ -n "$listeners" ]] || die "panel has no TCP listener on port $panel_port"

if awk '$0 !~ /^(127\.0\.0\.1|\[::1\]):/' <<<"$listeners" | grep -q .; then
  printf 'Unexpected listeners:\n%s\n' "$listeners" >&2
  die "panel is exposed on a non-loopback address"
fi

printf 'OK: 3x-ui panel listens only on loopback (%s).\n' "$listeners"
printf 'OK: built-in subscriptions are disabled and bound to loopback.\n'
printf 'SSH tunnel: ssh -N -L 127.0.0.1:12053:127.0.0.1:%s root@RU_SERVER_IP\n' "$panel_port"
