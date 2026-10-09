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

> **Status:** verified end to end on 2026-10-05, and on an MDM Mac (container
> CLI path) with the public demo API on 2026-10-07. Details:
> `guides/reference/verification.md`.

## If an AI coding agent is running this guide for you

The ground rules in `SKILL.md` apply. This section adds only what is specific
to the local setup.

Follow this guide literally and **do every step yourself**. `$SKILL_DIR` below means
the absolute path of this skill's folder (the folder containing
`SKILL.md`); `scripts/` and `templates/` live there. Substitute the real path:
each command runs in a fresh shell.

- **The registry key is the only human-only input here.** Have the user save it
  in their own terminal, so it never enters chat:
  `mkdir -p /tmp/pp-local && printf '%s' '<key>' > /tmp/pp-local/registry-key`.
  Read it from that file instead of relying on `export`.
- **The browser approvals** (`passport login`) are the user's. Show the login
  link on its own line, as a full `https://` URL with the confirmation code. If
  it expires, restart `login` and give a fresh one.
- **Read the team ID yourself** from `passport auth status` (4.3).
- **Do 5.1–5.3 through the API (5.4)**, never by asking the user to click
  through the web UI. The web UI steps are there for people following by hand.
- **MDM-managed Mac:** step 1 checks for it. If a sign shows up later anyway
  (`guides/reference/mdm-macs.md`, "How to tell"), switch then. On such a Mac
  the CLI ignores `--management-url`/`--proxy-url`, so every CLI command runs
  in that file's container.
- **Check existing state first** (containers, network, keys, CLI version) and
  reuse it; never regenerate `ref.pem` if one is registered.
- **Right after the step 7 test passes, continue with `guides/after-setup.md`**
  (mandatory): its short handoff first, then the offer to add their own API.
  Cleanup (step 8) waits until the user explicitly asks.

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

Check for an MDM-managed Mac first (read-only):

```bash
passport daemon status 2>&1 | grep -E 'routing source' || echo "(no host daemon running: no sign either way)"
```

