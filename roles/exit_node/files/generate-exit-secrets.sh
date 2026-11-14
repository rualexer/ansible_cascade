#!/usr/bin/env bash
set -euo pipefail

out=${1:?output file is required}
target=${2:?REALITY target is required}
xray_bin=${3:-/usr/local/bin/xray}

[[ ! -e "$out" ]] || exit 0
umask 077

legacy=${SPLIT_VPN_LEGACY_SECRETS:-/root/split-vpn-secrets.env}
if [[ -f "$legacy" ]]; then
  # Adopt secrets created by the original manual deployment. Its variables
  # used the old FI label even when the exit server was in Germany.
  set -a
  # shellcheck disable=SC1090
  source "$legacy"
  set +a
  uuid=${DE_TRANSIT_UUID:-${FI_TRANSIT_UUID:-}}
  private_key=${DE_REALITY_PRIVATE_KEY:-${FI_REALITY_PRIVATE_KEY:-}}
  public_key=${DE_REALITY_PUBLIC_KEY:-${FI_REALITY_PUBLIC_KEY:-}}
  short_id=${DE_REALITY_SHORT_ID:-${FI_REALITY_SHORT_ID:-}}
  xhttp_path=${DE_XHTTP_PATH:-${FI_XHTTP_PATH:-}}
  target=${DE_REALITY_TARGET:-${FI_REALITY_TARGET:-$target}}
fi

if [[ -z ${uuid:-} || -z ${private_key:-} || -z ${public_key:-} || -z ${short_id:-} || -z ${xhttp_path:-} ]]; then
  uuid=$($xray_bin uuid)
  keys=$($xray_bin x25519)
  private_key=$(awk '/^(PrivateKey:|Private key:)/ {print $NF; exit}' <<<"$keys")
  public_key=$(awk '/^(Password \(PublicKey\):|PublicKey:|Public key:)/ {print $NF; exit}' <<<"$keys")
  short_id=$(openssl rand -hex 8)
  xhttp_path=/$(openssl rand -hex 20)
fi

[[ -n "$uuid" && -n "$private_key" && -n "$public_key" ]] || {
  printf 'could not generate exit Xray secrets\n' >&2
  exit 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq -n \
  --arg uuid "$uuid" \
  --arg private_key "$private_key" \
  --arg public_key "$public_key" \
  --arg short_id "$short_id" \
  --arg xhttp_path "$xhttp_path" \
  --arg target "$target" \
  '{
    exit_transit_uuid: $uuid,
    exit_reality_private_key: $private_key,
    exit_reality_public_key: $public_key,
    exit_reality_short_id: $short_id,
    exit_xhttp_path: $xhttp_path,
    exit_reality_target: $target
  }' >"$tmp"
install -m 600 "$tmp" "$out"
