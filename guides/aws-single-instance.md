# Postman Passport proxy on AWS (single EC2 instance)

Deploys the **Passport Proxy on one EC2 instance** in your own AWS account,
using a stock **Amazon Linux 2023** image. The instance runs two Docker
containers: the **Passport Proxy** and a **HashiCorp Vault**, which is the only
secret backend in this setup. CloudFront gives the proxy's management port a
trusted HTTPS address. By the end you will have:

- the Passport CLI logged in, with a client certificate issued by your proxy,
  the Passport CA trusted, and (on macOS/Windows) the Passport daemon running;
- a real request that used a credential from Vault without you typing it into
  the request;
- a worked example of adding your own API.

> **⚠️ This is a demo setup, not for production.** It's for evaluating Passport:
> - **The proxy runs on one EC2 instance** (`t3.small`). There's no load
>   balancer, no redundancy and no backups. If the instance is terminated or
>   replaced, its keys are gone and every secret reference for it stops working.
> - **The secrets live in a HashiCorp Vault on that same instance,** running in
>   **dev mode, in memory**. Restarting the Vault container, or rebooting the
>   instance, erases every stored secret. Store only test or low-risk
>   credentials here.
>
> For production, run the proxy with redundancy and a durable, managed secret
> store. This guide doesn't cover that.

> **Status: this version has not yet completed a full run on EC2.** What has
> been verified, and where, is in `guides/reference/verification.md`. Treat any
> step that fails as a bug in this guide and fix the guide.

## Where things live (read this once)

| What | Where | Lifetime |
|---|---|---|
| **Proxy bootstrap keys**: `ca.pem` signs client certificates; `ref.pem` decrypts secret references | On the instance's disk, `/opt/passport/keys/`, generated at first boot | Survive container restarts and reboots. **Lost if the instance is terminated or replaced**, and every secret reference registered for this proxy then stops working |
| **Reference public key** | `/opt/passport/reference-public-key.pem`, registered with Passport Cloud | The only key material that leaves the instance |
| **API credentials** (the secrets your requests use) | The **HashiCorp Vault** container on the instance, at `secret/<vault-key>` | **The Vault runs in dev mode, in memory. Restarting its container, or rebooting, erases every API credential.** Re-store them with `passport-vault-put` |
| **Registry key** (pulls the proxy image) | You type it into `sudo docker login` in your own terminal; it's logged out right after the pull | Never in user-data, SSM parameters, chat, or this repo |
| **Your client certificate** | Your machine, `~/.passport/` (`cert.pem`, `key.pem`, `ca.pem`) | Short-lived; renewed by the daemon (`guides/reference/concepts.md`, "Client certificates") |

Nothing in this setup uses AWS Secrets Manager.

---

## Rules for an AI coding agent running this guide

The ground rules in `AGENTS.md` apply. This section adds only what is specific
to AWS.

**Before step 1, tell the user what this setup is**, in a few lines: it's a
**demo, not for production**; it starts the Passport proxy on **one EC2
instance**; and it starts a **HashiCorp Vault in dev mode on that instance**,
where their secrets are stored **in memory** (lost on a Vault restart or a
reboot). Use the warning at the top of this guide. Say it again before they
store a real credential (`guides/after-setup.md`, part 2).

Follow this guide literally and **do every step yourself**, except the steps
marked **[you]**, which need the human. `$REPO` means the absolute path of this
repository (the folder containing `AGENTS.md`). Start every command block with:

```bash
REPO=<absolute path of this repo>; . "$REPO/scripts/env.sh"
```

`scripts/env.sh` loads the manifest `/tmp/pp-aws/state.env` and defines four
helpers:
- `st`: record a value. It refuses empty, `None` and `null`, so a failed call
  can't record a bad ID.
- `api`: call Passport Cloud. A failed call also prints
  `api: <method> <path> -> <status> …` to stderr.
- `cli`: the Passport CLI. On an MDM-managed Mac (`MDM=1`, step 1) it runs in
  the Linux container.
- `onhost`: run a command on the instance. It prints the remote stderr and
  fails when the remote command fails.

**AWS changes need explicit approval, and the approval names every resource.**
Before any create or delete, show an **approval block**:
- a table with one row per resource: action (CREATE or DELETE), type, exact
  name, ID (or "assigned on create"), account, region and cost note;
- the complete commands that will run.

Ask once per block. Then:

- **A "yes", "go ahead" or "do it" approves exactly that block.** Don't ask again,
  and don't reply with "I'll proceed". **Run it, verify it, and report the
  results** in the same turn.
- **Record every created ID immediately.** Run `st` right after each create
  command, before the next command runs.
- **Never create anything outside the approved table.**
- **Never delete anything unconfirmed.** It must be in `state.env` or
  `resources.env`, **and** be confirmed by
  `bash "$REPO/scripts/aws-resources.sh" delete /tmp/pp-aws/state.env`. That
  script prints `STOP` if a recorded ID isn't tagged as ours. If it does, delete
  nothing and ask.
- **Passport Cloud API and CLI calls need no approval block** (`AGENTS.md`):
  run them, record the IDs with `st`, and say what you created. Step 6 makes
  your proxy the team default only while it creates the reference, then
  restores the previous default, even if the block fails partway. Tell the user
  you did.

