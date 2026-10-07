#!/usr/bin/env bash
# Read-only preflight for the AWS single-instance Passport proxy setup. Creates and changes NOTHING.
# Usage: AWS_PROFILE=<p> AWS_REGION=<r> [NAME=<name>] bash preflight.sh [instance-type]
#   NAME unset → proposes the first collision-free name (t<MMDD>, t<MMDD>b, …) and prints it.
set -uo pipefail
TYPE="${1:-t3.small}"
ok(){ printf "  ✅ %s\n" "$*"; }; bad(){ printf "  ❌ %s\n" "$*"; FAIL=1; }; info(){ printf "  ·  %s\n" "$*"; }; FAIL=0

echo "== local tools"
if command -v aws >/dev/null; then
  V="$(aws --version 2>&1)"; case "$V" in aws-cli/2.*) ok "$V";; *) bad "AWS CLI v2 required (got: $V)";; esac
else bad "AWS CLI not installed (guide step 1.2)"; fi
command -v session-manager-plugin >/dev/null && ok "session-manager-plugin $(session-manager-plugin --version 2>/dev/null)" \
  || bad "Session Manager plugin not installed (guide step 1.2) — needed for the interactive registry login"
if command -v passport >/dev/null; then ok "passport CLI $(passport --version 2>/dev/null) (setup needs >= 0.6.0)"
else info "passport CLI not on PATH (guide step 1.1; MDM Macs use the container CLI instead)"; fi
for t in openssl curl jq node; do command -v "$t" >/dev/null && ok "$t" || bad "$t not installed"; done

echo "== AWS identity"
ID="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1)" || {
  bad "not logged in to AWS: $(echo "$ID" | tail -1)"; echo "   fix: aws sso login --profile \"${AWS_PROFILE:-<profile>}\"  (or: aws login)"; echo; echo "PREFLIGHT FOUND PROBLEMS"; exit 1; }
ACCOUNT="${ID%%[[:space:]]*}"; ARN="${ID#*[[:space:]]}"
ok "account $ACCOUNT as $ARN (profile ${AWS_PROFILE:-default}, region ${AWS_REGION:-unset})"
[ -n "${AWS_REGION:-}" ] || bad "AWS_REGION is not set"
case "$ARN" in *:root) bad "root credentials: use an IAM Identity Center/SSO role or IAM user, never root";; esac

echo "== your public IP (client CIDR for 8443)"
MYIP="$(curl -s --max-time 5 https://checkip.amazonaws.com | tr -d '[:space:]')"
[ -n "$MYIP" ] && ok "$MYIP/32" || bad "could not determine your public IP"

echo "== network (default VPC, public subnet)"
VPC="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text 2>&1)"
case "$VPC" in vpc-*) ok "default VPC $VPC";; *) bad "no default VPC ($VPC): choose a VPC/public subnet yourself in step 3";; esac
SUBNET=""
if [ "${VPC#vpc-}" != "$VPC" ]; then
  for S in $(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC" Name=map-public-ip-on-launch,Values=true --query 'Subnets[].SubnetId' --output text); do
    GW="$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values="$S" --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text 2>/dev/null)"
    if [ -z "$GW" ] || [ "$GW" = None ]; then
      GW="$(aws ec2 describe-route-tables --filters Name=vpc-id,Values="$VPC" Name=association.main,Values=true --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text 2>/dev/null)"; fi
    case "$GW" in igw-*) SUBNET="$S"; break;; esac
  done
  [ -n "$SUBNET" ] && ok "public subnet $SUBNET (0.0.0.0/0 → igw)" || bad "no public subnet (needs MapPublicIpOnLaunch and a 0.0.0.0/0 → igw route)"
fi

echo "== AMI (stock Amazon Linux 2023, x86_64)"
AMI="$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text 2>&1)"
case "$AMI" in ami-*) ok "$AMI";; *) bad "ssm:GetParameter failed: $AMI";; esac
case "$TYPE" in *g.*|*g?.*|a1.*) bad "instance type $TYPE is arm64 but this guide uses the x86_64 AMI";; *) ok "instance type $TYPE (x86_64)";; esac

echo "== EC2 launch permission (dry run)"
if [ -n "$SUBNET" ] && [ "${AMI#ami-}" != "$AMI" ]; then
  R="$(aws ec2 run-instances --dry-run --image-id "$AMI" --instance-type "$TYPE" --subnet-id "$SUBNET" 2>&1)"
  echo "$R" | grep -q DryRunOperation && ok "RunInstances allowed" \
    || bad "RunInstances: $(echo "$R" | grep -oE 'UnauthorizedOperation|[A-Za-z]+Exception|InvalidParameter[A-Za-z]*' | head -1) — $(echo "$R" | tail -1 | cut -c1-160)"
