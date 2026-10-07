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
- a worked example of adding your own API, and optional protection demos.

> **Status:** rewritten 2026-10-06. Changes: no AWS Secrets Manager, keys
> generated on the instance, an interactive registry login. The previous EC2
> design was verified end to end. The add-an-API and protection-demo commands
> were verified on the local Docker setup with the same proxy image and CLI.
> **This EC2 version has not yet completed a full run.** Treat any step that
> fails as a bug in this guide and fix the guide.

## Where things live (read this once)

| What | Where | Lifetime |
|---|---|---|
| **Proxy bootstrap keys**: `ca.pem` signs client certificates; `ref.pem` decrypts secret references | On the instance's disk, `/opt/passport/keys/`, generated at first boot | Survive container restarts and reboots. **Lost if the instance is terminated or replaced**, and every secret reference registered for this proxy then stops working |
| **Reference public key** | `/opt/passport/reference-public-key.pem`, registered with Passport Cloud | The only key material that leaves the instance |
| **API credentials** (the secrets your requests use) | The **HashiCorp Vault** container on the instance, at `secret/<vault-key>` | **The Vault runs in dev mode, in memory. Restarting its container, or rebooting, erases every API credential.** Re-store them with `passport-vault-put` |
| **Registry key** (pulls the proxy image) | You type it into `sudo docker login` in your own terminal; it's logged out right after the pull | Never in user-data, SSM parameters, chat, or this repo |
| **Your client certificate** | Your machine, `~/.passport/` (`cert.pem`, `key.pem`, `ca.pem`) | Short-lived; renewed by the daemon (step 8.4) |

Nothing in this setup uses AWS Secrets Manager.

---

## Rules for an AI coding agent running this guide

Follow this guide literally and **do every step yourself**, except the steps
marked **[you]**, which need the human. `$REPO` means the absolute path of this
repository (the folder containing `AGENTS.md`). Start every command block with:

```bash
REPO=<absolute path of this repo>; . "$REPO/scripts/env.sh"
```

`scripts/env.sh` loads the manifest `/tmp/pp-aws/state.env` and defines three
helpers: `st` (record a value), `api` (call Passport Cloud) and `onhost` (run a
command on the instance).

**Context isolation:** use only this repository's files (`guides/`, `scripts/`,
`templates/`). If something is missing, ask the user. Don't search elsewhere.

**Discover before asking.** Run step 1's discovery first. Infer routine
choices (profile, region, subnet, name, client IP) from what exists, and *state*
them. Ask only for what you genuinely can't determine, and ask it all in one go.

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
- **Passport Cloud API calls are yours to run, without asking.** This covers
  registering the proxy and creating or deleting the namespace, resource group,
  secret reference, endpoint and grant. The same goes for every `passport` CLI
  command that needs no `sudo`, browser approval or secret value (`setup`,
  `whoami`, `daemon status`, `ca status`, `request`).
  - **Don't** ask permission for them.
  - **Don't** ask the user to run them.
  - **Do** run them, record the IDs with `st`, and say what you created.
  - **One guard stays:** if the team already has a proxy, register yours with
    `isDefault:false`, and tell the user why.
  - **AWS changes still need the approval blocks above.**

**Commands that need the human.** You can't type into the user's terminal, and
they can't type into yours. Anything that needs a password, `sudo`, a browser
approval or a secret value is a **[you]** step:
- give the exact commands in a code block, to run **in their own terminal**;
- say what they should see;
- wait for "done", then verify yourself.

Never ask for a secret's value in chat.

**Never print secrets.** That means the registry key, private keys, the Vault
token, login tokens and API credentials. Public keys, IDs and sha256 hashes are
fine. Never print an API response that could contain a secret.

**Don't call setup complete early.** Success is the checklist in step 8.5. If the
explicit `curl` works but `setup` exited 2, the daemon isn't running, or the CA
isn't trusted, say exactly that: *"requests work with explicit flags; the
CLI/daemon setup is not complete: …"*.

