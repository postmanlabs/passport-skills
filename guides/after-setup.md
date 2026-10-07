# After setup: show the value, add an API, demos

This is shared by both setups. Use it once the end-to-end test in your setup
guide passes:
- **Local Docker:** `guides/local-docker.md` step 7 printed `INJECTED`.
- **AWS:** `guides/aws-single-instance.md` step 8.5 passed.

It has four parts, run in order:
1. **Handoff:** one short message that shows the value.
2. **Add your own API:** offer this as the single next step.
3. **Protection demos:** offer these after their API works, or when asked.
4. **What to tell the user.**

Cleanup stays in each setup guide, and runs only when the user explicitly asks.

## 0. Load your setup (start every command block with one of these)

The rest of this file uses the same names for both setups.

**Local Docker:**

```bash
cd /tmp/pp-local; . ./ids.env; W=/tmp/pp-local
export PASSPORT_DIR=~/.passport                      # MDM Mac: ~/passport-cli-dl/.passport
api() { node /tmp/pp-local/passport-api.js "$@"; }
PROXY=https://localhost:8443; MGMT=http://localhost:8081; DESTCA=/tmp/pp-local/proxy-ca.pem; D=$PASSPORT_DIR
proxylogs() { docker logs pp-proxy-local 2>&1 | tail -300; }
```

**AWS:**

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"; cd /tmp/pp-aws; W=/tmp/pp-aws
PROXY=https://$PROXY_HOST:8443; MGMT=https://$CF_DOMAIN; DESTCA=/tmp/pp-aws/proxy-ca.pem; D=$PASSPORT_DIR
proxylogs() { onhost 'docker logs pp-proxy-local 2>&1 | tail -300'; }
```

| Name | Meaning |
|---|---|
| `$PROXY` | the Passport proxy's data plane, used with `--proxy` |
| `$MGMT` | the management URL, used with `passport setup --management-url` |
| `$DESTCA` | the proxy's CA as downloaded in your setup guide, used with `--cacert` |
| `$D` | the CLI's credentials folder: `cert.pem`, `key.pem`, `ca.pem` |
| `$NS`, `$PROXY_ID`, `$REF`, `$GR`, `$PREV_DEFAULT` | IDs from your setup guide's demo (namespace, registration, demo reference, demo grant, the team's previous default) |
| `$W/resources.env` | one line per API added in part 2, which cleanup reads |

**Refresh your certificate** after any grant change:
- normally: `passport setup --management-url $MGMT --proxy-url $PROXY`;
- on an MDM Mac: the container form from your MDM reference, with `--no-daemon`.

**[you] steps that differ by setup:**

| Step | Local Docker | AWS |
|---|---|---|
| Store a secret at a hidden prompt | In your own terminal: `read -rs -p "Secret value: " V; echo; printf %s "$V" \| docker exec -i -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-for-local-dev pp-vault-dev vault kv put secret/<vault-key> value=- >/dev/null && echo stored; unset V` | In your own terminal: `aws ssm start-session --target <INSTANCE> --region <AWS_REGION> --profile <AWS_PROFILE>`, then `sudo passport-vault-put <vault-key>`, then `exit` |
| Check a stored value without printing it | `docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=root-token-for-local-dev pp-vault-dev vault kv get -field=value secret/<vault-key> \| shasum -a 256` | in a session: `sudo passport-vault-sha256 <vault-key>` |

Both Vaults are dev mode and **in memory**. Restarting the Vault container
erases every stored secret, so store them again afterwards.

---

## 1. Handoff: show the value, briefly (mandatory)

One short message, with the real values. **Lead with the value**, and keep the
details out unless the user asks. If any check in your setup guide failed, say
which one first, in one line.

> **✅ Passport is working. You just called an API with a key you never had.**
>
> | | Without Passport | With Passport |
> |---|---|---|
> | Your script or AI agent holds | the real API key | only a pointer: `{{vault:<REF>}}` |
> | If it leaks | anyone can use the key, anywhere | useless outside the one granted endpoint |
> | To revoke or rotate | update every laptop, script and CI job | change it once, centrally |
>
> **Proof.** You sent only the pointer, and the API received the real key:
> ```
> curl -H "x-demo-api-key: {{vault:<REF>}}" https://passport-demo.mock.postman.postman.dev
> → {"status":"authenticated","key":"sdfds**************","key_length":19}
> ```
> (If the pointer had reached the API unchanged, it would show `"key":"{{vau…","key_length":46`.)
>
> **Try it on your own API?** Tell me the URL and how it takes the key (for
> example `Authorization: Bearer`). You'll store the key yourself through a
> hidden prompt, never in this chat, and I'll do the rest.
>
> <sub>Footer, one line: where it runs (local Docker, or proxy `<NAME>` on EC2 at about $0.70/day) · certificate renewal · "nothing is deleted until you ask".</sub>

Rules for this message:
- **The proof command.** Show the daemon form (no flags, as above) if the
  daemon is running. Otherwise show the explicit form you actually ran
  (`curl --proxy $PROXY … -H "x-demo-api-key: …" https://passport-demo…`), and
  say the daemon isn't set up. On an MDM Mac it never is.
