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
| 2026-10-12 | Install from GitHub, branch `fix/install-commands`, no GitHub credentials, sandboxed config dirs | Claude Code 2.1.287: `marketplace add` then `claude plugin install passport@passport-proxy-setup` and `passport-proxy-setup@passport-proxy-setup` both installed the whole skill folder. Codex 0.162.1: `codex plugin marketplace add … --ref` then `codex plugin add passport@passport-proxy-setup`; the skill is listed as `passport:passport-setup`. `npx skills@1.7.2 add` (Claude Code, Codex, Cursor) copied all 16 files into `.agents/skills/passport-setup` | ✅ |
| 2026-10-12 | Install, Cursor 3.23.12 loader code run outside the IDE (fake home) | The GitHub marketplace parser read the branch as marketplace `passport-proxy-setup` with plugin `passport` ("Postman Passport") and skill `passport-setup`; the local-plugin loader loaded `~/.cursor/plugins/local/passport` the same way. Without `.cursor-plugin/` it falls back to `.claude-plugin/` | ✅ (code only) |
| 2026-10-13 | Install from GitHub after the rename to `postmanlabs/passport-skills`, no GitHub credentials, sandboxed config dirs | With both `postmanlabs/passport-skills` and the old `postmanlabs/postman-passport-setup`: Claude Code 2.1.287 installed `passport@passport-proxy-setup` and `passport-proxy-setup@passport-proxy-setup`, and `marketplace update` worked; Codex 0.162.1 installed `passport@passport-proxy-setup`, and `marketplace upgrade` worked; `npx skills@1.7.2 add` copied all 16 files, and `skills check` found no update. Adding the marketplace again under the other name fails in both: Claude Code says its source doesn't match the `extraKnownMarketplaces` entry, and Codex says it is already added from a different source. `plugin@marketplace` installs still work. Switching takes `marketplace remove passport-proxy-setup` first; Claude Code then needs the plugin reinstalled, while Codex keeps it | ✅ |
| 2026-10-13 | Install from GitHub, branch `rename/marketplace-passport-skills` (marketplace renamed to `passport-skills`, alias entry removed), no GitHub credentials, sandboxed config dirs | Claude Code 2.1.287: `marketplace add postmanlabs/passport-skills#<branch>` registered marketplace `passport-skills`, and `claude plugin install passport@passport-skills` installed the skill. Codex 0.162.1: `marketplace add … --ref`, then `codex plugin add passport@passport-skills`. `npx skills@1.7.2 add` copied all 16 files of `passport-setup` | ✅ |

## Not verified yet

- Claude Code's `/plugin install passport --marketplace …` slash command (only
  its argument parser was read; the two-step form above was run).
- Cursor in the running IDE: the "Import from GitHub" marketplace flow (read
  from the app code, not clicked through), `/passport-setup` showing up, and
  `agent plugin marketplace add`.
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
