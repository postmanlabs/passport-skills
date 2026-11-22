# Postman Passport proxy — local Docker setup

A from-scratch walkthrough for one developer using the Passport CLI and a
public Proxy Docker image. No source checkout is needed. By the end you'll have:

- the **Passport CLI** installed and logged in,
- a **Passport Proxy** running locally in Docker, backed by a **local
  HashiCorp Vault**,
- an **access group** (called a namespace by the API) wired up to that proxy,
- and a request that proves the proxy read a secret from Vault and sent it to an API.

It assumes no prior Passport knowledge, just
comfort with a terminal and Docker.

## Deployment inputs

Set these **together** before starting. Use the production defaults unless the
developer explicitly supplies all three alternate URLs. Never mix the CLI,
app and API from different environments. Carry the same values into the
`passport-public-api` skill when handing off API work.

| Input | Default |
|---|---|
| `app_url` | `https://app.usepassport.ai` |
| `api_url` | `https://api.usepassport.ai` |
| `cli_download_base_url` | `https://dl-passport.pstmn.io/install/enterprise` |
| `cli_data_dir` | `~/.passport` (use a separate directory with an alternate environment) |

Record the selected values once. Substitute all three URLs if the developer
provided a complete alternate set, and use a separate CLI data directory for
that environment. If this file already exists, inspect it
and stop if any URL or the image reference differs from the requested
destination; do not overwrite it silently. For this beta test, use the pinned
public test tag below.
Every later command that calls the app, API or installer loads this file; the
companion skill loads it too.

```bash
mkdir -p /tmp/pp-local && chmod 700 /tmp/pp-local
if [ ! -e /tmp/pp-local/target.env ]; then
  (umask 077; cat > /tmp/pp-local/target.env <<'EOF'
APP_URL='https://app.usepassport.ai'
PASSPORT_API='https://api.usepassport.ai'
CLI_DOWNLOAD_BASE_URL='https://dl-passport.pstmn.io/install/enterprise'
PASSPORT_DIR="$HOME/.passport"
PROXY_IMAGE_REF='public.ecr.aws/q4k6e3c0/passport/passport-proxy:beta-71ed5cf'
EOF
  )
fi
```

## If an AI coding agent is running this guide for you

The ground rules in `SKILL.md` apply. This section adds only what is specific
to the local setup.

Follow this guide literally. Do the agent steps; the developer handles the
marked app, token and secret-entry steps. `$SKILL_DIR` below means
the absolute path of this skill's folder (the folder containing
`SKILL.md`); `scripts/` and `templates/` live there. Substitute the real path:
each command runs in a fresh shell.

- **Never request registry credentials.** The local proxy image is public.
- **The proxy token and any real secret are human-only inputs.** The developer
  enters each in their terminal's hidden prompt; never ask them to paste it
  into chat.
- **Public API bootstrap key:** the developer creates a user-owned admin key
  in the selected app at step 5.1 and relaunches the agent with
  `PASSPORT_API_KEY` set. It is temporarily readable by the agent's process. Never print it,
  inspect `passportrc`, or use the CLI's access/refresh tokens for API calls.
- **The browser approvals** (`passport login`) are the user's. Show the login
  link on its own line, as a full `https://` URL with the confirmation code. If
  it expires, restart `login` and give a fresh one.
- **Read the team ID yourself** from `passport whoami --json` after login.
- **The developer creates the named proxy in the app.** The proxy registers
  itself with its one-time token. Create the demo resources through the API
  after the app reports Healthy; do not create a second proxy record.
- **Check existing state first** (containers, network, keys, CLI version) and
  reuse it; never regenerate `ref.pem` if one is registered.
- **After the step 7 test, continue with `guides/after-setup.md`**: show the
  app's “See what was created” step, then offer the agent or app path for
  adding the developer's own API.
  Cleanup (step 8) waits until the user explicitly asks.

## What you need

Before installing anything, check which tools are already available. Tell the
developer only what is missing, what each missing tool does here, and the exact
official install command. Include Docker images that will be downloaded. Ask for
approval before installing or pulling anything.

- **Docker Desktop (or another Docker daemon), running:** runs the Passport proxy,
  which sends approved API requests, and a temporary HashiCorp Vault, which holds
  the secrets used in those requests. Vault dev mode loses its secrets on restart.
- **Passport account and team:** complete step 0 in the selected app before
  running `passport login`.