- **One next step:** their own API (part 2). Offer the demos (part 3) only after
  that works, or if they ask.
- **Be honest about the demo key.** It's the demo API's public sample key, so it
  appears in the guides. With their own key, the value goes only into a hidden
  prompt, and never into their shell history or this conversation. Say so if
  they ask, or if it's relevant.
- **On request only:** the full `curl` with every flag, what each flag does,
  certificate expiry and renewal, and the daemon (part 2, step 5).

---

## 2. Add your own API (call a real API through Passport)

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
setup (part 0 table). It never appears in chat, shell history or a process
list. Wait for "done".

**2. The agent creates the Passport objects itself**, without asking. Fill in
the first line:

```bash
EP_METHOD=GET; EP_HOST=api.github.com; EP_PATH=/user; VKEY=github-token; HDR=Authorization
# … then your part-0 load block …
PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)')
RG_N=$(api POST /api/v1/namespaces/$NS/resource-groups "$(jq -nc --arg n "$EP_HOST" '{name:$n,description:"Added after e2e",source:"manual"}')" | jq -r .body.data.id)
# References are encrypted for the team's DEFAULT proxy: be the default while creating it, then restore.
PREV=$(api GET /api/v2/tenant/config | jq -r '[.body.data[]|select(.isDefault==true)][0].proxyId // empty')
[ "$PREV" != "$PROXY_ID" ] && api PUT /api/v2/tenant/config/$PROXY_ID '{"isDefault":true}' >/dev/null
REF_N=$(api POST /api/v2/secret-references "$(jq -nc --arg ns "$NS" --arg k "$VKEY" '{namespaceId:$ns,name:$k,vaultType:"hashicorp",vaultKey:$k}')" | jq -r .body.data.id)
[ -n "$PREV" ] && [ "$PREV" != "$PROXY_ID" ] && api PUT /api/v2/tenant/config/$PREV '{"isDefault":true}' >/dev/null
EP_N=$(api POST /api/v2/resource-endpoints "$(jq -nc --arg ns "$NS" --arg m "$EP_METHOD" --arg h "$EP_HOST" --arg p "$EP_PATH" --arg l "$HDR" --arg r "$REF_N" --arg g "$RG_N" \
  '{namespaceId:$ns,method:$m,host:$h,path:$p,secrets:[{label:$l,secretReferenceId:$r}],resourceGroupIds:[$g]}')" | jq -r .body.data.id)
GR_N=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP_N" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport extra resource",validity:1}')" | jq -r '.body.data[0].id')
if [ -n "$RG_N" ] && [ -n "$REF_N" ] && [ -n "$EP_N" ] && [ -n "$GR_N" ] && [ "$GR_N" != null ]; then
  printf '%s RG=%s REF=%s EP=%s GR=%s\n' "$EP_METHOD $EP_HOST$EP_PATH" $RG_N $REF_N $EP_N $GR_N | tee -a $W/resources.env
else echo "INCOMPLETE: RG=$RG_N REF=$REF_N EP=$EP_N GR=$GR_N. Nothing recorded; delete any IDs shown, refresh the token, re-run" >&2; fi
```

- **`INCOMPLETE`** usually means the login token expired (it lasts about an
  hour). Delete any IDs it did create, run `passport auth status` (it refreshes
  the token), then re-run the block. Only complete results are recorded.
- **Reusing a resource group for the same host:** set `RG_N` to its ID and skip
  that line.
- **Why the default switch:** Passport encrypts a new reference for whichever
  proxy is the team default when the reference is created, and the key is fixed
  from then on. Restoring the previous default afterwards is safe. This was
  verified in `passport-service` and in a live run on 2026-10-07.

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

