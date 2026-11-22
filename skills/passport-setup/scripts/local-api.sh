#!/usr/bin/env bash
# Local setup only: keep the user-supplied public API key out of curl's command line.
set -o pipefail

[ -n "${PASSPORT_API_KEY:-}${PASSPORT_API_KEY_REF:-}" ] || { echo 'Set PASSPORT_API_KEY or PASSPORT_API_KEY_REF first.' >&2; exit 1; }
[ -z "${PASSPORT_API_KEY:-}" ] || [ -z "${PASSPORT_API_KEY_REF:-}" ] || { echo 'Use only one API key source.' >&2; exit 1; }
[ -n "${PASSPORT_API:-}" ] || { echo 'PASSPORT_API is not set.' >&2; exit 1; }
method=${1:?method required}; path=${2:?path required}; body=${3-}
case "$method" in GET|POST|PUT|PATCH|DELETE) ;; *) echo 'unsupported method' >&2; exit 1;; esac
case "$path" in /public/v1/*) ;; *) echo 'Only /public/v1/ API paths are allowed.' >&2; exit 1;; esac
tmp=$(mktemp) || exit 1
if [ -n "${PASSPORT_API_KEY_REF:-}" ]; then
  [[ "$PASSPORT_API_KEY_REF" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo 'Invalid API key reference UUID.' >&2; exit 1; }
  d=${PASSPORT_DIR:-$HOME/.passport}
  proxy_url=${PASSPORT_PROXY_URL:-https://passport-proxy.localhost}
  curl_with_auth() {
    curl --proxy "$proxy_url" --noproxy '' --proxy-cacert "$d/ca.pem" \
      --proxy-cert "$d/cert.pem" --proxy-key "$d/key.pem" \
      --cacert /tmp/pp-local/proxy-ca.pem \
      -H "Authorization: Bearer {{vault:$PASSPORT_API_KEY_REF}}" "$@"
  }
else
  curl_with_auth() {
    curl --config <(printf 'header = "Authorization: Bearer %s"\n' "$PASSPORT_API_KEY") "$@"
  }
fi
if [ -n "$body" ]; then
  case "$body" in @*) body=$(cat "${body#@}") || exit 1;; esac
  printf '%s' "$body" | jq empty || { rm -f "$tmp"; exit 1; }
  status=$(printf '%s' "$body" | curl_with_auth -sS \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -X "$method" \
    --data-binary @- -o "$tmp" -w '%{http_code}' "${PASSPORT_API%/}$path") || { rm -f "$tmp"; exit 1; }
else
  status=$(curl_with_auth -sS \
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
