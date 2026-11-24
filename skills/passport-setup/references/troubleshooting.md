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
| `docker_network`, `docker_volume`, `vault_start`, `vault_not_ready` | Docker couldn't start HashiCorp Vault | Check Docker is running; `docker logs passport-vault`. |
| `vault_init`, `vault_unseal`, `vault_kv`, `vault_seed` | HashiCorp Vault started but a setup command failed | `docker logs passport-vault`; rerun `vault up` (it's safe to repeat). |
| `vault_key_missing` | Vault is locked and its unseal key is gone | See **HashiCorp Vault data lost**. |
| `vault_down`, `vault_first` | A later step needs HashiCorp Vault running | `vault up`. |
| `keygen` | openssl couldn't create the Proxy's keys | Check `openssl version`; rerun `proxy prepare`. |
| `prepare_first` | The files the user fills in don't exist yet | `proxy prepare`. |
| `key_empty` | `PASSPORT_API_KEY` in `api-key.env` is blank | The user pastes the key and saves the file. |
| `key_rejected` | Passport Cloud refused the API key (401/403) | The user creates a new key at `<app>/me/api-keys` and pastes it. |
| `not_admin` | The key belongs to a team member | The user creates the key as a team admin, or signs up fresh with a new team. |
| `me_unavailable` | `GET /public/v1/me` isn't on this Passport Cloud yet, so the team ID can't be read | Stop at the Proxy stage and tell the user it's waiting on that API (dependencies list). Never read the team ID from `passportrc`. |
| `other_proxy_configuration` | The team already has a Proxy Configuration that isn't the one in `proxy.env` | The user deletes it in the app. The skill never deletes it. |
| `team_unknown` | `PASSPORT_PROXY_ALLOWED_TEAM_IDS` is blank | Run `key check` first. |
| `proxy_token_empty` | `PASSPORT_PROXY_TOKEN` in `proxy.env` is blank | The user pastes the token and saves. |
| `image_pull` | The Proxy image couldn't be downloaded | See **Proxy image**. |
| `proxy_run` | `docker run` failed for the Proxy | Ports 8443/8081 (and 443/80 with the `.localhost` names) must be free: `doctor`. |
| `registration_token_rejected` | Passport Cloud rejected the registration token (401) | The user regenerates the token on the Proxy Configuration page and pastes it into `proxy.env`; rerun `proxy start`. |
| `reference_key_mismatch` | Passport Cloud holds a different reference key for this Proxy (409) | See **Proxy keys lost**. |
| `proxy_not_registered` | No registration within 60 s | Read `docker logs passport-proxy`; check the network can reach Passport Cloud. |
| `refresh_failed` | `passport refresh` failed | `passport login` again. |
| `demo_first`, `check_first`, `verify_first` | A step ran out of order | Run the step the hint names. |
| `grant_missing` | Approved, but the Access Grant isn't visible yet | Wait a minute; rerun `demo apply`. |
| `demo_failed`, `handson_failed` | The call through the Proxy didn't pass | See **Calls through the Proxy**, using the HTTP status and proxy error in the hint. |
| `api_error` | The public API returned an unexpected status | Show the status and its `code`; don't retry. |

## Calls through the Proxy

| Symptom | Cause / fix |
|---|---|
| `502` with `x-passport-proxy-error: unsupported-vault-type` | The Secret Reference's vault type isn't one this Proxy reads. Use HashiCorp. |
| `x-passport-proxy-error: missing-ref` or `unauthorized` | No Access Grant covers this `METHOD host/path`, or the certificate predates the grant: `passport refresh`. |
| `x-passport-proxy-error: vault-error` | HashiCorp Vault is down or locked: `vault up`. |
| Demo API answers 401 with `"key":"{{vau…"` | The pointer arrived unchanged: the request skipped the Proxy (old terminal without `HTTPS_PROXY`, or a `NO_PROXY` host), or it used the Reference's name instead of its UUID. |
| `not authorized for vault refs` though the grant exists | The Endpoint `host` was stored with a port. Recreate it with a bare host, then `passport refresh`. |
| `failed to decrypt vault reference: <uuid>` | The Reference was encrypted for another Proxy. Create it again now that yours is the team's Proxy. |
| Secret value empty or not found | The Vault path or key is wrong: path relative to `secret/`, value under the key `value`. `vault check <path>` reports both. |
| Endpoint works but isn't in the app | It has no Resource Group. Attach one. |
| `code=WORKOS_REAUTH_REQUIRED` | The CLI's login lapsed: `passport login`. |
| `echo $HTTPS_PROXY` is empty after login | The terminal predates login. Open a new one. |

## Proxy image

The Proxy image in `references/urls.env` must be public. A `403` or `denied`
on download means it isn't published yet; never ask for registry credentials.
Tell the user the Proxy stage waits for the image (dependencies list).

## Proxy keys lost

`~/.passport/onboarding/keys/ref.pem` decrypts every Secret Reference made
for this Proxy. If it was deleted or changed, Passport Cloud refuses the Proxy
(`409`) and old References can't be decrypted. Explain this and stop: there's
no automatic fix. The user can delete the Proxy Configuration in the app and
start the Proxy stage again; the demo and hands-on References then need
creating again.

## HashiCorp Vault data lost

If the `passport-vault-data` volume or `~/.passport/onboarding/vault/` is
gone, run `vault up`: it creates a fresh Vault, stores the demo secret again
and writes the new `VAULT_TOKEN` into `proxy.env`. Then `proxy start` (it
recreates the Proxy so it reads the new token). The user stores the hands-on
secret again in the Vault UI. References keep working: they point at paths.

## Coming back to a broken setup

| What broke | What to do |
|---|---|
| Docker isn't running | The user starts Docker Desktop, OrbStack or Colima. |
| A container stopped | `vault up` / `proxy start` start it again. |
| HashiCorp Vault locked | It unlocks itself at start; if not, `vault up` unlocks it. |
| Registration token rejected | `registration_token_rejected` above. |
| CLI signed out | `passport login`. |
| The API key's team differs from the one recorded | Ask which team to continue with; a different team starts again from the Account stage. |
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