- **`openssl`:** creates the proxy's private keys. **`curl`:** downloads the CLI
  installer and tests the request through the proxy. **`jq`:** reads API responses
  while creating and checking the demo setup. **`ping`:** checks local name resolution.

On macOS or Linux, check without installing anything:

```bash
for tool in docker passport openssl curl jq ping; do
  command -v "$tool" >/dev/null && printf '%s: available\n' "$tool" || printf '%s: missing\n' "$tool"
done
```

On Windows, use PowerShell's `Get-Command` to check prerequisites. PowerShell
already parses JSON; do not ask a Windows developer to install `jq` for that.
The Windows setup needs PowerShell commands; do not run the bash blocks there.

No Node.js installation is needed for this path.

---

## 0. Create or select your Passport team

Ask whether the developer already has a Passport account with a team. For a
new account, ask for a team name; suggest “<first name>’s Passport Team”. Read
`APP_URL` from `target.env` and give them the full `<app_url>/signup?origin=agent`
link. Have them enter the chosen team name on the signup page and finish
signup. Wait until the app shows their team and setup page before continuing.

For an existing account, have them open `<app_url>/setup?origin=agent`, sign
in, and confirm the intended team is shown. If the account has no team, ask
for a name (suggest the same format) and have them use the app's **Create
team** action. A signed-in user should create the team there, not revisit
signup. The `origin=agent` link makes the app show the agent setup copy.

`passport login` in step 1 authorizes the CLI for this existing account and
team. It must not be the first signup step.

---

## 1. Install and log in to the Passport CLI

Check the active `passport --help` and all copies on PATH first. The Enterprise
CLI has `login` and `setup`; the Community CLI has `lens`. If the intended
Enterprise binary is already first on PATH, reuse it. Otherwise show the installer
from the selected `cli_download_base_url` and ask for approval before running it.
Ask before removing a shadowing binary.