else info "skipped (needs a subnet and an AMI)"; fi

echo "== CloudFront"
PL="$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text 2>&1)"
case "$PL" in pl-*) ok "origin-facing prefix list $PL";; *) bad "prefix list lookup failed: $PL";; esac
C="$(aws cloudfront list-distributions --query 'DistributionList.Items[].Id' --output text 2>&1)"
echo "$C" | grep -qE 'AccessDenied|not authorized' && bad "cloudfront:ListDistributions denied (see templates/operator-iam-policy.json)" || ok "CloudFront API reachable"

echo "== permissions (simulated against your identity)"
SRC="$ARN"; case "$ARN" in *:assumed-role/*) R="${ARN#*:assumed-role/}"; SRC="arn:aws:iam::$ACCOUNT:role/${R%%/*}";; esac
ACTIONS="ec2:RunInstances ec2:TerminateInstances ec2:CreateSecurityGroup ec2:DeleteSecurityGroup ec2:AuthorizeSecurityGroupIngress ec2:AllocateAddress ec2:AssociateAddress ec2:ReleaseAddress ec2:CreateTags iam:CreateRole iam:TagRole iam:PutRolePolicy iam:DeleteRolePolicy iam:DeleteRole iam:CreateInstanceProfile iam:DeleteInstanceProfile iam:AddRoleToInstanceProfile iam:RemoveRoleFromInstanceProfile iam:PassRole ssm:SendCommand ssm:GetCommandInvocation ssm:StartSession ssm:DescribeInstanceInformation cloudfront:CreateFunction cloudfront:PublishFunction cloudfront:DeleteFunction cloudfront:CreateDistribution cloudfront:UpdateDistribution cloudfront:DeleteDistribution"
# shellcheck disable=SC2086
SIM="$(aws iam simulate-principal-policy --policy-source-arn "$SRC" --action-names $ACTIONS --query 'EvaluationResults[?EvalDecision!=`allowed`].EvalActionName' --output text 2>&1)"
if echo "$SIM" | grep -qE 'AccessDenied|not authorized|InvalidInput|NoSuchEntity'; then
  info "cannot simulate (iam:SimulatePrincipalPolicy not allowed): missing permissions surface at the first create — compare with templates/operator-iam-policy.json"
elif [ -z "$SIM" ] || [ "$SIM" = None ]; then ok "all $(echo "$ACTIONS" | wc -w | tr -d ' ') create/delete actions allowed"
else bad "NOT allowed: $SIM (see templates/operator-iam-policy.json)"; info "a denial here is reliable; an allow is not a guarantee (SCPs/boundaries may still block)"; fi

echo "== resource name"
name_free() {   # every resource this guide would create for passport-proxy-$1 is absent
  local n="passport-proxy-$1"
  aws iam get-role --role-name "$n" >/dev/null 2>&1 && return 1
  aws iam get-instance-profile --instance-profile-name "$n" >/dev/null 2>&1 && return 1
  [ -n "$(aws ec2 describe-security-groups --filters Name=group-name,Values="$n" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)" ] && return 1
  [ -n "$(aws ec2 describe-instances --filters Name=tag:Name,Values="$n" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)" ] && return 1
  [ -n "$(aws ec2 describe-addresses --filters Name=tag:Name,Values="$n" --query 'Addresses[].AllocationId' --output text 2>/dev/null)" ] && return 1
  aws cloudfront describe-function --name "$n-404" >/dev/null 2>&1 && return 1
  return 0
}
if [ -n "${NAME:-}" ]; then
  name_free "$NAME" && ok "NAME=$NAME is free (resources will be passport-proxy-$NAME…)" \
    || bad "NAME=$NAME collides with an existing passport-proxy-$NAME resource; unset NAME to get a free one"
else
  BASE="t$(date +%m%d)"; NAME=""
  for suf in "" b c d e f g h; do name_free "$BASE$suf" && { NAME="$BASE$suf"; break; }; done
  [ -n "$NAME" ] && ok "proposed NAME=$NAME (collision-free)" || bad "no free name among $BASE…h; pass NAME=<name>"
fi
LIM="$(aws ec2 describe-addresses --query 'length(Addresses)' --output text 2>/dev/null)"
info "Elastic IPs in use in this region: ${LIM:-?} (default quota is 5)"
echo "PREFLIGHT_NAME=${NAME:-}"

echo; [ "$FAIL" = 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FOUND PROBLEMS (see ❌)"; exit 1; }
