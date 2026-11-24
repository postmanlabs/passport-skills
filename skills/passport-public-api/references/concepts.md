# Passport concepts

The single source of Passport's vocabulary and invariants for both skills.
Edit `shared/concepts.md`, then run `tools/sync-shared.sh`; each skill ships
its own copy because a skill folder must stand alone.

## Glossary

Capitalise these terms in user-facing copy. App labels can change late, so
they live only in this table.

| Term | What it is | In the app | In the public API |
|---|---|---|---|
| Passport Cloud | The hosted control plane. Holds the rules (who may call what) and never sees a secret value. | — | `api_url` |
| Proxy | Runs on your machine in Docker. Checks each request against your Access Grants and swaps `{{vault:<id>}}` for the real value on the way out. | — | — |
| Proxy Configuration | The app's record of your Proxy. It gives the Proxy ID and registration token the Proxy uses to register itself. One per zone. | Proxy Configuration | `GET /public/v1/proxies` (requested, not live yet) |
| HashiCorp Vault | Runs on your machine in Docker. Holds the real secret values. | — | — |
| Secret | A value in HashiCorp Vault at a path, stored as JSON key-value pairs. Passport reads the key `value`. | — | — |
| Secret Reference | A pointer to a Vault path. Its UUID is what goes in `{{vault:<uuid>}}`. | Secret references | `secret-references` |
| Namespace | A group of related APIs and their access rules. | Namespace | `namespaces` |
| Resource Group | One API host and its Endpoints. Makes an Endpoint visible in the app. | Resource group | `resource-groups` |
| Endpoint | A method, host and path Passport protects, with slots that map a header or query parameter to a Secret Reference. | Endpoint; a slot is "Sent in" | `endpoints`; slot = `secrets[].label` |
| Access Request | A request for access to Endpoints. A team admin's request for themselves is approved automatically. | Approvals | `access-requests` |
| Access Grant | Time-limited permission (7, 30 or 90 days) to call Endpoints. | My access | `access-grants` |
| Client certificate | Issued to you by `passport login`; tells the Proxy who you are and which Endpoints you may call. | — | — |
| Team | The people and catalog sharing one WorkOS `org_…` ID. | Team | `teamId` |
| Zone | A deployment boundary inside a team. Every team has Production. | — | `?zone=` |

## How a request is allowed

```
your client certificate      from `passport login`; lists the Endpoints granted when issued
 └─ Access Grant             lets you call Endpoints for a number of days
    └─ Endpoint              method + host + path, in a Namespace
       └─ slot               a header or query parameter, mapped to …
          └─ Secret Reference    a UUID; this is what goes in {{vault:<uuid>}}
             └─ Secret          in HashiCorp Vault next to the Proxy; never leaves it
```

The Proxy checks every link before it swaps the pointer for the real value.

## Invariants

- **Use the UUID, not the name:** `{{vault:<uuid>}}`. A name passes through
  unchanged and surfaces as a 401 from the upstream API.
- **The Proxy replaces only the `{{vault:…}}` text.**
  `Authorization: Bearer {{vault:<uuid>}}` arrives as `Bearer <secret>`.
- **A Secret Reference stores a path relative to the `secret/` mount**
  (`demo-api-key`, not `secret/data/demo-api-key`), with `vaultType`
  `hashicorp`. The secret value sits under the key `value`.
- **References are encrypted for the zone's default Proxy when created.** A
  Reference made for another Proxy can't be decrypted by yours. If `ref.pem`
  is ever regenerated, every existing Reference stops working, and
  re-registering with a different key is refused with `409`.
- **Endpoint fields:** `host` has no scheme and no port; `path` starts with `/`
  and has no query string. Method `*` matches any method. A trailing `*`
  matches the rest of the path (including the bare prefix); a `*`, `:var` or
  `{var}` in the middle matches one segment; the host must match exactly.
- **Endpoint create checks inline `secrets` against existing References**, so
  create the Secret Reference before the Endpoint that sends it.
- **After any grant change, run `passport refresh`.** The certificate lists the
  Endpoints granted when it was issued.
- **Never read `~/.passport/passportrc` or `~/.passport-beta/passportrc`.** They
  hold live CLI tokens.
- **Never approve your own Access Request.** Approval is the user's decision;
  an admin's request for themselves is approved by the service.

## The Proxy's keys

| File | Env variable | What it does |
|---|---|---|
| `ca.pem` | `PASSPORT_PROXY_PRIVATE_KEY_PATH` | Private key. The Proxy derives its CA from it, signs client certificates and re-signs destination certificates. |
| `ref.pem` | `PASSPORT_PROXY_REFERENCE_PRIVATE_KEY_PATH` | Private key that decrypts Secret References. Its public half is sent to Passport Cloud at registration. |

Both are made once with `openssl genrsa` and required: the Proxy refuses to
start without either. Never regenerate `ref.pem`.

## HashiCorp Vault in this setup

- Persistent: secrets live on a Docker volume and survive restarts. The
  container unlocks itself at start.
- The Proxy and the Vault UI both use the root token (`VAULT_TOKEN` in
  `~/.passport/onboarding/proxy.env`). In production, the Proxy gets its own
  read-only token and people sign in as themselves.
- `VAULT_ADDR` and `VAULT_TOKEN` are HashiCorp's own variable names, not
  `PASSPORT_PROXY_`-prefixed.

## Sending a request through the Proxy

- **`passport request`** carries your certificate and renews it inline; prefer
  it for anything the agent sends:
  `passport request -X POST -H 'Authorization: Bearer {{vault:<uuid>}}' -d '{…}' https://api.example.com/x`.
- **Other tools** go through the CLI's daemon (`HTTPS_PROXY=http://127.0.0.1:10144`),
  which `passport login` sets up (unverified on beta; see `verification.md`). A
  shell started before that doesn't see the variables; open a new one.
- **Node's built-in `fetch` ignores `HTTPS_PROXY`** unless run with
  `--use-env-proxy` or `NODE_USE_ENV_PROXY=1`; otherwise the literal
  `{{vault:…}}` goes straight to the upstream.
- **The daemon only routes external hosts.** `NO_PROXY` covers localhost,
  private IP ranges, `.local`, `.internal` and the Passport hosts; requests to
  those go direct and unsubstituted. Use `passport request` for them.
- **Certificates last about five minutes.** Don't cache `passport whoami`
  output within a task.
- **Trusting the CA:** `passport ca install` (macOS; needs the user's
  password) adds the Proxy's CA to the System keychain for tools that ignore
  env variables. Linux has no `ca install`.

## Errors that look like auth problems

- A `502` with an `x-passport-proxy-error` header is the Proxy refusing, not the
  upstream failing; read that header and `x-passport-proxy-refs` first.
- A `401` from the upstream, in order of likelihood: the grant is pending or
  expired; the request didn't go through the Proxy; the token is a Reference
  name instead of its UUID; the Reference points at a missing Vault path or a
  secret without the key `value`; the credential belongs in a different slot.

## The demo API

`https://passport-skill-demo.mock.postman.postman.dev/` returns `200` only when
`x-demo-api-key` holds the public sample key `sdfdsfdsfsdfdfsdfds`, and `401`
for anything else, including the unsubstituted pointer. Both replies show the
first five characters and the length of what arrived
(`"key":"sdfds**************","key_length":19` on success). The sample key is
public, so it may appear in commands.
