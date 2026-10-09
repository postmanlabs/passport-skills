#!/usr/bin/env bash
# Read-only view of the AWS resources recorded in a deployment's state.env.
#   bash aws-resources.sh show   <state.env>   table of every recorded resource with its live status
#   bash aws-resources.sh delete <state.env>   the exact deletion plan, after checking every resource is
#                                              really ours (tag project=passport, Name=passport-proxy-<NAME>)
# It never creates or deletes anything; it only prints what the guide's commands would act on.
set -uo pipefail
CMD="${1:?show|delete}"; S="${2:?state.env}"
[ -r "$S" ] || { echo "no state file at $S"; exit 2; }
# shellcheck disable=SC1090
. "$S"
export AWS_PROFILE AWS_REGION
N="passport-proxy-${NAME:?NAME missing in state.env}"
row(){ printf "  %-15s %-34s %-28s %s\n" "$1" "$2" "$3" "$4"; }
FAIL=0
tagcheck(){ # <describe output "project name"> → ok/mismatch
  case "$1" in "passport $N") echo "tags ok";; "") echo "NOT FOUND";; *) echo "TAG MISMATCH ($1)";; esac; }

ec2tags(){ aws ec2 "$1" "${@:2}" --output text 2>/dev/null | head -1; }
inst_status(){ [ -n "${INSTANCE:-}" ] || { echo "-"; return; }
  aws ec2 describe-instances --instance-ids "$INSTANCE" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "NOT FOUND"; }
inst_tags(){ [ -n "${INSTANCE:-}" ] || return; ec2tags describe-instances --instance-ids "$INSTANCE" \
  --query 'Reservations[0].Instances[0].[Tags[?Key==`project`]|[0].Value,Tags[?Key==`Name`]|[0].Value]'; }
eip_tags(){ [ -n "${ALLOC:-}" ] || return; ec2tags describe-addresses --allocation-ids "$ALLOC" \
  --query 'Addresses[0].[Tags[?Key==`project`]|[0].Value,Tags[?Key==`Name`]|[0].Value]'; }
sg_tags(){ [ -n "${SG:-}" ] || return; ec2tags describe-security-groups --group-ids "$SG" \
  --query 'SecurityGroups[0].[Tags[?Key==`project`]|[0].Value,Tags[?Key==`Name`]|[0].Value]'; }
role_ok(){ [ -n "${ROLE:-}" ] && aws iam get-role --role-name "$ROLE" >/dev/null 2>&1 && echo "exists" || echo "NOT FOUND"; }
prof_ok(){ [ -n "${PROFILE:-}" ] && aws iam get-instance-profile --instance-profile-name "$PROFILE" >/dev/null 2>&1 && echo "exists" || echo "NOT FOUND"; }
cf_status(){ [ -n "${CF_DIST:-}" ] || { echo "-"; return; }
  aws cloudfront get-distribution --id "$CF_DIST" --query '[Distribution.Status,Distribution.DistributionConfig.Enabled,Distribution.DistributionConfig.Comment]' --output text 2>/dev/null || echo "NOT FOUND"; }
fn_ok(){ [ -n "${CF_FUNCTION:-}" ] && aws cloudfront describe-function --name "$CF_FUNCTION" >/dev/null 2>&1 && echo "exists" || echo "NOT FOUND"; }

T_I="$(tagcheck "$(inst_tags | tr '\t' ' ')")"; T_E="$(tagcheck "$(eip_tags | tr '\t' ' ')")"; T_S="$(tagcheck "$(sg_tags | tr '\t' ' ')")"
case "$T_I$T_E$T_S" in *MISMATCH*) FAIL=1;; esac      # tagcheck runs in a subshell, so test its output here
CFS="$(cf_status)"; case "$CFS" in *"Passport proxy $NAME management"*|-|"NOT FOUND") ;; *) echo "  CloudFront $CF_DIST comment does not match '$NAME'"; FAIL=1;; esac

echo "Account $(aws sts get-caller-identity --query Account --output text 2>/dev/null)  region $AWS_REGION  profile $AWS_PROFILE  name $NAME"
row TYPE NAME ID STATUS
row "EC2 instance"   "$N" "${INSTANCE:--}" "$(inst_status), $T_I"
row "Elastic IP"     "$N" "${ALLOC:--} (${EIP:--})" "$T_E"
row "Security group" "$N" "${SG:--}" "$T_S"
row "IAM role"       "${ROLE:--}" "-" "$(role_ok)"
row "Inst. profile"  "${PROFILE:--}" "-" "$(prof_ok)"
row "CF distribution" "${CF_DOMAIN:--}" "${CF_DIST:--}" "$(echo "$CFS" | awk '{print $1", enabled="$2}')"
row "CF function"    "${CF_FUNCTION:--}" "-" "$(fn_ok)"
[ -n "${PROXY_ID:-}" ] && row "Passport proxy" "$N" "$PROXY_ID" "(Passport Cloud)"
[ -n "${NS:-}" ] && row "Passport ns"   "$N-e2e" "$NS" "(Passport Cloud; demo RG/REF/EP/GR in state.env)"
RES="$(dirname "$S")/resources.env"
[ -s "$RES" ] && while read -r m u rest; do row "Added API" "$m $u" "-" "(Passport Cloud) $rest"; done < "$RES"

if [ "$CMD" = delete ]; then
  echo
  if [ "$FAIL" != 0 ]; then echo "STOP: a recorded resource is not tagged as ours — do not delete anything; ask the user."; exit 1; fi
  echo "Deletion plan (in this order; only these IDs, nothing else):"
  i=1
  [ -s "$RES" ] && while read -r m u rest; do
    echo "  $i. Added API $m $u — Passport grant, endpoint, resource group, secret reference ($rest)"; i=$((i+1))
  done < "$RES"
  for line in \
    "${GR:+Passport access grant $GR}" "${EP:+Passport resource endpoint $EP}" "${RG:+Passport resource group $RG}" "${REF:+Passport secret reference $REF}" \
    "${NS:+Passport namespace $NS}" "${PROXY_ID:+Passport proxy registration $PROXY_ID}" \
    "${CF_DIST:+CloudFront distribution $CF_DIST ($CF_DOMAIN): disable, wait, delete}" "${CF_FUNCTION:+CloudFront function $CF_FUNCTION}" \
    "${INSTANCE:+EC2 instance $INSTANCE ($N): terminate — destroys its disk, keys and in-memory Vault}" \
    "${ALLOC:+Elastic IP $ALLOC ($EIP): release}" \
    "${PROFILE:+IAM instance profile $PROFILE}" "${ROLE:+IAM role $ROLE and its inline policies}" \
    "${SG:+Security group $SG ($N)}"; do
    [ -n "$line" ] && { echo "  $i. $line"; i=$((i+1)); }
  done
fi
