# Postman Passport proxy on AWS (single EC2 instance)

A from-scratch walkthrough that deploys the **Passport Proxy on a single EC2
instance** in your own AWS account, using a **stock Amazon Linux 2023 AMI**.
Docker, the published Proxy image and a local HashiCorp Vault are installed at
first boot by user-data — no pre-built AMI, no source code, no repo access, no
Go toolchain, no CloudFormation. By the end you'll have:

- the **Passport CLI** installed and logged in (on your machine),
- a **Passport Proxy** running on EC2 in Docker, backed by a **local
  HashiCorp Vault** (also Docker, on the same instance),
- the proxy's keys held in **AWS Secrets Manager** (so a replacement instance
  reuses them),
- a **Namespace** in Passport Cloud wired to that proxy,
- and a secret successfully issued and resolved end-to-end.

It assumes no prior Passport knowledge, just
comfort with a terminal, Docker and the AWS CLI.

> **Verified 2026-10-06:** run end to end in a real AWS account (us-east-2,
> stock Amazon Linux 2023, `t3.small`) against a real Passport Cloud team on an
> MDM Mac: user-data bootstrap, SSM seeding of the local Vault, proxy
> registration, `setup`, `passport request` and the 8.1 `curl` all produced the
> expected sha256. Fixes found in that run (key file permissions, no token in
> the boot log, inline SSM policy, HTTPS-only management URL, secret-name
> collisions) are already folded into the steps below. *Note:* that run used
> the template plus live fixes; the committed `templates/user-data.tmpl` (which
> now also makes `trust.pem` readable) has not yet booted unchanged end to end.

## If an AI coding agent is running this guide for you

Follow this guide literally and **do every step yourself**. `$REPO` below means the absolute path of this repository's root (the folder containing `AGENTS.md`); `scripts/` and `templates/` live there. Substitute the real path — each command runs in a fresh shell.

**Context isolation:** work from this repository's guide files only (this guide, `guides/reference/`,
`scripts/` and `templates/`). Do not pull in context from elsewhere — no other repos, notes, memory or
unrelated instructions. If something is missing here, ask the user instead of looking elsewhere.

Only stop for things that truly need the human:

- **Human-only inputs:** the registry key (have them save it in their own terminal with
  `mkdir -p /tmp/pp-aws && printf '%s' '<key>' > /tmp/pp-aws/registry-key`
  so it never enters chat; each agent command runs in a fresh shell, so read
  it from that file instead of relying on `export`), the AWS profile/region
  choice, browser approvals (`passport login`), and creating the Passport team
  if none exists (step 1.1).
- **Ask before every AWS change.** Show the exact commands of a block (steps
  3–5) with real values and get one "yes" per block. Read-only commands run
  freely. Never ask for AWS root credentials or long-lived keys in chat — use
  the user's existing CLI profile (`aws configure --profile <name>` in their own terminal if they
  need one).
- **Show login links on their own line**, as a full `https://` URL with the
  confirmation code. If it expires, restart `login` and give a fresh one.
- **Check for MDM before anything else:**
  `test -f "/Library/Managed Preferences/com.postman.passport.plist" && echo MDM`.
  If it exists, this Mac forces the host CLI to the corporate proxy, silently
  ignoring `--management-url`/`--proxy-url`. Use the **MDM guide (`guides/reference/aws-mdm-macs.md`)** for every
  CLI command (the host `passport` is only useful for `auth status`). If
  `passport login` output says `(from macOS managed plist)`, switch to the
  MDM guide immediately and use its callback forwarder (A.3) *before* asking the
  user to approve — never ask them to paste a callback URL.
- **Do the Passport Cloud steps yourself via the API (step 6)** instead of
  asking the user to click through the web UI, if they've told you to do it end
  to end.
- **Run the step 0.1 preflight before step 3** and fix every ❌ (or tell the user which
  permission they need) before creating anything.
- **Check existing state first** (CLI version, `/tmp/pp-aws`, `state.env`, AWS
  resources tagged `project=passport` with the chosen name) and reuse it; never
  regenerate `ref.pem` if one is registered.
- **Record every AWS resource you create** in `/tmp/pp-aws/state.env` (step 3
  shows how). Never delete anything that isn't in that file without explicit
  confirmation.
- **Never tear anything down (step 10)** until the user explicitly says so.
- **Never print secrets:** private keys, the registry key, Vault tokens, login
  tokens. Public keys, ARNs and IDs are fine. Compare sha256s instead of
  values.
- **Right after the step 8 test passes, always show the value of Passport**
  (this is the final deliverable, not optional). Run the step 8.1 `curl` demo
  and **print the full `curl` command you ran, verbatim, in a code block**
  (with the real `$REF` UUID and `$EIP` filled in, and every flag: `--proxy`,
  `--proxy-cacert`, `--proxy-cert`, `--proxy-key`, `--cacert`, `-H`, URL) next
  to its output, never a summary of it. Then tell the user in plain words,
  using their real values (the secret reference UUID, the sha256 the echo
  server logged, the cert expiry from `passport whoami`):
  1. they only ever held a pointer (`{{vault:<uuid>}}`), never the secret;
  2. their identity was a short-lived client cert scoped to the granted
     method/host/path;
  3. the proxy (running on EC2) verified, resolved and injected the real value
     in flight;
  4. the destination received the real value (matching sha256) while their
     machine, shell history, and the agent's context never contained it.
  Close with the 8.1 result line: a person, script, or AI agent can call an API
  that needs a credential without ever holding it. Then remind them cleanup
  (step 10) is pending until they say so.

