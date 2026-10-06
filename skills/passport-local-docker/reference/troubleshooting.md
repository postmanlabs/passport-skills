# Troubleshooting (local Docker)


| Symptom | Cause / fix |
|---|---|
| `passport login` fails with `authenticated login session has no organization` (or similar) | Your account has no Passport team yet. Retrying `login` won't show a team-creation screen — go create one directly at [https://app.usepassport.ai/dashboard](https://app.usepassport.ai/dashboard), then re-run `passport login`. See step 1.1. |
| `docker login ociregistry.usepassport.ai` fails, or you don't have a `PASSPORT_REGISTRY_KEY` at all | Stop and get one — regenerate/create it yourself at [https://app.usepassport.ai/org/registry](https://app.usepassport.ai/org/registry) if you have admin access, otherwise ask your team admin. Nothing past step 2 works without this. Also needs a team to exist first (step 1.1). |
| `docker: Cannot connect to the Docker daemon` | Docker isn't running — start Docker Desktop. |
| Proxy container exits immediately | `docker logs pp-proxy-local` for the real error. |
| `hashicorp vault: VAULT_ADDR is required` / `VAULT_TOKEN is required` | These two are the **plain Vault env var names**, not `PASSPORT_PROXY_`-prefixed like the rest. |
| Secret not found (HashiCorp) | Confirm it was written via `vault kv put secret/<name> value=...` — the field inside must be named `value`, and the full path is `secret/data/<name>`. |
| `passport request` fails `not authorized for vault refs: [...]` even though `passport whoami` shows the matching grant | The endpoint's `host` was registered **with** a port (step 5.2). Re-register with a bare hostname, recreate the grant, re-run `passport setup`. |
| Echoed value is the literal string `{{vault:demo}}` instead of a sha256, no error | You used the secret reference's friendly name instead of its UUID in `{{vault:...}}`. |
| `/issue-cert` fails with `unknown kid "acs-bundle-..."` | `PASSPORT_PROXY_JWKS_URL` is wrong — it must be the bundle-issuer JWKS (`https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json`), not WorkOS's SSO JWKS. |
| `curl: (77) error setting certificate verify locations` | You tried to use `/tmp/pp-local/ca.pem` as a CA cert — it's only a private key. Fetch the real cert from the running proxy: `curl http://localhost:8081/ca.pem`. |
| `bind: address already in use` restarting the proxy | The old container is still running — `docker rm -f pp-proxy-local` first, or just reuse `docker rm -f` + `docker run` together as in step 7. |
| `listen EADDRINUSE :9443` starting the echo server | A previous echo sidecar is still up: `docker rm -f pp-echo`. |
| `failed to decrypt vault reference: <uuid>` | That secret reference was encrypted under a *different* proxy registration's key than the one currently running. Create a fresh namespace/secret-reference/endpoint/grant under the current registration (see step 5.2's second gotcha). |
| `passport whoami` says `Managed Passport credentials could not be verified. Run passport setup again.` | MDM-managed Mac: the CLI is reading org-managed endpoints. Confirm by running `passport login` — if its output says `(from macOS managed plist)`, use the MDM guide. |
| (MDM guide) `Error: No Passport proxy is configured for your team` right after a successful `login` in `pp-cli-linux` | Expected — auto-setup ran before a proxy was registered. Register the proxy (step 5.1), then run `setup` (A.4). |
| (MDM guide) Approval link says expired / browser can't reach `127.0.0.1:<port>/auth/callback` | Start the callback forwarder from A.3 *before* approving; if the link expired, restart `login` (A.3) and approve promptly. |
| `setup` fails `POST /issue-cert returned 403: ... teamId "org_..." is not authorized for this deployment` even though `PASSPORT_PROXY_ALLOWED_TEAM_IDS` is correct, and `docker logs pp-proxy-local` shows no request | The request never reached your proxy: MDM is forcing the CLI to the corporate proxy (`setup` output says `(from macOS managed plist)`). Use the MDM guide. |
| `passport setup` silently ignores `--proxy-url`/`--management-url`, or auto-runs setup against unfamiliar endpoints right after login | MDM-managed Mac. See the MDM guide below. |
| (MDM guide) `login` inside `pp-cli-linux` hangs, then the callback replay 404s or connects to the wrong thing | A stale, zombie `login` process from an earlier attempt (killed by a timeout while waiting for browser approval) is still bound to an old port. Launch `login` detached (A.3) so it isn't tied to any timeout, and always read the *current* log for the current code/URL — don't replay an old one. |
| (MDM guide) `ECONNREFUSED 127.0.0.1:8081`/`:8443` running `setup`/`whoami`/`request` inside `pp-cli-linux` | The container was started with `--network pp-net` instead of `--network host` — a bridge-network container has its own isolated loopback and can't reach the proxy's published ports via `localhost`. Recreate it with `--network host` (A.2). |

