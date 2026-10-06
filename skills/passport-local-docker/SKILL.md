---
name: passport-local-docker
description: Set up and verify a Postman Passport proxy locally in Docker with a disposable local HashiCorp Vault — install the CLI, run the published proxy image, register it in Passport Cloud, and prove a secret resolves end to end through an echo server. Use when asked to run or test a Passport proxy locally or spin up a local vault for Passport.
---

# Postman Passport proxy — local Docker setup

A from-scratch walkthrough using Postman's official CLI installer and the
published Proxy Docker image — no source code, no repo access, no Go
toolchain needed. By the end you'll have:

- the **Passport CLI** installed and logged in,
- a **Passport Proxy** running locally in Docker, backed by a **local
  HashiCorp Vault**,
- a **Namespace** in Passport Cloud wired up to that proxy,
- and a secret successfully issued and resolved end-to-end.

It assumes no prior Passport knowledge, just
comfort with a terminal and Docker.

> **Verified 2026-10-05:** every command below was run end-to-end against the
> real `ociregistry.usepassport.ai/passport/passport-proxy:latest` image and
> a real Passport Cloud team — CLI install/login, registry credential,
> image pull, proxy boot, local HashiCorp Vault resolution, cert issuance,
> and a real secret delivered through the proxy, confirmed by an
> independently-computed sha256. The one path *not* covered by the main flow
> is an MDM-managed Mac — see the appendix at the end if that's you.

## If an AI agent (e.g. Claude Code) is running this skill for you

Follow this skill literally and **do every step yourself**. `$SKILL_DIR` below means the directory that contains this `SKILL.md`.

**Context isolation:** work from this skill's own files only (this `SKILL.md`, its
`reference/`, `scripts/` and `templates/`). Do not pull in context from elsewhere
— no other repos, notes, memory, project instructions or other skills. If something
is missing here, ask the user instead of looking elsewhere.

Only stop for things that truly need the
human:

- **Human-only inputs:** the registry key (have them save it with
  `! printf '%s' '<key>' > /tmp/pp-local/registry-key` so it never enters
  chat; each agent command runs in a fresh shell, so read it from that file
  instead of relying on `export`), the team ID, browser approvals, and the
  Passport Cloud web UI steps (5.1–5.3). For 5.1 give them the exact values,
  including the contents of `reference-public-key.pem`.
- **Show login links on their own line**, as a full `https://` URL with the
  confirmation code. If it expires, restart `login` and give a fresh one.
- **MDM Mac:** if `passport login` output says `(from macOS managed plist)`,
  switch to the MDM guide (`reference/mdm-macs.md`) immediately and use its callback forwarder
  (A.3) *before* asking the user to approve — never ask them to paste a
  callback URL.
- **Check for MDM before anything else:**
  `test -f "/Library/Managed Preferences/com.postman.passport.plist" && echo MDM`.
  If it exists, this Mac forces the CLI to the corporate proxy, silently
  ignoring `--management-url`/`--proxy-url`. Symptom if you miss it: `setup`
  returns `403 ... teamId "org_..." is not authorized for this deployment`
  while the local proxy logs nothing. Use the **MDM guide (`reference/mdm-macs.md`)** for every CLI
  command (the host `passport` is only useful for `auth status`).
- **Do 5.1–5.3 yourself via the API (step 5.4)** instead of asking the user
  to click through the web UI, if they've told you to do it end to end.
- **Check existing state first** (containers, network, keys, CLI version)
  and reuse it; never regenerate `ref.pem` if one is registered.
