# Troubleshooting (AWS single instance)


| Symptom | Cause / fix |
|---|---|
| `passport login` fails with `authenticated login session has no organization` | No Passport team yet. Create one at [https://app.usepassport.ai/dashboard](https://app.usepassport.ai/dashboard), then re-run `passport login`. See 1.1. |
| `Unknown options: --profile x --region y` | zsh didn't split a variable. Export `AWS_PROFILE`/`AWS_REGION` instead. |
| `UnauthorizedOperation` on `run-instances` | Missing EC2 permissions (table above); company accounts may need a platform request. |
| `InvalidParameterValue: Value (passport-proxy-…) for parameter iamInstanceProfile.name is invalid` | IAM propagation delay. Wait ~15 s and retry the launch. |
| `readyz` never 200 | Read the boot log (step 5). Common causes: registry key wrong/revoked (`docker login` fails → `docker pull` fails), role can't read the secrets (check the secret names/prefix), SG missing your *current* IP (your IP changed → `authorize-security-group-ingress` the new `/32`). |
| `docker login ociregistry.usepassport.ai` fails / no `PASSPORT_REGISTRY_KEY` | Stop and get one — [https://app.usepassport.ai/org/registry](https://app.usepassport.ai/org/registry) if you're admin, otherwise ask your team admin. Needs a team first (1.1). |
| `onhost`: "not registered with SSM" / `InvalidInstanceId` | Wait ~1–2 min after boot; the role must have the inline SSM policy (3.3) and the instance needs outbound internet (public subnet + public IP). |
| Proxy container exits immediately | `onhost 'docker logs pp-proxy-local 2>&1 \| tail -40'`. |
| `hashicorp vault: VAULT_ADDR is required` / `VAULT_TOKEN is required` | These two are the **plain Vault env var names**, not `PASSPORT_PROXY_`-prefixed like the rest. `/opt/passport/vault.env` must exist and be passed with `--env-file`. |
| Secret not found | The field inside must be named `value`, and `vaultKey` is relative to the `secret/` mount (`test-key`, not `secret/data/test-key`). The dev Vault is in-memory: re-seed (6.2) after the Vault container restarts. |
| `passport request` fails `not authorized for vault refs: [...]` though `whoami` shows the grant | The endpoint's `host` was registered **with** a port (6). Re-register with bare `localhost`, recreate the grant, re-run `passport setup`. |
| Echoed value is the literal `{{vault:demo}}`, no error | You used the reference's friendly name instead of its UUID. |
| `failed to decrypt vault reference: <uuid>` | The reference was encrypted under a *different* registration's key than the one running. Create a fresh namespace/reference/endpoint/grant under the current registration (6's second gotcha). |
| `/issue-cert` fails with `unknown kid "acs-bundle-..."` | `PASSPORT_PROXY_JWKS_URL` is wrong — it must be the bundle-issuer JWKS (`https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json`), not WorkOS's SSO JWKS. |
| `/issue-cert` 403 `teamId "org_..." is not authorized for this deployment` | `PASSPORT_PROXY_ALLOWED_TEAM_IDS` (user-data `ORG`) doesn't match your team ID, **or** MDM is forcing the CLI to the corporate proxy (setup says `(from macOS managed plist)`) → use the appendix. |
| `curl: (77) error setting certificate verify locations` | You used a private key as a CA cert. Fetch the real CA: `curl http://$EIP:8081/ca.pem`. |
| TLS error to the proxy: hostname mismatch / `certificate is not valid for` | The name you connect with isn't in `PASSPORT_PROXY_DATAPLANE_CERT_SANS` (user-data `SANS`). Use `$HOST`/`$EIP`, or recreate the instance with the right SANs. |
| `setup`: `invalid management URL: expected an HTTPS origin (or http://localhost for local dev)` | The CLI won't take `http://<public-ip>`. Use the CloudFront URL from 3.4 (`https://$CF_DOMAIN`), or step 7's localhost-forwarder fallback. |
| CloudFront returns 502/504 for `/ca.pem` | The proxy isn't up yet, or the security group doesn't allow the CloudFront prefix list on 8081 (3a). |
| Proxy container `Restarting`, log says `open /opt/passport/ca.pem: permission denied` | Key files must be readable by the container's non-root user (`chmod 0644`, see 4.1). Fix live: `onhost 'chmod 644 /opt/passport/{ca,ref,trust}.pem; docker restart pp-proxy-local; docker rm -f pp-echo; docker run -d --name pp-echo --restart unless-stopped --network container:pp-proxy-local -v /opt/passport/echo:/echo -w /echo node:20 node server.js'`. |
| `iam:AttachRolePolicy` AccessDenied | Expected for many IAM users; 3.3 uses an inline policy instead. |
| `create-secret`: already scheduled for deletion | See the note under 3.2 (pick a new NAME). |
| `passport setup` silently ignores `--proxy-url`/`--management-url`, or auto-runs setup against unfamiliar endpoints after login | MDM-managed Mac → MDM guide. |
| (MDM) `Error: No Passport proxy is configured for your team` right after a successful `login` in `pp-cli-linux` | Expected — auto-setup ran before a proxy was registered. Register (6), then run `setup` (A.4). |
| (MDM) Approval link says expired / browser can't reach `127.0.0.1:<port>/auth/callback` | Start the callback forwarder (A.3) *before* approving; if the link expired, restart `login`. |
| (MDM) `login` inside `pp-cli-linux` hangs, callback replay 404s | A stale `login` process is bound to an old port. Launch `login` detached (A.3), read the *current* log, or recreate the container (A.2). |
| (MDM) `ECONNREFUSED` running `setup`/`request` in `pp-cli-linux` | Unlike the local walkthrough, the proxy is on the internet, so `--network host` is only needed for the login callback; if you used a bridge network, outbound to `$EIP` still works — check the SG CIDR and that Docker Desktop egresses from the same public IP. |

