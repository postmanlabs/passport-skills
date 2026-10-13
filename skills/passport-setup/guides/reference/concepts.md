# Passport concepts and rules (shared by both setups)

The guides link here for the *why*. The rules an agent must follow are in
`SKILL.md`; symptoms and fixes are in `troubleshooting.md`; what has been
tested, and when, is in `verification.md`.

## How a request is allowed

```
your client certificate      from `passport setup`; lists the endpoints granted when it was issued
 └─ access grant             lets your user call one or more endpoints, for a number of days
    └─ endpoint              method + host + path, in a namespace
       └─ credential slot    a header (or query parameter) label, mapped to …
          └─ secret reference    a UUID; this is what goes in {{vault:<uuid>}}
             └─ Vault key    on the proxy's own Vault; the value never leaves the proxy
```

The proxy checks every link before it swaps the pointer for the real value.
A **team** and an **org** are the same thing: the team ID is the `org_…` value
on the `org` line of `passport auth status`.

## Secret references are encrypted for the team's default proxy

*Verified in `passport-service` and in a live run on 2026-10-07.*

- Passport encrypts each new secret reference with the public key of the
  team's **default** proxy registration. If there's no default, it uses an
  arbitrary registration. Nothing in the request chooses the proxy.
- The key is fixed when the reference is created. A reference created while
  another proxy is the default can't be decrypted by yours
  (`failed to decrypt vault reference: <uuid>`).
- So, on a team that already has a default:
  1. remember the current default;
  2. make your proxy the default;
  3. create your references;
  4. restore the previous default.

  Your references keep working, and teammates aren't left on your test proxy.
  If the team had no default, yours stays the default.
- **New key, new references.** If you re-register the proxy with a new
  keypair (for example `ref.pem` was regenerated, or `/tmp/pp-local` was
  wiped), references created earlier can't be decrypted. Create new ones.
  Don't reuse an old registration whose `publicKey` differs from your current
  key; leave it in place unless the user says to delete it.
- **Repairing a reference:** make your proxy the default
  (`api PUT /api/v2/tenant/config/<your proxyId> '{"isDefault":true}'`),
  re-encrypt the reference
  (`api PUT /api/v2/secret-references/<ref> '{"vaultKey":"<its vault key>"}'`),
  run `passport setup` again, then restore the previous default.

## Endpoints

- **The host never includes a port.** The proxy strips the port from the
  request's target host, but not from the endpoint's stored `host`. An endpoint
  stored as `example.com:443` fails every request with
  `not authorized for vault refs`, even though `passport whoami` looks right.
- **The path has no query string.**
- **A resource group makes the endpoint visible in the web UI.** The namespace
  page lists resource groups, then the endpoints inside each one. An endpoint
  created without `resourceGroupIds` works through the proxy but never shows
  in Passport Cloud. `source:"manual"` is what the web UI's **Manual** flow
  uses. To attach a group to an existing endpoint (a `PUT` changes only the
  fields you send):
  `api PUT /api/v2/resource-endpoints/<id> "$(jq -nc --arg g "$RG" '{resourceGroupIds:[$g]}')"`
- **`{{vault:…}}` takes the reference's UUID, not its name.** A name passes
  through unchanged, with no error.
- **Where the pointer can go:** headers and query parameters are tested. For a
  query parameter, give curl `-g`, or it reads `{{` as its own URL-glob syntax
  (`nested brace in URL`). The CLI says the body and URL path also work; that
  isn't tested here.

## The proxy's keys

| File | What it does |
|---|---|
| `ca.pem` | A private key. The proxy derives its self-signed CA from it at boot, signs client certificates with it, and re-signs destination certificates during the TLS interception (MITM) it does |
| `ref.pem` | A private key that decrypts secret references. Its public half (`reference-public-key.pem`) is registered with Passport Cloud |

Never regenerate `ref.pem` while a registration uses it: every reference
created for it stops working. `ca.pem` is not a certificate; the proxy's CA
certificate is served at `<management URL>/ca.pem`.

## The Vault (dev mode)

- Both setups run HashiCorp Vault in **dev mode, in memory**. Restarting its
  container (or rebooting the EC2 instance) erases every stored value. Store
  them again afterwards.
- A reference's `vaultKey` is relative to `secret/`: `demo-api-key`, not
  `secret/data/demo-api-key`. The value is stored in the field `value`
  (`vault kv put secret/<key> value=…`).
- `VAULT_ADDR` and `VAULT_TOKEN` are plain Vault variable names, not
  `PASSPORT_PROXY_`-prefixed like the rest of the proxy's settings.

## Client certificates: lifetime and renewal

- **Expiry:** `notAfter` in `passport whoami` and `passport daemon status`.
- **Requested vs actual:** the CLI requests 1 hour by default
  (`passport setup --ttl <seconds>`), but the proxy may issue less. Earlier
  runs got about 5 minutes. Report the real value.
