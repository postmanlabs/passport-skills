#!/usr/bin/env bash
# Read-only preflight for the AWS single-instance Passport proxy setup. Creates nothing.
# Usage: NAME=<name> AWS_PROFILE=<p> AWS_REGION=<r> bash preflight.sh [instance-type]
set -uo pipefail
NAME="${NAME:?set NAME}"; TYPE="${1:-t3.small}"
ok(){ printf "  ✅ %s\n" "$*"; }; bad(){ printf "  ❌ %s\n" "$*"; FAIL=1; }; info(){ printf "  ·  %s\n" "$*"; }; FAIL=0

echo "== identity"
ID="$(aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1)" || { bad "$ID"; echo "PREFLIGHT FOUND PROBLEMS"; exit 1; }
ACCOUNT="${ID%%[[:space:]]*}"; ARN="${ID#*[[:space:]]}"; ok "$ID (region ${AWS_REGION:-unset})"
[ -n "${AWS_REGION:-}" ] || bad "AWS_REGION is not set"
case "$ARN" in *:root) bad "root credentials: use an IAM user/role (never root)";; esac

echo "== your public IP (client CIDR for 8443)"
MYIP="$(curl -s --max-time 5 https://checkip.amazonaws.com | tr -d '[:space:]')"; [ -n "$MYIP" ] && ok "$MYIP/32" || bad "could not determine your public IP"

echo "== network (default VPC, public subnet)"
VPC="$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text 2>&1)"
case "$VPC" in vpc-*) ok "default VPC $VPC";; *) bad "no default VPC ($VPC): pass your own VPC/subnet in step 3";; esac
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
case "$TYPE" in *g.*|*g?.*|a1.*) bad "instance type $TYPE is arm64 but this file uses the x86_64 AMI";; *) ok "instance type $TYPE (x86_64)";; esac

echo "== EC2 launch permission (dry run)"
if [ -n "$SUBNET" ] && [ "${AMI#ami-}" != "$AMI" ]; then
  R="$(aws ec2 run-instances --dry-run --image-id "$AMI" --instance-type "$TYPE" --subnet-id "$SUBNET" 2>&1)"
  echo "$R" | grep -q DryRunOperation && ok "RunInstances allowed" || bad "RunInstances: $(echo "$R" | grep -oE 'UnauthorizedOperation|[A-Za-z]+Exception|InvalidParameter[A-Za-z]*' | head -1) — $(echo "$R" | tail -1 | cut -c1-160)"
else info "skipped (needs a subnet and an AMI)"; fi

echo "== CloudFront"
PL="$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text 2>&1)"
case "$PL" in pl-*) ok "origin-facing prefix list $PL";; *) bad "prefix list lookup failed: $PL";; esac
C="$(aws cloudfront list-distributions --query 'DistributionList.Items[].Id' --output text 2>&1)"
echo "$C" | grep -qE 'AccessDenied|not authorized' && bad "cloudfront:ListDistributions denied (CloudFront actions are in the permissions table)" || ok "CloudFront API reachable"