Use the official installer from the
[Passport CLI install docs](https://docs.usepassport.ai/passport/reference/passport-cli/install).
It detects the OS and architecture and always installs the latest version. It
may ask for administrator credentials, so the user runs it in their own
terminal.

**macOS or Linux:**

```bash
. /tmp/pp-local/target.env
curl -fsSL "$CLI_DOWNLOAD_BASE_URL/unix.sh" | sh
```

**Windows (PowerShell):**

```powershell
irm "<selected cli_download_base_url>/win64.ps1" | iex
```

Check `passport --help` again after installation: it must list `login` and
`setup`.

On macOS or Linux, run `which -a passport`. The installer puts the CLI in
`/usr/local/bin/passport`. If another copy comes first, it shadows the new
install. Compare `/usr/local/bin/passport --help` with `passport --help` and
correct `PATH` before continuing. On Windows, use
`Get-Command passport -All` to find each copy. Do not delete a shadowing
binary without asking: a running daemon may use it.

Then log in with the CLI installed from the selected URL:

```bash
. /tmp/pp-local/target.env; export PASSPORT_DIR
passport login
```

This opens a browser to authenticate and runs the CLI's initial setup. An empty
bundle with no secret references is expected before the local proxy and demo
access are created. Run `passport setup` again after the proxy is Healthy and
the demo access is granted (step 6).

### 1.1 Confirm you have a team

If `login` says `authenticated login session has no organization`, return to
the selected app and check that the intended team was created or selected.
If the account has no team, use the app's **Create team** action, then re-run
`passport login`.

Retrying `passport login` does **not** surface any team-selection or
team-creation screen, even on a fresh account. The CLI's own hint ("select an
organization during `passport login`") is misleading here; don't look for a
prompt that won't appear.

Confirm `passport whoami --json` reports the intended `org_...` team ID. Use
this ID for the proxy's allowed team list.

---

## 2. Pull the public proxy image

Pull the `beta-71ed5cf` test image from public ECR without registry credentials. A fresh setup
uses the image returned by this pull; an existing proxy container keeps the
image it was started with. The local path uses Docker only; Helm is for a
team deployment.

```bash
. /tmp/pp-local/target.env
docker pull "$PROXY_IMAGE_REF"
```

---

## 3. Start or reuse local HashiCorp Vault

Vault runs in **dev mode, in memory**. A Vault or Docker restart erases its
secrets; use a test credential and store it again after a restart. Never remove
an existing Vault container automatically. Vault is reachable by the proxy on
their Docker network, with no host-published port.

```bash
mkdir -p /tmp/pp-local && chmod 700 /tmp/pp-local
docker network inspect pp-net >/dev/null 2>&1 || docker network create pp-net
if docker container inspect pp-vault-dev >/dev/null 2>&1; then
  [ "$(docker inspect -f '{{.State.Running}}' pp-vault-dev)" = true ] &&
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 pp-vault-dev vault status >/dev/null &&
    [ -s /tmp/pp-local/vault-token ] || { echo 'Existing Vault cannot be reused; stop and inspect it.' >&2; exit 1; }
else
  (umask 077; openssl rand -hex 32 > /tmp/pp-local/vault-token) || exit 1
  export VAULT_DEV_ROOT_TOKEN_ID
  VAULT_DEV_ROOT_TOKEN_ID=$(cat /tmp/pp-local/vault-token)
  docker run --cap-add=IPC_LOCK -d --name pp-vault-dev --network pp-net \
    -e VAULT_DEV_ROOT_TOKEN_ID -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
    hashicorp/vault server -dev || exit 1
  unset VAULT_DEV_ROOT_TOKEN_ID
  tries=0
  until docker exec -e VAULT_ADDR=http://127.0.0.1:8200 pp-vault-dev vault status >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ "$tries" -lt 20 ] || { echo 'Vault did not become ready; inspect its logs.' >&2; exit 1; }
    sleep 1
  done
fi
export VAULT_TOKEN
VAULT_TOKEN=$(cat /tmp/pp-local/vault-token)
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN pp-vault-dev vault token lookup >/dev/null ||
  { unset VAULT_TOKEN; echo 'Vault token does not match this container.' >&2; exit 1; }
unset VAULT_TOKEN
```

Seed the demo API's **public sample key**, using Vault's own CLI *inside* the container:

```bash
export VAULT_TOKEN
VAULT_TOKEN=$(cat /tmp/pp-local/vault-token)
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN \
  pp-vault-dev vault kv put secret/demo-api-key value="sdfdsfdsfsdfdfsdfds"
unset VAULT_TOKEN
```

This lands at `secret/data/demo-api-key`, the default path the proxy's
HashiCorp backend expects. It's a known sample value; real credentials go in
through a hidden prompt (`guides/after-setup.md`, part 2).

---

## 4. Create and run the Proxy

### 4.1 Generate local keys

- A CA/signing private key (the proxy derives its own self-signed CA cert from this at boot).
- A reference keypair used to encrypt references. The proxy sends its public
  half to Passport during self-registration.

```bash
mkdir -p /tmp/pp-local
# Only generate if missing — regenerating ref.pem breaks existing secret
# references (see `guides/reference/concepts.md`).
[ -f /tmp/pp-local/ca.pem ]  || openssl genrsa -out /tmp/pp-local/ca.pem 2048
[ -f /tmp/pp-local/ref.pem ] || openssl genrsa -out /tmp/pp-local/ref.pem 2048
openssl rsa -in /tmp/pp-local/ref.pem -pubout -out /tmp/pp-local/reference-public-key.pem
```

### 4.2 Create the named proxy in the app

Check **Proxy settings** first. A fresh signup should have no proxy. If one
already exists, stop and inspect it; do not create another.

The developer opens **Proxy settings → Add proxy** in `<app_url>` and chooses a
unique name such as `passport-local-<your-name>`. The app shows its one-time
setup token. Keep that view open; do not paste the token into chat. If the
app still shows the older manual URL/public-key form, stop: the token flow
has not reached this environment. The agent does not create a second proxy
through the API.

Read the `org_...` team ID from `passport whoami --json` with the selected
`PASSPORT_DIR` exported. The app's setup view
also supplies a bundle issuer and, sometimes, an audience. Use those exact
non-secret values in the command below; omit the audience flag when it is
null. The app's proxy URL and management URL for local Docker are
`https://passport-proxy.localhost` and `http://passport-management.localhost`.
The proxy still listens on ports 8443 and 8081 inside Docker; host ports 443
and 80 give both URLs names without ports. Before starting, check that both
names resolve to loopback and that host ports 443 and 80 are free. Do not edit
`/etc/hosts`. If either check fails, use `https://localhost:8443` and
`http://localhost:8081` consistently for the public URLs, `passport setup`,
and the test requests; omit both 443 and 80 port mappings below.

```bash
for host in passport-proxy.localhost passport-management.localhost; do
  ping -c 1 "$host" 2>&1 | head -1 | grep -q '127\.0\.0\.1' ||
    { echo "$host does not resolve to IPv4 loopback" >&2; exit 1; }
done
```

### 4.3 Start the container

The developer runs this block in their own **bash or zsh terminal**. It
prints `Proxy registration token: ` and hides the pasted token. The token
is exported only inside the function, passed to Docker, then cleared from
the shell. Anyone with Docker-host access can inspect the container's
environment. Replace every angle-bracket value before running.

```bash
start_passport_proxy() {
  local PASSPORT_PROXY_TOKEN VAULT_TOKEN
  printf 'Proxy registration token: '
  IFS= read -rs PASSPORT_PROXY_TOKEN || { printf '\nInput cancelled.\n' >&2; return 1; }
  printf '\n'
  [ -n "$PASSPORT_PROXY_TOKEN" ] || { echo 'Empty token; proxy not started.' >&2; return 1; }
  VAULT_TOKEN=$(cat /tmp/pp-local/vault-token) || return 1
  export PASSPORT_PROXY_TOKEN VAULT_TOKEN
  docker run -d --name pp-proxy-local --network pp-net \
    -p 127.0.0.1:443:8443 -p 127.0.0.1:80:8081 \
    -p 8443:8443 -p 8081:8081 -v /tmp/pp-local:/tmp/pp-local \
    -e PASSPORT_PROXY_TOKEN -e PASSPORT_CONTROL_PLANE_URL="$PASSPORT_API" \
    -e PASSPORT_PROXY_PUBLIC_URL=https://passport-proxy.localhost \
    -e PASSPORT_PROXY_PUBLIC_MANAGEMENT_URL=http://passport-management.localhost \
    -e PASSPORT_PROXY_PRIVATE_KEY_PATH=/tmp/pp-local/ca.pem \
    -e PASSPORT_PROXY_REFERENCE_PRIVATE_KEY_PATH=/tmp/pp-local/ref.pem \
    -e PASSPORT_PROXY_JWKS_URL="$PASSPORT_API/api/v1/bundles/.well-known/jwks.json" \
    -e PASSPORT_PROXY_BUNDLE_ISSUER=<issuer-from-app> \
    -e PASSPORT_PROXY_ALLOWED_TEAM_IDS=<org-id-from-cli> \
    -e PASSPORT_PROXY_AUDIT_SINK=stdout \
    -e PASSPORT_PROXY_DATAPLANE_CERT_SANS=localhost,passport-proxy.localhost \
    -e PASSPORT_PROXY_VAULT_SOURCE=hashicorp \
    -e VAULT_ADDR=http://pp-vault-dev:8200 -e VAULT_TOKEN \
    "$PROXY_IMAGE_REF"
}
. /tmp/pp-local/target.env
if docker container inspect pp-proxy-local >/dev/null 2>&1; then
  [ "$(docker inspect -f '{{.Image}}' pp-proxy-local)" = "$(docker image inspect -f '{{.Id}}' "$PROXY_IMAGE_REF")" ] ||
    { echo 'Existing proxy uses a different image; ask before replacing it.' >&2; exit 1; }
  echo 'Existing proxy uses the pulled image; inspect its registration before reusing it.' >&2
else
  start_passport_proxy
fi
unset -f start_passport_proxy
```

Add `-e PASSPORT_PROXY_BUNDLE_AUDIENCE=<audience-from-app>` to `docker run`
only if the app supplies an audience. On a rerun, inspect and reuse the
existing proxy if it is the intended one; do not delete or replace it
automatically. A failed registration is a stop condition, not a reason to
fall back to manual registration.

`VAULT_ADDR` points at the Vault container by its Docker name (`pp-vault-dev`)
because both containers share the `pp-net` network — no `host.docker.internal`
needed. The Windows bind-mount and secret-entry path still need validation;
do not report that platform as tested.

### 4.4 Verify it booted and registered

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://passport-management.localhost/knockknock   # expect 200
curl -s -o /dev/null -w "%{http_code}\n" http://passport-management.localhost/readyz      # expect 200
docker logs pp-proxy-local 2>&1 | tail -30      # inspect errors; never paste a token into chat
```

`/readyz` confirms the process is serving, **not** that cloud registration
finished. Wait for the named proxy in **Proxy settings** to show **Healthy**.
If it remains Not connected, check `docker logs pp-proxy-local` for the
registration error and stop before creating references.

---

## 5. Create the demo access group, endpoint and access grant

The agent creates the demo through `<api_url>` after the proxy is **Healthy**.
The app calls its access group a **namespace** in API paths. Use a bare host
without a port. The reference is encrypted for the zone's **default** proxy.
For this local flow, the named proxy must be the zone's only proxy and its
default; stop if another proxy is present. Details: `guides/reference/concepts.md`.

### 5.1 Get a temporary public API key

Ask the developer to open `<app_url>/me/api-keys` as a team **admin** and
create a key named `passport-local-setup`. The app derives its permissions
from the creator's team role; a member's key cannot create the demo catalog.
The app shows the key once. Do not paste it
into chat. Have the developer set `PASSPORT_API_KEY` in the shell that launches
the agent, then start a new agent session from that shell. For example, in
bash or zsh:

```bash
printf 'Paste temporary Passport API key: '
IFS= read -rs PASSPORT_API_KEY; printf '\n'
export PASSPORT_API_KEY
claude
```

Use the developer's actual agent command in place of `claude`. In Windows
PowerShell, in the shell that launches the agent:

```powershell
$secure = Read-Host 'Temporary Passport API key' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $env:PASSPORT_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose() }
claude
```

The environment variable is plaintext in either shell; this avoids chat and
shell history, not access by the agent process.
The agent must only check whether the variable is set, never print its value.
If the agent is already running without the variable, stop and relaunch it;
exporting in a separate terminal does not update a running agent.

**Security tradeoff:** an environment variable is readable to this agent and
other processes with access to its environment. The LLM or a tool can
accidentally expose it. Use this key only for initial setup. After the e2e
test, follow step 7.1 to replace it with a key held in Vault and revoke the
bootstrap key. Do not put either key in a repo, command argument, or chat.

Check that `PASSPORT_API_KEY` is present, `PASSPORT_API` points to the selected
environment, and `passport whoami --json` reports the intended team. A public
API key cannot identify its team; the developer must confirm in the app that
they created it in that same team. A read of `/public/v1/namespaces` checks
that the key works. Do not infer admin permission from that read.

### 5.2 Build the demo through the public API

Before a mutation, inspect `/tmp/pp-local/ids.env` and list namespaces. Reuse
recorded objects only after verifying them. If the demo exists without a
record, stop and inspect rather than creating a duplicate. Confirm in the app
that the named proxy is Healthy, the zone's only proxy, and its default. The
public API does not expose proxy registration or its key; do not claim it
verified those details from an API response.

```bash
cp "$SKILL_DIR/scripts/local-api.sh" /tmp/pp-local/local-api.sh
. /tmp/pp-local/target.env
export PASSPORT_API PASSPORT_DIR
[ -n "${PASSPORT_API_KEY:-}" ] || { echo 'Start the agent with PASSPORT_API_KEY set.' >&2; exit 1; }
api() { bash /tmp/pp-local/local-api.sh "$@"; }
set -o pipefail
cd /tmp/pp-local
[ ! -e ids.env ] || { echo 'Existing demo IDs found; inspect and resume, do not recreate.' >&2; exit 1; }
api GET /public/v1/namespaces | jq -e '.body.pagination.nextCursor == null and ([.body.data[]? | select(.name == "passport-proxy-local-dev-e2e")] | length == 0)' >/dev/null ||
  { echo 'Demo namespace already exists; inspect before creating.' >&2; exit 1; }
