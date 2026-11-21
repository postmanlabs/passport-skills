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
and stop if any URL differs from the requested destination; do not overwrite
it silently. Keep its image reference at the public `:latest` address below.
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
PROXY_IMAGE_REF='public.ecr.aws/q4k6e3c0/passport/passport-proxy:latest'
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
- **The browser approvals** (`passport login`) are the user's. Show the login
  link on its own line, as a full `https://` URL with the confirmation code. If
  it expires, restart `login` and give a fresh one.
- **Read the team ID yourself** from `passport auth status` (step 4.2).
- **The developer creates the named proxy in the app.** The proxy registers
  itself with its one-time token. Create the demo resources through the API
  after the app reports Healthy; do not create a second proxy record.
- **MDM-managed Mac:** step 1 checks for it. If a sign shows up later anyway
  (`guides/reference/mdm-macs.md`, "How to tell"), switch then. On such a Mac
  the CLI ignores `--management-url`/`--proxy-url`, so every CLI command runs
  in that file's container.
- **Check existing state first** (containers, network, keys, CLI version) and
  reuse it; never regenerate `ref.pem` if one is registered.
- **After the step 7 test, continue with `guides/after-setup.md`**: show the
  app's “See what was created” step, then offer the agent or app path for
  adding the developer's own API.
  Cleanup (step 8) waits until the user explicitly asks.

## What you need

- Docker Desktop (or another Docker daemon), running.
- A Passport account and team; open `<app_url>/signup?origin=agent` for a new
  account, or open the selected `app_url` to sign in. The agent reads
  `APP_URL` from `target.env` and gives the developer the full link.
- `openssl`, `curl`, `jq`, `node` (`jq` and `node` may need installation).

---

## 1. Install and log in to the Passport CLI

Create or select a team in the app before logging in to the CLI. Keep
`?origin=agent` in the app link so its setup copy matches this path.

Check the active `passport --help` and all copies on PATH first. The Enterprise
CLI has `login` and `setup`; the Community CLI has `lens`. If the intended
Enterprise binary is already first on PATH, reuse it. Otherwise install from
the selected `cli_download_base_url`; ask before removing a shadowing binary.

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
`setup`. Check `passport login --help` for `--no-setup`.

On macOS or Linux, run `which -a passport`. The installer puts the CLI in
`/usr/local/bin/passport`. If another copy comes first, it shadows the new
install. Compare `/usr/local/bin/passport --help` with `passport --help` and
correct `PATH` before continuing. On Windows, use
`Get-Command passport -All` to find each copy. Do not delete a shadowing
binary without asking: a running daemon may use it.

Check for an MDM-managed Mac first (read-only):

```bash
passport daemon status 2>&1 | grep -E 'routing source' || echo "(no host daemon running: no sign either way)"
```

