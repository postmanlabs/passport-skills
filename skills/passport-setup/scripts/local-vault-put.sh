#!/usr/bin/env bash
set -euo pipefail

key=${1:-}
if [[ ! $key =~ ^[A-Za-z0-9][A-Za-z0-9/_-]*$ ]]; then
  echo 'Usage: local-vault-put.sh <vault-key> (letters, digits, /, _ or -)' >&2
  exit 2
fi
token_file=/tmp/pp-local/vault-token
if [[ ! -s $token_file || ! -t 0 ]]; then
  echo 'Vault token file and an interactive terminal are required.' >&2
  exit 1
fi

trap 'unset value VAULT_TOKEN' EXIT
printf 'Secret value: ' >&2
IFS= read -rs value || { printf '\nInput cancelled; nothing stored.\n' >&2; exit 1; }
printf '\n' >&2
[[ -n $value ]] || { echo 'Empty value; nothing stored.' >&2; exit 1; }
export VAULT_TOKEN
VAULT_TOKEN=$(cat "$token_file")
printf '%s' "$value" | docker exec -i \
  -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN \
  pp-vault-dev vault kv put "secret/$key" value=- >/dev/null
echo stored