record() { printf '%s=%s\n' "$1" "$2" >> ids.env; }
NS=$(api POST /public/v1/namespaces '{"name":"passport-proxy-local-dev-e2e","description":"Passport proxy e2e test"}' | jq -er '.body.data.id') || exit 1
record NS "$NS"
RG=$(api POST "/public/v1/namespaces/$NS/resource-groups" '{"name":"passport-demo.mock.postman.postman.dev","description":"Passport proxy e2e test","source":"manual"}' | jq -er '.body.data.id') || exit 1
record RG "$RG"
REF=$(api POST "/public/v1/namespaces/$NS/secret-references" '{"name":"demo","vaultType":"hashicorp","vaultKey":"demo-api-key"}' | jq -er '.body.data.id') || exit 1
record REF "$REF"
EP=$(api POST "/public/v1/namespaces/$NS/endpoints" "$(jq -nc --arg r "$REF" --arg g "$RG" '{method:"GET",host:"passport-demo.mock.postman.postman.dev",path:"/",secrets:[{label:"x-demo-api-key",secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -er '.body.data.id') || exit 1
record EP "$EP"
```

> **The resource group is what makes the endpoint visible in the web UI**
> (`concepts.md`, "Endpoints", also shows how to attach one to an existing
> endpoint).

Each successful create records its ID immediately. If a later call fails,
inspect recorded IDs and resume from the failed step; do not rerun the whole
block. Keep the named proxy when cleaning up the demo.

### 5.3 Request access and check its grant

The key belongs to the developer, so omit `email` and `requesterId`: the
request is for the key's owner. The service normally auto-approves an admin's
request for themselves. The agent verifies `approved` and finds the grant.
If it remains `pending`, ask the developer to decide it in the app. Never
call the approve endpoint for the agent's own request. `passport setup`
cannot issue access that does not exist.

```bash
. /tmp/pp-local/target.env; export PASSPORT_API
api() { bash /tmp/pp-local/local-api.sh "$@"; }
. /tmp/pp-local/ids.env
AR=$(api POST /public/v1/access-requests "$(jq -nc --arg ns "$NS" --arg ep "$EP" '{namespaceId:$ns,entities:[{type:"resource_endpoint",id:$ep}],message:"Local Passport demo",durationDays:7}')" | jq -er '.body.data.id') || exit 1
printf 'AR=%s\n' "$AR" >> /tmp/pp-local/ids.env
# Check immediately; if pending, wait for the developer's decision in the app.
api GET "/public/v1/access-requests/$AR" | jq -e '.body.data.status == "approved"' || exit 1
GR=$(api GET "/public/v1/access-grants?namespaceId=$NS&scopeType=endpoint&status=active" | jq -er --arg ar "$AR" --arg ep "$EP" '.body.data[] | select(.reason == ("access_request:" + $ar) and .scopeValue == $ep) | .id') || exit 1
printf 'GR=%s\n' "$GR" >> /tmp/pp-local/ids.env
```

Check `pagination.nextCursor` before concluding the grant is absent. Never
re-submit a request merely because approval is still pending. Show whether
`autoApproved` was true; do not imply a person approved it when the service
did so.

---

## 6. `passport setup`

```bash
. /tmp/pp-local/target.env; export PASSPORT_DIR
passport setup --management-url http://passport-management.localhost --proxy-url https://passport-proxy.localhost
```

Sanity-check what got embedded in your issued cert:

```bash
. /tmp/pp-local/target.env; export PASSPORT_DIR
passport whoami
```

It should show `allowedApiRefs` with your endpoint's method/host/path and
`{{vault:<your secret reference's UUID>}}`.

---

## 7. Test it end to end

The test calls the public **Passport demo API**,
`https://passport-demo.mock.postman.postman.dev`. It replies with the first 5
characters and the length of whatever `x-demo-api-key` it received. **It
accepts any key**, so `"authenticated"` alone proves nothing. The proof is
what it saw:

| The API received | Response |
|---|---|
| the real key (Passport injected it) | `"key":"sdfds**************","key_length":19` |
| the pointer, unchanged (no injection) | `"key":"{{vau*****…","key_length":46` |

```bash
. /tmp/pp-local/target.env; export PASSPORT_DIR
source /tmp/pp-local/ids.env                         # gives $REF (step 5), or take the UUID from `passport whoami`
D=$PASSPORT_DIR
curl -s http://passport-management.localhost/ca.pem -o /tmp/pp-local/proxy-ca.pem
R=$(curl -sS --proxy https://passport-proxy.localhost \
  --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem \
  --cacert /tmp/pp-local/proxy-ca.pem \
  -H "x-demo-api-key: {{vault:$REF}}" \
  https://passport-demo.mock.postman.postman.dev); echo "$R"
echo "$R" | jq -e '(.key // "")|startswith("sdfds")' >/dev/null 2>&1 && [ "$(echo "$R" | jq .key_length)" = 19 ] \
  && echo "INJECTED: the API received the real key" || echo "NOT injected (see the table above)"
```

`passport request "https://passport-demo.mock.postman.postman.dev" -H "x-demo-api-key: {{vault:$REF}}"`
does the same thing through the CLI.

- **`{{vault:...}}` must hold the reference's UUID**, not its name. Anything
  else passes through unchanged, with no error.
- **The demo API isn't in the daemon's `NO_PROXY` list,** so after setup the
  daemon form works too, with no flags: in a new terminal,
  `curl -sS -H "x-demo-api-key: {{vault:$REF}}" https://passport-demo.mock.postman.postman.dev`
  (`guides/after-setup.md`, part 2, explains the daemon).

`INJECTED` proves the **demo secret was substituted**. Also run the CLI form
and check its result; report the proxy process, Healthy registration, demo
substitution, CLI request and daemon separately. A daemon claim needs its own
test in a fresh terminal. Never infer that the app marked a step complete:
look at the app. Continue with step 7.1.

---

### 7.1 Replace the bootstrap API key

After the demo succeeds, the developer creates a second admin
key at `<app_url>/me/api-keys`, named `passport-local-ongoing`. They enter its
value into local Vault with `scripts/local-vault-put.sh passport-api-key` (or
the PowerShell equivalent). The agent never receives this new key. Vault dev
mode loses the key on restart, so it is not durable production storage.

While the bootstrap key still works, the agent creates a second resource
group, reference, and endpoint under the demo namespace. This endpoint covers
`* <api_url>/public/v1/*`; its `Authorization` slot maps to Vault key
`passport-api-key`. This is broad authority over the public API, matching the
admin key. Explain that scope to the developer before creating it.
Record each ID immediately as in step 5. Check for an
existing record before rerunning after a partial failure.

```bash
cd /tmp/pp-local; . ./target.env; export PASSPORT_API PASSPORT_DIR
. ./ids.env
api() { bash /tmp/pp-local/local-api.sh "$@"; }
case "$PASSPORT_API" in https://*) ;; *) echo 'Expected an HTTPS API URL.' >&2; exit 1;; esac
API_HOST=${PASSPORT_API#https://}; API_HOST=${API_HOST%%/*}
API_RG=$(api POST "/public/v1/namespaces/$NS/resource-groups" "$(jq -nc --arg h "$API_HOST" '{name:$h,description:"Passport API key rotation",source:"manual"}')" | jq -er '.body.data.id') || exit 1
printf 'API_RG=%s\n' "$API_RG" >> ids.env
API_REF=$(api POST "/public/v1/namespaces/$NS/secret-references" '{"name":"passport-api-key","vaultType":"hashicorp","vaultKey":"passport-api-key"}' | jq -er '.body.data.id') || exit 1
printf 'API_REF=%s\n' "$API_REF" >> ids.env
API_EP=$(api POST "/public/v1/namespaces/$NS/endpoints" "$(jq -nc --arg h "$API_HOST" --arg g "$API_RG" --arg r "$API_REF" '{method:"*",host:$h,path:"/public/v1/*",resourceGroupIds:[$g],secrets:[{label:"Authorization",secretReferenceId:$r}]}')" | jq -er '.body.data.id') || exit 1
printf 'API_EP=%s\n' "$API_EP" >> ids.env
API_AR=$(api POST /public/v1/access-requests "$(jq -nc --arg ns "$NS" --arg ep "$API_EP" '{namespaceId:$ns,entities:[{type:"resource_endpoint",id:$ep}],message:"Use Passport API key through local proxy",durationDays:7}')" | jq -er '.body.data.id') || exit 1
printf 'API_AR=%s\n' "$API_AR" >> ids.env
```

The agent checks for auto-approval as in step 5. If pending, the developer
decides it in the app. The agent records the new grant as `API_GR` and runs
`passport setup` again.
Then it tests the replacement key through the proxy, without printing the
response or the key:

```bash
cd /tmp/pp-local; . ./target.env; export PASSPORT_API PASSPORT_DIR
. ./ids.env
api() { bash /tmp/pp-local/local-api.sh "$@"; }
api GET "/public/v1/access-requests/$API_AR" | jq -e '.body.data.status == "approved"' >/dev/null || exit 1
API_GR=$(api GET "/public/v1/access-grants?namespaceId=$NS&scopeType=endpoint&status=active" | jq -er --arg ar "$API_AR" --arg ep "$API_EP" '.body.data[] | select(.reason == ("access_request:" + $ar) and .scopeValue == $ep) | .id') || exit 1
printf 'API_GR=%s\n' "$API_GR" >> ids.env
passport setup --management-url http://passport-management.localhost --proxy-url https://passport-proxy.localhost || exit 1
( unset PASSPORT_API_KEY; export PASSPORT_API_KEY_REF=$API_REF; api GET /public/v1/namespaces | jq -e '.body.data | type == "array"' >/dev/null ) || exit 1
```

The helper uses explicit proxy and certificate flags plus `--noproxy ''` for
the reference case. This avoids the normal `.usepassport.ai` proxy bypass.
If the app/CLI selected localhost ports instead of the named URLs, set
`PASSPORT_PROXY_URL` to that chosen proxy URL and use the matching setup URL.
The helper uses the current CLI certificate; run `passport setup` to refresh
it after expiry or a grant change. The approved grant expires after seven
days, so access must be requested and granted again before then.

Only after that check succeeds, the developer revokes `passport-local-setup`
in the app. Unset `PASSPORT_API_KEY`, set `PASSPORT_API_KEY_REF` to the new
reference UUID, and restart the agent with the reference variable. The local
API helper then sends that pointer through the proxy; it never reads the new
key. Verify a public API read through this helper before further writes. If the
replacement check fails, keep the bootstrap key until it is fixed and report
that rotation is incomplete. This rotation path is **not yet verified end to
end**; never claim the API key is protected by Vault without the proxied test.

### 7.2 Next: see what was made, add an API

Continue with **`guides/after-setup.md`**, which is shared with the AWS setup.
First guide the developer through **“See what was created”** in the app. The
tour shows proxy settings, namespace, resource group and endpoint, secret
reference, and access. Point to the objects actually created and the working
request, then offer **“Add your own API”** through the agent or the app.

---

## 8. Cleanup (only after you confirm you're done testing)

**Don't run this until you've actually said you're done.** It tears down
containers, the network, and (if full e2e was done) real objects in your
Passport Cloud team — none of that should happen just because a test
finished or a step succeeded.

If you added your own APIs, delete their recorded objects first through the
public API. Then delete the demo objects in dependency order. Do not run
cleanup without a working API key source (`PASSPORT_API_KEY` or the verified
`PASSPORT_API_KEY_REF`), and review any extra objects made during rotation.
For complete cleanup, use a fresh temporary admin key in `PASSPORT_API_KEY`:
deleting the endpoint that carries the Vault-held key removes the agent's
ability to make later API calls through that reference. Revoke the temporary
cleanup key in the app when deletion is verified.

```bash
cd /tmp/pp-local; . ./target.env; export PASSPORT_API PASSPORT_DIR
api() { bash /tmp/pp-local/local-api.sh "$@"; }
[ -f ids.env ] || { echo 'Demo IDs missing; inspect the app before cleanup.' >&2; exit 1; }
. ./ids.env
[ -z "${API_GR:-}" ] || api DELETE "/public/v1/access-grants/$API_GR"
[ -z "${GR:-}" ] || api DELETE "/public/v1/access-grants/$GR"
[ -z "${API_EP:-}" ] || api DELETE "/public/v1/endpoints/$API_EP"
[ -z "${EP:-}" ] || api DELETE "/public/v1/endpoints/$EP"
[ -z "${API_RG:-}" ] || api DELETE "/public/v1/resource-groups/$API_RG"
[ -z "${RG:-}" ] || api DELETE "/public/v1/resource-groups/$RG"
[ -z "${API_REF:-}" ] || api DELETE "/public/v1/secret-references/$API_REF"
[ -z "${REF:-}" ] || api DELETE "/public/v1/secret-references/$REF"
[ -z "${NS:-}" ] || api DELETE "/public/v1/namespaces/$NS"
passport daemon stop
```

Then:

```bash
docker rm -f pp-proxy-local pp-vault-dev
docker network rm pp-net
rm -rf /tmp/pp-local
```

`pp-vault-dev` was in-memory only, so removing it wipes the test secret
completely — nothing else to clean up. If you also created the namespace /
access proxy / grant in Passport Cloud purely for this test, delete them
there too (Access groups → delete; Proxy settings → remove).

---


## Troubleshooting and safety

- Troubleshooting (shared with the AWS setup): `guides/reference/troubleshooting.md`
- Why things work the way they do: `guides/reference/concepts.md`

## Safety notes

- Never paste a real secret's raw value, proxy token, Vault token or login token
  into chat, a commit, or a log you'll share — compare sha256 hashes instead
  (as step 7 does).
- `pp-vault-dev` is a disposable, in-memory dev server — fine for this test,
  never point it at anything you care about keeping.
- This setup registers a real namespace/endpoint/grant in your Passport Cloud
  team (step 5) — clean those up (step 8) once you're done, especially if this
  was a one-off test on a shared team.