echo "== IAM + other permissions (simulated against your identity)"
SRC="$ARN"; case "$ARN" in *:assumed-role/*) R="${ARN#*:assumed-role/}"; SRC="arn:aws:iam::$ACCOUNT:role/${R%%/*}";; esac
ACTIONS="iam:CreateRole iam:PutRolePolicy iam:DeleteRolePolicy iam:DeleteRole iam:CreateInstanceProfile iam:AddRoleToInstanceProfile iam:RemoveRoleFromInstanceProfile iam:DeleteInstanceProfile iam:PassRole iam:TagRole secretsmanager:CreateSecret secretsmanager:DeleteSecret secretsmanager:TagResource ssm:SendCommand ssm:GetCommandInvocation ssm:DescribeInstanceInformation cloudfront:CreateFunction cloudfront:PublishFunction cloudfront:CreateDistribution cloudfront:UpdateDistribution cloudfront:DeleteDistribution cloudfront:DeleteFunction ec2:CreateSecurityGroup ec2:AuthorizeSecurityGroupIngress ec2:AllocateAddress ec2:AssociateAddress ec2:ReleaseAddress ec2:TerminateInstances"
SIM="$(aws iam simulate-principal-policy --policy-source-arn "$SRC" --action-names $ACTIONS --query 'EvaluationResults[?EvalDecision!=`allowed`].EvalActionName' --output text 2>&1)"
if echo "$SIM" | grep -qE 'AccessDenied|not authorized|InvalidInput|NoSuchEntity'; then
  info "cannot simulate (iam:SimulatePrincipalPolicy not allowed to you): IAM/SSM/CloudFront/Secrets permissions can't be pre-checked and will surface at the first create"
elif [ -z "$SIM" ] || [ "$SIM" = None ]; then ok "all $(echo $ACTIONS | wc -w | tr -d ' ') required actions allowed"
else bad "NOT allowed: $SIM"; info "(simulation ignores some SCPs/permission boundaries; a denial here is reliable, an allow is not a guarantee)"; fi

echo "== name '$NAME': existing resources and secrets"
SECS="$(aws secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values="passport/$NAME/" --query 'SecretList[].[Name,DeletedDate]' --output text 2>&1)"
if echo "$SECS" | grep -qE 'AccessDenied|not authorized'; then bad "secretsmanager:ListSecrets denied"
elif [ -z "$SECS" ]; then ok "no secrets under passport/$NAME/"
else echo "$SECS" | while read -r n d; do
  if [ -n "$d" ] && [ "$d" != None ]; then printf "  ❌ %s is SCHEDULED FOR DELETION: creating it will fail. Pick another NAME\n" "$n"; else printf "  ·  %s already exists (reuse? the proxy will use these keys)\n" "$n"; fi; done
  echo "$SECS" | grep -qvE 'None$' && FAIL=1; fi
for kind in role profile; do
  if [ "$kind" = role ]; then aws iam get-role --role-name "passport-proxy-$NAME" >/dev/null 2>&1 && bad "IAM role passport-proxy-$NAME already exists" || ok "no IAM role passport-proxy-$NAME"
  else aws iam get-instance-profile --instance-profile-name "passport-proxy-$NAME" >/dev/null 2>&1 && bad "instance profile passport-proxy-$NAME already exists" || ok "no instance profile passport-proxy-$NAME"; fi
done
if [ "${VPC#vpc-}" != "$VPC" ]; then
  SGS="$(aws ec2 describe-security-groups --filters Name=group-name,Values="passport-proxy-$NAME" Name=vpc-id,Values="$VPC" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null)"
  [ -z "$SGS" ] && ok "no security group passport-proxy-$NAME" || bad "security group passport-proxy-$NAME already exists ($SGS)"; fi
INST="$(aws ec2 describe-instances --filters Name=tag:Name,Values="passport-proxy-$NAME" Name=instance-state-name,Values=pending,running,stopped --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null)"
[ -z "$INST" ] && ok "no instance named passport-proxy-$NAME" || bad "instance passport-proxy-$NAME already exists ($INST)"
EIPS="$(aws ec2 describe-addresses --filters Name=tag:Name,Values="passport-proxy-$NAME" --query 'Addresses[].AllocationId' --output text 2>/dev/null)"
[ -z "$EIPS" ] && ok "no Elastic IP tagged passport-proxy-$NAME" || bad "Elastic IP already exists ($EIPS)"
LIM="$(aws ec2 describe-addresses --query 'length(Addresses)' --output text 2>/dev/null)"; info "Elastic IPs in use in this region: ${LIM:-?} (default quota is 5)"

echo "== local inputs"
[ -s /tmp/pp-aws/registry-key ] && ok "registry key file present (/tmp/pp-aws/registry-key)" || bad "no registry key at /tmp/pp-aws/registry-key (step 2)"
for t in openssl curl jq node; do command -v $t >/dev/null && ok "$t" || bad "$t not installed"; done

echo; [ "$FAIL" = 0 ] && echo "PREFLIGHT OK" || { echo "PREFLIGHT FOUND PROBLEMS (see ❌)"; exit 1; }