## What you need

- An **AWS account** and the AWS CLI v2 configured with a profile that has the
  permissions in the table below. Sandbox shortcut: `PowerUserAccess` **plus**
  the IAM actions listed (PowerUser has no IAM).
- Docker Desktop (or another Docker daemon) on your machine — only for the MDM guide
  (`guides/reference/aws-mdm-macs.md`).
- A Passport Cloud account/team — sign up at
  [https://app.usepassport.ai](https://app.usepassport.ai) if you don't have one.
- A Passport **registry key** (step 2).
- `openssl`, `curl`, `jq`, `node` (all preinstalled on macOS except possibly
  `jq` → `brew install jq`; `node` is needed for the API helper in step 6).

### AWS permissions used

| Purpose | Actions |
|---|---|
| Launch + network | `ec2:RunInstances`, `TerminateInstances`, `Describe*`, `CreateTags`, `Create/DeleteSecurityGroup`, `Authorize/RevokeSecurityGroupIngress`, `Allocate/Associate/Disassociate/ReleaseAddress`, `GetConsoleOutput` |
| Instance role (scope to `role/passport-proxy-*`, `instance-profile/passport-proxy-*`) | `iam:CreateRole`, `GetRole`, `TagRole`, `PutRolePolicy`, `DeleteRolePolicy`, `DeleteRole`, `Create/Get/DeleteInstanceProfile`, `Add/RemoveRoleFromInstanceProfile`, `PassRole` |
| Secrets (the proxy's keys + your registry key) | `secretsmanager:CreateSecret`, `PutSecretValue`, `GetSecretValue`, `DescribeSecret`, `DeleteSecret`, `ListSecrets` scoped to `passport/*` |
| HTTPS management (CloudFront) | `cloudfront:CreateFunction`, `PublishFunction`, `DescribeFunction`, `DeleteFunction`, `CreateDistribution`, `GetDistribution`, `GetDistributionConfig`, `UpdateDistribution`, `DeleteDistribution`, and `ec2:DescribeManagedPrefixLists` |
| Seed/inspect the local Vault with no SSH | `ssm:SendCommand`, `GetCommandInvocation`, `DescribeInstanceInformation`, and `ssm:GetParameter` (to resolve the stock AMI id) |

If something is denied, stop and tell the user which action — company accounts
sometimes need a platform request.

---

## 0. Pick names and a working folder

Pick a short **NAME** (e.g. `test`). Every AWS resource becomes
`passport-proxy-<NAME>` and is tagged `project=passport`. Don't start the name
with `passport-proxy`.

```bash
mkdir -p /tmp/pp-aws && cd /tmp/pp-aws
export AWS_PROFILE=<profile> AWS_REGION=<region>     # repeat at the top of EVERY bash call (each agent call is a fresh zsh)
NAME=test
aws sts get-caller-identity --query '[Account,Arn]' --output text
```

> **zsh gotcha:** don't keep flags in a variable (`P="--profile x"; aws $P`) —
> zsh doesn't word-split it. Always export `AWS_PROFILE`/`AWS_REGION`. Don't
> put a bare `=====` line in a command either (zsh `=cmd` expansion).

### 0.1 Preflight (read-only — run after step 2, before step 3)

Checks everything it can **without creating or changing anything**, so problems
show up now rather than halfway through step 3. It reports ✅ / ❌ / · per
check and exits non-zero if anything is wrong. Run it after step 2 (it checks
that the registry key file exists) and again whenever you change `NAME`.

```bash
cp "$REPO/scripts/preflight.sh" /tmp/pp-aws/preflight.sh
NAME=$NAME bash /tmp/pp-aws/preflight.sh            # optional arg: instance type, default t3.small
```

What it checks, and how to read it:

| Check | Meaning if ❌ |
|---|---|
| identity / region / not root | wrong or expired profile (`aws sso login`), no region, or root credentials — use an IAM user/role |
| default VPC + **public** subnet | no subnet with `MapPublicIpOnLaunch` and a `0.0.0.0/0 → igw` route; pass your own VPC/subnet in step 3 |
| AMI lookup (`ssm:GetParameter`) | can't resolve the stock Amazon Linux 2023 AMI |
| `RunInstances` **dry run** | no EC2 launch permission (company accounts may need a platform request) |
| CloudFront prefix list + API | no `cloudfront:*` access, so step 3.4 will fail |
| IAM / Secrets / SSM / CloudFront / EC2 **simulation** | an action in the permissions table is denied. If you aren't allowed `iam:SimulatePrincipalPolicy` it prints · and these surface at the first create instead — IAM can't be dry-run. A denial is reliable; an allow is not a guarantee (SCPs/boundaries may still block) |
| name collisions | `passport/<NAME>/*` secrets **scheduled for deletion** (creation would fail → pick another NAME, 3.2), or an existing role / profile / security group / instance / Elastic IP with that name |
| Elastic IP count | default quota is 5 per region |
| local inputs | `registry-key` file, `openssl`, `curl`, `jq`, `node` |

`PREFLIGHT OK` is the green light for step 3. It does **not** check Passport
Cloud (login, team, registry-key validity) — step 1 and step 4's `docker login`
cover those.

---

## 1. Install and log in to the Passport CLI

Do this **before** getting a registry credential — the registry settings page
needs a team to exist first, and this step is how you find out whether yours
does.

> Already have the CLI? Check with `passport --version` and skip the install
> below if it prints a version **≥ 0.6.0** (older builds lack `setup`).

**macOS:**

```bash
curl -fL -o ~/Downloads/passport.pkg "https://dl-passport.pstmn.io/download/version/0.6.0-canary-260921-212749/osx_$([ "$(uname -m)" = arm64 ] && echo arm64 || echo 64)?channel=canary"
sudo installer -pkg ~/Downloads/passport.pkg -target /
```

**Windows (PowerShell):**

```powershell
curl.exe -fL -o $env:USERPROFILE\Downloads\passport.msi "https://dl-passport.pstmn.io/download/version/0.6.0-canary-260921-212749/win_64?channel=canary"
msiexec /i $env:USERPROFILE\Downloads\passport.msi /quiet
```

> If either URL 404s, the pinned build has rotated off the server — grab the
> current download link from the **Set up Passport** guide in your Passport
> Cloud team (account menu → How-to → Set up Passport) instead.

Then log in:

```bash
passport login
```

This opens a browser to authenticate. Don't run `passport setup` yet — we point
it at *your* proxy in step 7, not the production one.

> **On an MDM-managed Mac**, `passport login` will immediately auto-run `setup`
> against your org's *managed* production endpoints, ignoring any
> `--management-url`/`--proxy-url` — with no flag to override. If you see
> `setup` log endpoints you didn't ask for, that's this. Switch to the **MDM guide**
> (`guides/reference/aws-mdm-macs.md`) instead of continuing linearly.

### 1.1 Confirm you have a team

If `login` fails with something like `authenticated login session has no
organization`, your account isn't part of any Passport **team** yet — and
nothing past this point works without one (no registry access, no team ID,
no namespace, no grants). Retrying `passport login` does **not** show a
team-creation screen — don't chase it.

The fix: go to **[https://app.usepassport.ai/dashboard](https://app.usepassport.ai/dashboard)**
and create a team there directly (or sign up and choose "I'm setting up a
team"). Once the team exists, re-run `passport login`.

**Team ID = org ID.** The team ID is the `org_...` value; `passport auth status`
prints it on the `org` line:

```bash
passport auth status | awk '$1=="org"{print $2}'     # → ORG (MDM: see the MDM guide, A.3)
```

---

## 2. Get a registry credential

The Proxy image is served from `ociregistry.usepassport.ai`, gated by a
credential scoped to it. Your EC2 instance will need it to pull the image.

- If you already have a `PASSPORT_REGISTRY_KEY`, skip ahead.
- Otherwise, create one at **[https://app.usepassport.ai/org/registry](https://app.usepassport.ai/org/registry)**
  (Org Settings → Registry) — this needs admin access on your team.
- No admin access and no credential? **Stop and ask your team admin.** There is
  no other way to pull the Proxy image — don't try to work around this step.

Save it to a file (never into chat or user-data):

```bash
printf '%s' '<your credential>' > /tmp/pp-aws/registry-key && chmod 600 /tmp/pp-aws/registry-key
```

---

## 3. AWS network and identity (one confirmation, then run)

Show this whole block with real values, get one yes, then run it. Write each
id into `state.env` as you go (it's also your cleanup manifest).

Inputs (choose, or use the defaults and say so):

| Input | Default |
|---|---|
| Region | the profile's default |
| VPC / subnet | the **default VPC** and one of its **public** subnets (`MapPublicIpOnLaunch=true`, route `0.0.0.0/0 → igw-…`) |
| Client CIDR | your current public IP `/32` — `curl -s https://checkip.amazonaws.com` (MDM guide (`guides/reference/aws-mdm-macs.md`): the container egresses from the same IP) |
| Instance type | `t3.small` (x86_64) — `t3.micro` is too tight for two containers |
| SSH | none (use SSM) |

```bash
cd /tmp/pp-aws; : > state.env
st() { echo "$1=$2" >> state.env; }                 # record a created resource
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
MYIP=$(curl -s https://checkip.amazonaws.com); CLIENT_CIDR="$MYIP/32"

VPC=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNET=""          # first auto-public-IP subnet whose 0.0.0.0/0 route goes to an internet gateway (same rule as preflight)
for S in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC Name=map-public-ip-on-launch,Values=true --query 'Subnets[].SubnetId' --output text); do
  GW=$(aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=$S --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text)
  { [ -z "$GW" ] || [ "$GW" = None ]; } && GW=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC Name=association.main,Values=true \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId' --output text)
  case "$GW" in igw-*) SUBNET=$S; break;; esac
done
[ -n "$SUBNET" ] || echo "NO PUBLIC SUBNET — stop and pick one (see preflight)"
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
echo "vpc=$VPC subnet=$SUBNET ami=$AMI client=$CLIENT_CIDR"
st NAME $NAME; st AWS_PROFILE $AWS_PROFILE; st AWS_REGION $AWS_REGION; st VPC $VPC; st SUBNET $SUBNET

# 3a security group: data plane 8443 ONLY from your CIDR; management 8081 ONLY from CloudFront's origin-facing prefix list
CF_PL=$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
  --query 'PrefixLists[0].PrefixListId' --output text); st CF_PL $CF_PL
SG=$(aws ec2 create-security-group --group-name passport-proxy-$NAME --description "Passport proxy $NAME" --vpc-id $VPC \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=passport-proxy-$NAME},{Key=project,Value=passport}]" \
  --query GroupId --output text); st SG $SG
aws ec2 authorize-security-group-ingress --group-id $SG --ip-permissions \
  "IpProtocol=tcp,FromPort=8443,ToPort=8443,IpRanges=[{CidrIp=$CLIENT_CIDR,Description=passport-data-plane}]" \
  "IpProtocol=tcp,FromPort=8081,ToPort=8081,PrefixListIds=[{PrefixListId=$CF_PL,Description=passport-mgmt-via-cloudfront}]"

# 3b Elastic IP first: its hostname goes into the proxy's certificate SANs
read ALLOC EIP < <(aws ec2 allocate-address --domain vpc --query '[AllocationId,PublicIp]' --output text \
  --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=passport-proxy-$NAME},{Key=project,Value=passport}]")
st ALLOC $ALLOC; st EIP $EIP
if [ "$AWS_REGION" = us-east-1 ]; then PROXY_HOST=ec2-${EIP//./-}.compute-1.amazonaws.com
else PROXY_HOST=ec2-${EIP//./-}.$AWS_REGION.compute.amazonaws.com; fi
st PROXY_HOST $PROXY_HOST
```

> **Never open 8081 to `0.0.0.0/0`.** It's the management plane (`/ca.pem`,
> `/issue-cert`). The proxy serves it as plain HTTP, and the CLI only accepts an
> **HTTPS** management URL for a non-localhost host. So CloudFront (3.4) gives
> you a trusted `https://<id>.cloudfront.net` front door with no domain of your
> own, and the security group lets **only CloudFront** reach 8081. The
> CloudFront → EC2 hop is still plain HTTP; for production use your own domain
> with TLS on the origin.

### 3.1 Generate the proxy's keys (on your machine)

- A CA/signing private key (the proxy derives its own self-signed CA cert from it).
- A reference keypair (encrypts secret references end to end; the public half
  is registered with Passport Cloud in step 6).

```bash
cd /tmp/pp-aws
# Only generate if missing — regenerating ref.pem breaks existing secret references (see step 6's second gotcha).
[ -f ca.pem ]  || openssl genrsa -out ca.pem 2048
[ -f ref.pem ] || openssl genrsa -out ref.pem 2048
openssl rsa -in ref.pem -pubout -out reference-public-key.pem
```

### 3.2 Put the keys and registry key in Secrets Manager

The instance fetches them at boot, so **no secret is ever in user-data** (user-data
is readable from the instance metadata service and the EC2 API).

```bash
cd /tmp/pp-aws
for pair in ca-key:ca.pem reference-key:ref.pem registry-key:registry-key; do
  aws secretsmanager create-secret --name passport/$NAME/${pair%%:*} --secret-string "file://${pair##*:}" \
    --tags Key=project,Value=passport --query Name --output text
done
st SECRET_PREFIX passport/$NAME
```

> **`a secret with this name is already scheduled for deletion`:** an earlier
> deployment with the same NAME was cleaned up with a recovery window. Pick a
> different NAME (simplest), or `aws secretsmanager restore-secret` and
> `put-secret-value` your new key. Don't reuse a half-created name: roll back
> what you created (it's all in `state.env`) before restarting under a new one.

### 3.3 Instance role (least privilege) and profile

The role can read **only** the three secrets above, and run the SSM agent
(needed for Run Command). The SSM permissions are an **inline policy** rather
than the managed `AmazonSSMManagedInstanceCore`, because many IAM users may
create inline policies but are denied `iam:AttachRolePolicy`.

```bash
aws iam create-role --role-name passport-proxy-$NAME --tags Key=project,Value=passport --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
st ROLE passport-proxy-$NAME
aws iam put-role-policy --role-name passport-proxy-$NAME --policy-name passport-proxy-secrets --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"secretsmanager:GetSecretValue","Resource":"arn:aws:secretsmanager:'$AWS_REGION':'$ACCOUNT':secret:passport/'$NAME'/*"}]}'
aws iam put-role-policy --role-name passport-proxy-$NAME --policy-name passport-proxy-ssm --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ssm:UpdateInstanceInformation","ssm:ListInstanceAssociations","ssm:ListAssociations","ssm:GetDocument","ssm:DescribeDocument","ssm:GetParameters","ssm:PutComplianceItems","ssm:UpdateAssociationStatus","ssm:UpdateInstanceAssociationStatus","ssmmessages:CreateControlChannel","ssmmessages:CreateDataChannel","ssmmessages:OpenControlChannel","ssmmessages:OpenDataChannel","ec2messages:AcknowledgeMessage","ec2messages:DeleteMessage","ec2messages:FailMessage","ec2messages:GetEndpoint","ec2messages:GetMessages","ec2messages:SendReply"],"Resource":"*"}]}'
aws iam create-instance-profile --instance-profile-name passport-proxy-$NAME >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name passport-proxy-$NAME --role-name passport-proxy-$NAME
st PROFILE passport-proxy-$NAME
sleep 12      # IAM propagation; if run-instances later says the profile is invalid, wait and retry
```

### 3.4 CloudFront in front of the management port (HTTPS)

CloudFront exposes **only** `/ca.pem` and `/issue-cert`; every other path
(`/metrics`, `/readyz`, …) returns 404 from a viewer-request function. It can
be created before the instance exists (the origin is the EIP's DNS name).
Its ~3-minute deploy overlaps the instance boot.

```bash
cd /tmp/pp-aws
cp "$REPO/templates/cloudfront-404.js" .
cp "$REPO/templates/cloudfront-dist.json.tmpl" .
ETAG=$(aws cloudfront create-function --name passport-proxy-$NAME-404 --function-config Comment=passport-404,Runtime=cloudfront-js-2.0 \
  --function-code fileb://cloudfront-404.js --query ETag --output text); st CF_FUNCTION passport-proxy-$NAME-404
FN=$(aws cloudfront publish-function --name passport-proxy-$NAME-404 --if-match $ETAG --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
sed -e "s|__CALLER_REF__|passport-proxy-$NAME-$(date +%s)|" -e "s|__NAME__|$NAME|" -e "s|__HOSTNAME__|$PROXY_HOST|" -e "s|__FN_ARN__|$FN|" \
  cloudfront-dist.json.tmpl > cf-dist.json
read DIST CFDOMAIN < <(aws cloudfront create-distribution --distribution-config file://cf-dist.json --query 'Distribution.[Id,DomainName]' --output text)
st CF_DIST $DIST; st CF_DOMAIN $CFDOMAIN
aws cloudfront wait distribution-deployed --id $DIST          # ~3 min; fine to run after step 4.2 instead
```

> Verified 2026-10-06: `/ca.pem` → 200 (`CN=passport-proxy`), `/metrics` and
> `/readyz` → 404, empty `POST /issue-cert` → `csr is required`, and
> `passport setup --management-url https://$CF_DOMAIN` plus the 8.1 `curl`
> returned the expected sha256 with security group 8081 open only to CloudFront.

---

## 4. Render user-data and launch the instance

User-data does everything the AMI would have pre-baked: installs Docker, pulls
the images, starts Vault and the Proxy. It contains **no secrets** — only the
team ID, hostnames and secret *names*.

### 4.1 Render user-data

```bash
cd /tmp/pp-aws
ORG="<org_... from step 1.1>"
cp "$REPO/templates/user-data.tmpl" user-data.tmpl
sed -e "s|__REGION__|$AWS_REGION|" -e "s|__PREFIX__|passport/$NAME|" -e "s|__ORG__|$ORG|" -e "s|__SANS__|$PROXY_HOST,$EIP,localhost|" \
  user-data.tmpl > user-data.sh
grep -nE 'sk_|PRIVATE KEY' user-data.sh && echo "SECRET IN USER-DATA — STOP" || echo "user-data has no secrets"
```

> Symptom if the key files aren't world-readable: the proxy container restarts
> forever with `PASSPORT_PROXY_PRIVATE_KEY_PATH: open /opt/passport/ca.pem: permission denied`.
>
> `PASSPORT_PROXY_DATAPLANE_CERT_SANS` lists the names clients use for `:8443`.
> The CLI connects to `$EIP`/`$PROXY_HOST`, so both must be there (`localhost` is kept
> for the in-instance test traffic).
>
> `ca-bundle.crt` is the Amazon Linux 2023 path (verified). Appending the system
> bundle to the echo cert means the proxy trusts both the public CAs and the
> echo server, whether `SSL_CERT_FILE` adds to or replaces its roots.

### 4.2 Launch

```bash
I=$(aws ec2 run-instances --image-id $AMI --instance-type t3.small --subnet-id $SUBNET --security-group-ids $SG \
  --iam-instance-profile Name=passport-proxy-$NAME --associate-public-ip-address \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=2 \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true}' \
  --user-data file://user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=passport-proxy-$NAME},{Key=project,Value=passport}]" \
  --query 'Instances[0].InstanceId' --output text); st INSTANCE $I
aws ec2 wait instance-running --instance-ids $I
aws ec2 associate-address --instance-id $I --allocation-id $ALLOC >/dev/null
```

> `HttpPutResponseHopLimit=2` is deliberate: containers are one network hop
> behind the host, and the AWS CLI inside user-data runs on the host, so 1 would
> also work — but 2 lets you run `aws` inside a container if you ever need to.
> IMDSv2 stays required.

---

## 5. Verify the instance (read-only)

Boot takes ~2–4 minutes (package install + image pulls).

CloudFront only forwards `/ca.pem` and `/issue-cert`, so poll `/ca.pem` over HTTPS:

```bash
source /tmp/pp-aws/state.env; export AWS_PROFILE AWS_REGION
for i in $(seq 1 30); do
  c=$(curl -s -m 8 -o /tmp/pp-aws/proxy-ca.pem -w '%{http_code}' https://$CF_DOMAIN/ca.pem); [ "$c" = 200 ] && break; sleep 10
done
echo "ca.pem=$c"
for p in /metrics /readyz; do echo "$p -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' https://$CF_DOMAIN$p) (must be 404)"; done
curl -s -m 8 -X POST -H 'content-type: application/json' -d '{}' https://$CF_DOMAIN/issue-cert   # expect: csr is required
```

If it never reaches 200, read the boot log without SSH:

```bash
aws ec2 get-console-output --instance-id $INSTANCE --latest --query Output --output text | tail -40
# or, once SSM shows the instance as Online (the `onhost` helper from step 6.2):
#   onhost 'tail -60 /var/log/passport-bootstrap.log; docker ps -a; docker logs pp-proxy-local 2>&1 | tail -30'
```

Management/data-plane sanity (read-only; no cert needed):

```bash
openssl x509 -in /tmp/pp-aws/proxy-ca.pem -noout -subject
curl -s -m 10 -o /dev/null -D - --proxy https://$PROXY_HOST:8443 --proxy-insecure https://example.com/ | head -3   # expect 407 (client cert required)
```

---

## 6. Register the proxy and create a Namespace in Passport Cloud

You can do this in the web UI or through the API. The API path is below; the
UI path is:

- **Team Settings → Access Proxies → Create Access Proxy** with
  Proxy URL `https://<PROXY_HOST>:8443` (the `ec2-…` name, or the EIP), Management
  Host `https://<CF_DOMAIN>` (the CloudFront domain from 3.4), and Proxy public key = contents of
  `/tmp/pp-aws/reference-public-key.pem`.
- **Home → Create Namespace → Add Resources → Manual**: Method `GET`, Host
  `localhost` **(no port)**, Path `/echo`, Secret labelled `x-key`, vault type
  **HashiCorp**, vault key `test-key`.
- Grant yourself access to that endpoint.

> **Gotcha:** the proxy strips the port off the *request's* target host before
> matching, but does **not** strip the port off the endpoint's stored `host`.
> Register `host` as `localhost`, with no port — even though the request goes
> to `https://localhost:9443/echo`. Registering `localhost:9443` silently fails
> every request with `not authorized for vault refs`.
>
> **Second gotcha:** a secret reference's vault config is encrypted server-side
> under the public key of whichever proxy registration was active when you
> created it. If you re-register the proxy with a *new* keypair, old references
> become undecryptable (`failed to decrypt vault reference: <uuid>`). Create a
> fresh namespace/reference/endpoint/grant under the currently registered proxy.

### 6.1 Via the API (no web UI)

The web app is a front end for `https://api.usepassport.ai`; the CLI login
session's token authenticates the same calls. The token is read from
`passportrc` and never printed. `PASSPORT_DIR` is the CLI's credentials folder:
`~/.passport` normally, `~/passport-cli-dl/.passport` on the MDM path.

```bash
cp "$REPO/scripts/passport-api.js" /tmp/pp-aws/passport-api.js
```

```bash
source /tmp/pp-aws/state.env; cd /tmp/pp-aws
export PASSPORT_DIR=~/.passport            # MDM: ~/passport-cli-dl/.passport
api() { node /tmp/pp-aws/passport-api.js "$@"; }

api GET /api/v2/tenant/config | jq -c '.body.data[]|{proxyId,proxyEndpoint,isDefault}'   # existing registrations
```

> **Production care:** `isDefault:true` changes which proxy every developer's
> `passport setup` discovers and which key encrypts new references. If the team
> already has a proxy, tell the user and use `isDefault:false`. A registration
> with the same endpoint but a different `publicKey` is *stale* — don't reuse
> it; register a fresh one and leave the old one unless the user says to delete it.

```bash
# 6.1a register the proxy, then confirm the stored key matches your local one
jq -n --rawfile k reference-public-key.pem --arg n "passport-proxy-$NAME" --arg e "https://$PROXY_HOST:8443" --arg m "https://$CF_DOMAIN" \
  '{encryptionMode:"B",publicKey:$k,proxyName:$n,proxyEndpoint:$e,managementHostUrl:$m,isDefault:true}' > register-body.json
api POST /api/v2/tenant/config @register-body.json | tee register-out.json | jq -c '{status,proxyId:.body.data.proxyId}'
PROXY_ID=$(jq -r .body.data.proxyId register-out.json); st PROXY_ID $PROXY_ID
WANT=$(openssl pkey -pubin -in reference-public-key.pem -outform DER | openssl dgst -sha256 | awk '{print $NF}')
GOT=$(api GET /api/v2/tenant/config | jq -r --arg p "$PROXY_ID" '.body.data[]|select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$WANT" = "$GOT" ] && echo "key match" || echo "KEY MISMATCH"
```

The secret must exist in the instance's Vault **before** a request can resolve
it. Seed it (step 6.2), then create the Passport objects (6.3).

### 6.2 Seed the Vault on the instance (via SSM — no SSH, no open port)

The Vault is not published on any host port, so reach it with SSM Run Command.
Wait until the instance shows as online first.

```bash
source /tmp/pp-aws/state.env; export AWS_PROFILE AWS_REGION
for i in $(seq 1 20); do
  aws ssm describe-instance-information --filters Key=InstanceIds,Values=$INSTANCE \
    --query 'InstanceInformationList[0].PingStatus' --output text | grep -q Online && break; sleep 10
done

# run a shell snippet on the instance, print its output
onhost() {
  local id; id=$(aws ssm send-command --instance-ids $INSTANCE --document-name AWS-RunShellScript \
    --parameters "$(jq -nc --arg c "$1" '{commands:[$c]}')" --query Command.CommandId --output text)
  aws ssm wait command-executed --command-id $id --instance-id $INSTANCE 2>/dev/null
  aws ssm get-command-invocation --command-id $id --instance-id $INSTANCE --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
}

# Seed secret/test-key with a FAKE value; the token is read on the instance and never leaves it.
onhost 'set -a; . /opt/passport/vault.env; set +a
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN pp-vault-dev vault kv put secret/test-key value="some-local-test-value" | tail -4'
```

This lands at `secret/data/test-key` — the default path the proxy's HashiCorp
backend expects (`vaultKey` is relative to the `secret/` mount: `test-key`, not
`secret/data/test-key`). The Vault is in-memory dev mode: a **reboot of the
Vault container loses it** — re-run this step. Use a fake value for this test;
for anything real, run a properly initialised Vault.

### 6.3 Create the namespace, secret reference, endpoint and grant

```bash
source /tmp/pp-aws/state.env; cd /tmp/pp-aws; export PASSPORT_DIR=~/.passport    # MDM: ~/passport-cli-dl/.passport
api() { node /tmp/pp-aws/passport-api.js "$@"; }
PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const rc=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8"));console.log(JSON.parse(Buffer.from(rc.login._profiles[0].workos.accessToken.split(".")[1],"base64url")).sub)')
NS=$(api POST /api/v1/namespaces "$(jq -nc --arg n "passport-proxy-$NAME-e2e" '{name:$n,description:"Passport proxy e2e test"}')" | jq -r '.body.data.id')
REF=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"test-key"}')" | jq -r '.body.data.id')
EP=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" '{namespaceId:$ns,method:"GET",host:"localhost",path:"/echo",secrets:[{label:"x-key",secretReferenceId:$r}]}')" | jq -r '.body.data.id')
GR=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy aws e2e",validity:1}')" | jq -r '.body.data[0].id')
st NS $NS; st REF $REF; st EP $EP; st GR $GR; cat state.env | tail -4
```

Cleanup order (step 10) is: grant → endpoint → secret reference → namespace.

---

## 7. `passport setup`

```bash
source /tmp/pp-aws/state.env
passport setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443
```

On an MDM Mac use the MDM guide (A.4) instead — same flags.

> **Why CloudFront:** the CLI rejects a plain-HTTP management URL on a public
> address (`invalid management URL: expected an HTTPS origin (or http://localhost
> for local dev)…`). If you skipped 3.4, the fallback is a local TCP forwarder
> so the CLI sees `http://localhost:8081`: run
> `node -e "require('net').createServer(c=>{const u=require('net').connect(8081,'$EIP');c.pipe(u).pipe(c);c.on('error',()=>u.destroy());u.on('error',()=>c.destroy())}).listen(8081,'127.0.0.1')" &`
> (MDM Mac: inside `pp-cli-linux`), open 8081 to your own `/32` in the
> security group, and pass `--management-url http://localhost:8081`.

Sanity-check what got embedded in your issued cert:

```bash
passport whoami
```

It should show `allowedApiRefs` with `GET localhost/echo` and
`{{vault:<your secret reference's UUID>}}`.

---

## 8. Test it end to end

The echo server and the proxy trust were already set up by user-data (an echo
sidecar sharing the proxy's network namespace, so `localhost:9443` is exactly
`localhost` from the proxy's point of view — which is why the endpoint host
must be `localhost`).

```bash
source /tmp/pp-aws/state.env
passport request "https://localhost:9443/echo" -H "x-key: {{vault:$REF}}"
echo -n "some-local-test-value" | shasum -a 256          # must equal the sha256 in the response
```

On the instance, confirm the destination logged the same hash (it never
logs the value itself):

```bash
onhost 'docker logs pp-echo 2>&1 | tail -1'              # onhost is defined in step 6.2
```

> `{{vault:...}}` **must** contain the secret reference's UUID, not its
> friendly name — anything else streams through unsubstituted with no error.
> MDM Mac: run the request through `pp-cli-linux` (MDM guide, A.4).

If you see a sha256 (not the literal `{{vault:...}}`) and it matches, the
secret was resolved and injected by the proxy running **on EC2** — **a complete,
verified end-to-end setup.**

**Next, do step 8.1 right away** — it's the payoff of the whole setup.

### 8.1 The value of Passport: use a secret you never see

`passport request` is a thin wrapper. This plain `curl` does the same thing
(`D` is the CLI's credentials folder: `~/.passport`, or
`~/passport-cli-dl/.passport` on the MDM path; re-run `passport setup` first if
the ~5-minute cert has expired):

```bash
source /tmp/pp-aws/state.env
D=~/.passport                                    # MDM: ~/passport-cli-dl/.passport
curl -s https://$CF_DOMAIN/ca.pem -o /tmp/pp-aws/proxy-ca.pem

curl -sS --proxy https://$EIP:8443 \
  --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem \
  --cacert /tmp/pp-aws/proxy-ca.pem \
  -H "x-key: {{vault:$REF}}" \
  https://localhost:9443/echo
```

Output: `{"ok":true,"sha256":"a91317c5…a1f8"}`, the sha256 of the real secret
(`some-local-test-value`).

**How the secret was used without being seen**

1. **You only hold a pointer.** The header you sent is
   `x-key: {{vault:<uuid>}}`. The UUID names a secret; it isn't the secret.
   **Your machine, shell history and this guide never contain the value.**
2. **Your identity is a short-lived client cert.** `passport setup` issued
   `cert.pem` (about 5 min). It encodes *which* references you may use, on
   *which* method, host and path (`GET localhost/echo`). That's the grant from
   6.3. **Access is scoped to exactly what you were granted.**
3. **The proxy checks, then swaps.** It verifies your cert, confirms the
   request matches your grant, decrypts the reference to learn where the secret
   lives (`test-key` in the instance's Vault), fetches it, and replaces
   `{{vault:<uuid>}}` with the real value *in flight*, only for the allowed
   host and path. **The real value is injected by the proxy, never by you.**
4. **The destination gets the real value.** The echo server received it (its
   hash matches ours). **Your side saw only the UUID going out and the response
   coming back.**

**Result: you (or a script, or an AI agent) can call an API that needs a
credential without ever holding that credential.** **It can't be leaked from
your machine**, **it works only on endpoints you were granted**, and **access
ends when the cert or grant expires.**

---

## 9. Adding or changing an app secret later

Same path as 6.2 with a different key and value, then a Passport secret
reference with that `vaultKey`:

```bash
onhost 'set -a; . /opt/passport/vault.env; set +a
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN pp-vault-dev vault kv put secret/<vaultKey> value="<value>" | tail -3'
```

The proxy caches HashiCorp lookups (~60 s by default), so a changed value shows
up on the next request after that window. KV v2 versions writes — old values
are kept. Each new endpoint also needs a grant **and a fresh `passport setup`**
(the cert lists granted endpoints at issue time).

---

## 10. Cleanup (only after you confirm you're done testing)

**Don't run this until you've actually said you're done.** It deletes real AWS
resources and real objects in your Passport Cloud team. Show the list from
`state.env` and get one yes. Delete in this order; a failure on one step
shouldn't stop you reporting the rest.

```bash
source /tmp/pp-aws/state.env; export AWS_PROFILE AWS_REGION; export PASSPORT_DIR=~/.passport   # MDM: ~/passport-cli-dl/.passport
api() { node /tmp/pp-aws/passport-api.js "$@"; }

# 10.1 Passport Cloud (refresh the token first if needed: passport auth status)
api DELETE /api/v2/access-grants/$GR
api DELETE /api/v2/resource-endpoints/$EP
api DELETE /api/v2/secret-references/$REF      # 409 while an endpoint still maps it
api DELETE /api/v1/namespaces/$NS
api DELETE /api/v2/tenant/config/$PROXY_ID     # the proxy registration — the route takes the proxyId UUID, not a numeric id

# 10.2a CloudFront: disable -> wait deployed -> delete distribution -> delete function (several minutes)
CFG=$(aws cloudfront get-distribution-config --id $CF_DIST); ET=$(echo "$CFG" | jq -r .ETag)
echo "$CFG" | jq '.DistributionConfig|.Enabled=false' > /tmp/pp-aws/cf-disabled.json
aws cloudfront update-distribution --id $CF_DIST --if-match $ET --distribution-config file:///tmp/pp-aws/cf-disabled.json >/dev/null
aws cloudfront wait distribution-deployed --id $CF_DIST
aws cloudfront delete-distribution --id $CF_DIST --if-match $(aws cloudfront get-distribution --id $CF_DIST --query ETag --output text)
aws cloudfront delete-function --name $CF_FUNCTION --if-match $(aws cloudfront describe-function --name $CF_FUNCTION --query ETag --output text)

# 10.2 EC2: terminate (this permanently deletes the instance's Vault data), then release the EIP
aws ec2 terminate-instances --instance-ids $INSTANCE >/dev/null
aws ec2 wait instance-terminated --instance-ids $INSTANCE
aws ec2 release-address --allocation-id $ALLOC

# 10.3 IAM
aws iam remove-role-from-instance-profile --instance-profile-name $PROFILE --role-name $ROLE
aws iam delete-instance-profile --instance-profile-name $PROFILE
aws iam delete-role-policy --role-name $ROLE --policy-name passport-proxy-ssm
aws iam delete-role-policy --role-name $ROLE --policy-name passport-proxy-secrets
aws iam delete-role --role-name $ROLE

# 10.4 Security group (after the instance is gone)
aws ec2 delete-security-group --group-id $SG

# 10.5 Secrets: the proxy keys AND the registry key. Deleting the keys makes every secret reference made for
# this proxy undecryptable — fine here, since the registration is removed above. For a throwaway test use
# --force-delete-without-recovery: a recovery window (min 7 days) blocks re-creating the same name (step 3.2).
# For a real proxy use --recovery-window-in-days 7 instead.
for s in ca-key reference-key registry-key; do
  aws secretsmanager delete-secret --secret-id passport/$NAME/$s --force-delete-without-recovery --query Name --output text
done

# 10.6 Local files
rm -rf /tmp/pp-aws
```

MDM guide (`guides/reference/aws-mdm-macs.md`) users also run: `docker rm -f pp-cli-linux; rm -rf ~/passport-cli-dl; pkill -f cb-forward.js`.

If you wish to **keep** the keys (so a future proxy can reuse them and old
references keep working), skip 10.5 and the registration delete in 10.1, and
keep `/tmp/pp-aws/ca.pem` + `ref.pem` safe — they're recoverable from Secrets
Manager (`passport/$NAME/ca-key`, `reference-key`) anyway.

---


## Troubleshooting, MDM Macs, safety

- Troubleshooting table: `guides/reference/aws-troubleshooting.md`
- MDM-managed Macs (run the CLI in a Linux container): `guides/reference/aws-mdm-macs.md`

## Safety notes

- Never paste a real secret's raw value, your registry key, an AWS credential
  or a login token into chat, a commit, or a log you'll share — compare sha256
  hashes instead (as step 8 does).
- The Vault here is a disposable, in-memory **dev** server on a single
  instance — fine for this test, never for anything you care about keeping.
- 8443 is open **only** to your `/32`, and 8081 **only** to CloudFront's
  origin-facing prefix list. If your IP changes, update the 8443 rule; never
  widen either to `0.0.0.0/0`.
- This setup creates real AWS resources (instance, EIP, role, security group,
  secrets) that **cost money while they exist** and real objects in your
  Passport Cloud team — clean them up (step 10) once you're done, especially on
  a shared account.
