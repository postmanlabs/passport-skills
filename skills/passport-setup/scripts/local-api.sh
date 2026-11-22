#!/usr/bin/env bash
# Local setup only: keep the CLI token out of curl's command line and shell history.
set -o pipefail

token=$(jq -er '.login._profiles[0].workos.accessToken' "${PASSPORT_DIR:-$HOME/.passport}/passportrc") || exit 1
payload=${token#*.}; payload=${payload%%.*}
claims=$(printf '%s===' "$payload" | tr '_-' '/+' | openssl base64 -d -A 2>/dev/null) || exit 1
user_id=$(printf '%s' "$claims" | jq -er '.sub') || exit 1
expiry=$(printf '%s' "$claims" | jq -er '.exp') || exit 1
[ "$expiry" -gt "$(date +%s)" ] || { echo 'token expired; run passport auth status' >&2; exit 1; }
[ -n "$(printf '%s' "$claims" | jq -er '.org_id')" ] || exit 1

if [ "${1:-}" = user-id ]; then printf '%s\n' "$user_id"; exit 0; fi
method=${1:?method required}; path=${2:?path required}; body=${3-}
case "$method" in GET|POST|PUT|PATCH|DELETE) ;; *) echo 'unsupported method' >&2; exit 1;; esac
case "$path" in /*) ;; *) echo 'API path must start with /' >&2; exit 1;; esac
tmp=$(mktemp) || exit 1
if [ -n "$body" ]; then
  case "$body" in @*) body=$(cat "${body#@}") || exit 1;; esac
  printf '%s' "$body" | jq empty || { rm -f "$tmp"; exit 1; }
  status=$(printf '%s' "$body" | curl -sS --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -X "$method" \
    --data-binary @- -o "$tmp" -w '%{http_code}' "${PASSPORT_API%/}$path") || { rm -f "$tmp"; exit 1; }
else
  status=$(curl -sS --config <(printf 'header = "Authorization: Bearer %s"\n' "$token") \
    -H 'Accept: application/json' -X "$method" -o "$tmp" -w '%{http_code}' "${PASSPORT_API%/}$path") || { rm -f "$tmp"; exit 1; }
fi
case "$status" in 2??)
    if [ -s "$tmp" ]; then
      jq -n --argjson status "$status" --slurpfile body "$tmp" '{status:$status,body:$body[0]}'
    else
      jq -n --argjson status "$status" '{status:$status,body:""}'
    fi
    result=$?;;
  *) echo "api: $method $path -> $status" >&2; result=1;; esac
rm -f "$tmp"
exit "$result"