- **Success:** a 2xx from the API means the proxy injected the real credential.
  Don't print the body if it could echo the credential back.
- **Credential in a query parameter?** Add `-g`. Without it, curl reads `{{` as
  its own URL-glob syntax and fails with `nested brace in URL`:
  `curl -sS -g … "https://api.example.com/v1/items?api_key={{vault:<REF_N>}}"`.
- **Body or URL path:** the CLI says the pointer also works there. Only headers
  and query parameters have been tested.

**5. The daemon form: no proxy or certificate flags.** The CLI's **daemon** is a
small local proxy on `http://127.0.0.1:10144`. It holds your client certificate,
talks mTLS to the Passport proxy, and gets a fresh certificate when yours is
about to expire. With its environment variables set, a plain request carrying
only the pointer goes through Passport:

```bash
curl -sS -H "Authorization: Bearer {{vault:<REF_N>}}" "https://api.github.com/user"
```

- **macOS/Windows (not MDM):** `passport setup` without `--no-daemon` installs
  the daemon and sets `HTTPS_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS`,
  `REQUESTS_CA_BUNDLE` and `SSL_CERT_FILE` for your login session. It prints
  `[5/5] daemon installed + HTTPS_PROXY set`.
  - **Pick up the variables:** the terminal you ran setup in doesn't see them
    yet. Quit the terminal app completely (not just the tab) and reopen it, or
    paste the `export …` lines setup printed.
  - **Check:** `echo $HTTPS_PROXY` (should be `http://127.0.0.1:10144`) and
    `passport daemon status`.
  - **[you]** run `passport ca install` once (it needs `sudo`) for tools that
    use the OS trust store.
- **Linux:** setup can't install the daemon, so start it and export the variables yourself:
  ```bash
  passport daemon start
  export HTTPS_PROXY=http://127.0.0.1:10144
  export SSL_CERT_FILE=~/.passport/ca.pem REQUESTS_CA_BUNDLE=~/.passport/ca.pem NODE_EXTRA_CA_CERTS=~/.passport/ca.pem
  ```
- **MDM Mac:** the daemon isn't available on the container path. Use the explicit form.
- **The daemon only routes external hosts.** These always go direct, never
  through Passport: `localhost`, `127.0.0.1`, `::1`, private IP ranges,
  `.local`, `.internal`, `.svc`, `.cluster.local`, `.postmanlabs.com` and
  `.usepassport.ai`, plus their `-beta`/`-stage` variants. Use the explicit form
  for an API on those hosts.
- **Shell rc file:** `passport daemon install --write-to ~/.zshrc` adds the
  variables to your rc file. It also adds `NODE_OPTIONS=--use-env-proxy` (Node's
  built-in fetch ignores `HTTPS_PROXY` without it) and `JAVA_TOOL_OPTIONS`.
- **Node needs both:** `passport ca install` doesn't replace
  `NODE_EXTRA_CA_CERTS`, because Node uses its own bundled roots.

> **Verified 2026-10-06** on the local Docker setup (MDM container path, daemon
> started by hand), with `postman-echo.com` and a fake value:
> - **Both request forms** delivered the Vault value, in a header and in a query parameter.
> - **The daemon** renewed its expired certificate by itself.
>
> **Not run:** the non-MDM `passport setup` daemon install, and this part on EC2.
>
> **Re-verified 2026-10-07 from this shared file** (local Docker, MDM container path):
> - **Part 0 and the part 2 agent block** (with the default-proxy switch) created
>   all four objects for `GET postman-echo.com/headers`.
> - **The explicit request** delivered the stored fake value.
> - **Demos A and B** behaved as described, with `0` secret values in the proxy logs.

---

## 3. Protection demos (offer one at a time, explain each result)

Use the explicit form from part 2, step 4, with your API's pointer
(`<REF_N>`, `<HDR>`) or the demo's (`$REF`, `x-demo-api-key`).

**A. A leaked pointer is useless anywhere else.** Send the *same* pointer to a
host that wasn't granted:

```bash
curl -sS --proxy $PROXY --proxy-cacert $D/ca.pem --proxy-cert $D/cert.pem --proxy-key $D/key.pem --cacert $DESTCA \
  -H "x-demo-api-key: {{vault:$REF}}" https://httpbin.org/headers
```