**Mandatory ending:** after step 8.5 passes, do the step 9 walkthrough, then
offer step 10 (their own API) and step 11 (protection demos), one at a time.
Never run cleanup (step 12) until the user explicitly asks for it.

**MDM-managed Mac:** switch to `guides/reference/aws-mdm-macs.md` as soon as any
of these appears:
- CLI output says `(from macOS managed plist)`;
- `setup` fails with `403 … teamId "org_…" is not authorized for this deployment`
  while the proxy logs nothing;
- `passport whoami` says `Managed Passport credentials could not be verified`.

---

## 1. Discover (read-only, no questions yet)

```bash
mkdir -p /tmp/pp-aws; REPO=<repo>; . "$REPO/scripts/env.sh"
echo "--- tools"; for t in aws session-manager-plugin passport docker node jq openssl; do printf '%-24s %s\n' "$t" "$(command -v $t >/dev/null && ($t --version 2>/dev/null | head -1) || echo MISSING)"; done
echo "--- aws profiles"; for p in $(aws configure list-profiles 2>/dev/null); do printf '%-20s region=%-12s %s\n' "$p" "$(aws configure get region --profile $p)" "$(aws sts get-caller-identity --profile $p --query Arn --output text 2>&1 | tail -1 | cut -c1-90)"; done
echo "--- passport"; passport --version 2>/dev/null; passport auth status 2>&1 | grep -E 'org|expires|not logged'
echo "--- manifest"; cat /tmp/pp-aws/state.env 2>/dev/null
```

From this output, decide without asking where you can:
- **Profile:** the profile with a working session. If more than one works, ask which.
- **Region:** that profile's configured region.
- **Existing deployment:** if `/tmp/pp-aws/state.env` has a `NAME`, run
  `bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env` and resume
  from there instead of creating a new one.

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
- **Team ID:** the `org_…` value on the `org` line of `passport auth status`.

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
- **IAM actions:** only on roles and instance profiles named `passport-proxy-*`.

An administrator attaches it to the permission set, role or user. For a sandbox
account, `PowerUserAccess` plus the policy's IAM statements also works.

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

It also picks a **collision-free name**, printed as `PREFLIGHT_NAME=<name>`.
Every resource will be called `passport-proxy-<name>`.

Fix every ❌ before going on. Then record the inputs:

```bash
REPO=<repo>; export AWS_PROFILE=<profile> AWS_REGION=<region>; . "$REPO/scripts/env.sh"
st AWS_PROFILE "$AWS_PROFILE"; st AWS_REGION "$AWS_REGION"
st NAME "$(sed -n 's/^PREFLIGHT_NAME=//p' /tmp/pp-aws/preflight.txt)"
st ACCOUNT "$(aws sts get-caller-identity --query Account --output text)"
st ORG "$(passport auth status | awk '$1=="org"{print $2}')"          # MDM Mac: read it from the container CLI (MDM guide A.3)
st CLIENT_CIDR "$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32"
st VPC "$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)"
st SUBNET "$(sed -n 's/.*public subnet \(subnet-[0-9a-f]*\).*/\1/p' /tmp/pp-aws/preflight.txt)"
st AMI "$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)"
st CF_PL "$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text)"
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
sed -e "s|__ORG__|$ORG|" -e "s|__SANS__|$PROXY_HOST,$EIP,localhost|" "$REPO/templates/user-data.tmpl" > user-data.sh
! grep -qE 'sk_|PRIVATE KEY|VAULT_TOKEN=[0-9a-f]' user-data.sh || { echo "SECRET IN USER-DATA — STOP"; exit 1; }
sleep 10    # IAM instance-profile propagation
st INSTANCE "$(aws ec2 run-instances --image-id $AMI --instance-type t3.small --subnet-id $SUBNET --security-group-ids $SG \
  --iam-instance-profile Name=$N --associate-public-ip-address \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=2 \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3,Encrypted=true}' \
  --user-data file://user-data.sh --tag-specifications "ResourceType=instance,Tags=[$TAGS]" "ResourceType=volume,Tags=[$TAGS]" \
  --query 'Instances[0].InstanceId' --output text)"
aws ec2 wait instance-running --instance-ids $INSTANCE
aws ec2 associate-address --instance-id $INSTANCE --allocation-id $ALLOC >/dev/null
bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env
```