**Long waits.** `aws cloudfront wait distribution-deployed` (steps 5 and 10)
and `aws ec2 wait instance-terminated` (step 10) can take 3–15 minutes. If your
command tool has a time limit, give these commands a longer timeout or run them
in the background and check back. A tool timeout is not an AWS failure: re-run
only the wait.

**Success is the checklist in step 8.4,** reported line by line. If the
explicit `curl` works but `setup` exited 2, the daemon isn't running, or the CA
isn't trusted, say exactly that: *"requests work with explicit flags; the
CLI/daemon setup is not complete: …"*.

**After step 8.4:** continue with `guides/after-setup.md`: the handoff, then
their own API. Never run cleanup (step 10) until the user explicitly asks for
it.

**MDM-managed Mac:** step 1 checks for it. If a sign shows up later anyway
(`guides/reference/mdm-macs.md`, "How to tell"), stop and switch then, using
that file's "Found MDM after AWS step 3" if the instance already exists.

---

## 1. Discover (read-only, no questions yet)

```bash
mkdir -p /tmp/pp-aws; REPO=<repo>; . "$REPO/scripts/env.sh"
echo "--- tools"; for t in aws session-manager-plugin passport docker node jq openssl; do printf '%-24s %s\n' "$t" "$(command -v $t >/dev/null && ($t --version 2>/dev/null | head -1) || echo MISSING)"; done
echo "--- aws profiles"; for p in $(aws configure list-profiles 2>/dev/null); do printf '%-20s region=%-12s %s\n' "$p" "$(aws configure get region --profile $p)" "$(aws sts get-caller-identity --profile $p --query Arn --output text 2>&1 | tail -1 | cut -c1-90)"; done
echo "--- passport"; passport --version 2>/dev/null; passport auth status 2>&1 | grep -E 'org|expires|not logged'
echo "--- mdm signs"; passport daemon status 2>&1 | grep -E 'routing source' || echo "(no host daemon running: no sign either way)"
echo "--- manifest"; cat /tmp/pp-aws/state.env 2>/dev/null
```

From this output, decide without asking where you can:
- **Profile:** the profile with a working session. If more than one works, ask which.
- **Region:** that profile's configured region.
- **Existing deployment:** if `/tmp/pp-aws/state.env` has a `NAME`, run
  `bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env` and resume
  from there instead of creating a new one.
- **MDM-managed Mac:** `routing source managed` above, or any other sign in
  `guides/reference/mdm-macs.md` ("How to tell"). Decide this now, before
  anything reads the team ID: the instance is built for that team in step 3.
  Record it with `st MDM 1; st PASSPORT_DIR ~/passport-cli-dl/.passport`, and
  in 1.1 do `mdm-macs.md` A.1–A.3 instead of the host login. From then on,
  `cli` and `api` use the container's login.

Then go through 1.1–1.4 and do only what's missing.

### 1.1 Passport CLI ([you] for the install and the browser approval)

You need **version 0.6.0 or later**.