> **On an MDM-managed Mac** (`routing source managed` above, or later `login`
> auto-running `setup` against endpoints you didn't ask for), the CLI is pinned
> to your organisation's proxy and ignores `--management-url`/`--proxy-url`.
> Follow `guides/reference/mdm-macs.md` from here instead of logging in below:
> it runs the CLI in a Linux container, and tells you which steps change.

Then log in:

```bash
passport login
```

This opens a browser to authenticate. Don't run `passport setup` yet — we
point it at our *local* proxy in step 6, not the production one.

### 1.1 Confirm you have a team

If `login` fails with something like `authenticated login session has no
organization`, your account isn't part of any Passport **team** yet — and
nothing past this point works without one (no registry access, no team ID,
no namespace, no grants).

Retrying `passport login` does **not** surface any team-selection or
team-creation screen, even on a fresh account. The CLI's own hint ("select an
organization during `passport login`") is misleading here; don't look for a
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

# Re-running this guide? Remove any old Vault container first (it's in-memory, nothing is lost).
docker rm -f pp-vault-dev 2>/dev/null

docker run --cap-add=IPC_LOCK -d --name pp-vault-dev --network pp-net -p 8200:8200 \
  -e 'VAULT_DEV_ROOT_TOKEN_ID=root-token-for-local-dev' \
  -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200' \
  hashicorp/vault server -dev

sleep 2
docker logs pp-vault-dev 2>&1 | tail -20     # expect "Vault server started!"
curl -s http://127.0.0.1:8200/v1/sys/health  # sealed:false, initialized:true
```

Seed the demo API's **public sample key**, using Vault's own CLI *inside* the container:

```bash
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-for-local-dev \
  pp-vault-dev vault kv put secret/demo-api-key value="sdfdsfdsfsdfdfsdfds"
```

This lands at `secret/data/demo-api-key`, the default path the proxy's
HashiCorp backend expects. It's a known sample value; real credentials go in
through a hidden prompt (`guides/after-setup.md`, part 2).

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
- Host: `passport-demo.mock.postman.postman.dev` **(no port; see the gotcha below)**
- Path: `/`
- Secret: label it `x-demo-api-key`, vault type **HashiCorp**, vault key `demo-api-key`

> **Two gotchas** (details in `guides/reference/concepts.md`):
> - Register `host` **without a port**. `example.com:443` silently fails every
>   request with `not authorized for vault refs`, even though `passport whoami`
>   looks correct.
> - A secret reference is encrypted for the team's **default** proxy when you
>   create it. If another proxy is the default, or you later re-register with a
>   new key, it fails with `failed to decrypt vault reference: <uuid>`. Make
>   yours the default while you create references (5.4 does this).

### 5.3 Grant yourself access

Still in Passport Cloud, request/grant access to the endpoint you just
created for your own user (as the account owner this is usually immediate).

### 5.4 Alternative: do 5.1–5.3 via the API (no web UI)

The web app is a front end for `https://api.usepassport.ai`; the CLI login
session's WorkOS token authenticates the same calls. The token is read from
`passportrc` and never printed. On an MDM Mac, use the container's login:
`export PASSPORT_DIR=~/passport-cli-dl/.passport` first.

```bash
cp "$SKILL_DIR/scripts/passport-api.js" /tmp/pp-local/passport-api.js
api() { node /tmp/pp-local/passport-api.js "$@"; }
cd /tmp/pp-local

api GET /api/v2/tenant/config     # list existing proxy registrations
```

> **The default proxy and stale registrations:** the block below makes yours
> the team default while it creates the reference, then restores the previous
> default. If an earlier run left a registration with the same endpoint but a
> different `publicKey`, don't reuse it: register a fresh one, and leave the
> old one unless the user says to delete it. Why:
> `guides/reference/concepts.md`, "Secret references are encrypted for the
> team's default proxy".

```bash
# 5.1 remember the team's current default, register ours AS the default (references are encrypted for it)
PREV_DEFAULT=$(api GET /api/v2/tenant/config | jq -r '[.body.data[]|select(.isDefault==true)][0].proxyId // empty')
jq -n --rawfile k reference-public-key.pem --arg n "passport-proxy-local-dev" --arg e "https://localhost:8443" \
  '{encryptionMode:"B",publicKey:$k,proxyName:$n,proxyEndpoint:$e,managementHostUrl:null,isDefault:true}' > register-body.json
api POST /api/v2/tenant/config @register-body.json | tee register-out.json | jq -c '{status,proxyId:.body.data.proxyId}'
PROXY_ID=$(jq -r .body.data.proxyId register-out.json)
WANT=$(openssl pkey -pubin -in reference-public-key.pem -outform DER | openssl dgst -sha256 | awk '{print $NF}')
GOT=$(api GET /api/v2/tenant/config | jq -r --arg p "$PROXY_ID" '.body.data[]|select(.proxyId==$p).publicKey' | openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')
[ "$WANT" = "$GOT" ] && echo "key match" || echo "KEY MISMATCH"

# 5.2 namespace, resource group, secret reference, endpoint (host WITHOUT port, see gotcha above)
PP_USER=$(node -e 'const fs=require("fs"),os=require("os"),p=require("path");const rc=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR||p.join(os.homedir(),".passport"),"passportrc"),"utf8"));console.log(JSON.parse(Buffer.from(rc.login._profiles[0].workos.accessToken.split(".")[1],"base64url")).sub)')
NS=$(api POST /api/v1/namespaces '{"name":"passport-proxy-local-dev-e2e","description":"Passport proxy e2e test"}' | jq -r '.body.data.id')
RG=$(api POST /api/v1/namespaces/$NS/resource-groups '{"name":"passport-demo.mock.postman.postman.dev","description":"Passport proxy e2e test","source":"manual"}' | jq -r '.body.data.id')
REF=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" '{namespaceId:$ns,name:"demo",vaultType:"hashicorp",vaultKey:"demo-api-key"}')" | jq -r '.body.data.id')
EP=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg r "$REF" --arg g "$RG" '{namespaceId:$ns,method:"GET",host:"passport-demo.mock.postman.postman.dev",path:"/",secrets:[{label:"x-demo-api-key",secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -r '.body.data.id')

# 5.3 grant to yourself
GR=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport proxy local e2e",validity:1}')" | jq -r '.body.data[0].id')
# restore the previous default, if there was one (our reference stays decryptable)
[ -n "$PREV_DEFAULT" ] && api PUT /api/v2/tenant/config/$PREV_DEFAULT '{"isDefault":true}' | jq -c .status
# record only a complete set (a failed call gives an empty value or "null"; api also prints it as "api: … -> <status>")
MISSING=; for v in PROXY_ID NS RG REF EP GR; do eval "x=\${$v:-}"; case "$x" in ''|null) MISSING="$MISSING $v";; esac; done
if [ -z "$MISSING" ]; then printf 'PROXY_ID=%s\nPREV_DEFAULT=%s\nNS=%s\nRG=%s\nREF=%s\nEP=%s\nGR=%s\n' $PROXY_ID "$PREV_DEFAULT" $NS $RG $REF $EP $GR | tee ids.env
else echo "INCOMPLETE, missing:$MISSING. Delete any IDs that were created, run 'passport auth status' (refreshes the token), re-run." >&2; fi
```

> **The resource group is what makes the endpoint visible in the web UI**
> (`concepts.md`, "Endpoints", also shows how to attach one to an existing
> endpoint).

`ids.env` keeps the IDs for step 7 (`REF`) and for cleanup. Cleanup deletes, in
order: `api DELETE /api/v2/access-grants/$GR`, `/api/v2/resource-endpoints/$EP`,
`/api/v1/resource-groups/$RG`, `/api/v2/secret-references/$REF`, `/api/v1/namespaces/$NS`.

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
source /tmp/pp-local/ids.env                         # gives $REF (step 5.4), or take the UUID from `passport whoami`
D=~/.passport                                        # MDM: ~/passport-cli-dl/.passport
curl -s http://localhost:8081/ca.pem -o /tmp/pp-local/proxy-ca.pem
R=$(curl -sS --proxy https://localhost:8443 \
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

`INJECTED` means **a complete, verified end-to-end setup.** Continue with step 7.1.

---

### 7.1 Next: show the value, add an API

Continue with **`guides/after-setup.md`**, which is shared with the AWS setup.
Use its *Local Docker* load block. It covers the handoff message and adding
your own API.

---

## 8. Cleanup (only after you confirm you're done testing)

**Don't run this until you've actually said you're done.** It tears down
containers, the network, and (if full e2e was done) real objects in your
Passport Cloud team — none of that should happen just because a test
finished or a step succeeded.

If you added APIs (`guides/after-setup.md`, part 2), delete those first (grant → endpoint →
group → secret reference), and stop the daemon:

```bash
cd /tmp/pp-local; export PASSPORT_DIR=~/.passport   # MDM: ~/passport-cli-dl/.passport
api() { node /tmp/pp-local/passport-api.js "$@"; }
[ -f resources.env ] && while read -r m u rest; do
  eval "$rest"   # sets RG REF EP GR
  api DELETE /api/v2/access-grants/$GR; api DELETE /api/v2/resource-endpoints/$EP
  api DELETE /api/v1/resource-groups/$RG; api DELETE /api/v2/secret-references/$REF
done < resources.env
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
there too (Namespace settings → delete; Team Settings → Access Proxies →
remove).

---


## Troubleshooting, MDM Macs, safety

- Troubleshooting (shared with the AWS setup): `guides/reference/troubleshooting.md`
- MDM-managed Macs (run the CLI in a Linux container): `guides/reference/mdm-macs.md`
- Why things work the way they do: `guides/reference/concepts.md`

## Safety notes

- Never paste a real secret's raw value, your registry key, or a login token
  into chat, a commit, or a log you'll share — compare sha256 hashes instead
  (as step 7 does).
- `pp-vault-dev` is a disposable, in-memory dev server — fine for this test,
  never point it at anything you care about keeping.
- This setup registers a real namespace/endpoint/grant in your Passport Cloud
  team (step 5) — clean those up (step 8) once you're done, especially if this
  was a one-off test on a shared team.