**If a command fails halfway:**
- **What happens:** `set -e` stops the block, and everything created so far is
  already recorded in `state.env`.
- **What to tell the user:** show `aws-resources.sh show` and explain the error.
- **IAM propagation** (`… instance profile is invalid`): wait about 15 s and
  re-run only A5.
- **Anything else:** roll back what was created (step 12, with approval), then retry.

Never re-run the whole block, because that creates duplicates.

---

## 4. Wait for the instance (read-only)

First boot installs Docker and starts Vault, which takes about 2 minutes. The
proxy isn't running yet, because it needs your registry login (step 5).

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
for i in $(seq 1 30); do
  aws ssm describe-instance-information --filters Key=InstanceIds,Values=$INSTANCE \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null | grep -q Online && break; sleep 10; done
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
sudo passport-start-proxy                                          # pulls the image, logs out of the registry, starts proxy + echo
exit
```

- **No registry key yet?** Create one at
  <https://app.usepassport.ai/org/registry> (Org Settings → Registry; needs
  admin), or ask the team admin.
- **Expected output:** `pp-proxy-local Up …`, `pp-echo Up …` and `readyz=200`.
- **The key doesn't stay on the instance:** `passport-start-proxy` runs
  `docker logout` right after the pull.

When the user says done, verify it yourself:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
onhost 'docker ps --format "{{.Names}} {{.Status}}"; curl -s -o /dev/null -w "readyz=%{http_code}\n" http://localhost:8081/readyz'
aws cloudfront wait distribution-deployed --id $CF_DIST
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
| CREATE | Proxy registration | `passport-proxy-<NAME>`, endpoint `https://<PROXY_HOST>:8443`, management `https://<CF_DOMAIN>`, key sha256 `<REF_KEY_SHA256>`. **Made the default only if the team has no proxy yet**, because the default changes what every teammate's `passport setup` uses |
| CREATE | Namespace | `passport-proxy-<NAME>-e2e` |
| CREATE | Resource group | `localhost` (`source: manual`), so the endpoint shows in the web UI |
| CREATE | Secret reference | `demo` → HashiCorp Vault key `test-key` |
| CREATE | Resource endpoint | `GET localhost /echo`, credential slot `x-key` |
| CREATE | Access grant | you, on that endpoint, for 1 day |
| WRITE | Vault entry on the instance | `secret/test-key` = the **known fake** value `some-local-test-value` |

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"; set -e; cd /tmp/pp-aws
DEFAULT=$(api GET /api/v2/tenant/config | jq '(.body.data|length)==0')
jq -n --rawfile k reference-public-key.pem --arg n "passport-proxy-$NAME" --arg e "https://$PROXY_HOST:8443" --arg m "https://$CF_DOMAIN" \
  --argjson d "$DEFAULT" '{encryptionMode:"B",publicKey:$k,proxyName:$n,proxyEndpoint:$e,managementHostUrl:$m,isDefault:$d}' > register-body.json
