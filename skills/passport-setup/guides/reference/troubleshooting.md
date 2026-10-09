# Troubleshooting (both setups)

"Local *N*" means step *N* of `guides/local-docker.md`; "AWS *N*" means step
*N* of `guides/aws-single-instance.md`. The background for most fixes is in
`concepts.md`.

## Login, team, CLI and daemon

| Symptom | Cause / fix |
|---|---|
| `passport login` fails with `authenticated login session has no organization` | Your account has no Passport team yet. Retrying `login` won't show a team-creation screen, and the CLI's hint to "select an organization" is misleading. Create a team at <https://app.usepassport.ai/dashboard>, then run `passport login` again (local 1.1, AWS 1.1). |
| `api` prints `token expired`, an `api: … -> 401` line, or `st: refusing to record empty value` | The login token (about an hour) expired, or the call before it failed (its error is printed as `api: <method> <path> -> <status> …`). Run `passport auth status` (it refreshes the token; AWS on an MDM Mac: `cli auth status`), then re-run. AWS step 6 skips everything already recorded. |
| `setup: invalid management URL: expected an HTTPS origin (or http://localhost for local dev)` | Local: `http://localhost:8081`. AWS: the CloudFront URL `https://$CF_DOMAIN`. |
| `passport setup` exits `2` | Partial success: credentials are fine, but the daemon or environment step failed. Read setup's output and fix that part. Setup is **not complete** (AWS 8.4). |
| `echo $HTTPS_PROXY` is empty after setup | The terminal predates setup. Quit the terminal app completely and reopen it, or paste the `export …` lines setup printed. On Linux, export them yourself (`concepts.md`, "Two ways to send a request"). |
| Daemon request returns `502 cert unavailable — run passport setup` | No usable cert on disk. Run `passport setup`. If renewal keeps failing, the saved login has expired too: run `passport login`, then `passport setup`. |
| Daemon request returns `502 denied by daemon allowlist` | `~/.passport/daemon.yml` routes that host to `deny`. Check its `mode`. |
| A `localhost` / private-IP / `.internal` request bypasses Passport (the literal `{{vault:…}}` arrives) | Those hosts are in `NO_PROXY` by design. Use the explicit `--proxy …` form. |
| `curl: (60) SSL certificate problem: unable to get local issuer certificate` / `self signed certificate in certificate chain`, or a Node `UNABLE_TO_VERIFY_LEAF_SIGNATURE` | A **local certificate validation failure**. The CLI doesn't map these errors to a fix, so diagnose rather than assume: see the last section. |
| `passport request` prints `Error: … code=…` with no hint | It reports raw TLS/socket errors. Treat them like the row above. |

## Passport Cloud objects and secret injection