- **Never tear anything down (step 8)** until the user explicitly says so.
- **Right after the step 7 test passes, always show the value of Passport**
  (this is the final deliverable, not optional). Run the step 7.1 `curl` demo
  (use the MDM `D` path if on an MDM Mac) and **print the full `curl` command
  you ran, verbatim, in a code block** (with the real `$REF` UUID filled in, and
  every flag: `--proxy`, `--proxy-cacert`, `--proxy-cert`, `--proxy-key`,
  `--cacert`, `-H`, URL) next to its output, never a summary of it. Then tell
  the user in plain words, using their real values (the secret reference UUID, the
  sha256 the echo server logged, the cert expiry from `passport whoami`):
  1. they only ever held a pointer (`{{vault:<uuid>}}`), never the secret;
  2. their identity was a short-lived client cert scoped to the granted
     method/host/path;
  3. the proxy verified, resolved and injected the real value in flight;
  4. the destination received the real value (matching sha256) while their
     machine, shell history, and the agent's context never contained it.
  Close with the 7.1 result line: a person, script, or AI agent can call an API
  that needs a credential without ever holding it. Then remind them cleanup
  (step 8) is pending until they say so.

## What you need

- Docker Desktop (or another Docker daemon), running.
- A Passport Cloud account — sign up at [https://app.usepassport.ai](https://app.usepassport.ai) if you don't have one.
- `openssl`, `curl`, `jq` (all preinstalled on macOS; `jq` may need `brew install jq`).

---

## 1. Install and log in to the Passport CLI

Do this **before** getting a registry credential — the registry settings
page needs a team to exist first, and this step is how you find out whether
yours does.

> Already have the CLI? Check with `passport --version` and skip the install
> below if it prints a version.

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

This opens a browser to authenticate. Don't run `passport setup` yet — we
point it at our *local* proxy in step 6, not the production one.

> **On an MDM-managed Mac**, `passport login` will immediately auto-run
> `setup` against your org's *managed* production endpoints (from the macOS
> configuration profile), ignoring any `--management-url`/`--proxy-url` you
> later pass to `setup` — with no flag to override. If you see `setup` log
> endpoints you didn't ask for, that's this. Skip to the **MDM guide (`reference/mdm-macs.md`)** at
> the end of this skill instead of continuing linearly.

### 1.1 Confirm you have a team

If `login` fails with something like `authenticated login session has no
organization`, your account isn't part of any Passport **team** yet — and
nothing past this point works without one (no registry access, no team ID,
no namespace, no grants).

**Confirmed live 2026-10-05:** simply retrying `passport login` does **not**
surface any team-selection or team-creation screen in the browser, even on a
completely fresh account — the CLI's own error text ("select an organization
during `passport login`") is misleading here, don't chase it looking for a
prompt that won't appear.