st PROXY_ID "$(api POST /api/v2/tenant/config @register-body.json | jq -r .body.data.proxyId)"
GOT=$(api GET /api/v2/tenant/config | jq -r --arg p "$PROXY_ID" '.body.data[]|select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$GOT" = "$REF_KEY_SHA256" ] && echo "registered key matches the instance's key" || { echo "KEY MISMATCH"; exit 1; }

# Demo credential: a deliberately FAKE, publicly known value, so passing it via Run Command is fine. Real ones: step 10.
onhost '. /opt/passport/vault.env; docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN pp-vault-dev vault kv put secret/test-key value=some-local-test-value >/dev/null && echo stored'

PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)')
st NS  "$(api POST /api/v1/namespaces "$(jq -nc --arg n "passport-proxy-$NAME-e2e" '{name:$n,description:"Passport proxy e2e demo"}')" | jq -r .body.data.id)"
st RG  "$(api POST /api/v1/namespaces/$NS/resource-groups '{"name":"localhost","description":"Passport proxy e2e demo","source":"manual"}' | jq -r .body.data.id)"
st REF "$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"test-key"}')" | jq -r .body.data.id)"
st EP  "$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" --arg g "$RG" '{namespaceId:$ns,method:"GET",host:"localhost",path:"/echo",secrets:[{label:"x-key",secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -r .body.data.id)"
st GR  "$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy e2e",validity:1}')" | jq -r '.body.data[0].id')"
grep -E '^(PROXY_ID|NS|RG|REF|EP|GR)=' state.env
```

`st` refuses to record an empty value. If an ID comes back empty, run
`passport auth status` (it refreshes the login token), then re-run only the
lines that didn't record.

- **Endpoint hosts never include a port.** The proxy strips the port from the
  request but not from the stored host, so `localhost:9443` would never match.
- **The resource group is what makes the endpoint visible in the web UI.** An
  endpoint created without `resourceGroupIds` works, but never shows in
  Passport Cloud. To fix one created earlier, run
  `api PUT /api/v2/resource-endpoints/<id> "$(jq -nc --arg g "$RG" '{resourceGroupIds:[$g]}')"`.
- **A secret reference only works with the proxy registration that was active
  when it was created.** If you re-register with a new key, create new
  references.

---

## 7. Issue your certificate, trust the CA, start the daemon

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
passport setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443; echo "setup exit=$?"
```

What the exit code means:
- **`0`:** credentials issued **and** the daemon and environment are configured.
- **`2`:** **partial.** Credentials are OK, but the daemon or environment step
  failed (read the output). Setup is **not** complete.
- **`1`:** failed.

On success, setup prints `[5/5] daemon installed + HTTPS_PROXY set`.

