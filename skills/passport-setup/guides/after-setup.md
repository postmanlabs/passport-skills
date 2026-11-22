# After setup: show the value, add an API

This is shared by both setups. Use it once the end-to-end test in your setup
guide passes:
- **Local Docker:** `guides/local-docker.md` step 7 printed `INJECTED`.
- **AWS:** `guides/aws-single-instance.md` step 8.4 (success checklist) passed.

For **local Docker**, report each verified check, then point the developer to
the app's **“See what was created”** step. After they inspect the demo, offer
to add their own API either with the agent or in the app. For **AWS**, keep the
existing handoff and offer to add an API. Never create duplicate objects when
the developer uses the app.

Cleanup stays in each setup guide, and runs only when the user explicitly asks.

## 0. Load your setup (start every command block with one of these)

The rest of this file uses the same names for both setups.

**Local Docker:**

```bash
cd /tmp/pp-local; . ./ids.env; W=/tmp/pp-local
. ./target.env; export PASSPORT_API PASSPORT_DIR
api() { bash /tmp/pp-local/local-api.sh "$@"; }
PROXY=https://localhost:8443; MGMT=http://localhost:8081; DESTCA=/tmp/pp-local/proxy-ca.pem; D=$PASSPORT_DIR
```

**AWS:**

```bash
SKILL_DIR=<skill dir>; . "$SKILL_DIR/scripts/env.sh"; cd /tmp/pp-aws; W=/tmp/pp-aws
PROXY=https://$PROXY_HOST:8443; MGMT=https://$CF_DOMAIN; DESTCA=/tmp/pp-aws/proxy-ca.pem; D=$PASSPORT_DIR
```

| Name | Meaning |
|---|---|
| `$PROXY` | the Passport proxy's data plane, used with `--proxy` |
| `$MGMT` | the management URL, used with `passport setup --management-url` |
| `$DESTCA` | the proxy's CA as downloaded in your setup guide, used with `--cacert` |
| `$D` | the CLI's credentials folder: `cert.pem`, `key.pem`, `ca.pem` |
| `$NS`, `$PROXY_ID`, `$REF`, `$GR` | IDs from the demo (namespace, proxy, secret reference, grant); `$PREV_DEFAULT` is used only by the AWS guide |
| `$W/resources.env` | one line per API added in part 2, which cleanup reads |

**Refresh your certificate** after any grant change:
- **local:** `passport setup --management-url $MGMT --proxy-url $PROXY`;
- **AWS:** `cli setup --management-url $MGMT --proxy-url $PROXY`.

**[you] steps that differ by setup:**

| Step | Local Docker | AWS |
|---|---|---|
| Store a secret at a hidden prompt | Give the developer `bash <absolute skill path>/scripts/local-vault-put.sh <vault-key>` on macOS/Linux or the PowerShell script below on Windows. They enter the value in their terminal. | In their terminal: `aws ssm start-session --target <INSTANCE> --region <AWS_REGION> --profile <AWS_PROFILE>`, then `sudo passport-vault-put <vault-key>`, then `exit` |
| Check a stored value without printing it | Use the unique token from `/tmp/pp-local/vault-token` with `docker exec ... vault kv get -field=value secret/<vault-key> \| shasum -a 256`; do not print the value. | In a session: `sudo passport-vault-sha256 <vault-key>` |

Both Vaults are dev mode and **in memory**. Restarting the Vault container
erases every stored secret, so store them again afterwards.

For Windows PowerShell, the developer runs
`& "<absolute skill path>/scripts/local-vault-put.ps1" <vault-key>` instead.
Both scripts prompt without echoing the value, read the restricted local Vault
token file, and send the secret through standard input to the Vault CLI inside
`pp-vault-dev`. The agent waits for “stored” and never receives the value.

---

## 1. Handoff: show the value, briefly (mandatory)

One short message, with the real values. **Lead with the value**, and keep the
details out unless the user asks. For local setup, report process readiness,
Healthy registration, demo substitution, CLI request and daemon as separate
checks; mark the daemon unverified unless its request ran successfully. If
any check failed, say which one first.

