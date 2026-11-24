# Passport concepts

The single source of Passport's vocabulary and invariants for both skills.
Edit `shared/concepts.md`, then run `tools/sync-shared.sh`; each skill ships
its own copy because a skill folder must stand alone.

## Glossary

Capitalise these terms in user-facing copy. App labels can change late, so
they live only in this table.

| Term | What it is | In the app | In the public API |
|---|---|---|---|
| Passport Cloud | The hosted Passport Control Plane. Holds the rules (who may use which secret, on which API, for which operation) and never sees a secret value. | — | `api_url` |
| Proxy | The data plane, in your network next to the Secret Vault (for one developer, in Docker on their machine). Checks each request against your Access Grants, swaps `{{vault:<pointer>}}` for the real value on the way out, and writes an audit log. | — | — |
| Proxy Configuration | The app's record of your Proxy. It gives the Proxy ID and enrollment token the Proxy uses to register itself, and shows whether the Proxy is healthy. One per zone. | Proxy Configuration | `GET /public/v1/proxies` |
| Secret Vault | Holds the real secret values, next to the Proxy. The Proxy reads HashiCorp Vault, AWS Secrets Manager or Google Secret Manager. This setup runs HashiCorp Vault in Docker: call it Secret Vault (HashiCorp), never "HashiCorp Vault" alone, so it doesn't read as the only vault. | Vault type | `vaultType` |
| Secret | A value in the Secret Vault at a path, stored as JSON key-value pairs. Passport reads the key `value`. | — | — |
| Secret Reference | Where a secret lives: a vault type and a path in the Secret Vault. Endpoint slots map to it; requests never name it. | Secret references | `secret-references` |
| Pointer | What a request carries: `{{vault:<pointer>}}`. Passport Cloud issues one to you for each slot of each Endpoint your Access Grant covers, and your client certificate lists it. A new Access Grant issues new pointers. | My access | `passport whoami --json` |
| Namespace | A group of related APIs and their access rules. | Namespace | `namespaces` |
| Resource Group | One API and its Endpoints, named for the API (`Passport demo API`). Access is requested on it; it makes an Endpoint visible in the app. | Resource group | `resource-groups` |
| Endpoint | The resource: a method, host and path Passport protects, with slots that map a header or query parameter to a Secret Reference. | Endpoint; a slot is "Sent in" | `endpoints`; slot = `secrets[].label` |
| Access Request | A request for access to Endpoints. A team admin's request for themselves is approved automatically. | Approvals | `access-requests` |
| Access Grant | Time-limited permission (7, 30 or 90 days) to call Endpoints. | My access | `access-grants` |
| Client certificate | Issued to you by `passport login`; tells the Proxy who you are, which Endpoints you may call, and your pointer for each of their slots. | — | — |
| Team | The people and catalog sharing one WorkOS `org_…` ID. | Team | `teamId` |
| Zone | A deployment boundary inside a team. Every team has Production. | — | `?zone=` |

## How a request is allowed

```
your client certificate      from `passport login`; lists the Endpoints granted when issued
 └─ Access Grant             lets you call Endpoints for a number of days
    └─ Endpoint              method + host + path, in a Namespace
       └─ slot               a header or query parameter; your pointer for it goes in {{vault:<pointer>}}
          └─ Secret Reference    where the value lives; mapped to the slot, never named in a request
             └─ Secret          in the Secret Vault next to the Proxy; never leaves it
```

The Proxy checks every link before it swaps the pointer for the real value.

## Invariants

- **A request carries your pointer, never a Secret Reference's ID or name.**
  Read it from `passport whoami --json`: `allowedApiRefs` is keyed by
  `"<METHOD> <host><path>"` exactly as the Endpoint was created
  (`"GET api.example.com/v1/*"`), and lists one entry per slot, with the
  pointer in `secretReference` and the Secret Reference's `name`:

  ```bash
  passport whoami --json | jq -r --arg ep 'GET api.example.com/v1/*' --arg n weather-key \
    '.allowedApiRefs[$ep][]? | select(.name == $n) | .secretReference'
  ```

  Anything else in `{{vault:…}}` passes through unchanged and surfaces as a
  401 from the upstream API.
- **The Proxy replaces only the `{{vault:…}}` text.**
  `Authorization: Bearer {{vault:<pointer>}}` arrives as `Bearer <secret>`.
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
- **After any grant change, run `passport refresh`, then read the pointer
  again.** The certificate lists the Endpoints granted when it was issued, and a
  new Access Grant comes with new pointers. Code that keeps a pointer needs
  the new one once its grant is renewed; tell the user when you write such code.
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

## Secret Vault (HashiCorp) in this setup

- Persistent: secrets live on a Docker volume and survive restarts. The
  container unlocks itself at start.
- The Proxy and the Secret Vault (HashiCorp) UI both use the root token (`VAULT_TOKEN` in
  `~/.passport/onboarding/proxy.env`). In production, the Proxy gets its own
  read-only token and people sign in as themselves.
- `VAULT_ADDR` and `VAULT_TOKEN` are HashiCorp's own variable names, not
  `PASSPORT_PROXY_`-prefixed.

## Sending a request through the Proxy

- **`passport request`** carries your certificate and renews it inline; prefer
  it for anything the agent sends:
  `passport request -X POST -H 'Authorization: Bearer {{vault:<pointer>}}' -d '{…}' -- https://api.example.com/x`.
  Put `--` before the URL: `-H` takes every value up to the next option, so a
  URL right after a header would be read as another header.
- **Other tools** go through the CLI's daemon (`HTTPS_PROXY=http://127.0.0.1:10144`),
  which `passport login` sets up (unverified; see `verification.md`). A
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
  expired; the request didn't go through the Proxy; the token is a Secret
  Reference's ID or name instead of your pointer, or a pointer from an earlier
  grant; the Reference points at a missing Secret Vault path or a secret without
  the key `value`; the credential belongs in a different slot.

## The demo API

`https://passport-skill-demo.mock.postman.postman.dev/` returns `200` only when
`x-demo-api-key` holds the public sample key `sdfdsfdsfsdfdfsdfds`, and `401`
for anything else, including the unsubstituted pointer. Both replies show the
first five characters and the length of what arrived
(`"key":"sdfds**************","key_length":19` on success). The sample key is
public, so it may appear in commands.
