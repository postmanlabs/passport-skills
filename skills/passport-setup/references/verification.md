# What has been tested

The single record of what was run, where and when. Static reading of source is
marked as such; it isn't a test.

## Run

2026-11-24 · macOS (Darwin 25.5, arm64) · `/bin/bash` 3.2.57 · Docker 29.6.2 ·
`passport-onboard` with test-only Docker names:

- `status`, `status --line`, `mark`, `doctor`, `demo plan`, `handson plan`:
  correct JSON and exit codes; unknown stage exits 1.
- `vault up`: starts `hashicorp/vault:2.2.1`, initialises it, enables
  `secret/` (KV v2), stores `secret/demo-api-key`. Running it twice changes
  nothing. After `docker restart` the Vault is unlocked again. After the
  container is removed and recreated, the secrets are still there. The UI
  answers 200.
- `vault check`: reports a missing path, and a secret without the key `value`,
  without printing any value.
- `proxy prepare`: creates `ca.pem`, `ref.pem`, `api-key.env`, `proxy.env`
  (all owner-only) and fills every skill-owned line of `proxy.env`.
- `proxy start`: stops with `image_pull` because the Proxy image tag
  `onboarding-beta` isn't published yet (404).
- `proxy start` with a Proxy image built locally from the beta source and a
  fake registration token: the Proxy starts as the host user, reads its keys
  from the read-only mount and its settings from `proxy.env`, reaches Passport
  Cloud, and is refused with 401. The script reports
  `registration_token_rejected` in about 7 s and stops the container so its
  restart policy doesn't retry forever.
- Proxy console on the same image (run without registration): `/console`
  answers 200; `/auth/login` accepts `admin` / `passport-local` from
  `proxy.env` (200) and refuses a wrong password (401). With the file audit
  sink from `proxy.env`, the Proxy writes `audit/audit.jsonl` as the host user
  and the console's audit page (`/audit/ui`, `/audit/api/list`) answers 200 and
  lists that file. No request went through, so no audit event was seen yet.

2026-11-24 · every `passport-onboard` branch against stand-ins for `docker`,
`curl` and `passport` (44 cases, all passing on macOS bash 3.2 and on Debian
bash 5.2 with GNU tools): `key check` for an admin, a member, a rejected key,
a missing `/me` and another team's Proxy Configuration; `proxy start` for an empty token, a
registration, a reuse without recreating, a 401 token, a 409 key mismatch, a
failed download and a Healthy status; `demo apply` creating, reusing across
paginated lists without writes, a pending Access Request and a 500;
`demo verify` passing, receiving the unswapped pointer, and a Proxy refusal;
`handson check` complete and incomplete, `verify` through the Secret
Reference, `finish` with the first key still live and revoked; public API
calls through the Proxy after the hands-on; no network, an API error during the hands-on check, a non-JSON reply, and an expired CLI sign-in mid-call, each reported as a clear error; `status` resuming, and noticing a
stopped Vault and a signed-out CLI.

## Not run yet

Blocked by missing pieces (dependencies list): `key check` against a real
`GET /public/v1/me`, a real Proxy registration (needs a public Proxy image and
a real token), and everything after it against beta: `passport login` finding
the Proxy, `demo apply/verify`, `handson check/verify/finish`, resume after a
reboot. HashiCorp Vault and the Proxy on Linux Docker.

## Read in source, not run (beta, 2026-11-24)

- The Proxy registers with `PASSPORT_PROXY_TOKEN` and learns its ID from the
  token (it reads no `PASSPORT_PROXY_ID` variable), still requires
  `PASSPORT_PROXY_ALLOWED_TEAM_IDS`, reads KV v2 key `value`, replaces only
  the `{{vault:…}}` text in headers, and matches `*` methods and trailing-`*`
  paths.
- Passport Cloud approves an admin's request for themselves, and stores the
  Proxy's public URLs at registration; the CLI (0.9.4 beta) reads them after
  login to find the Proxy.

## Assumptions to check on the first full run

- `passport login` sets up the daemon and `HTTPS_PROXY` on its own.
- `passport request --show-headers` prints the status line and headers, a
  blank line, then the body.
- The Proxy reads its key files on Linux when run with the host user's ID
  (`--user`).
- `*.localhost` resolves to 127.0.0.1 for the CLI; otherwise the script uses
  `https://localhost:8443`.
