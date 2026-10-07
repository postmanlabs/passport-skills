# Troubleshooting (AWS single instance)

Step numbers refer to `guides/aws-single-instance.md`.

## Sign-in, tools, permissions

| Symptom | Cause / fix |
|---|---|
| `passport login` fails with `authenticated login session has no organization` | Your account has no Passport team yet. Create one at <https://app.usepassport.ai/dashboard>, then run `passport login` again (step 1.1). |
| `aws …`: `Token has expired and refresh failed` / `The SSO session … has expired` | Run `aws sso login --profile <p>` in your own terminal (step 1.3). |
| `SessionManagerPlugin is not found` | Install the Session Manager plugin (step 1.2). It's required for step 5. |
| `AccessDenied … ssm:StartSession` / `ssm:SendCommand` | Your identity lacks the SSM statements in `templates/operator-iam-policy.json`. |
| `UnauthorizedOperation` on `run-instances` / `iam:… AccessDenied` | Compare your policy with `templates/operator-iam-policy.json`. If the guide uses an action the file lacks, fix the file. |
| `InvalidParameterValue … iamInstanceProfile.name is invalid` | IAM propagation delay. Wait about 15 s and re-run only step A5. |
| `Unknown options: --profile x --region y` | zsh doesn't split a variable into words. Export `AWS_PROFILE`/`AWS_REGION` instead (`scripts/env.sh` does this). |
| `$PROXY_HOST` is your Mac's name / an `ec2-…` name you didn't expect | The manifest wasn't loaded. Start the block with `. "$REPO/scripts/env.sh"`. In zsh, `$HOST` is built in, which is why this guide uses `PROXY_HOST`. |

## Instance and proxy