It's refused with `passport: not authorized for vault refs: [<uuid>]`.
- **This proves:** the secret is injected only on the exact method, host and
  path that were granted.
- **Why it matters:** a pointer that ends up in a log, a copied script or a
  prompt-injected AI agent can't be used to send the secret anywhere else.

**B. Every call is audited, and the logs never hold the secret.**

```bash
proxylogs | grep passport.proxy.request | grep -o '{"resourceLogs".*' \
  | jq -r '.resourceLogs[].scopeLogs[].logRecords[] | ([.attributes[] | {(.key): (.value|to_entries[0].value)}] | add) as $a
  | [$a["http.request.method"], $a["server.address"] + $a["http.route"], $a["passport.outcome"], $a["enduser.id"]] | @tsv' | tail
```

- **What each line shows:** the method, host and path, the outcome (`success`
  or `unauthorized`), and the user ID.
- **No values:** the records carry secret-reference UUIDs only. To prove it with
  the demo key, `proxylogs | grep -c sdfdsfdsfsdfdfsdfds` prints `0`.

**C. Revoke a grant and access ends.** Once the user picks this demo, the agent
deletes the grant itself (`$GR_N` for their API, `$GR` for the demo), refreshes
the certificate (part 0), and repeats the call:

```bash
api DELETE /api/v2/access-grants/$GR
passport whoami                 # after the refresh: the endpoint is gone from allowedApiRefs
```

- **Expect:** the same call is now refused with `not authorized for vault refs`.
- **This proves:** access ends centrally, and a copied certificate expires within
  minutes. The user never held the credential, so there's nothing for them to keep.
- **Restore access** for an API added in part 2 (`EP_N` and `GR_N` from its `resources.env` line):
  ```bash
  PP_USER=$(node -e 'const fs=require("fs"),p=require("path");const t=JSON.parse(fs.readFileSync(p.join(process.env.PASSPORT_DIR,"passportrc"),"utf8")).login._profiles[0].workos.accessToken;console.log(JSON.parse(Buffer.from(t.split(".")[1],"base64url")).sub)')
  NEW_GR=$(api POST /api/v2/access-grants "$(jq -nc --arg u "$PP_USER" --arg ns "$NS" --arg e "$EP_N" '{userId:$u,namespaceId:$ns,endpointIds:[$e],reason:"passport extra resource",validity:1}')" | jq -r '.body.data[0].id')
  [ -n "$NEW_GR" ] && [ "$NEW_GR" != null ] && sed -i.bak "s/GR=$GR_N/GR=$NEW_GR/" $W/resources.env && echo "restored $NEW_GR"
  ```
  For the demo grant, use `$EP` and record the new ID as `GR` (local: edit
  `ids.env`; AWS: `st GR "$NEW_GR"`). Then refresh the certificate (part 0).

**D. Rotate the secret with no client changes.**
1. **[you]** store a new value under the same Vault key (part 0 table).
2. Wait about 60 s, because the proxy caches Vault lookups.
3. Repeat the same call.

- **Expect:** the same pointer now delivers the new value. With the demo API,
  the response shows the new value's first 5 characters and its length.
- **This proves:** no script, configuration, CI variable or teammate's laptop
  needs an update.

> **Verified 2026-10-06** on the local Docker setup (MDM container path), with
> `postman-echo.com` and fake values:
> - **A** refused both another path and `httpbin.org`.
> - **B** listed every call, with no secret value in the logs.
> - **C** refused the call after the revoke and a fresh certificate.
> - **D** delivered the rotated value on the same pointer 28 s after the Vault write.
>
> **Re-verified 2026-10-07 from this shared file** (local Docker, MDM container path,
> `postman-echo.com`, fake values):
> - **C:** after the revoke and a refresh, the endpoint left `whoami` and the call
>   was refused. The restore commands above brought access back.
> - **D:** the old value was returned at +0, +20 and +40 s, and the new value at +60 s.

---

## 4. What to tell the user, in their terms

- **Nothing to leak:** no API key on laptops, in repos, in CI or in an AI agent's context.
- **Least privilege:** access is per method, host and path, per person.
- **Central control:** revoke or rotate from one place.
- **An audit trail** of who called what, and whether it was allowed.

It works with the tools they already use: curl, scripts and SDKs, through the
daemon's environment variables. End every reply in this phase with the resource
status, any open issue, and the reminder that **nothing is deleted until they
explicitly ask for cleanup.**