> **On an MDM-managed Mac** (`routing source managed` above, or later `login`
> auto-running `setup` against endpoints you didn't ask for), the CLI is pinned
> to your organisation's proxy and ignores `--management-url`/`--proxy-url`.
> Follow `guides/reference/mdm-macs.md` from here instead of logging in below:
> it runs the CLI in a Linux container, and tells you which steps change.

Then log in with the CLI installed from the selected URL:

```bash
. /tmp/pp-local/target.env; export PASSPORT_DIR
passport login --no-setup
```

This opens a browser to authenticate without configuring a proxy. Run explicit
`passport setup` only after the local proxy is Healthy (step 6).

### 1.1 Confirm you have a team

If `login` says `authenticated login session has no organization`, create a
Passport **team** at `<app_url>` and re-run `passport login --no-setup`.

Retrying `passport login` does **not** surface any team-selection or
team-creation screen, even on a fresh account. The CLI's own hint ("select an
organization during `passport login`") is misleading here; don't look for a
prompt that won't appear.

Confirm `passport auth status` reports the intended `org_...` team ID. Use
this ID for the proxy's allowed team list.

---

## 2. Pull the public proxy image

Pull `:latest` from public ECR without registry credentials. A fresh setup
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

Read the `org_...` team ID from `passport auth status` with the selected
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
node - <<'NODE'
for (const host of ['passport-proxy.localhost', 'passport-management.localhost']) {
  require('node:dns').lookup(host, { all: true }, (error, addresses) => {
    if (error || !addresses.some(({ address }) => address === '127.0.0.1')) {
      console.error(`${host} does not resolve to loopback`);
      process.exitCode = 1;
    }
  });
}
NODE
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

## 5. Create the demo access group, endpoint and grant

The agent creates the demo through `<api_url>` after the proxy is **Healthy**.
The app calls its access group a **namespace** in API paths. Use a bare host
without a port. The reference is encrypted for the zone's **default** proxy.
For this local flow, the named proxy must be the zone's only proxy and its
default; stop if another proxy is present. Details: `guides/reference/concepts.md`.

The CLI session authenticates these calls. The token is read from `passportrc`
and never printed. On an MDM Mac, set
`PASSPORT_DIR=~/passport-cli-dl/.passport` first.
Before running the create block, check `/tmp/pp-local/ids.env` and list the
team's namespaces. If the demo was already created, verify and reuse its
recorded IDs; if objects exist without that record, stop and inspect them
instead of creating duplicates.

```bash
cp "$SKILL_DIR/scripts/passport-api.js" /tmp/pp-local/passport-api.js
. /tmp/pp-local/target.env
export PASSPORT_API PASSPORT_DIR
api() { node /tmp/pp-local/passport-api.js "$@"; }
set -o pipefail
cd /tmp/pp-local
PROXY_NAME='<exact name created in the app>'
PROXY_LIST=$(api GET /api/v2/tenant/config) || exit 1
PROXY_ID=$(printf '%s' "$PROXY_LIST" | jq -er --arg n "$PROXY_NAME" \
  '.body.data as $p | if ($p|length)==1 and $p[0].proxyName==$n and
   $p[0].status=="healthy" and $p[0].isDefault==true and
   ($p[0].publicKey // "")!="" then $p[0].proxyId
   else error("expected one Healthy default proxy with this name") end') || exit 1
WANT=$(openssl pkey -pubin -in reference-public-key.pem -outform DER | openssl dgst -sha256 | awk '{print $NF}')
GOT=$(printf '%s' "$PROXY_LIST" | jq -r --arg p "$PROXY_ID" \
  '.body.data[] | select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$WANT" = "$GOT" ] || { echo 'Registered key differs from local ref.pem; stop.' >&2; exit 1; }
# Create the demo in its own namespace; do not reuse it for the developer's API.
PP_USER=$(node -e 'const fs=require("fs"),os=require("os"),p=require("path");const rc=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR||p.join(os.homedir(),".passport"),"passportrc"),"utf8"));console.log(JSON.parse(Buffer.from(rc.login._profiles[0].workos.accessToken.split(".")[1],"base64url")).sub)')
NS=$(api POST /api/v1/namespaces '{"name":"passport-proxy-local-dev-e2e","description":"Passport proxy e2e test"}' | jq -er '.body.data.id') || exit 1
RG=$(api POST /api/v1/namespaces/$NS/resource-groups '{"name":"passport-demo.mock.postman.postman.dev","description":"Passport proxy e2e test","source":"manual"}' | jq -er '.body.data.id') || exit 1
REF=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"demo-api-key"}')" | jq -er '.body.data.id') || exit 1
EP=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" --arg g "$RG" '{namespaceId:$ns,method:"GET",host:"passport-demo.mock.postman.postman.dev",path:"/",secrets:[{label:"x-demo-api-key",secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -er '.body.data.id') || exit 1
GR=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy local e2e",validity:1}')" | jq -er '.body.data[0].id') || exit 1
MISSING=; for v in PROXY_ID NS RG REF EP GR; do eval "x=\${$v:-}"; case "$x" in ''|null) MISSING="$MISSING $v";; esac; done
if [ -z "$MISSING" ]; then printf 'PROXY_ID=%s\nNS=%s\nRG=%s\nREF=%s\nEP=%s\nGR=%s\n' "$PROXY_ID" "$NS" "$RG" "$REF" "$EP" "$GR" | tee ids.env
else echo "INCOMPLETE, missing:$MISSING. Delete any IDs that were created, run 'passport auth status' (refreshes the token), re-run." >&2; fi
```

> **The resource group is what makes the endpoint visible in the web UI**
> (`concepts.md`, "Endpoints", also shows how to attach one to an existing
> endpoint).

`ids.env` keeps the IDs for step 7 and explicitly requested cleanup. Do not
delete the named proxy merely because the demo test ended.

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
D=$PASSPORT_DIR                                      # MDM: ~/passport-cli-dl/.passport
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

### 7.1 Next: show the value, add an API

Continue with **`guides/after-setup.md`**, which is shared with the AWS setup.
Use its *Local Docker* load block. First guide the developer through **“See
what was created”** in the app, then offer to add their own API through the
agent or the app.

---

## 8. Cleanup (only after you confirm you're done testing)

**Don't run this until you've actually said you're done.** It tears down
containers, the network, and (if full e2e was done) real objects in your
Passport Cloud team — none of that should happen just because a test
finished or a step succeeded.

If you added APIs through the agent (`guides/after-setup.md`, part 2), delete
those first (grant → endpoint → group → secret reference → namespace), and
stop the daemon:

```bash
cd /tmp/pp-local; . ./target.env; export PASSPORT_API PASSPORT_DIR   # MDM: set PASSPORT_DIR=~/passport-cli-dl/.passport
api() { node /tmp/pp-local/passport-api.js "$@"; }
[ -f resources.env ] && while read -r m u rest; do
  eval "$rest"   # sets NS_N NS_CREATED RG REF EP GR
  api DELETE /api/v2/access-grants/$GR; api DELETE /api/v2/resource-endpoints/$EP
  api DELETE /api/v1/resource-groups/$RG; api DELETE /api/v2/secret-references/$REF
done < resources.env
# Remove a shared, newly created access group only after all its APIs are gone.
[ -f resources.env ] && sed -n 's/.*NS_CREATED=1 .*/&/p' resources.env | sed -n 's/.*NS_N=\([^ ]*\).*/\1/p' | sort -u | while read -r NS_ID; do
  api DELETE /api/v1/namespaces/$NS_ID
done
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


## Troubleshooting, MDM Macs, safety

- Troubleshooting (shared with the AWS setup): `guides/reference/troubleshooting.md`
- MDM-managed Macs (run the CLI in a Linux container): `guides/reference/mdm-macs.md`
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
