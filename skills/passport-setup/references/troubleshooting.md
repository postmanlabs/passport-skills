# Troubleshooting

Find the script's `error.code` in the first table; symptoms seen outside the
script follow. Stop at a failure, show the user what happened and the fix, and
don't retry silently. What has been tested is in `verification.md`.

## Script error codes

| `error.code` | What it means | Fix |
|---|---|---|
| `unsupported_os` | Not macOS or Linux | Stop. Windows isn't supported yet. |
| `missing_tool` | A tool the step needs is absent | Run `doctor`; stage 3. |
| `name_taken` | A container named `passport-vault` or `passport-proxy` exists but this skill didn't make it | Never touch it. The user renames or removes it. |
| `docker_network`, `docker_volume`, `vault_start`, `vault_not_ready` | Docker couldn't start the Secret Vault (HashiCorp) | Check Docker is running; `docker logs passport-vault`. |
| `vault_init`, `vault_unseal`, `vault_kv`, `vault_seed` | The Secret Vault (HashiCorp) started but a setup command failed | `docker logs passport-vault`; rerun `vault up` (it's safe to repeat). |
| `vault_key_missing` | The Secret Vault (HashiCorp) is locked and its unseal key is gone | See **Secret Vault (HashiCorp) data lost**. |
| `vault_down`, `vault_first` | A later step needs the Secret Vault (HashiCorp) running | `vault up`. |
| `keygen` | openssl couldn't create the Proxy's keys | Check `openssl version`; rerun `proxy prepare`. |
| `prepare_first` | The files the user fills in don't exist yet | `proxy prepare`. |
| `key_empty` | `PASSPORT_API_KEY` in `api-key.env` is blank | The user pastes the key and saves the file. |
| `key_rejected` | Passport Cloud refused the API key (401/403) | The user creates a new key at `<app>/me/api-keys` and pastes it. |
| `not_admin` | The key belongs to a team member | The user creates the key as a team admin, or signs up fresh with a new team. |
| `me_unavailable` | `GET /public/v1/me` isn't on this Passport Cloud yet, so the team ID can't be read | Stop at the Proxy stage and tell the user it's waiting on that API (dependencies list). Never read the team ID from `passportrc`. |
| `other_proxy_configuration` | The team already has a Proxy Configuration that isn't the one in `proxy.env` | The user deletes it in the app. The skill never deletes it. |
| `team_unknown` | `PASSPORT_PROXY_ALLOWED_TEAM_IDS` is blank | Run `key check` first. |
| `proxy_id_empty`, `proxy_token_empty` | `PASSPORT_PROXY_ID` or `PASSPORT_PROXY_TOKEN` in `proxy.env` is blank | The user copies both from the Proxy Configuration in the app and saves. |
| `image_pull` | The Proxy image couldn't be downloaded | See **Proxy image**. |
| `proxy_run` | `docker run` failed for the Proxy | Ports 8443/8081 (and 443/80 with the `.localhost` names) must be free: `doctor`. |
| `proxy_crashed` | The Proxy exited or keeps restarting; the script stopped it | Read `error.logs`: the Proxy names the setting or key at fault. Fix it, then rerun `proxy start`. Keys that don't match what Passport Cloud holds: **Proxy keys lost**. |
| `proxy_not_found` | No Proxy Configuration in the team has the `PASSPORT_PROXY_ID` in `proxy.env` | The user copies the Proxy ID again from the app. |
| `proxy_setup_expired` | The enrollment token expired or was revoked before the Proxy registered | The user makes a new token on the Proxy Configuration page (`<app>/access-proxies`) and pastes it into `proxy.env`; rerun `proxy start`. |
| `proxy_disabled` | The Proxy Configuration is disabled in the app | The user enables it, then rerun `proxy start`. |
| `proxy_not_healthy` | After 90 s Passport Cloud still reports `not_connected` (never registered) or `unreachable` (no heartbeat for 3 minutes); the Proxy keeps retrying | Read `error.logs` for the reason (token refused, wrong Proxy ID, clock, network). Fix it, then rerun `proxy start`. |
| `refresh_failed` | `passport refresh` failed | `passport login` again. |
| `cli_signed_out` | The CLI's sign-in expired mid-call (`WORKOS_REAUTH_REQUIRED`) | `passport login`, then rerun the step. |
| `demo_first`, `check_first`, `verify_first` | A step ran out of order | Run the step the hint names. |
| `grant_missing` | Approved, but the Access Grant isn't visible yet | Wait a minute; rerun `demo apply`. |
| `no_pointer` | The client certificate has no pointer for the Endpoint, even after `passport refresh`: no active Access Grant covers it yet | Check the Access Grant in the app (pending, expired, or on another Resource Group), then rerun. |
| `demo_failed`, `handson_failed` | The call through the Proxy didn't pass | See **Calls through the Proxy**, using the HTTP status and proxy error in the hint. |
| `api_error` | The public API returned an unexpected status, or no reply at all (status `000`: network or VPN) | Show the status and its `code`; don't retry. |

## Calls through the Proxy

| Symptom | Cause / fix |
|---|---|
| `502` with `x-passport-proxy-error: unsupported-vault-type` | The Secret Reference's vault type isn't one this Proxy reads. Use HashiCorp. |
| `x-passport-proxy-error: missing-ref` or `unauthorized` | No Access Grant covers this `METHOD host/path`, or the certificate predates the grant: `passport refresh`. |
| `x-passport-proxy-error: vault-error` | The Secret Vault (HashiCorp) is down or locked: `vault up`. |
| Demo API answers 401 with `"key":"{{vau…"` | The pointer arrived unchanged: the request skipped the Proxy (old terminal without `HTTPS_PROXY`, or a `NO_PROXY` host), or it carried a Secret Reference's ID or name instead of the pointer from `passport whoami --json`. |
| `not authorized for vault refs` though the grant exists | The Endpoint `host` was stored with a port. Recreate it with a bare host, then `passport refresh`. |
| `failed to decrypt vault reference: <uuid>` | The Reference was encrypted for another Proxy. Create it again now that yours is the team's Proxy. |
| Secret value empty or not found | The Secret Vault path or key is wrong: path relative to `secret/`, value under the key `value`. `vault check <path>` reports both. |
| Endpoint works but isn't in the app | It has no Resource Group. Attach one. |
| `code=WORKOS_REAUTH_REQUIRED` | The CLI's login lapsed: `passport login`. |
| `echo $HTTPS_PROXY` is empty after login | The terminal predates login. Open a new one. |

## Proxy image

The Proxy image in `references/urls.env` must be public. A `404`, `403` or
`denied` on download means that tag isn't published yet; never ask for
registry credentials.
Tell the user the Proxy stage waits for the image (dependencies list).

## Proxy keys lost

`~/.passport/onboarding/keys/ref.pem` decrypts every Secret Reference made
for this Proxy. If it was deleted or changed, Passport Cloud refuses the Proxy
(`409`) and old References can't be decrypted. Explain this and stop: there's
no automatic fix. The user can delete the Proxy Configuration in the app and
start the Proxy stage again; the sample API's and the first API's References
then need creating again.

## Secret Vault (HashiCorp) data lost

If the `passport-vault-data` volume or `~/.passport/onboarding/vault/` is
gone, run `vault up`: it creates a fresh Secret Vault (HashiCorp), stores the demo secret again
and writes the new `VAULT_TOKEN` into `proxy.env`. Then `proxy start` (it
recreates the Proxy so it reads the new token). The user stores the first API's
secret again in the Secret Vault (HashiCorp) UI. References keep working: they point at paths.

## Coming back to a broken setup

| What broke | What to do |
|---|---|
| Docker isn't running | The user starts Docker Desktop, OrbStack or Colima. |
| A container stopped | `vault up` / `proxy start` start it again. |
| Secret Vault (HashiCorp) locked | It unlocks itself at start; if not, `vault up` unlocks it. |
| Proxy not Healthy | `proxy start` again, then follow its error code above. |
| CLI signed out | `passport login`. |
| The API key's team differs from the one recorded | Ask which team to continue with; a different team starts again from the sign-in step. |
| `~/.passport/onboarding/` deleted | **Proxy keys lost**: explain and stop. |

## Certificate errors on this machine

`curl: (60) unable to get local issuer certificate`, `self signed certificate
in certificate chain`, or Node's `UNABLE_TO_VERIFY_LEAF_SIGNATURE`. Check in
order and stop at the first that's wrong:

1. The trusted CA is this Proxy's: compare
   `openssl x509 -in ~/.passport/ca.pem -noout -fingerprint -sha256` with
   `curl -s <management URL>/ca.pem | openssl x509 -noout -fingerprint -sha256`.
   Different: `passport login` again.
2. macOS trusts it for SSL:
   `security verify-cert -c ~/.passport/ca.pem -p ssl -k /Library/Keychains/System.keychain`.
   Fails: the user runs `passport ca install`.
3. The tool reads the right trust store: curl `SSL_CERT_FILE`, Node
   `NODE_EXTRA_CA_CERTS`, Python `REQUESTS_CA_BUNDLE`.
4. The certificate is current: `passport whoami`. Expired: `passport login`.
5. The destination's own certificate: read `docker logs passport-proxy`.
