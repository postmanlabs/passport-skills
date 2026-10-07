# shellcheck shell=bash
# Source at the top of every command block of guides/aws-single-instance.md (each agent command runs in a fresh shell):
#   REPO=<absolute repo path>; . "$REPO/scripts/env.sh"
# Loads the deployment manifest (/tmp/pp-aws/state.env) and defines: st (record), api (Passport Cloud), onhost (SSM Run Command).
W=/tmp/pp-aws
mkdir -p "$W"
touch "$W/state.env"
# shellcheck disable=SC1091
. "$W/state.env"
export AWS_PROFILE AWS_REGION
export PASSPORT_DIR="${PASSPORT_DIR:-$HOME/.passport}"

# st KEY VALUE — record a value in the manifest IMMEDIATELY (replaces an older value for KEY)
st() {
  [ -n "${2:-}" ] && [ "$2" != None ] || { echo "st: refusing to record empty value for $1" >&2; return 1; }
  grep -v "^$1=" "$W/state.env" > "$W/state.env.tmp" 2>/dev/null; mv "$W/state.env.tmp" "$W/state.env"
  echo "$1=$2" >> "$W/state.env"; eval "$1=\"\$2\""
}

# api METHOD PATH [JSON|@file] — Passport Cloud API with the CLI login token (never printed)
api() { node "$REPO/scripts/passport-api.js" "$@"; }

# onhost 'shell snippet' — run on the instance via SSM Run Command. NEVER pass a secret in the snippet:
# its text is stored in SSM command history. Secrets go through the interactive session (step 5).
onhost() {
  local id
  id=$(aws ssm send-command --instance-ids "$INSTANCE" --document-name AWS-RunShellScript \
    --parameters "$(jq -nc --arg c "$1" '{commands:[$c]}')" --query Command.CommandId --output text) || return 1
  aws ssm wait command-executed --command-id "$id" --instance-id "$INSTANCE" 2>/dev/null
  aws ssm get-command-invocation --command-id "$id" --instance-id "$INSTANCE" --query StandardOutputContent --output text
}