The actual fix: go to **[https://app.usepassport.ai/dashboard](https://app.usepassport.ai/dashboard)**
and create a team there directly (the product calls this a "team", not an
"org" — matches "Team Settings" elsewhere in the UI). Once the team exists,
re-run `passport login`.

---

## 2. Get a registry credential

Now that you have a team, the Proxy image and Helm chart are served from
`ociregistry.usepassport.ai`, gated by a credential scoped to it.

- If you already have a `PASSPORT_REGISTRY_KEY`, skip ahead.
- Otherwise, create one yourself at **[https://app.usepassport.ai/org/registry](https://app.usepassport.ai/org/registry)**
  (Org Settings → Registry) — this needs admin access on your team.
- If you don't have admin access and don't already have a credential, **stop
  here and ask your team admin for one.** There is no other way to pull the
  Proxy image or chart — don't try to work around this step.

```bash
export PASSPORT_REGISTRY_KEY="<paste your credential here>"
```

---

## 3. Stand up a local HashiCorp Vault

A disposable, in-memory Vault dev server — nothing to clean up anywhere but
this machine.

```bash
docker network inspect pp-net >/dev/null 2>&1 || docker network create pp-net

# Re-running this skill? Remove any old Vault container first (it's in-memory, nothing is lost).
docker rm -f pp-vault-dev 2>/dev/null

docker run --cap-add=IPC_LOCK -d --name pp-vault-dev --network pp-net -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=root-token-for-local-dev' \
  -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
  hashicorp/vault server -dev

sleep 2
docker logs pp-vault-dev 2>&1 | tail -20     # expect "Vault server started!"
curl -s http://127.0.0.1:8200/v1/sys/health  # sealed:false, initialized:true
```

Seed one test secret, using Vault's own CLI *inside* the container:

```bash
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-for-local-dev \
  pp-vault-dev vault kv put secret/test-key value="some-local-test-value"
```

This lands at `secret/data/test-key` — the default path the proxy's
HashiCorp backend expects.

---

## 4. Pull and run the Proxy

### 4.1 Pull the image

```bash
printf '%s' "$PASSPORT_REGISTRY_KEY" | docker login ociregistry.usepassport.ai --username passport --password-stdin
docker pull ociregistry.usepassport.ai/passport/passport-proxy:latest
```

### 4.2 Generate local keys

- A CA/signing private key (the proxy derives its own self-signed CA cert from this at boot).
- A reference keypair (used to encrypt secrets end-to-end; you'll register its public half with Passport Cloud in step 6).

```bash
mkdir -p /tmp/pp-local
# Only generate if missing — regenerating ref.pem breaks existing secret
# references (see step 5.2's second gotcha).
[ -f /tmp/pp-local/ca.pem ]  || openssl genrsa -out /tmp/pp-local/ca.pem 2048
[ -f /tmp/pp-local/ref.pem ] || openssl genrsa -out /tmp/pp-local/ref.pem 2048
openssl rsa -in /tmp/pp-local/ref.pem -pubout -out /tmp/pp-local/reference-public-key.pem
```

### 4.3 Find your team ID

In Passport Cloud, open **Team Settings** (account menu, top right) — your
team ID is shown on that page (you already confirmed the team itself exists
back in step 1.1). You'll need the ID below.

> **Team ID = org ID.** Passport's "team" and "org" are the same thing. The
> team ID is the `org_...` value, and `passport auth status` prints it on the
> `org` line, so you can read it from the CLI after login instead of the UI.

### 4.4 Run the container

```bash
docker run -d --name pp-proxy-local --network pp-net \
  -p 8443:8443 -p 8081:8081 \
  -v /tmp/pp-local:/tmp/pp-local \
  -e PASSPORT_PROXY_PRIVATE_KEY_PATH=/tmp/pp-local/ca.pem \
  -e PASSPORT_PROXY_REFERENCE_PRIVATE_KEY_PATH=/tmp/pp-local/ref.pem \
  -e PASSPORT_PROXY_JWKS_URL=https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json \
  -e PASSPORT_PROXY_ALLOWED_TEAM_IDS="<your team ID from step 4.3>" \
  -e PASSPORT_PROXY_AUDIT_SINK=stdout \
  -e PASSPORT_PROXY_DATAPLANE_CERT_SANS=localhost \
  -e PASSPORT_PROXY_VAULT_SOURCE=hashicorp \
  -e VAULT_ADDR=http://pp-vault-dev:8200 \
  -e VAULT_TOKEN=root-token-for-local-dev \
  ociregistry.usepassport.ai/passport/passport-proxy:latest
```

`VAULT_ADDR` points at the Vault container by its Docker name (`pp-vault-dev`)
because both containers share the `pp-net` network — no `host.docker.internal`
needed, and this works the same on macOS, Linux, and Windows.

### 4.5 Verify it booted

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/knockknock   # expect 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8081/readyz      # expect 200
docker logs pp-proxy-local 2>&1 | grep -i vault   # should be silent — no "vault: none configured" warning
```

---

## 5. Register the proxy and create a Namespace in Passport Cloud

### 5.1 Register the access proxy

In Passport Cloud: **Team Settings → Access Proxies → Create Access Proxy**,
and enter:

| Field | Value |
|---|---|
| Proxy URL | `https://localhost:8443` |
| Management Host | `http://localhost:8081` |
| Proxy public key | contents of `/tmp/pp-local/reference-public-key.pem` |

### 5.2 Create a namespace and resource

On the **Home** page: **Create Namespace** → **Add Resources** → **Manual**,
and add:

- Method: `GET`
- Host: `localhost` **(no port — see gotcha below)**
- Path: `/echo`
- Secret: label it `x-key`, vault type **HashiCorp**, vault key `test-key`

> **Gotcha:** the proxy strips the port off the *request's* target host
> before matching, but does **not** strip the port off the endpoint's stored
> `host`. Register `host` as `localhost`, with no port — even though the
> actual request in step 7 goes to `https://localhost:9443/echo`. Registering
> `localhost:9443` will silently fail every request with `not authorized for
> vault refs`, even though `passport whoami` looks correct.
>
> **Second gotcha:** a secret reference's vault config is encrypted
> server-side under the public key of whichever proxy registration was
> active when you created it (step 5.1's "Proxy public key"). If you ever
> re-register the proxy with a *new* keypair (e.g. you regenerated
> `ref.pem`), old secret references become undecryptable by the new proxy —
> you'll see `failed to decrypt vault reference: <uuid>` with no further
> detail. Fix: create a fresh namespace/secret-reference/endpoint/grant under
> the currently-registered proxy, don't reuse ones from an earlier
> registration.

### 5.3 Grant yourself access

Still in Passport Cloud, request/grant access to the endpoint you just
created for your own user (as the account owner this is usually immediate).

### 5.4 Alternative: do 5.1–5.3 via the API (no web UI)

The web app is a front end for `https://api.usepassport.ai`; the CLI login
session's WorkOS token authenticates the same calls. The token is read from
`passportrc` and never printed. (On an MDM Mac, `~/.passport` on the host still
has a valid session from `passport login`; run `passport auth status` first to
refresh it.)

```bash
cp "$SKILL_DIR/scripts/passport-api.js" /tmp/pp-local/passport-api.js
api() { node /tmp/pp-local/passport-api.js "$@"; }
cd /tmp/pp-local

api GET /api/v2/tenant/config     # list existing proxy registrations
```

> **Stale registration:** if an earlier run left a proxy registration with the
> same endpoint but a different `publicKey` (e.g. `/tmp/pp-local` was wiped and
> `ref.pem` regenerated), don't reuse it — secret references created under it
> can't be decrypted by your current key. Register a fresh one below; making
> it `isDefault:true` flips the old one to non-default. Leave the old one in
> place unless the user says to delete it.

```bash
# 5.1 register the proxy, then confirm the stored key matches your local one
jq -n --rawfile k reference-public-key.pem --arg n "passport-proxy-local-dev" --arg e "https://localhost:8443" \
  '{encryptionMode:"B",publicKey:$k,proxyName:$n,proxyEndpoint:$e,managementHostUrl:null,isDefault:true}' > register-body.json
api POST /api/v2/tenant/config @register-body.json | tee register-out.json | jq -c '{status,proxyId:.body.data.proxyId}'
PROXY_ID=$(jq -r .body.data.proxyId register-out.json)
WANT=$(openssl pkey -pubin -in reference-public-key.pem -outform DER | openssl dgst -sha256 | awk '{print $NF}')
GOT=$(api GET /api/v2/tenant/config | jq -r --arg p "$PROXY_ID" '.body.data[]|select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$WANT" = "$GOT" ] && echo "key match" || echo "KEY MISMATCH"

# 5.2 namespace, secret reference, endpoint (host WITHOUT port, see gotcha above)
USER=$(node -e 'const fs=require("fs"),os=require("os"),p=require("path");const rc=JSON.parse(fs.readFileSync(p.join(os.homedir(),".passport","passportrc"),"utf8"));console.log(JSON.parse(Buffer.from(rc.login._profiles[0].workos.accessToken.split(".")[1],"base64url")).sub)')
NS=$(api POST /api/v1/namespaces '{"name":"passport-proxy-local-dev-e2e","description":"Passport proxy e2e test"}' | jq -r '.body.data.id')
REF=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"test-key"}')" | jq -r '.body.data.id')
EP=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" '{namespaceId:$ns,method:"GET",host:"localhost",path:"/echo",secrets:[{label:"x-key",secretReferenceId:$r}]}')" | jq -r '.body.data.id')

# 5.3 grant to yourself
GR=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy local e2e",validity:1}')" | jq -r '.body.data[0].id')
printf 'NS=%s\nREF=%s\nEP=%s\nGR=%s\n' $NS $REF $EP $GR | tee ids.env
```

`ids.env` keeps the IDs for step 7 (`REF`) and for cleanup. Cleanup deletes, in
order: `api DELETE /api/v2/access-grants/$GR`, `/api/v2/resource-endpoints/$EP`,
`/api/v2/secret-references/$REF`, `/api/v1/namespaces/$NS`.

---

## 6. `passport setup`

```bash
passport setup --management-url http://localhost:8081 --proxy-url https://localhost:8443
```

Sanity-check what got embedded in your issued cert:

```bash
passport whoami
```

It should show `allowedApiRefs` with your endpoint's method/host/path and
`{{vault:<your secret reference's UUID>}}`.

---

## 7. Test it end-to-end

**Never send a real-looking secret to a public host just to see it echoed
back.** Instead, stand up a tiny local HTTPS server that only logs a sha256
of what it received — proof the secret resolved, without ever printing it:

```bash
mkdir -p /tmp/pp-local/echo && cd /tmp/pp-local/echo

cat > san.cnf << 'EOF'
[req]
distinguished_name = req
x509_extensions = v3_req
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
EOF
openssl req -x509 -newkey rsa:2048 -keyout echo-key.pem -out echo-cert.pem -days 7 -nodes -subj "/CN=localhost" -extensions v3_req -config san.cnf

cat > server.js << 'EOF'
const https = require('https'), crypto = require('crypto'), fs = require('fs');
const options = { key: fs.readFileSync(__dirname + '/echo-key.pem'), cert: fs.readFileSync(__dirname + '/echo-cert.pem') };
https.createServer(options, (req, res) => {
  const val = req.headers['x-key'] || '';
  const sha256 = crypto.createHash('sha256').update(val).digest('hex');
  console.log(JSON.stringify({ path: req.url, method: req.method, 'x-key-sha256': sha256, 'x-key-len': val.length }));
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ ok: true, sha256 }));
}).listen(9443, '0.0.0.0', () => console.log('echo server listening on :9443'));
EOF
chmod 644 echo-key.pem
```

> **Don't run this server on the host.** The proxy runs in Docker, so
> `localhost:9443` from the proxy's point of view is its own container, not
> your Mac. Run the echo server as a sidecar that shares the proxy's network
> namespace (below). That's also why the endpoint host must be exactly
> `localhost` (step 5.2).

Now restart the proxy container with the echo server's self-signed cert
trusted for outbound connections, so the proxy's TLS MITM to `localhost:9443`
succeeds, then start the echo sidecar next to it (re-create the sidecar every
time you re-create the proxy):

```bash
docker rm -f pp-proxy-local
docker run -d --name pp-proxy-local --network pp-net \
  -p 8443:8443 -p 8081:8081 \
  -v /tmp/pp-local:/tmp/pp-local \
  -e SSL_CERT_FILE=/tmp/pp-local/echo/echo-cert.pem \
  -e PASSPORT_PROXY_PRIVATE_KEY_PATH=/tmp/pp-local/ca.pem \
  -e PASSPORT_PROXY_REFERENCE_PRIVATE_KEY_PATH=/tmp/pp-local/ref.pem \
  -e PASSPORT_PROXY_JWKS_URL=https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json \
  -e PASSPORT_PROXY_ALLOWED_TEAM_IDS="<your team ID>" \
  -e PASSPORT_PROXY_AUDIT_SINK=stdout \
  -e PASSPORT_PROXY_DATAPLANE_CERT_SANS=localhost \
  -e PASSPORT_PROXY_VAULT_SOURCE=hashicorp \
  -e VAULT_ADDR=http://pp-vault-dev:8200 \
  -e VAULT_TOKEN=root-token-for-local-dev \
  ociregistry.usepassport.ai/passport/passport-proxy:latest

# echo sidecar: shares the proxy's network namespace, so "localhost:9443" works
docker run -d --name pp-echo --network container:pp-proxy-local \
  -v /tmp/pp-local/echo:/echo -w /echo node:20 node server.js
```

Grab the secret reference's UUID from `passport whoami`'s `allowedApiRefs`
output (step 6; or `source /tmp/pp-local/ids.env` if you used step 5.4) and call it `REF`, then make the real request:

```bash
REF="<uuid from allowedApiRefs>"
passport request "https://localhost:9443/echo" -H "x-key: {{vault:$REF}}"
docker logs pp-echo 2>&1 | tail -1
echo -n "some-local-test-value" | shasum -a 256   # must equal x-key-sha256
```

> `{{vault:...}}` **must** contain the secret reference's UUID, not its
> friendly name — anything else streams through unsubstituted with no error.

If you see a sha256 hash logged by the echo server (not the literal string
`{{vault:...}}`), the secret was resolved and injected correctly — **that's
a complete, verified end-to-end setup.**

**Next, do step 7.1 right away** — it's the payoff of the whole setup (the same
call with a plain `curl`, showing you used a secret you never saw).

---

### 7.1 The value of Passport: use a secret you never see

`passport request` is a thin wrapper. This plain `curl` does the same thing
(verified; `D` is the CLI's credentials folder: `~/.passport`, or
`~/passport-cli-dl/.passport` on the MDM path):

```bash
source /tmp/pp-local/ids.env     # gives $REF, the secret reference UUID
D=~/passport-cli-dl/.passport
curl -s http://localhost:8081/ca.pem -o /tmp/pp-local/proxy-ca.pem

curl -sS --proxy https://localhost:8443 \
  --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem \
  --cacert /tmp/pp-local/proxy-ca.pem \
  -H "x-key: {{vault:$REF}}" \
  https://localhost:9443/echo
```

Output: `{"ok":true,"sha256":"a91317c5…a1f8"}`, the sha256 of the real secret
(`some-local-test-value`).

**How the secret was used without being seen**

1. **You only hold a pointer.** The header you sent is
   `x-key: {{vault:<uuid>}}`. The UUID names a secret; it isn't the secret.
   **Your machine, shell history and this skill never contain the value.**
2. **Your identity is a short-lived client cert.** `passport setup` issued
   `cert.pem` (about 5 min). It encodes *which* references you may use, on
   *which* method, host and path (`GET localhost/echo`). That's the grant
   from 5.3. **Access is scoped to exactly what you were granted.**
3. **The proxy checks, then swaps.** It verifies your cert, confirms the
   request matches your grant, decrypts the reference to learn where the
   secret lives (`test-key` in Vault), fetches it, and replaces
   `{{vault:<uuid>}}` with the real value *in flight*, only for the allowed
   host and path. **The real value is injected by the proxy, never by you.**
4. **The destination gets the real value.** The echo server received it
   (its hash matches ours). **Your side saw only the UUID going out and the
   response coming back.**

**Result: you (or a script, or an AI agent) can call an API that needs a
credential without ever holding that credential.** **It can't be leaked from
your machine**, **it works only on endpoints you were granted**, and
**access ends when the cert or grant expires.**

---

## 8. Cleanup (only after you confirm you're done testing)

**Don't run this until you've actually said you're done.** It tears down
containers, the network, and (if full e2e was done) real objects in your
Passport Cloud team — none of that should happen just because a test
finished or a step succeeded.

```bash
docker rm -f pp-echo pp-proxy-local pp-vault-dev
docker network rm pp-net
rm -rf /tmp/pp-local
```

`pp-vault-dev` was in-memory only, so removing it wipes the test secret
completely — nothing else to clean up. If you also created the namespace /
access proxy / grant in Passport Cloud purely for this test, delete them
there too (Namespace settings → delete; Team Settings → Access Proxies →
remove).

---


## Troubleshooting, MDM Macs, safety

- Troubleshooting table: `reference/troubleshooting.md`
- MDM-managed Macs (run the CLI in a Linux container): `reference/mdm-macs.md`

## Safety notes

- Never paste a real secret's raw value, your registry key, or a login token
  into chat, a commit, or a log you'll share — compare sha256 hashes instead
  (as step 7 does).
- `pp-vault-dev` is a disposable, in-memory dev server — fine for this test,
  never point it at anything you care about keeping.
- This setup registers a real namespace/endpoint/grant in your Passport Cloud
  team (step 5) — clean those up (step 8) once you're done, especially if this
  was a one-off test on a shared team.