**[you] Trust the Passport CA** (needs `sudo` or admin, so it runs in the user's terminal):

```bash
passport ca install
```

- **On macOS** it runs
  `sudo security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain ~/.passport/ca.pem`.
  That adds the CA to the System keychain, trusted for the **SSL policy** only.
- **On Windows** it adds the CA to `LocalMachine\Root`, with a UAC prompt.
- **Undo** with `passport ca uninstall`.

### 7.1 Validate trust with the SSL policy

`passport ca status` reports whether the CA is *present*. On macOS it doesn't
check the trust setting, so also verify against the SSL policy that `ca install`
set:

```bash
passport ca status
security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain   # macOS: expect "certificate verification successful"
openssl x509 -in ~/.passport/ca.pem -noout -fingerprint -sha256                           # should match the sha256 that 'ca status' shows
```

---

## 8. Verify everything (each item separately)

### 8.1 Your identity

```bash
passport whoami
```

Expect your `teamId`, `allowedApiRefs` with `GET localhost/echo → {{vault:<REF>}}`,
and a `notAfter` time.

### 8.2 Explicit request with proxy and certificate flags

This needs no daemon, and the localhost demo **requires** it (see 8.3):

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
curl -sS --proxy https://$PROXY_HOST:8443 \
  --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem --proxy-key ~/.passport/key.pem \
  --cacert /tmp/pp-aws/proxy-ca.pem \
  -H "x-key: {{vault:$REF}}" \
  https://localhost:9443/echo
echo -n "some-local-test-value" | shasum -a 256          # must equal "sha256" in the response
onhost 'docker logs pp-echo 2>&1 | tail -1'             # the destination logged the same hash
```

- **`--proxy-cacert`** trusts the proxy itself.
- **`--cacert`** trusts the certificate the proxy presents for the destination,
  which the proxy re-signs with its CA.
- **`{{vault:…}}` needs the reference's UUID, not its name.** A name passes
  through unchanged, with no error.

### 8.3 Daemon status and environment

```bash
passport daemon status        # pid, port (default 10144), upstream reachable, cert expiry
echo "$HTTPS_PROXY"           # http://127.0.0.1:10144 — in a NEW terminal window after setup
```

- **macOS:** setup sets `HTTPS_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`,
  `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` for your login session. The
  terminal you ran setup in doesn't see them yet. Either quit the terminal app
  completely and reopen it, or paste the `export …` lines that setup printed.
- **Windows:** setup writes the same variables to the user environment.
- **Shell rc file (optional):** `passport daemon install --write-to ~/.zshrc`
  also appends the variables to your rc file. That block also sets
  `NODE_OPTIONS=--use-env-proxy` (Node's built-in fetch ignores `HTTPS_PROXY`
  without it) and `JAVA_TOOL_OPTIONS` proxy settings.
- **The daemon only routes external hosts.** `NO_PROXY` always includes
  `localhost`, `127.0.0.1`, `::1`, private IP ranges, `.local`, `.internal`,
  `.svc`, `.cluster.local`, `.postmanlabs.com` and `.usepassport.ai`, plus
  their `-beta`/`-stage` variants. That's why the localhost echo demo **can't**
  use the daemon and needs 8.2's explicit flags. Real APIs (step 10) can use it.
- **Linux:** setup can't install the daemon. Start it with
  `passport daemon start`, then export the variables yourself:
  `HTTPS_PROXY=http://127.0.0.1:10144`, and `SSL_CERT_FILE`,
  `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` set to `~/.passport/ca.pem`.

### 8.4 Certificate lifetime and renewal

- **Expiry:** `notAfter` in `passport whoami` and `passport daemon status`.
- **Requested vs actual:** the CLI requests 1 hour by default
  (`passport setup --ttl <seconds>`), but the proxy may issue less. Earlier runs
  got about 5 minutes. Report the real value.
- **With the daemon:** it renews **on demand**. When a request starts with less
  than 60 s left, it mints a new cert using your saved login. If the login has
  also expired, run `passport login` then `passport setup`.
- **Without the daemon:** `passport request` renews inline, but nothing renews
  the files that plain `curl` reads, so run `passport setup` again.

### 8.5 Success checklist (report each line as ✅ or ❌)

1. `passport setup` exited `0`. An exit of `2` means the daemon or environment
   step failed, so this line is ❌ even if the rest pass.
2. `passport whoami` shows the `GET localhost/echo` grant and a future `notAfter`.
3. `passport ca status` says trusted, **and** `security verify-cert … -p ssl`
   succeeds (macOS).
4. `passport daemon status` shows it running with the upstream reachable
   (macOS/Windows; on Linux, after `daemon start`).
5. The 8.2 request returned the expected sha256, and the echo log shows the same hash.

**All five ✅ means setup is complete.** If only line 5 passes, report:
*"requests work with explicit flags; the CLI/daemon setup is not complete:
<items>"*, then fix those items or say what's blocking them.

---

## 9. Mandatory handoff walkthrough (after 8.5 passes)

One self-contained message, using real values:

**9.1 The request, verbatim.** Print the exact 8.2 command you ran, with every
value filled in: `--proxy https://<PROXY_HOST>:8443`, the three `~/.passport`
paths, `--cacert`, `-H "x-key: {{vault:<REF>}}"` and the URL. Then show its
actual output.

**9.2 What each part did:**
- **`--proxy https://<PROXY_HOST>:8443`:** the request goes to **your proxy on
  EC2**, not straight to the destination.
- **`--proxy-cert` and `--proxy-key`:** your short-lived client certificate. It
  **identifies you** and lists the grants you hold (`GET localhost/echo`).
- **`{{vault:<REF>}}`:** a **pointer** to a Vault entry (`test-key`). It isn't
  the credential itself.
- **The proxy:** checks the certificate and checks that the request matches a
  grant. It then decrypts the reference with its bootstrap key (`ref.pem`, on
  the instance), reads the value from Vault, and **injects it in flight**, only
  for the granted method, host and path.

**9.3 What the test proved, stated honestly:**
- **The proxy resolved and injected the value.** The destination received it,
  and its logged sha256 matches the known value.
- **The request carried only the pointer.** The request and its tools held
  `{{vault:<REF>}}`, never the value.
- **This was a fake test value.** Because it's known, it *was* present locally,
  in this guide and in the `shasum` check. Don't claim it never touched the
  machine.
- **Real credentials (step 10) work differently.** The value is typed only into
  a hidden prompt on the instance, and never reaches the requester's machine,
  shell history or this conversation.

**9.4 Expiry and renewal:** state the real `notAfter`, then explain 8.4 in two
sentences.

**9.5 Two ways to make requests:**
- **Explicit flags** (as in 9.1): works anywhere and needs no daemon. It's
  required for `localhost` and the other `NO_PROXY` destinations.
- **Through the daemon:** in a new terminal, a plain
  `curl -H "Authorization: Bearer {{vault:<uuid>}}" https://api.example.com/...`.
  `HTTPS_PROXY` routes it, and `SSL_CERT_FILE` trusts the CA. Step 10 shows it
  for real.

**9.6 Next:**
- Offer step 10 (your own API) and step 11 (protection demos).
- Close with the resource status:
  `bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env`.
- List any open ❌ from 8.5.
- Remind the user that **nothing is deleted until they explicitly ask for cleanup.**

---

## 10. Add your own API (offer it; the agent creates the Passport objects itself)

Ask for these. The credential's **value** is never one of them:

| Input | Example |
|---|---|
| Method and URL | `GET https://api.example.com/me` |
| Credential format | `Authorization: Bearer …`, `x-api-key: …`, or a query parameter `?api_key=…` |
| Vault key name | `example-api-token` |

The API must be reachable from the instance: the public internet works, since
the security group's default egress allows it. The proxy trusts the system CA
bundle, so publicly trusted HTTPS certificates work as they are.

**The sequence:**

1. **[you] Store the credential privately** on the instance, through a hidden
   prompt. It never goes on a command line, into SSM Run Command history, into
   chat or into the agent's context. In your own terminal:
   ```bash
   aws ssm start-session --target <INSTANCE> --region <AWS_REGION> --profile <AWS_PROFILE>
   sudo passport-vault-put example-api-token        # paste the token at the hidden prompt
   exit
   ```
2. **The agent creates the Passport objects itself**, without asking. That's a
   resource group for the host, a secret reference, an endpoint (host without a
   port, path without a query string) and a grant for you:
   ```bash
   EP_METHOD=GET; EP_HOST=api.example.com; EP_PATH=/me; VKEY=example-api-token; HDR=Authorization
   REPO=<repo>; . "$REPO/scripts/env.sh"; cd /tmp/pp-aws
   PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)')
   RG_N=$(api POST /api/v1/namespaces/$NS/resource-groups "$(jq -nc --arg n "$EP_HOST" '{name:$n,description:"Added after e2e",source:"manual"}')" | jq -r .body.data.id)
   REF_N=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" --arg k "$VKEY" '{namespaceId:$ns,name:$k,vaultType:"hashicorp",vaultKey:$k}')" | jq -r .body.data.id)
   EP_N=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg m "$EP_METHOD" --arg h "$EP_HOST" --arg p "$EP_PATH" --arg l "$HDR" --arg r "$REF_N" --arg g "$RG_N" \
     '{namespaceId:$ns,method:$m,host:$h,path:$p,secrets:[{label:$l,secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -r .body.data.id)
   GR_N=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP_N" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport extra resource",validity:1}')" | jq -r '.body.data[0].id')
   printf '%s RG=%s REF=%s EP=%s GR=%s\n' "$EP_METHOD $EP_HOST$EP_PATH" $RG_N $REF_N $EP_N $GR_N | tee -a resources.env
   ```
   `resources.env` keeps one line per added API, and cleanup reads it. If an ID
   comes back empty, run `passport auth status` and re-run the block.
3. **Refresh your certificate** so it includes the new grant. Run step 7's
   `passport setup …`, then check that `passport whoami` lists the endpoint and
   `{{vault:<REF_N>}}`.
4. **Make the request in both forms**, with the real values:
   ```bash
   # explicit flags
   curl -sS --proxy https://<PROXY_HOST>:8443 --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem \
     --proxy-key ~/.passport/key.pem --cacert /tmp/pp-aws/proxy-ca.pem \
     -H "Authorization: Bearer {{vault:<REF_N>}}" https://api.example.com/me
   # through the daemon (new terminal, HTTPS_PROXY set by setup): no proxy or cert flags
   curl -sS -H "Authorization: Bearer {{vault:<REF_N>}}" https://api.example.com/me
   ```
   - **What success looks like:** a 2xx from the API means the proxy injected the
     real token. Don't print the body if it could echo the credential.
   - **Query parameters:** if the credential goes in a query parameter, add `-g`.
     Otherwise curl reads `{{` as URL-glob syntax and fails with
     `nested brace in URL`.

The credential is lost if the Vault container restarts, so re-run
`passport-vault-put`. To check it without printing it, run
`sudo passport-vault-sha256 example-api-token` inside a session, and compare the
result with the sha256 of the token at its source.

---

## 11. Protection demos (offer one at a time, explain each result)

Use the explicit form from 8.2 or 10.4. Each demo shows one thing a plain API
key can't do.

**A. A leaked pointer is useless anywhere else.** Send the *same* pointer to a
path or host that wasn't granted:

```bash
curl -sS --proxy https://$PROXY_HOST:8443 --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem --proxy-key ~/.passport/key.pem \
  --cacert /tmp/pp-aws/proxy-ca.pem -H "x-key: {{vault:$REF}}" https://localhost:9443/not-granted
curl -sS --proxy https://$PROXY_HOST:8443 --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem --proxy-key ~/.passport/key.pem \
  --cacert /tmp/pp-aws/proxy-ca.pem -H "x-key: {{vault:$REF}}" https://httpbin.org/headers
```

Both are refused with `passport: not authorized for vault refs: [<uuid>]`.
- **This proves:** the secret is only injected on the exact method, host and
  path that were granted.
- **Why it matters:** a pointer that ends up in a log, a copied script or a
  prompt-injected AI agent can't be used to send the secret anywhere else.

**B. Every call is audited, and the logs never hold the secret.**

```bash
onhost 'docker logs pp-proxy-local 2>&1 | grep passport.proxy.request | tail -10' | grep -o '{"resourceLogs".*' \
  | jq -r '.resourceLogs[].scopeLogs[].logRecords[] | ([.attributes[] | {(.key): (.value|to_entries[0].value)}] | add) as $a
  | [$a["http.request.method"], $a["server.address"] + $a["http.route"], $a["passport.outcome"], $a["enduser.id"]] | @tsv'
```

Each line shows the method, host and path, the outcome (`success` or
`unauthorized`) and the user ID. The records carry secret-reference UUIDs,
never values.

**C. Revoke a grant and access ends.** Once the user picks this demo, delete the grant yourself, get a
new certificate, and repeat the call:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
api DELETE /api/v2/access-grants/$GR
passport setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443
passport whoami                       # the endpoint is gone from allowedApiRefs; 8.2 is now refused
```

- **This proves:** removing the grant cuts access once the cert is refreshed,
  and the user never held the credential, so there's nothing for them to keep.
- **Restore access:** re-run the `GR` line from step 6 (`st GR …`) to create
  the grant again.

**D. Rotate the secret with no client changes.**
1. In a session, the user runs `sudo passport-vault-put test-key` and enters a new value.
2. Wait about 60 s, because the proxy caches lookups.
3. Repeat 8.2.

- **Expect:** the response sha256 changes to the new value's hash, using the
  same pointer.
- **This proves:** rotating the secret needs no change to any script,
  configuration or laptop.

**What to tell the user**, in their own terms:
- **Nothing to leak:** no API key on laptops, in repos, in CI or in an AI agent's context.
- **Least privilege:** access is per method, host and path, per person.
- **Central control:** revoke or rotate from one place.
- **An audit trail** of who called what, and whether it was allowed.

---

## 12. Cleanup (only when the user explicitly asks): approval block D

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
bash "$REPO/scripts/aws-resources.sh" delete /tmp/pp-aws/state.env
```

Show the user the printed plan word for word. It lists every ID in order, and
checks that each one is tagged as ours. If it prints `STOP`, delete nothing and
ask. After a yes, run exactly that plan:

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
passport daemon stop
# APIs added in step 10 first
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
  aws cloudfront wait distribution-deployed --id $CF_DIST         # several minutes
  aws cloudfront delete-distribution --id $CF_DIST --if-match "$(aws cloudfront get-distribution --id $CF_DIST --query ETag --output text)" && echo "deleted $CF_DIST"
fi
[ -n "${CF_FUNCTION:-}" ] && aws cloudfront delete-function --name $CF_FUNCTION --if-match "$(aws cloudfront describe-function --name $CF_FUNCTION --query ETag --output text)" && echo "deleted $CF_FUNCTION"
[ -n "${INSTANCE:-}" ] && aws ec2 terminate-instances --instance-ids $INSTANCE >/dev/null && aws ec2 wait instance-terminated --instance-ids $INSTANCE && echo "terminated $INSTANCE"
[ -n "${ALLOC:-}" ] && aws ec2 release-address --allocation-id $ALLOC && echo "released $ALLOC ($EIP)"
[ -n "${PROFILE:-}" ] && aws iam remove-role-from-instance-profile --instance-profile-name $PROFILE --role-name $ROLE && aws iam delete-instance-profile --instance-profile-name $PROFILE && echo "deleted profile $PROFILE"
[ -n "${ROLE:-}" ] && aws iam delete-role-policy --role-name $ROLE --policy-name passport-proxy-ssm && aws iam delete-role --role-name $ROLE && echo "deleted role $ROLE"
[ -n "${SG:-}" ] && aws ec2 delete-security-group --group-id $SG && echo "deleted $SG"
bash "$REPO/scripts/aws-resources.sh" show /tmp/pp-aws/state.env      # every AWS row should now say NOT FOUND
```

- **Report the result per row.** One failure must not hide the others.
- **Then the local side**, with the user's OK: `passport ca uninstall` **[you]**
  (needs sudo), `passport daemon uninstall`, and `rm -rf /tmp/pp-aws`.
- **Terminating the instance destroys its bootstrap keys and its Vault.** That's
  intended here. For a long-lived proxy, back up `/opt/passport/keys` first.

---

## Troubleshooting and MDM

- Troubleshooting table: `guides/reference/aws-troubleshooting.md`
- MDM-managed Macs: `guides/reference/aws-mdm-macs.md`

## Safety notes

- **No secrets in chat or logs.** Never paste a real credential, the registry
  key, an AWS key or a login token into chat, a commit or a shared log. Compare
  sha256 hashes instead.
- **Open ports.** 8443 is open only to your `/32`, and 8081 only to CloudFront's
  prefix list. If your IP changes, update the 8443 rule; never use `0.0.0.0/0`.
- **The Vault is dev mode, in memory.** That's fine for this setup, but it isn't
  durable storage for production credentials.
- **It costs money.** The instance, Elastic IP and CloudFront are billed while
  they exist. Clean up (step 12) when you're done, especially on a shared account.
