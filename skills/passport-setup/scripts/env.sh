# shellcheck shell=bash
# Source at the top of every command block of guides/aws-single-instance.md (each agent command runs in a fresh shell):
#   SKILL_DIR=<absolute skill folder path>; . "$SKILL_DIR/scripts/env.sh"
# Loads the deployment manifest (/tmp/pp-aws/state.env) and defines: st (record), api (Passport Cloud),
# cli (the Passport CLI, host or MDM container), onhost (SSM Run Command).
W=/tmp/pp-aws
mkdir -p "$W"
touch "$W/state.env"
# shellcheck disable=SC1091
. "$W/state.env"
export AWS_PROFILE AWS_REGION
export PASSPORT_DIR="${PASSPORT_DIR:-$HOME/.passport}"

# st KEY VALUE — record a value in the manifest IMMEDIATELY (replaces an older value for KEY).
# Refuses empty, "None" (aws --output text) and "null" (jq on a failed API response).
st() {
  case "${2:-}" in ''|None|null) echo "st: refusing to record empty value for $1 (did the call before it fail?)" >&2; return 1;; esac
  grep -v "^$1=" "$W/state.env" > "$W/state.env.tmp" 2>/dev/null; mv "$W/state.env.tmp" "$W/state.env"
  echo "$1=$2" >> "$W/state.env"; eval "$1=\"\$2\""
}

# api METHOD PATH [JSON|@file] — Passport Cloud API with the CLI login token (never printed)
api() { node "$SKILL_DIR/scripts/passport-api.js" "$@"; }

# cli ARGS — the Passport CLI. With MDM=1 recorded (guides/reference/mdm-macs.md) it runs in the
# pp-cli-linux container, because a managed Mac's own CLI ignores --management-url/--proxy-url.
cli() {
  if [ -n "${MDM:-}" ]; then docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport "$@"
  else passport "$@"; fi
}

# onhost 'shell snippet' — run on the instance via SSM Run Command. NEVER pass a secret in the snippet:
# its text is stored in SSM command history. Secrets go through the interactive session (step 5).
# Prints the remote stdout (and stderr, to stderr) and returns non-zero if the remote command failed.
onhost() {
  local id out cst rc
  id=$(aws ssm send-command --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
    --parameters "$(jq -nc --arg c "$1" '{commands:[$c]}')" --query Command.CommandId --output text) || return 1
  aws ssm wait command-executed --command-id "$id" --instance-id "$INSTANCE" 2>/dev/null || true   # fails on a failed command; checked below
  out=$(aws ssm get-command-invocation --command-id "$id" --instance-id "$INSTANCE" --output json) || return 1
  printf '%s' "$out" | jq -j .StandardOutputContent
  printf '%s' "$out" | jq -j .StandardErrorContent >&2
  cst=$(printf '%s' "$out" | jq -r .Status); rc=$(printf '%s' "$out" | jq -r .ResponseCode)
  [ "$cst" = Success ] && return 0
  echo "onhost: remote command $cst (exit $rc)" >&2
  [ "$rc" -gt 0 ] 2>/dev/null && return "$rc"
  return 1
}