**macOS** (needs `sudo`, so it runs in the user's terminal):

```bash
curl -fL -o ~/Downloads/passport.pkg "https://dl-passport.pstmn.io/download/version/0.6.0-canary-260921-212749/osx_$([ "$(uname -m)" = arm64 ] && echo arm64 || echo 64)?channel=canary"
sudo installer -pkg ~/Downloads/passport.pkg -target /
```

**Windows (PowerShell, as administrator):**

```powershell
curl.exe -fL -o $env:USERPROFILE\Downloads\passport.msi "https://dl-passport.pstmn.io/download/version/0.6.0-canary-260921-212749/win_64?channel=canary"
msiexec /i $env:USERPROFILE\Downloads\passport.msi /quiet
```

If either URL returns 404, the pinned build has rotated off the server. Get the
current link from the **Set up Passport** guide in your Passport team (account
menu → How-to).

**Log in:**
- **Run it:** the agent runs `passport login` and shows the printed URL and
  confirmation code on their own line, as a full `https://` link. The user
  approves it in their browser.
- **No team:** if login says `authenticated login session has no organization`,
  the user must create a team at <https://app.usepassport.ai/dashboard>, then
  run `passport login` again. Retrying login won't offer to create one.
- **MDM Mac (`MDM=1`):** log in inside the container instead
  (`guides/reference/mdm-macs.md`, A.1–A.3).
- **Team ID:** the `org_…` value on the `org` line of `cli auth status`.

### 1.2 AWS CLI v2 and the Session Manager plugin ([you], needs `sudo`)

The plugin is required. Step 5 opens an interactive session on the instance,
and that session is the only way the registry key reaches the instance.

**macOS:**

```bash
# AWS CLI v2 (official installer). Skip if `aws --version` already shows aws-cli/2.x
curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg && sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
# Session Manager plugin (official package)
ARCH=$([ "$(uname -m)" = arm64 ] && echo mac_arm64 || echo mac)
curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/$ARCH/session-manager-plugin.pkg" -o /tmp/session-manager-plugin.pkg
sudo installer -pkg /tmp/session-manager-plugin.pkg -target /
sudo ln -sf /usr/local/sessionmanagerplugin/bin/session-manager-plugin /usr/local/bin/session-manager-plugin
session-manager-plugin --version
```

**Windows:** install `https://awscli.amazonaws.com/AWSCLIV2.msi` and
`https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe`.

**Linux and other details:** see the official AWS documentation pages
"Installing or updating the latest version of the AWS CLI" and "Install the
Session Manager plugin for the AWS CLI".

### 1.3 AWS sign-in (prefer browser-based, short-lived credentials)

Use the first option that applies. The user runs it in **their** terminal, and
each option opens a browser:

1. **IAM Identity Center (SSO)**, if the organisation has it:
   ```bash
   aws configure sso --profile passport        # once: SSO start URL, region, account, role
   aws sso login --profile passport            # whenever the session expires
   ```
2. **Console sign-in (AWS CLI 2.32 and later):** `aws login --profile passport`
   reuses your AWS console login. *Unverified here:* the CLI tested was 2.31.
3. **Long-lived access keys:** a last resort, and only for an IAM user, never
   root. Run `aws configure --profile passport` in the user's terminal. Never
   paste keys into chat.

Check it with `aws sts get-caller-identity --profile passport`.

### 1.4 Permissions

`templates/operator-iam-policy.json` is the complete policy for the identity
that runs this guide:
- **What it allows:** every action the commands below use, nothing else.
- **Deletes:** only on resources tagged `project=passport`.
- **SSM sessions and Run Command:** only on instances tagged `project=passport`,
  not every instance in the account.
- **Tags:** only while creating a resource, so the identity can't tag an existing
  resource `project=passport` to get around the two limits above.
- **IAM actions:** only on roles and instance profiles named `passport-proxy-*`.

It's over the 2,048-character limit for an inline user policy, so create it as
a managed policy. An administrator attaches it to the permission set, role or
user. For a sandbox account, `PowerUserAccess` plus the policy's IAM statements
also works.

If an action is still denied, the guide stops and names the action. Fix the
policy file in this repo, not just the account.

---

## 2. Preflight (read-only) and the plan

```bash
REPO=<repo>; export AWS_PROFILE=<profile> AWS_REGION=<region>; . "$REPO/scripts/env.sh"
bash "$REPO/scripts/preflight.sh" | tee /tmp/pp-aws/preflight.txt
```

It checks:
- the local tools and the Session Manager plugin;
- the AWS session;
- a public subnet and the AMI;
- a `RunInstances` dry run;
- CloudFront access;
- simulated permissions.

It also picks a **collision-free name**: every resource will be called
`passport-proxy-<name>`. At the end it prints what it found as
machine-readable lines (`PREFLIGHT_NAME=`, `PREFLIGHT_VPC=`,
`PREFLIGHT_SUBNET=`, `PREFLIGHT_AMI=`, `PREFLIGHT_CF_PL=`,
`PREFLIGHT_CLIENT_CIDR=`), which the next block records.

Fix every ❌ before going on. Then record the inputs:

```bash
REPO=<repo>; export AWS_PROFILE=<profile> AWS_REGION=<region>; . "$REPO/scripts/env.sh"
pf() { sed -n "s/^PREFLIGHT_$1=//p" /tmp/pp-aws/preflight.txt; }
st AWS_PROFILE "$AWS_PROFILE"; st AWS_REGION "$AWS_REGION"
st NAME "$(pf NAME)"; st VPC "$(pf VPC)"; st SUBNET "$(pf SUBNET)"; st AMI "$(pf AMI)"; st CF_PL "$(pf CF_PL)"; st CLIENT_CIDR "$(pf CLIENT_CIDR)"
st ACCOUNT "$(aws sts get-caller-identity --query Account --output text)"
st ORG "$(cli auth status | awk '$1=="org"{print $2}')"          # on an MDM Mac, cli is the container's CLI (step 1)
cat /tmp/pp-aws/state.env
```

---

## 3. Approval block A: create the AWS resources

Show the user this table with real values, plus the full command block below,
and ask once. Nothing exists until they say yes.

| Action | Type | Name | ID | Notes |
|---|---|---|---|---|
| CREATE | Security group | `passport-proxy-<NAME>` | assigned on create | In `<VPC>`. Inbound **8443 from `<CLIENT_CIDR>` only**; **8081 from CloudFront (`<CF_PL>`) only** |
| CREATE | Elastic IP | `passport-proxy-<NAME>` | assigned on create | About $3.60/month |
| CREATE | IAM role | `passport-proxy-<NAME>` | n/a | Lets the instance run the SSM agent. **No access to any secret** |
| CREATE | IAM instance profile | `passport-proxy-<NAME>` | n/a | Wraps the role |
| CREATE | CloudFront function | `passport-proxy-<NAME>-404` | n/a | Returns 404 for everything except `/ca.pem` and `/issue-cert` |
| CREATE | CloudFront distribution | "Passport proxy `<NAME>` management" | assigned on create | HTTPS front door for port 8081, `PriceClass_100` |
| CREATE | EC2 instance (+ its root volume) | `passport-proxy-<NAME>` | assigned on create | `t3.small`, `<AMI>` (Amazon Linux 2023), `<SUBNET>`, 20 GB encrypted gp3, IMDSv2 only. About $15/month |

Everything is in account `<ACCOUNT>`, region `<AWS_REGION>`, tagged
`project=passport`. Nothing else is created.

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"; set -e; cd /tmp/pp-aws
N=passport-proxy-$NAME; TAGS="{Key=Name,Value=$N},{Key=project,Value=passport}"

# A1 security group
st SG "$(aws ec2 create-security-group --group-name $N --description "Passport proxy $NAME" --vpc-id $VPC \
  --tag-specifications "ResourceType=security-group,Tags=[$TAGS]" --query GroupId --output text)"
aws ec2 authorize-security-group-ingress --group-id $SG --ip-permissions \
  "IpProtocol=tcp,FromPort=8443,ToPort=8443,IpRanges=[{CidrIp=$CLIENT_CIDR,Description=passport-data-plane}]" \
  "IpProtocol=tcp,FromPort=8081,ToPort=8081,PrefixListIds=[{PrefixListId=$CF_PL,Description=passport-mgmt-via-cloudfront}]" >/dev/null

# A2 Elastic IP (its DNS name goes into the proxy cert and the CloudFront origin)
read -r A E < <(aws ec2 allocate-address --domain vpc --tag-specifications "ResourceType=elastic-ip,Tags=[$TAGS]" \
  --query '[AllocationId,PublicIp]' --output text); st ALLOC "$A"; st EIP "$E"
if [ "$AWS_REGION" = us-east-1 ]; then st PROXY_HOST "ec2-${EIP//./-}.compute-1.amazonaws.com"
else st PROXY_HOST "ec2-${EIP//./-}.$AWS_REGION.compute.amazonaws.com"; fi

# A3 instance role (SSM agent only) + instance profile
aws iam create-role --role-name $N --tags Key=project,Value=passport --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
st ROLE $N
aws iam put-role-policy --role-name $N --policy-name passport-proxy-ssm --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ssm:UpdateInstanceInformation","ssm:ListInstanceAssociations","ssm:ListAssociations","ssm:GetDocument","ssm:DescribeDocument","ssm:GetParameters","ssm:PutComplianceItems","ssm:UpdateAssociationStatus","ssm:UpdateInstanceAssociationStatus","ssmmessages:CreateControlChannel","ssmmessages:CreateDataChannel","ssmmessages:OpenControlChannel","ssmmessages:OpenDataChannel","ec2messages:AcknowledgeMessage","ec2messages:DeleteMessage","ec2messages:FailMessage","ec2messages:GetEndpoint","ec2messages:GetMessages","ec2messages:SendReply"],"Resource":"*"}]}'
aws iam create-instance-profile --instance-profile-name $N >/dev/null; st PROFILE $N
aws iam add-role-to-instance-profile --instance-profile-name $N --role-name $N

# A4 CloudFront function + distribution (its ~3-minute deploy overlaps the boot)
ETAG=$(aws cloudfront create-function --name $N-404 --function-config Comment=passport-404,Runtime=cloudfront-js-2.0 \
  --function-code "fileb://$REPO/templates/cloudfront-404.js" --query ETag --output text); st CF_FUNCTION $N-404
FN=$(aws cloudfront publish-function --name $N-404 --if-match $ETAG --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text)
sed -e "s|__CALLER_REF__|$N-$(date +%s)|" -e "s|__NAME__|$NAME|" -e "s|__HOSTNAME__|$PROXY_HOST|" -e "s|__FN_ARN__|$FN|" \
  "$REPO/templates/cloudfront-dist.json.tmpl" > cf-dist.json
read -r D DOM < <(aws cloudfront create-distribution --distribution-config file://cf-dist.json --query 'Distribution.[Id,DomainName]' --output text)
st CF_DIST "$D"; st CF_DOMAIN "$DOM"

# A5 instance. User-data holds NO secrets, only the team ID and hostnames (checked below).
sed -e "s|__ORG__|$ORG|" -e "s|__SANS__|$PROXY_HOST,$EIP|" "$REPO/templates/user-data.tmpl" > user-data.sh
! grep -qE 'sk_|PRIVATE KEY|VAULT_TOKEN=[0-9a-f]' user-data.sh || { echo "SECRET IN USER-DATA — STOP"; exit 1; }
# A new instance profile takes a few seconds to reach EC2. Retry only that error (no instance is created
# when it happens), for up to a minute; stop on any other error.
for i in 1 2 3 4 5 6; do
  OUT=$(aws ec2 run-instances --image-id $AMI --instance-type t3.small --subnet-id $SUBNET --security-group-ids $SG \
    --iam-instance-profile Name=$N --associate-public-ip-address \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=2 \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true}' \
    --user-data file://user-data.sh --tag-specifications "ResourceType=instance,Tags=[$TAGS]" "ResourceType=volume,Tags=[$TAGS]" \
    --query 'Instances[0].InstanceId' --output text 2>&1) && break
  case "$OUT" in *iamInstanceProfile*|*"Invalid IAM Instance Profile"*) echo "waiting for the instance profile ($i/6)"; sleep 10;; *) break;; esac