- **With the daemon:** it renews **on demand**. When a request starts with
  less than 60 s left, it mints a new certificate using your saved login. If
  the login has also expired, run `passport login`, then `passport setup`.
- **Without the daemon:** `passport request` renews inline, but nothing renews
  the files that plain `curl` reads, so run `passport setup` again.
- **After any grant change**, run `passport setup` again: the certificate
  lists the endpoints granted when it was issued.

## Two ways to send a request

**Explicit form** (no daemon; works everywhere):

```bash
# proxy-ca.pem: the proxy's CA certificate, downloaded from <management URL>/ca.pem
curl --proxy https://<proxy host>:8443 \
  --proxy-cacert ~/.passport/ca.pem --proxy-cert ~/.passport/cert.pem --proxy-key ~/.passport/key.pem \
  --cacert proxy-ca.pem \
  -H "x-demo-api-key: {{vault:<uuid>}}" https://passport-demo.mock.postman.postman.dev
```

- `--proxy-cacert` trusts the proxy itself.
- `--cacert` trusts the certificate the proxy presents for the destination,
  which it re-signs with its CA.

**Daemon form** (no flags). The CLI's daemon is a small local proxy on
`http://127.0.0.1:10144`. It holds your client certificate, talks mTLS to the
Passport proxy, and gets a fresh certificate when yours is about to expire.

- **macOS/Windows (not MDM):** `passport setup` without `--no-daemon` installs
  the daemon and sets `HTTPS_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`,
  `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` for your login session
  (Windows: the user environment). It prints
  `[5/5] daemon installed + HTTPS_PROXY set`.
- **Picking up the variables:** the terminal you ran setup in doesn't see them
  yet. Quit the terminal app completely (not just the tab) and reopen it, or
  paste the `export …` lines setup printed.
- **Linux:** setup can't install the daemon. Run `passport daemon start`, then
  export `HTTPS_PROXY=http://127.0.0.1:10144`, and `SSL_CERT_FILE`,
  `NODE_EXTRA_CA_CERTS` and `REQUESTS_CA_BUNDLE` set to `~/.passport/ca.pem`.
- **MDM Mac:** setup doesn't install it; see `mdm-macs.md`, A.5.
- **Shell rc file (optional):** `passport daemon install --write-to ~/.zshrc`
  appends the variables to your rc file. That block also sets
  `NODE_OPTIONS=--use-env-proxy` (Node's built-in fetch ignores `HTTPS_PROXY`
  without it) and `JAVA_TOOL_OPTIONS` proxy settings.
- **The daemon only routes external hosts.** `NO_PROXY` always includes
  `localhost`, `127.0.0.1`, `::1`, private IP ranges, `.local`, `.internal`,
  `.svc`, `.cluster.local`, `.postmanlabs.com` and `.usepassport.ai`, plus
  their `-beta`/`-stage` variants. Requests to those go direct and the literal
  `{{vault:…}}` arrives unsubstituted, so use the explicit form for them. The
  demo API isn't on that list.

## Trusting the Passport CA

- `passport ca install` needs `sudo`/admin, so the user runs it.
  - **macOS:** it runs
    `sudo security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain ~/.passport/ca.pem`,
    which trusts the CA in the System keychain for the **SSL policy** only.
  - **Windows:** it adds the CA to `LocalMachine\Root`, with a UAC prompt.
  - **Undo:** `passport ca uninstall`.
- On macOS, `passport ca status` checks only that the certificate is
  *present*, not its trust setting. The real test is
  `security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain`.
- **Node needs both:** `ca install` doesn't replace `NODE_EXTRA_CA_CERTS`,
  because Node uses its own bundled roots. Python `requests` needs
  `REQUESTS_CA_BUNDLE`.
- `passport ca install` isn't available on the Linux CLI, so it doesn't apply
  on the MDM container path.

## The demo API

`https://passport-demo.mock.postman.postman.dev` replies with the first 5
characters and the length of whatever `x-demo-api-key` it received. It
accepts any key, so `"authenticated"` alone proves nothing; what it saw is
the proof:

| The API received | Response |
|---|---|
| the real key (Passport injected it) | `"key":"sdfds**************","key_length":19` |
| the pointer, unchanged (no injection) | `"key":"{{vau*****…","key_length":46` |

Its sample key `sdfdsfdsfsdfdfsdfds` is public, which is why the guides may
pass it on a command line. Real credentials only ever go into a hidden prompt.

## Deleting Passport objects

Order: access grant → endpoint → resource group → secret reference →
namespace → proxy registration.

- A secret reference returns `409` while an endpoint still maps it.
- `DELETE /api/v2/tenant/config/<id>` takes the `proxyId` UUID, not the
  numeric `id`.
