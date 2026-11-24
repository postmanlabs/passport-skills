---
name: passport-setup
description: >
  Set up Postman Passport for one developer on their own machine (macOS or Linux): a Passport Proxy
  and a Secret Vault (HashiCorp) in Docker, the Passport CLI signed in, a verified demo call, and a hands-on
  round where the user stores a key in the Secret Vault (HashiCorp) and calls an API with only a pointer. Use when the user
  says "set up passport", "setup passport", "run Passport locally", "install the Passport proxy",
  or wants to stop putting API keys in .env files and doesn't have Passport running yet. Also use
  to resume or check an earlier Passport setup on this machine. Once Passport is set up, the
  passport-public-api skill registers APIs and credentials through the Passport public API.
---

# Passport setup

You walk a developer through setting up Passport on their machine, from first
introduction to a call they built themselves. `$SKILL_DIR` is this skill's
folder; everything it needs is inside it.

Read `references/concepts.md` before the first stage. The stage-by-stage copy
is in `references/stages.md`; follow it in order.

## Rules

1. **Secrets never go through the chat.** The user pastes them into the files
   or the Secret Vault (HashiCorp) UI the stages name. If a secret lands in the chat
   anyway, tell the user to revoke it and make a new one.
2. **Never read `~/.passport/passportrc`** (or `~/.passport-beta/passportrc`).
   It holds live CLI tokens. Never print the contents of the files in
   `~/.passport/onboarding/` or run `docker inspect` on the Proxy's env.
3. **Never approve your own Access Request.** An admin's request for
   themselves is approved by the service; anything else is the user's decision.
4. **Never delete what you didn't make.** Not a Proxy Configuration (the user
   deletes it in the app), not a Docker container without this skill's label,
   not a Passport object. The script reuses objects by name and deletes none.
5. **Show the plan before creating anything,** and install a tool only after
   the user says yes. Commands that need `sudo`, and the Passport CLI
   installer, the user runs in their own terminal.
6. **What the user types is always a real tool:** the Passport app, the
   Secret Vault (HashiCorp) UI, their editor, `passport`, `docker`, an installer. Never
   ask the user to run `passport-onboard`; it's yours.
7. **Report what the script reports.** One line per check, failures included.
   On an error, stop, show `error.hint`, look the code up in
   `references/troubleshooting.md`, and don't retry silently.
8. **Name stages by what they do** ("the Proxy stage"), never by number.
9. **Use the glossary's capitalised terms** (Proxy, Secret Vault, Secret
   Reference, Namespace, Endpoint, Access Grant, Proxy Configuration) and say
   "Passport Cloud", never "Postman Cloud".

## The script

Run `"$SKILL_DIR/scripts/passport-onboard" <command>`. Every command prints one
JSON object:

```json
{"ok": true, "stage": "vault", "data": {}, "next": {"who": "user", "say": "…", "run": "…"}}
{"ok": false, "stage": "proxy", "error": {"code": "key_rejected", "hint": "…"}}
```

Exit code `0` = done, `2` = waiting on the user (relay `next.say` or
`error.hint`, then wait), `3` = something earlier is missing (do what the hint
says), `1` = an error. Turn `data` into plain sentences or a short table; never
paste raw JSON at the user. State lives in `~/.passport/onboarding/state.json`.

| Command | Does |
|---|---|
| `status` / `status --line` | OS check, what's done (checked against Docker and the CLI), the progress line |
| `mark <stage>` | Records a stage the user finished: `welcome`, `setup-type`, `account`, `tour` |
| `doctor` | Machine check, with an install command for anything missing |
| `vault up` · `vault check <path>` | Starts the Secret Vault (HashiCorp); checks a secret exists with the key `value` |
| `proxy prepare` · `key check` · `proxy start` | The Proxy's keys and files; the API key and team; start and registration |
| `cli check` | Is the Passport CLI signed in |
| `demo plan` · `demo apply` · `demo verify` | The demo objects and the proof call |
| `handson plan` · `check` · `verify` · `finish` | The values to create, the check of what the user made, the call, revoking the first key |

## Stages

Start every stage message with the progress line (`status --line`). Ask
choices with your menu tool (in Claude Code, `AskUserQuestion`: 2–4 options,
header ≤ 12 characters), or a numbered list where there is none. End a stage
with the docs link (`PASSPORT_DOCS_URL` in `references/urls.env`) for anyone
who'd rather do it by hand.

| Stage | Who | Script |
|---|---|---|
| Welcome | agent | `status`, then `references/welcome.md` as written |
| Setup type | user | `mark setup-type` |
| Machine check | agent; the user approves installs | `doctor` |
| Account | user, in the browser | `mark account` |
| Local Vault | agent | `vault up` |
| Proxy | user fills two files, agent starts it | `proxy prepare`, `key check`, `proxy start` |
| CLI sign-in | agent runs `passport login`, user approves | `cli check` |
| Demo | agent, after the user OKs the plan | `demo plan`, `demo apply`, `demo verify` |
| Tour | user, in the app | `mark tour` |
| Hands-on | user builds, agent checks | `handson plan`, `check`, `verify`, `finish` |

Coming back later: `status` reports `resume: true`; follow "Coming back" in
`references/stages.md`.

## What the skill leaves on the machine

- Docker: `passport-vault`, `passport-proxy`, network `passport-net`, volume
  `passport-vault-data`, all labelled `com.postman.passport-onboarding`.
- `~/.passport/onboarding/`: `state.json`; `proxy.env` (the Proxy's settings,
  including the Secret Vault token); `api-key.env` until the hands-on deletes it;
  `keys/` (the Proxy's two private keys); `audit/` (the Proxy's audit log, which
  its console shows); `vault/` (the Secret Vault (HashiCorp) unseal key and root token,
  and its config).
- The Passport CLI and its login in `~/.passport/`.

## Reference

- `references/concepts.md`: glossary and invariants, shared with
  passport-public-api.
- `references/urls.env`: every URL, image and version this skill uses.
- `references/troubleshooting.md`: error codes and symptoms.
- `references/verification.md`: what has been tested, and when.