done
case "$OUT" in i-*) st INSTANCE "$OUT";; *) echo "run-instances failed: $OUT"; exit 1;; esac
aws ec2 wait instance-running --instance-ids $INSTANCE
aws ec2 associate-address --instance-id $INSTANCE --allocation-id $ALLOC >/dev/null
bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env
```

**If a command fails halfway:**
- **What happens:** `set -e` stops the block, and everything created so far is
  already recorded in `state.env`.
- **What to tell the user:** show `aws-resources.sh show` and explain the error.
- **IAM propagation** (`run-instances failed: … iamInstanceProfile.name is
  invalid` after A5's own retries): wait a little and re-run only A5.
- **Anything else:** roll back what was created (step 10, with approval), then retry.

Never re-run the whole block, because that creates duplicates.

---

## 4. Wait for the instance (read-only)

First boot installs Docker and starts Vault, which takes about 2 minutes. The
proxy isn't running yet, because it needs your registry login (step 5).

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
ONLINE=
for i in $(seq 1 30); do
  [ "$(aws ssm describe-instance-information --filters Key=InstanceIds,Values=$INSTANCE \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)" = Online ] && { ONLINE=1; break; }; sleep 10; done
[ -n "$ONLINE" ] || { echo "instance $INSTANCE not Online in SSM after 5 minutes (see troubleshooting.md, 'AWS: instance and proxy')"; exit 1; }
onhost 'tail -2 /var/log/passport-bootstrap.log; docker ps --format "{{.Names}} {{.Status}}"'
```