| Symptom | Cause / fix |
|---|---|
| Instance never shows `Online` in SSM | Wait 1–2 min after boot. The role needs the inline SSM policy (A3), and the instance needs outbound internet (public subnet and public IP). |
| `passport-start-proxy`: `unauthorized` / `denied` on `docker pull` | Wrong or revoked registry key, or `docker login` was skipped. Re-run step 5's `sudo docker login …` and paste the key again. |
| Proxy container `Restarting`, log `open /opt/passport/keys/ca.pem: permission denied` | The keys must be readable by the proxy's non-root user. `passport-start-proxy` sets ownership from the image's `User`. Check with `onhost 'docker image inspect -f "{{.Config.User}}" ociregistry.usepassport.ai/passport/passport-proxy:latest; ls -l /opt/passport/keys'`. |
| `hashicorp vault: VAULT_ADDR is required` / `VAULT_TOKEN is required` | `/opt/passport/vault.env` is missing, or wasn't passed with `--env-file`. Re-run `sudo passport-start-proxy`. |
| Secret not found / the injected value is empty | Either the Vault lost it, or the key is wrong. The dev Vault is in memory, so **a restart of `pp-vault-dev` erases every value**; re-store with `passport-vault-put` (or step 6's demo line). The `vaultKey` is relative to `secret/` (`test-key`, not `secret/data/test-key`), and the field must be `value`. |
| `https://$CF_DOMAIN/ca.pem` returns 502/504 | The proxy isn't running (step 5 not done yet), CloudFront is still deploying, or the security group doesn't allow the CloudFront prefix list on 8081. |
| `https://$CF_DOMAIN/ca.pem` never returns 200 | Run `onhost 'docker ps -a; curl -s -o /dev/null -w %{http_code} http://localhost:8081/readyz'`, then read `/var/log/passport-bootstrap.log` on the instance. |
| TLS hostname mismatch to the proxy (`certificate is not valid for …`) | The name you connect with isn't in `PASSPORT_PROXY_DATAPLANE_CERT_SANS` (from user-data `SANS`). Use `$PROXY_HOST` or `$EIP`. |
| `/issue-cert` fails with `unknown kid "acs-bundle-…"` | The JWKS URL must be the bundle issuer's: `https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json`. |
| `setup` returns 403 `teamId "org_…" is not authorized for this deployment` | `ORG` in user-data doesn't match your team, **or** MDM is in play (setup says `(from macOS managed plist)`). For MDM, use `aws-mdm-macs.md`. |

## CLI, daemon and certificates

| Symptom | Cause / fix |
|---|---|
| `setup: invalid management URL: expected an HTTPS origin (or http://localhost for local dev)` | Use the CloudFront URL `https://$CF_DOMAIN` (step 3, A4). |
| `passport setup` exits `2` | Partial success: credentials are fine, but the daemon or environment step failed. Read setup's output and fix that part. Setup is **not complete** (step 8.5). |
| `echo $HTTPS_PROXY` is empty after setup | The terminal predates setup. Quit the terminal app completely and reopen it, or paste the `export …` lines setup printed. On Linux, export them yourself (step 8.3). |
| Daemon request returns `502 cert unavailable — run passport setup` | No usable cert on disk. Run `passport setup`. If renewal keeps failing, the saved login has expired too: run `passport login`, then `passport setup`. |
| Daemon request returns `502 denied by daemon allowlist` | `~/.passport/daemon.yml` routes that host to `deny`. Check its `mode`. |
| A `localhost` / private-IP / `.internal` request bypasses Passport (the literal `{{vault:…}}` arrives) | Those hosts are in `NO_PROXY` by design. Use the explicit `--proxy …` form (step 8.2). |
| `curl: (60) SSL certificate problem: unable to get local issuer certificate` / `self signed certificate in certificate chain`, or a Node `UNABLE_TO_VERIFY_LEAF_SIGNATURE` | The **local certificate validation failure**. The CLI doesn't map these errors to a fix, so diagnose rather than assume. Re-logging in fixed it once, but that won't always be the cause. Work through the next table. |
| `passport request` prints `Error: … code=…` with no hint | It reports raw TLS/socket errors. Treat them like the row above. |

### Diagnosing a local certificate validation failure

Check in this order, and stop at the first one that's wrong:

1. **Is the CA you trust the one the proxy uses?** Compare
   `openssl x509 -in ~/.passport/ca.pem -noout -fingerprint -sha256` with the
   CA served by the proxy:
   `curl -s https://$CF_DOMAIN/ca.pem | openssl x509 -noout -fingerprint -sha256`.
   - **If they differ:** `~/.passport` is from another proxy or an earlier
     instance. Run `passport setup` with this proxy's URLs again, then
     `passport ca install` again.
2. **Is it trusted for the SSL policy (macOS)?** Run
   `security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain`.
   - **If verification fails, or `passport ca status` says not trusted:** run
     `passport ca install` **[you]**, which needs sudo.
   - **Note:** `passport ca status` checks only that the cert is present, not
     its trust setting, so `verify-cert` is the real test.
3. **Does the tool use the right trust store?**
   - **curl:** pass `--cacert` (explicit form), or rely on `SSL_CERT_FILE`
     (daemon form, new terminal).
   - **Node:** needs `NODE_EXTRA_CA_CERTS`; `ca install` doesn't cover Node.
   - **Python requests:** needs `REQUESTS_CA_BUNDLE`.
   - **Check:** `env | grep -E 'SSL_CERT_FILE|NODE_EXTRA_CA_CERTS|REQUESTS_CA_BUNDLE'`.
4. **Are the cert and the login still valid?** `passport whoami`: a
   `notAfter` in the past, or "credentials could not be verified" / "do not match
   the active login profile", means you should run `passport login` then
   `passport setup`. This is the re-login fix. Apply it only when this step
   shows the problem.
5. **Is it the destination's own certificate?** The proxy validates the real
   destination with its own trust bundle. A destination with a private or
   self-signed certificate fails there, not on your machine. Check
   `onhost 'docker logs pp-proxy-local 2>&1 | tail -20'`.

## Passport Cloud objects

| Symptom | Cause / fix |
|---|---|
| `not authorized for vault refs: [...]` though `whoami` shows the grant | The endpoint `host` was registered **with** a port. Re-create it with a bare hostname, recreate the grant, and run `passport setup` again. This error is also the *expected* result of protection demo 11.A. |
| The demo API shows `"key":"{{vau…"` / `"key_length":46` (the pointer arrived unchanged) | Either the request didn't go through the proxy (daemon form in an old terminal without `HTTPS_PROXY`, or a `NO_PROXY` host), or you used the reference's name instead of its UUID. |
| `failed to decrypt vault reference: <uuid>` | The reference was created under a different proxy registration (key) than the one running. Create a fresh reference, endpoint and grant under the current registration. |
| The endpoint works but doesn't show in the web UI | It was created without `resourceGroupIds`. Attach a resource group (step 6). |
| `api` prints `token expired` / an ID comes back empty | Run `passport auth status` to refresh the login token, then re-run only the missing lines. |
| `DELETE /api/v2/tenant/config/<id>` returns 404 | Use the `proxyId` UUID, not the numeric `id`. |
| `DELETE /api/v2/secret-references/<id>` returns 409 | An endpoint still maps it. Delete the endpoint first (step 12's order). |

## MDM-managed Mac

| Symptom | Cause / fix |
|---|---|
| CLI output says `(from macOS managed plist)`, or `whoami` says `Managed Passport credentials could not be verified` | The CLI is pinned to the organisation's proxy. Use `aws-mdm-macs.md`. |
| (MDM) `Error: No Passport proxy is configured for your team` right after `login` in `pp-cli-linux` | Expected: auto-setup ran before a proxy was registered. Register first (step 6), then run setup (A.4). |
| (MDM) The approval link says expired, or the browser can't reach `127.0.0.1:<port>/auth/callback` | Start the callback forwarder (A.3) *before* approving. If the link expired, restart `login`. |
| (MDM) `login` inside `pp-cli-linux` hangs, or the callback replay returns 404 | A stale `login` process is bound to an old port. Launch `login` detached (A.3), or recreate the container (A.2). |