| Symptom | Cause / fix |
|---|---|
| `not authorized for vault refs: [...]` though `whoami` shows the grant | The endpoint `host` was registered **with** a port. Re-create it with a bare hostname, recreate the grant, and run `passport setup` again. |
| The demo API shows `"key":"{{vau…"` / `"key_length":46` (the pointer arrived unchanged) | The request didn't go through the proxy (daemon form in an old terminal without `HTTPS_PROXY`, or a `NO_PROXY` host), or you used the reference's name instead of its UUID. |
| `failed to decrypt vault reference: <uuid>` | The reference was encrypted for a different proxy: the team's **default** registration when it was created, or an earlier registration of yours with another key. Repair it as in `concepts.md`, "Secret references are encrypted for the team's default proxy". |
| Secret not found, or the injected value is empty | The Vault lost it (dev mode, in memory: a restart erases every value), or the key is wrong. `vaultKey` is relative to `secret/` (`demo-api-key`, not `secret/data/demo-api-key`) and the field must be `value`. Store it again: local, the hidden-prompt command in `after-setup.md` part 0; AWS, `sudo passport-vault-put <key>` in a session (or step 6's demo line). |
| `hashicorp vault: VAULT_ADDR is required` / `VAULT_TOKEN is required` | These are plain Vault variable names, not `PASSPORT_PROXY_`-prefixed. Local: check the `-e` flags of 4.4. AWS: `/opt/passport/vault.env` is missing or wasn't passed with `--env-file`; have the user re-run `sudo passport-start-proxy`. |
| `/issue-cert` fails with `unknown kid "acs-bundle-…"` | `PASSPORT_PROXY_JWKS_URL` must be the bundle issuer's JWKS, `https://api.usepassport.ai/api/v1/bundles/.well-known/jwks.json`, not WorkOS's SSO JWKS. |
| The endpoint works but doesn't show in the web UI | It was created without `resourceGroupIds`. Attach a resource group (`concepts.md`, "Endpoints"). |
| `DELETE /api/v2/tenant/config/<id>` returns 404 | Use the `proxyId` UUID, not the numeric `id`. |
| `DELETE /api/v2/secret-references/<id>` returns 409 | An endpoint still maps it. Delete the endpoint first. |

## Local Docker

| Symptom | Cause / fix |
|---|---|
| `docker login ociregistry.usepassport.ai` fails, or you have no registry key | Create one at <https://app.usepassport.ai/org/registry> (Org Settings → Registry; needs admin, and a team must exist), or ask your team admin. Nothing past local 2 works without it. |
| `docker: Cannot connect to the Docker daemon` | Docker isn't running. Start Docker Desktop. |
| Proxy container exits immediately | `docker logs pp-proxy-local` shows the real error. |
| `curl: (77) error setting certificate verify locations` | You used `/tmp/pp-local/ca.pem` as a CA certificate. It's a private key. Fetch the proxy's CA certificate: `curl http://localhost:8081/ca.pem`. |
| `bind: address already in use` when restarting the proxy | The old container is still running. `docker rm -f pp-proxy-local`, then run local 4.4 again. |

## AWS: sign-in, tools, permissions

| Symptom | Cause / fix |
|---|---|
| `aws …`: `Token has expired and refresh failed` / `The SSO session … has expired` | Run `aws sso login --profile <p>` in your own terminal (AWS 1.3). |
| `SessionManagerPlugin is not found` | Install the Session Manager plugin (AWS 1.2). It's required for AWS 5. |
| `AccessDenied … ssm:StartSession` / `ssm:SendCommand` | Your identity lacks the SSM statements in `templates/operator-iam-policy.json`. |
| `UnauthorizedOperation` on `run-instances` / `iam:… AccessDenied` | Compare your policy with `templates/operator-iam-policy.json`. If the guide uses an action the file lacks, fix the file. |
| `run-instances failed: … iamInstanceProfile.name is invalid` | IAM propagation took longer than A5's one-minute retry. Wait a little and re-run only A5. |
| `Unknown options: --profile x --region y` | zsh doesn't split a variable into words. Export `AWS_PROFILE`/`AWS_REGION` instead (`scripts/env.sh` does this). |
| `$PROXY_HOST` is your Mac's name / an `ec2-…` name you didn't expect | The manifest wasn't loaded. Start the block with `. "$SKILL_DIR/scripts/env.sh"`. In zsh, `$HOST` is built in, which is why the guide uses `PROXY_HOST`. |
| A block stops with your tool's own timeout during `aws cloudfront wait …` or `aws ec2 wait …` | Not an AWS failure: those waits can take 3–15 minutes. Re-run only the wait, with a longer timeout or in the background. |

## AWS: instance and proxy

| Symptom | Cause / fix |
|---|---|
| `instance … not Online in SSM after 5 minutes` (AWS 4) | The role needs the inline SSM policy (A3), and the instance needs outbound internet (public subnet and public IP). Check the EC2 console's system log for the bootstrap. |
| `onhost: remote command Failed (exit N)` | The remote command's stderr is printed just above. For boot problems read `/var/log/passport-bootstrap.log`: `onhost 'tail -30 /var/log/passport-bootstrap.log'`. |
| `passport-start-proxy`: `unauthorized` / `denied` on `docker pull` | Wrong or revoked registry key, or `docker login` was skipped. Re-run AWS 5's `sudo docker login …` and paste the key again. |
| Proxy container `Restarting`, log `open /opt/passport/keys/ca.pem: permission denied` | The keys must be readable by the proxy's non-root user. `passport-start-proxy` sets ownership from the image's `User`. Check with `onhost 'docker image inspect -f "{{.Config.User}}" ociregistry.usepassport.ai/passport/passport-proxy:latest; ls -l /opt/passport/keys'`. |
| `https://$CF_DOMAIN/ca.pem` returns 502/504 | The proxy isn't running (AWS 5 not done yet), CloudFront is still deploying, or the security group doesn't allow the CloudFront prefix list on 8081. |
| `https://$CF_DOMAIN/ca.pem` never returns 200 | Run `onhost 'docker ps -a; curl -s -o /dev/null -w %{http_code} http://localhost:8081/readyz'`, then read `/var/log/passport-bootstrap.log` on the instance. |
| TLS hostname mismatch to the proxy (`certificate is not valid for …`) | The name you connect with isn't in `PASSPORT_PROXY_DATAPLANE_CERT_SANS` (from user-data `SANS`). Use `$PROXY_HOST` or `$EIP`. |
| `setup` returns 403 `teamId "org_…" is not authorized for this deployment` | `ORG` in user-data doesn't match your team, **or** this is an MDM-managed Mac (see below). To fix `ORG` without rebuilding: `mdm-macs.md`, "Found MDM after AWS step 3". |
| The 8443 requests time out after your network changed | Your public IP changed, so the security group's `/32` no longer matches. Updating the rule is an AWS change: show an approval block first. |
| `delete-security-group`: `DependencyViolation` | The terminated instance's network interface hasn't been released yet. Step 10 retries for a minute; if it still fails, wait and re-run that line. |

## MDM-managed Mac

| Symptom | Cause / fix |
|---|---|
| CLI output says `(from macOS managed plist)`, `passport daemon status` shows `routing source managed`, or `whoami` says `Managed Passport credentials could not be verified` | The CLI is pinned to the organisation's proxy. Use `mdm-macs.md`. |
| `setup` returns 403 `teamId "org_…" is not authorized for this deployment`, and your proxy's logs show no request | The request never reached your proxy: MDM sent it to the organisation's proxy. Use `mdm-macs.md`. |
| `passport setup` silently ignores `--proxy-url`/`--management-url`, or `login` auto-runs setup against endpoints you didn't choose | Same cause. Use `mdm-macs.md`. |
| `Error: No Passport proxy is configured for your team` right after `login` in `pp-cli-linux` | Expected: login's auto-setup ran before a proxy was registered. Register first (local 5 / AWS 6), then run setup (`mdm-macs.md`, A.4). |
| The approval link says expired, or the browser can't reach `127.0.0.1:<port>/auth/callback` | Start the callback forwarder (A.3) *before* approving. If the link expired, restart `login` (A.3) and approve promptly. |
| `login` inside `pp-cli-linux` hangs, or the callback replay returns 404 / connects to the wrong thing | A stale `login` process from an earlier attempt (killed by a timeout while waiting for approval) is bound to an old port. Launch `login` detached (A.3) and read the *current* log; or recreate the container (A.2). |
| `ECONNREFUSED 127.0.0.1:8081` / `:8443` running `setup`, `whoami` or `request` inside `pp-cli-linux` (local) | The container was started on `pp-net` instead of `--network host`. A bridge-network container has its own loopback. Recreate it with `--network host` (A.2). |
| The A.5 daemon answers `502`, and its log says `Passport daemon ownership state has unsafe permissions` | It was given the shared `~/passport-cli-dl/.passport`. Use A.5 as written: the daemon gets its own private folder. |

## Diagnosing a local certificate validation failure

Check in this order, and stop at the first one that's wrong. `<mgmt>` is
`http://localhost:8081` (local) or `https://$CF_DOMAIN` (AWS); `$D` is your
credentials folder (`~/.passport`, or `~/passport-cli-dl/.passport` on an MDM
Mac).

1. **Is the CA you trust the one the proxy uses?** Compare
   `openssl x509 -in $D/ca.pem -noout -fingerprint -sha256` with
   `curl -s <mgmt>/ca.pem | openssl x509 -noout -fingerprint -sha256`.
   - **If they differ:** `$D` is from another proxy or an earlier instance.
     Run `passport setup` with this proxy's URLs again, then
     `passport ca install` again.
2. **Is it trusted for the SSL policy (macOS)?** Run
   `security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain`.
   If it fails, or `passport ca status` says not trusted, the user runs
   `passport ca install` (needs sudo). `ca status` alone doesn't check the
   trust setting.
3. **Does the tool use the right trust store?**
   - **curl:** pass `--cacert` (explicit form), or rely on `SSL_CERT_FILE`
     (daemon form, new terminal).
   - **Node:** needs `NODE_EXTRA_CA_CERTS`; `ca install` doesn't cover Node.
   - **Python requests:** needs `REQUESTS_CA_BUNDLE`.
   - **Check:** `env | grep -E 'SSL_CERT_FILE|NODE_EXTRA_CA_CERTS|REQUESTS_CA_BUNDLE'`.
4. **Are the cert and the login still valid?** `passport whoami`: a `notAfter`
   in the past, or "credentials could not be verified" / "do not match the
   active login profile", means run `passport login`, then `passport setup`.
   Re-logging in fixed this once, but apply it only when this step shows the
   problem.
5. **Is it the destination's own certificate?** The proxy validates the real
   destination with its own trust bundle, so a destination with a private or
   self-signed certificate fails there, not on your machine. Check the proxy's
   log: `docker logs pp-proxy-local 2>&1 | tail -20` (local) or
   `onhost 'docker logs pp-proxy-local 2>&1 | tail -20'` (AWS).