Expect `passport-bootstrap: done …` and `pp-vault-dev Up …`.

Then fetch the reference **public** key and record its fingerprint. It's public,
so it's safe to pass through SSM output:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
onhost 'cat /opt/passport/reference-public-key.pem' > /tmp/pp-aws/reference-public-key.pem
grep -q 'BEGIN PUBLIC KEY' /tmp/pp-aws/reference-public-key.pem && \
  st REF_KEY_SHA256 "$(openssl pkey -pubin -in /tmp/pp-aws/reference-public-key.pem -outform DER | openssl dgst -sha256 | awk '{print $NF}')"
```

---

## 5. [you] Log in to the registry and start the proxy (interactive session)

The registry key must never pass through the agent, user-data or SSM Run
Command, so **the user types it into their own terminal**. Give them this block
with the real values filled in:

```bash
aws ssm start-session --target <INSTANCE> --region <AWS_REGION> --profile <AWS_PROFILE>
# — now on the instance —
sudo docker login ociregistry.usepassport.ai --username passport   # paste the registry key at the Password: prompt (hidden)
sudo passport-start-proxy                                          # pulls the image, logs out of the registry, starts the proxy
exit
```

- **No registry key yet?** Create one at
  <https://app.usepassport.ai/org/registry> (Org Settings → Registry; needs
  admin), or ask the team admin.
- **Expected output:** `pp-proxy-local Up …` and `readyz=200`.
- **The key doesn't stay on the instance:** `passport-start-proxy` runs
  `docker logout` right after the pull.

When the user says done, verify it yourself:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
onhost 'docker ps --format "{{.Names}} {{.Status}}"; curl -s -o /dev/null -w "readyz=%{http_code}\n" http://localhost:8081/readyz'
aws cloudfront wait distribution-deployed --id $CF_DIST       # usually done by now; can take minutes ("Long waits")
curl -s -m 10 -o /tmp/pp-aws/proxy-ca.pem -w "ca.pem via CloudFront=%{http_code}\n" https://$CF_DOMAIN/ca.pem
openssl x509 -in /tmp/pp-aws/proxy-ca.pem -noout -subject                 # CN=passport-proxy
for p in /metrics /readyz; do echo "$p -> $(curl -s -m 8 -o /dev/null -w '%{http_code}' https://$CF_DOMAIN$p) (must be 404)"; done
curl -s -m 10 -o /dev/null -D - --proxy https://$PROXY_HOST:8443 --proxy-insecure https://example.com/ | head -1   # 407 = needs a client cert
```

---

## 6. Passport Cloud: register the proxy and create the demo (agent runs it, no approval needed)

First list what exists:
`api GET /api/v2/tenant/config | jq -c '.body.data[]|{proxyId,proxyName,isDefault}'`.
Then run the block below without asking. Afterwards, tell the user what was
created, using this table with the real IDs:

| Action | Object | Name / value |
|---|---|---|
| CREATE | Proxy registration | `passport-proxy-<NAME>`, endpoint `https://<PROXY_HOST>:8443`, management `https://<CF_DOMAIN>`, key sha256 `<REF_KEY_SHA256>`. Made the team default **only while the reference is created**; the previous default (if any) is restored right after, or as soon as the block fails |
| CREATE | Namespace | `passport-proxy-<NAME>-e2e` |
| CREATE | Resource group | `passport-demo.mock.postman.postman.dev` (`source: manual`), so the endpoint shows in the web UI |
| CREATE | Secret reference | `demo` → HashiCorp Vault key `demo-api-key` |
| CREATE | Resource endpoint | `GET passport-demo.mock.postman.postman.dev /`, credential slot `x-demo-api-key` |
| CREATE | Access grant | you, on that endpoint, for 1 day |
| WRITE | Vault entry on the instance | `secret/demo-api-key` = the demo API's **known sample key** `sdfdsfdsfsdfdfsdfds` |

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"; cd /tmp/pp-aws
# No `set -e` here: each step ends in `|| die`, which hands the team's default back before stopping.
# (A trap can't do this reliably: zsh skips EXIT traps when `set -e` fires inside a function.)
restore_default() {
  [ -n "${PREV_DEFAULT:-}" ] && [ "$PREV_DEFAULT" != "${PROXY_ID:-}" ] || return 0
  api PUT /api/v2/tenant/config/$PREV_DEFAULT '{"isDefault":true}' >/dev/null && echo "restored the team's default proxy ($PREV_DEFAULT)" \
    || echo "WARNING: our proxy is still the team default. Restore it: api PUT /api/v2/tenant/config/$PREV_DEFAULT '{\"isDefault\":true}'" >&2
}
die() { echo "STOPPED at: $*" >&2; restore_default; exit 1; }
CUR=$(api GET /api/v2/tenant/config | jq -r '[.body.data[]|select(.isDefault==true)][0].proxyId // empty') || die "list proxy registrations"
[ -n "$CUR" ] && [ "$CUR" != "${PROXY_ID:-}" ] && st PREV_DEFAULT "$CUR"      # the team's default before us

