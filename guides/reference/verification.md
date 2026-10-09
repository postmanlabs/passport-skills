# What has been verified

The guides state rules, not history. This file records which parts have been
run for real, when, and on what. Add a row whenever a run confirms or breaks
something, and keep "Not verified yet" honest.

## Verified

| Date | Setup | What ran | Result |
|---|---|---|---|
| 2026-10-05 | Local Docker | Whole guide against the real `passport-proxy:latest` image and a real team: CLI install/login, registry credential, pull, proxy boot, Vault resolution, cert issuance, a secret delivered through the proxy (then an echo server, checked by sha256) | ✅ |
| 2026-10-05 | Local, MDM Mac | `mdm-macs.md` A.3: detached `login` plus the callback forwarder. An attached `login` killed by a timeout caused the earlier failures | ✅ |
| 2026-10-05 | Local | Retrying `passport login` on an account with no team shows no team-creation screen | Confirmed |
| 2026-10-06 | Local, MDM container path, daemon started by hand | `after-setup.md` part 2 with `postman-echo.com` and a fake value: both request forms delivered the Vault value, in a header and in a query parameter; the daemon renewed its expired certificate by itself | ✅ |
| before 2026-10-06 | AWS | The *previous* EC2 design (with Secrets Manager) ran end to end. On 2026-10-06 the guide was rewritten: no Secrets Manager, keys generated on the instance, an interactive registry login | Old design ✅; new design not yet run |
| 2026-10-07 | Local, MDM container path, cached image | The e2e test against the public demo API: the proxy reached it with no custom trust bundle, the `/` endpoint matched, `curl` and `passport request` returned `"key":"sdfds**************","key_length":19` | ✅ |
| 2026-10-07 | Local, MDM | A reference kept working after another proxy became the team default | ✅ |
| 2026-10-07 | `passport-service` code + live run | References are encrypted for the team's default proxy; restoring the previous default afterwards is safe; repairing a reference with `PUT … {"vaultKey":…}` works | ✅ |
| 2026-10-07 | Local, MDM container path | `after-setup.md` part 0 and the part 2 agent block (with the default switch) created all four objects for `GET postman-echo.com/headers`; the explicit request delivered the stored fake value | ✅ |
| 2026-10-07 | Local, MDM | `mdm-macs.md` A.5 (local): the daemon block in a clean shell returned `"key_length":19` (without the `export` lines, the pointer arrived unchanged); after the first 5-minute certificate expired, the daemon minted a new one on the next request | ✅ |
| 2026-10-08 | MDM Mac, CLI `0.6.0-canary-261008-055959` | `passport daemon status` shows `routing source   managed`; `auth status` and `whoami` show no managed sign | Observed |
| 2026-10-08 | Scripts only, with a mocked `aws` (zsh and bash) | `st` refuses empty, `None` and `null`; `onhost` returns the remote exit code and prints its stderr; a function failing under `set -e` skips zsh's `EXIT` trap, so AWS step 6 uses `\|\| die` instead | ✅ |

## Not verified yet

- **The AWS guide, end to end, in its current form.** This includes the
  2026-10-08 changes: the `run-instances` retry, the SSM wait check, the
  re-runnable step 6 with `die`, `PREFLIGHT_*` values, `cli`, and the
  security-group delete retry.
- `after-setup.md` part 2 on EC2.
- The non-MDM `passport setup` daemon install (`after-setup.md` part 2, step 5).
- `mdm-macs.md` A.5 on EC2 (the bridge-network daemon).
- `aws login` (AWS CLI 2.32 and later); the CLI tested was 2.31.
- The Windows commands (`after-setup.md` "Run it yourself" for PowerShell).
- A public download location for the Linux CLI build.
- A `{{vault:…}}` pointer in a request body or URL path (only headers and
  query parameters are tested).
- What `passport daemon status` shows on a Mac *without* MDM.
