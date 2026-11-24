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
- `proxy start`: stops with `image_pull` because the beta Proxy image returns
  403.

## Not run yet

Blocked by missing pieces (dependencies list): `key check` (needs
`GET /public/v1/me`), Proxy registration (needs a public Proxy image), and
everything after it: `passport login` finding the Proxy, `demo apply/verify`,
`handson check/verify/finish`, resume after a reboot, Linux.

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