# Register as the default (references are encrypted for the default). On a re-run, skip what's recorded.
if [ -z "${PROXY_ID:-}" ]; then
  jq -n --rawfile k reference-public-key.pem --arg n "passport-proxy-$NAME" --arg e "https://$PROXY_HOST:8443" --arg m "https://$CF_DOMAIN" \
    '{encryptionMode:"B",publicKey:$k,proxyName:$n,proxyEndpoint:$e,managementHostUrl:$m,isDefault:true}' > register-body.json
  st PROXY_ID "$(api POST /api/v2/tenant/config @register-body.json | jq -r .body.data.proxyId)" || die "register the proxy"
elif [ -z "${REF:-}" ]; then
  api PUT /api/v2/tenant/config/$PROXY_ID '{"isDefault":true}' >/dev/null || die "make our proxy the default again"
fi
GOT=$(api GET /api/v2/tenant/config | jq -r --arg p "$PROXY_ID" '.body.data[]|select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$GOT" = "$REF_KEY_SHA256" ] && echo "registered key matches the instance's key" || die "KEY MISMATCH"

# Demo credential: the demo API's publicly known sample key, so passing it via Run Command is fine.
# Real credentials only go in through a hidden prompt (guides/after-setup.md, part 2).
onhost '. /opt/passport/vault.env; docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN pp-vault-dev vault kv put secret/demo-api-key value=sdfdsfdsfsdfdfsdfds >/dev/null && echo stored' || die "store the demo key in Vault"

PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)') || die "read your user ID"
[ -n "${NS:-}" ]  || st NS  "$(api POST /api/v1/namespaces "$(jq -nc --arg n "passport-proxy-$NAME-e2e" '{name:$n,description:"Passport proxy e2e demo"}')" | jq -r .body.data.id)" || die namespace
[ -n "${RG:-}" ]  || st RG  "$(api POST /api/v1/namespaces/$NS/resource-groups '{"name":"passport-demo.mock.postman.postman.dev","description":"Passport proxy e2e demo","source":"manual"}' | jq -r .body.data.id)" || die "resource group"
[ -n "${REF:-}" ] || st REF "$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"demo-api-key"}')" | jq -r .body.data.id)" || die "secret reference"
restore_default      # the reference's key is fixed now; nothing below depends on the default
[ -n "${EP:-}" ]  || st EP  "$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" --arg g "$RG" '{namespaceId:$ns,method:"GET",host:"passport-demo.mock.postman.postman.dev",path:"/",secrets:[{label:"x-demo-api-key",secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -r .body.data.id)" || die endpoint
[ -n "${GR:-}" ]  || st GR  "$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy e2e",validity:1}')" | jq -r '.body.data[0].id')" || die "access grant"
grep -E '^(PROXY_ID|NS|RG|REF|EP|GR|PREV_DEFAULT)=' state.env
```

- **Why the default switch:** Passport encrypts each new secret reference for
  the team's *default* proxy, fixed at creation. So the block makes yours the
  default, creates the reference, and hands the default back straight away. If
  the team had no default, yours stays the default. Details:
  `guides/reference/concepts.md`, "Secret references are encrypted for the
  team's default proxy".
- **If it stops** (`STOPPED at: …`, usually after an `api: … -> 401` line):
  run `cli auth status` (it refreshes the login token), then **re-run the whole
  block**. It skips everything already recorded, so it never registers a
  second proxy or creates duplicates.
- **Rules it follows** (`concepts.md`, "Endpoints"): the endpoint host has no
  port, and a resource group makes the endpoint show in the web UI.

---

## 7. Issue your certificate, trust the CA, start the daemon

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
cli setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443 ${MDM:+--no-daemon}; echo "setup exit=$?"
```

What the exit code means:
- **`0`:** credentials issued **and** the daemon and environment are configured.
- **`2`:** **partial.** Credentials are OK, but the daemon or environment step
  failed (read the output). Setup is **not** complete.
- **`1`:** failed.

On success, setup prints `[5/5] daemon installed + HTTPS_PROXY set` (not on an
MDM Mac, where `--no-daemon` skips that part).

