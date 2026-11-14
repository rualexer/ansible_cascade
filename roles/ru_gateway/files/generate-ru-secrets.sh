#!/usr/bin/env bash
set -euo pipefail

out=${1:?output file is required}
target=${2:?REALITY target is required}
xray_bin=${3:-/usr/local/x-ui/bin/xray-linux-amd64}

[[ ! -e "$out" ]] || exit 0
umask 077

legacy=${SPLIT_VPN_LEGACY_SECRETS:-/root/split-vpn-secrets.env}
if [[ -f "$legacy" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$legacy"
  set +a
  owner_uuid=${OWNER_UUID:-}
  private_key=${RU_REALITY_PRIVATE_KEY:-}
  public_key=${RU_REALITY_PUBLIC_KEY:-}
  short_id=${RU_REALITY_SHORT_ID:-}
  xhttp_path=${RU_XHTTP_PATH:-}
  target=${RU_REALITY_TARGET:-$target}
fi

if [[ -z ${owner_uuid:-} || -z ${private_key:-} || -z ${public_key:-} || -z ${short_id:-} || -z ${xhttp_path:-} ]]; then
  owner_uuid=$($xray_bin uuid)
  keys=$($xray_bin x25519)
  private_key=$(awk '/^(PrivateKey:|Private key:)/ {print $NF; exit}' <<<"$keys")
  public_key=$(awk '/^(Password \(PublicKey\):|PublicKey:|Public key:)/ {print $NF; exit}' <<<"$keys")
  short_id=$(openssl rand -hex 8)
  xhttp_path=/$(openssl rand -hex 20)
fi

[[ -n "$owner_uuid" && -n "$private_key" && -n "$public_key" ]] || {
  printf 'could not generate RU Xray secrets\n' >&2
  exit 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq -n \
  --arg owner_uuid "$owner_uuid" \
  --arg private_key "$private_key" \
  --arg public_key "$public_key" \
  --arg short_id "$short_id" \
  --arg xhttp_path "$xhttp_path" \
  --arg target "$target" \
  '{
    owner_uuid: $owner_uuid,
    ru_reality_private_key: $private_key,
    ru_reality_public_key: $public_key,
    ru_reality_short_id: $short_id,
    ru_xhttp_path: $xhttp_path,
    ru_reality_target: $target
  }' >"$tmp"
install -m 600 "$tmp" "$out"