> **✅ The demo request used a key stored in local Vault.**
> This is a public sample key, so the test proves substitution, not that the
> agent could not know this particular value. For your own API, you enter the
> secret yourself and I use only its reference.
>
> | | Without Passport | With Passport |
> |---|---|---|
> | Your script or AI agent holds | the real API key | only a pointer: `{{vault:<REF>}}` |
> | If it leaks | anyone can use the key, anywhere | useless outside the one granted endpoint |
> | To revoke or rotate | update every laptop, script and CI job | change it once, centrally |
>
> **What I ran**, exactly (copy-paste works):
> ```bash
> curl -sS --proxy https://localhost:8443 \
>   --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem --proxy-key ~/.passport/key.pem \
>   --cacert /tmp/pp-local/proxy-ca.pem \
>   -H "x-demo-api-key: {{vault:d625f364-3d76-4a14-9db5-b217cbfd3e23}}" \
>   https://passport-demo.mock.postman.postman.dev
> ```
> **What came back:**
> ```
> {"status":"authenticated","key":"sdfds**************","key_length":19}
> ```
> The API saw a 19-character key starting `sdfds`, which is the real key. If the
> pointer had reached it unchanged, it would show `"key":"{{vau…","key_length":46`.
>
> **How this request was allowed:**
> ```
> your certificate      user_01M479T6…, valid until 17:23 UTC (from `passport setup`)
>  └─ access grant      fc78372c…   you may call ↓ for 1 day
>     └─ endpoint       cec48684…   GET passport-demo.mock.postman.postman.dev /
>        └─ header x-demo-api-key ← secret reference d625f364… ("demo")
>                                    └─ Vault  secret/demo-api-key, on the proxy; never sent to you
> ```
> The proxy checked each link before it swapped the pointer for the real key.
>
> **Run it yourself:** open a **new terminal window**, paste this and press Enter:
> ```bash
> export HTTPS_PROXY=http://127.0.0.1:10144
> export SSL_CERT_FILE=~/.passport/ca.pem
> curl -sS -H "x-demo-api-key: {{vault:d625f364-3d76-4a14-9db5-b217cbfd3e23}}" https://passport-demo.mock.postman.postman.dev; echo
> ```
> You should get the same `"key":"sdfds**************","key_length":19`. No
> `--proxy`, no certificate flags: the Passport daemon holds your certificate.
> (If you see `"{{vau…",46`, the `export` lines didn't apply in that window.)
>
> **Local:** Open **“See what was created”** in the Passport app to inspect
> this demo. Then choose: “I can add your own API, or you can follow the
> app's guided steps.” If I add it, tell me its URL and how it takes the key;
> you'll enter the key in your terminal, not in chat.
>
> **AWS:** Want to try your own API? Tell me its URL and how it takes the key.
>
> <sub>Footer, one line: where it runs (local Docker, or proxy `<NAME>` on EC2 at about $0.70/day) · certificate renewal · "nothing is deleted until you ask".</sub>

(The IDs, paths and time above are from a real run; use yours.)

Rules for this message:
- **"What I ran" is the exact command, verbatim:** every flag and real value,
  no `…` and no variables. "What came back" is its real output. Never summarise
  either.
- **The access chain uses the real IDs:** grant → endpoint (method, host,
  path) → header → secret reference → Vault key, plus the certificate's expiry
  from `passport whoami`. Shorten IDs to 8 characters plus `…`.
- **"Run it yourself" is mandatory, and you must run it first.** Run that exact
  block yourself in a clean shell:
  `env -i HOME=$HOME PATH=/usr/bin:/bin:/usr/local/bin zsh -c '<the block>'`.
  Give it to the user only if it returned the same result. Use the variant for
  their platform:

  | User's machine | Block to give |
  |---|---|
  | **macOS**, after `passport setup` installed the daemon | the block above. New terminal windows already have these variables, and the `export` lines just make that explicit |
  | **Windows** (PowerShell), after `passport setup` | `$env:HTTPS_PROXY="http://127.0.0.1:10144"; curl.exe -sS -H "x-demo-api-key: {{vault:<REF>}}" https://passport-demo.mock.postman.postman.dev`. `curl.exe` uses the Windows certificate store, so run `passport ca install` first. *Unverified* |
  | **Linux** | first `passport daemon start` (setup can't install the daemon on Linux), then the block above |

  If the daemon isn't running, give the explicit form ("What I ran") as the
  thing to copy, and say why.
- **The proof command.** Show the daemon form (no flags, as above) if the
  daemon is running. Otherwise show the explicit form you actually ran
  (`curl --proxy $PROXY … -H "x-demo-api-key: …" https://passport-demo…`), and
  say the daemon isn't set up.
- **One next step:** for local, inspect “See what was created,” then choose
  agent or app for their own API; for AWS, offer their own API (part 2).
- **Be honest about the demo key.** It's the demo API's public sample key, so it
  appears in the guides. With their own key, the value goes only into a hidden
  prompt, and never into their shell history or this conversation. Say so if
  they ask, or if it's relevant.
- **On request only:** the full `curl` with every flag, what each flag does,
  certificate expiry and renewal, and the daemon (part 2, step 5).

---

## How to report every step after this (part 2)

For each step you run, show three things, in this order:
1. **What I ran:** the exact commands, verbatim, with real values. If several
   commands ran (create objects, refresh the certificate, the request), show
   them all, in order. For Passport API calls, show the call line
   (`api POST /api/v2/access-grants …`) and the ID it returned.
2. **What came back:** the real output. Trim long output, but never paraphrase it.
3. **What it proves:** one plain sentence.

When the access chain changes (an API is added), show the chain again with the
new link marked:

```
 └─ access grant      a5087ac2…   + new: GET api.github.com /user
```

## 2. Add your own API (call a real API through Passport)

For **local Docker**, first ask whether the developer wants the agent to add
the API or prefers the app's **“Add your own API”** flow. If they choose the
app, guide its access group → API/resource group → endpoint → secret mapping
→ access steps. The developer still stores the value in local Vault with the
part-0 hidden-prompt command; the app stores only its Vault path. Then inspect
the created objects and verify a request; do not run the create calls below.
Before either path, confirm the named proxy is still the zone's only proxy
and its default; stop if that is no longer true.
Either path must use an existing **non-demo** access group or create one.
The demo namespace is excluded from the app's own-API progress. The agent
path below is also used for AWS, without changing its deployment steps.

### 2.1 Ask for three things (never the secret value)

| Input | Example |
|---|---|
| Method and URL | `GET https://api.github.com/user` |
| How the API takes the credential | header `Authorization: Bearer …`, header `x-api-key: …`, or a query parameter `?api_key=…` |
| A name for the secret in Vault | `github-token` |

The API must be reachable from the proxy: the public internet works, but hosts
reachable only over your VPN may not be. Publicly trusted HTTPS certificates work
as they are.

### 2.2 What gets set, in order

| What | Where | Why |
|---|---|---|
| The secret value | the proxy's Vault, `secret/<vault-key>` | the proxy fetches it at request time |
| Secret reference | Passport Cloud | points at `<vault-key>`; its UUID is what goes in your requests |
| Resource group | Passport Cloud | makes the endpoint show in the web UI |
| Endpoint | Passport Cloud | method, host (**no port**) and path (no query string), linked to the reference |
| Access grant | Passport Cloud | lets your user call that endpoint |
| Fresh certificate | your CLI | the certificate lists the endpoints granted when it was issued |

### 2.3 The sequence

**1. [you] Store the secret value** with the hidden-prompt command for your
setup (part 0 table). It never appears in chat or shell history. Wait for
“stored”. The Vault is dev mode and in memory, so use a test or low-risk
credential. On local Docker, the developer runs the script in their terminal;
the agent never receives the value.

**2. The agent creates the Passport objects itself**, without asking. Fill in
the first line:

```bash
EP_METHOD=GET; EP_HOST=api.github.com; EP_PATH=/user; VKEY=github-token; HDR=Authorization
# … then your part-0 load block …
set -o pipefail
if [ "$W" = /tmp/pp-local ]; then
  PP_USER=$(api user-id) || exit 1
else
  PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)')
fi
# Local: list access groups and choose a non-demo one, or create one named for the project.
# AWS: preserve the original flow by using its demo namespace.
if [ "$W" = /tmp/pp-local ]; then
  api GET /api/v1/namespaces
  NS_N=$(api POST /api/v1/namespaces '{"name":"<project-access-group>","description":"Developer API"}' | jq -er .body.data.id) || exit 1
  NS_CREATED=1                     # if reusing a non-demo group: set its ID and NS_CREATED=0
else
  NS_N=$NS; NS_CREATED=0
fi
RG_N=$(api POST /api/v1/namespaces/$NS_N/resource-groups "$(jq -nc --arg n "$EP_HOST" '{name:$n,description:"Added after e2e",source:"manual"}')" | jq -er .body.data.id) || exit 1
PROXIES=$(api GET /api/v2/tenant/config) || exit 1
if [ "$W" = /tmp/pp-local ]; then
  printf '%s' "$PROXIES" | jq -e --arg p "$PROXY_ID" \
    '(.body.data | length)==1 and .body.data[0].proxyId==$p and .body.data[0].isDefault==true' >/dev/null || exit 1
else
  # AWS retains the existing default-proxy procedure.
  PREV=$(printf '%s' "$PROXIES" | jq -r '[.body.data[]|select(.isDefault==true)][0].proxyId // empty')
  [ "$PREV" = "$PROXY_ID" ] || api PUT /api/v2/tenant/config/$PROXY_ID '{"isDefault":true}' >/dev/null || exit 1
fi
REF_RESPONSE=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS_N" --arg k "$VKEY" '{namespaceId:$ns,name:$k,vaultType:"hashicorp",vaultKey:$k}')")
REF_STATUS=$?
if [ "$W" != /tmp/pp-local ]; then
  [ -z "$PREV" ] || [ "$PREV" = "$PROXY_ID" ] || api PUT /api/v2/tenant/config/$PREV '{"isDefault":true}' >/dev/null || exit 1
fi
[ "$REF_STATUS" -eq 0 ] || { echo 'Reference creation failed; stop.' >&2; exit 1; }
REF_N=$(printf '%s' "$REF_RESPONSE" | jq -er .body.data.id) || exit 1
EP_N=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS_N" --arg m "$EP_METHOD" --arg h "$EP_HOST" --arg p "$EP_PATH" --arg l "$HDR" --arg r "$REF_N" --arg g "$RG_N" \
  '{namespaceId:$ns,method:$m,host:$h,path:$p,secrets:[{label:$l,secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -er .body.data.id) || exit 1
GR_N=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS_N" --arg e "$EP_N" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport extra resource",validity:1}')" | jq -er '.body.data[0].id') || exit 1
OK=1; for v in "$NS_N" "$RG_N" "$REF_N" "$EP_N" "$GR_N"; do case "$v" in ''|null) OK=;; esac; done
if [ -n "$OK" ]; then
  printf '%s NS_N=%s NS_CREATED=%s RG=%s REF=%s EP=%s GR=%s\n' "$EP_METHOD $EP_HOST$EP_PATH" "$NS_N" "$NS_CREATED" "$RG_N" "$REF_N" "$EP_N" "$GR_N" | tee -a $W/resources.env
else echo "INCOMPLETE: RG=$RG_N REF=$REF_N EP=$EP_N GR=$GR_N. Nothing recorded; delete any IDs shown, refresh the token, re-run" >&2; fi
```

- **`INCOMPLETE`** usually means the login token expired (it lasts about an
  hour); the failed call is also printed as `api: <method> <path> -> <status>`.
  Delete any IDs it did create, run `passport auth status` (it refreshes the
  token), then re-run the block. Only
  complete results are recorded.
- **Reusing a resource group for the same host:** set `RG_N` to its ID and skip
  that line.
- **AWS default switch:** a new reference is encrypted for the zone's default
  proxy when created, and that's fixed from then on, so restoring the previous
  default afterwards is safe
  (`guides/reference/concepts.md`, "Secret references are encrypted for the
  zone's default proxy").

**3. Refresh the certificate** (part 0), then check that `passport whoami` lists
the new endpoint and `{{vault:<REF_N>}}`.

**4. The explicit request, with proxy and certificate flags.** Put the pointer
exactly where the API expects the credential:

```bash
curl -sS --proxy $PROXY \
  --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem \
  --cacert $DESTCA \
  -H "Authorization: Bearer {{vault:<REF_N>}}" \
  "https://api.github.com/user"
```

- **Success:** verify the upstream performed an operation that requires the
  credential; a 2xx alone does not prove substitution if that API also allows
  anonymous requests. Do not print a body that could echo the credential.
- **Credential in a query parameter?** Add `-g`. Without it, curl reads `{{` as
  its own URL-glob syntax and fails with `nested brace in URL`:
  `curl -sS -g … "https://api.example.com/v1/items?api_key={{vault:<REF_N>}}"`.
- **Body or URL path:** the CLI says the pointer also works there. Only headers
  and query parameters have been tested.

**5. The daemon form: no proxy or certificate flags.** The CLI's daemon
(`http://127.0.0.1:10144`) holds your client certificate and renews it, so a
plain request carrying only the pointer goes through Passport once its
environment variables are set:

```bash
curl -sS -H "Authorization: Bearer {{vault:<REF_N>}}" "https://api.github.com/user"
```

- **macOS/Windows:** `passport setup` without `--no-daemon` installed
  it. Check with `echo $HTTPS_PROXY` (`http://127.0.0.1:10144`, in a terminal
  opened after setup) and `passport daemon status`. For tools that use the OS
  trust store, the user runs `passport ca install` once (it needs `sudo`).
- **Linux:** `passport daemon start`, then export the variables yourself.
- **Hosts it never routes** (`localhost`, private ranges, `.internal`,
  `.usepassport.ai` and others in `NO_PROXY`): use the explicit form for an API
  on those. The full list, the per-platform variables, the rc-file option and
  Node's needs: `guides/reference/concepts.md`, "Two ways to send a request".

What has been verified for this part, and what hasn't:
`guides/reference/verification.md`.

For **local Docker**, after the developer's own API request is verified, ask
them to tick **“My request went through and the API received the real key”**
in the app. The earlier demo request does not count. Report whether the app
actually reflected the completion; do not infer it from the API response.