**[you] Trust the Passport CA** (needs `sudo` or admin, so it runs in the
user's terminal; not applicable on an MDM Mac). What it changes, and how to
undo it: `guides/reference/concepts.md`, "Trusting the Passport CA".

```bash
passport ca install
```

### 7.1 Validate trust with the SSL policy

On macOS, `passport ca status` checks only that the CA is *present*, so also
verify it against the SSL policy that `ca install` set:

```bash
passport ca status
security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain   # macOS: expect "certificate verification successful"
openssl x509 -in ~/.passport/ca.pem -noout -fingerprint -sha256                           # should match the sha256 that 'ca status' shows
```

---

## 8. Verify everything (each item separately)

### 8.1 Your identity

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
cli whoami
```

Expect your `teamId`, `allowedApiRefs` with
`GET passport-demo.mock.postman.postman.dev/ → {{vault:<REF>}}`, and a
`notAfter` time. Report the real `notAfter`: the proxy may issue less than the
hour the CLI asks for (earlier runs got about 5 minutes). Renewal:
`concepts.md`, "Client certificates: lifetime and renewal".

### 8.2 Call the demo API through Passport

The demo API echoes the first 5 characters and the length of the key it
received, so the response shows whether Passport injected the real key:

| The API received | Response |
|---|---|
| the real key (Passport injected it) | `"key":"sdfds**************","key_length":19` |
| the pointer, unchanged (no injection) | `"key":"{{vau*****…","key_length":46` |

**Explicit form** (needs no daemon; works on every platform; what each flag
does: `concepts.md`, "Two ways to send a request"):

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"; D=$PASSPORT_DIR
R=$(curl -sS --proxy https://$PROXY_HOST:8443 \
  --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem \
  --cacert /tmp/pp-aws/proxy-ca.pem \
  -H "x-demo-api-key: {{vault:$REF}}" \
  https://passport-demo.mock.postman.postman.dev); echo "$R"
echo "$R" | jq -e '(.key // "")|startswith("sdfds")' >/dev/null 2>&1 && [ "$(echo "$R" | jq .key_length)" = 19 ] \
  && echo "INJECTED: the API received the real key" || echo "NOT injected (see the table above)"
```

**Daemon form** (macOS/Windows after step 7, in a **new** terminal; no proxy or
cert flags; on an MDM Mac it needs the `mdm-macs.md` A.5 daemon):

```bash
curl -sS -H "x-demo-api-key: {{vault:<REF>}}" https://passport-demo.mock.postman.postman.dev
```

`{{vault:…}}` takes the reference's **UUID**, not its name; a name passes
through unchanged, with no error.

### 8.3 Daemon status and environment

```bash
passport daemon status        # pid, port (default 10144), upstream reachable, cert expiry. MDM: the pp-daemon command in mdm-macs.md A.5
echo "$HTTPS_PROXY"           # http://127.0.0.1:10144 — in a NEW terminal window after setup
```

- **The terminal you ran setup in doesn't see the variables yet.** Quit the
  terminal app completely and reopen it, or paste the `export …` lines setup
  printed.
- **Linux:** setup can't install the daemon. Run `passport daemon start` and
  export the variables yourself.
- **Hosts the daemon never routes** (`NO_PROXY`), the rc-file option and the
  per-platform variables: `concepts.md`, "Two ways to send a request". The
  demo API isn't in `NO_PROXY`, so the daemon form works for it.

### 8.4 Success checklist (report each line as ✅ or ❌)

1. `setup` exited `0`. An exit of `2` means the daemon or environment step
   failed, so this line is ❌ even if the rest pass.
2. `whoami` shows the `GET passport-demo.mock.postman.postman.dev/` grant and a future `notAfter`.
3. `passport ca status` says trusted, **and** `security verify-cert … -p ssl`
   succeeds (macOS). MDM Mac: "not applicable (MDM container path)".
4. `passport daemon status` shows it running with the upstream reachable
   (macOS/Windows; on Linux, after `daemon start`). MDM Mac: the A.5 daemon's
   status, or "not applicable" without it.
5. The 8.2 explicit request printed `INJECTED`.
6. The 8.2 daemon-form request shows `"key_length":19` (macOS/Windows; MDM Mac
   with the A.5 daemon).

**All ✅ (or "not applicable" for the MDM lines) means setup is complete.** If
only line 5 passes, report: *"requests work with explicit flags; the CLI/daemon
setup is not complete: <items>"*, then fix those items or say what's blocking
them.

---

## 9. After setup: show the value, add an API (mandatory)

Continue with **`guides/after-setup.md`**, which is shared with the local
setup. Use its *AWS* load block. It covers:
- the short handoff message;
- adding your own API (you store the secret over an SSM session with
  `passport-vault-put`; the agent creates the Passport objects).

---

## 10. Cleanup (only when the user explicitly asks): approval block D

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
bash "$REPO/scripts/aws-resources.sh" delete /tmp/pp-aws/state.env
```

Show the user the printed plan word for word. It lists every ID in order, and
checks that each one is tagged as ours. If it prints `STOP`, delete nothing and
ask. After a yes, run exactly that plan:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
[ -n "${MDM:-}" ] || passport daemon stop          # MDM Mac: its daemon container goes with the local side, below
# APIs added via guides/after-setup.md part 2 first
[ -s /tmp/pp-aws/resources.env ] && while read -r m u rest; do
  eval "$rest"     # sets RG REF EP GR for that API
  for p in access-grants/$GR resource-endpoints/$EP; do echo "$m $u $p -> $(api DELETE /api/v2/$p | jq -c .status)"; done
  echo "$m $u resource-group -> $(api DELETE /api/v1/resource-groups/$RG | jq -c .status)"
  echo "$m $u secret-reference -> $(api DELETE /api/v2/secret-references/$REF | jq -c .status)"
done < /tmp/pp-aws/resources.env
. /tmp/pp-aws/state.env    # restore the demo IDs the loop overwrote
for p in ${GR:+access-grants/$GR} ${EP:+resource-endpoints/$EP}; do echo "$p -> $(api DELETE /api/v2/$p | jq -c .status)"; done
[ -n "${RG:-}" ]  && echo "resource-group -> $(api DELETE /api/v1/resource-groups/$RG | jq -c .status)"
[ -n "${REF:-}" ] && echo "secret-reference -> $(api DELETE /api/v2/secret-references/$REF | jq -c .status)"   # 409 while an endpoint still maps it
[ -n "${NS:-}" ]  && echo "namespace -> $(api DELETE /api/v1/namespaces/$NS | jq -c .status)"
[ -n "${PROXY_ID:-}" ] && echo "proxy registration -> $(api DELETE /api/v2/tenant/config/$PROXY_ID | jq -c .status)"
if [ -n "${CF_DIST:-}" ]; then
  CFG=$(aws cloudfront get-distribution-config --id $CF_DIST)
  echo "$CFG" | jq '.DistributionConfig|.Enabled=false' > /tmp/pp-aws/cf-disabled.json
  aws cloudfront update-distribution --id $CF_DIST --if-match "$(echo "$CFG" | jq -r .ETag)" --distribution-config file:///tmp/pp-aws/cf-disabled.json >/dev/null
  aws cloudfront wait distribution-deployed --id $CF_DIST         # several minutes ("Long waits")
  aws cloudfront delete-distribution --id $CF_DIST --if-match "$(aws cloudfront get-distribution --id $CF_DIST --query ETag --output text)" && echo "deleted $CF_DIST"
fi
[ -n "${CF_FUNCTION:-}" ] && aws cloudfront delete-function --name $CF_FUNCTION --if-match "$(aws cloudfront describe-function --name $CF_FUNCTION --query ETag --output text)" && echo "deleted $CF_FUNCTION"
[ -n "${INSTANCE:-}" ] && aws ec2 terminate-instances --instance-ids $INSTANCE >/dev/null && aws ec2 wait instance-terminated --instance-ids $INSTANCE && echo "terminated $INSTANCE"
[ -n "${ALLOC:-}" ] && aws ec2 release-address --allocation-id $ALLOC && echo "released $ALLOC ($EIP)"
[ -n "${PROFILE:-}" ] && aws iam remove-role-from-instance-profile --instance-profile-name $PROFILE --role-name $ROLE && aws iam delete-instance-profile --instance-profile-name $PROFILE && echo "deleted profile $PROFILE"
[ -n "${ROLE:-}" ] && aws iam delete-role-policy --role-name $ROLE --policy-name passport-proxy-ssm && aws iam delete-role --role-name $ROLE && echo "deleted role $ROLE"
if [ -n "${SG:-}" ]; then for i in 1 2 3 4 5 6; do   # the instance's network interface can take a moment to be released
  E=$(aws ec2 delete-security-group --group-id $SG 2>&1) && { echo "deleted $SG"; break; }
  case "$E" in *DependencyViolation*) [ $i = 6 ] && echo "$SG still in use: re-run this line in a minute" || sleep 10;; *) echo "$SG: $E"; break;; esac
done; fi
bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env      # every AWS row should now say NOT FOUND
```

- **Report the result per row.** One failure must not hide the others.
- **Then the local side**, with the user's OK: `passport ca uninstall` **[you]**
  (needs sudo), `passport daemon uninstall`, and `rm -rf /tmp/pp-aws`. On an
  MDM Mac: the containers and files in `guides/reference/mdm-macs.md`, "Cleanup".
- **Terminating the instance destroys its bootstrap keys and its Vault.** That's
  intended here. For a long-lived proxy, back up `/opt/passport/keys` first.

---

## Troubleshooting and MDM

- Troubleshooting (shared with the local setup): `guides/reference/troubleshooting.md`
- MDM-managed Macs: `guides/reference/mdm-macs.md`
- Why things work the way they do: `guides/reference/concepts.md`

## Safety notes

- **No secrets in chat or logs.** Never paste a real credential, the registry
  key, an AWS key or a login token into chat, a commit or a shared log. Compare
  sha256 hashes instead.
- **Open ports.** 8443 is open only to your `/32`, and 8081 only to CloudFront's
  prefix list. If your IP changes, update the 8443 rule; never use `0.0.0.0/0`.
- **The Vault is dev mode, in memory.** That's fine for this setup, but it isn't
  durable storage for production credentials.
- **It costs money.** The instance, Elastic IP and CloudFront are billed while
  they exist. Clean up (step 10) when you're done, especially on a shared account.
