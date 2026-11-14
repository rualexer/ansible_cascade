#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
inventory=$script_dir/inventory.yml
export ANSIBLE_CONFIG=${ANSIBLE_CONFIG:-$script_dir/ansible.cfg}

if (( $# > 0 )) && [[ $1 != -* ]]; then
  inventory=$1
  shift
fi

[[ -f "$inventory" ]] || {
  printf 'Inventory not found: %s\nCopy inventory.example.yml to inventory.yml and edit it.\n' "$inventory" >&2
  exit 1
}

exec ansible-playbook -i "$inventory" "$script_dir/site.yml" "$@"
