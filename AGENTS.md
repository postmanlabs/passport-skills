# Passport setup — instructions for AI coding agents

This repository sets up and verifies a **Postman Passport proxy**, end to end. It is meant to be run by
an agent (or a person) from a clone of this repo.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally",
"deploy Passport on AWS"):

1. Ask which target they want — one question:
   - **Local Docker** → follow `guides/local-docker.md`
   - **AWS single EC2 instance** → follow `guides/aws-single-instance.md`
2. Follow that guide **literally and do every step yourself**. Its first section lists the only things that
   need the human (registry key, browser approvals, cloud login). Work from the repo root; `$REPO` in the
   guides means the absolute path of this repository.

## Ground rules (apply to everything here)
- **Use only this repo's files** (`guides/`, `scripts/`, `templates/`) as the source. If something is
  missing, ask the user — don't search elsewhere.
- **Ask before every cloud (AWS) change.** Show the exact commands and get a yes first. Read-only commands
  run freely.
- **Never print or paste secrets:** registry key, private keys, Vault tokens, login tokens. Compare sha256s
  instead. Never put a secret in user-data, a commit, or chat.
- **Never tear anything down** until the user explicitly says so.
- **Check existing state first** and reuse it; record every resource you create so cleanup is exact.
- If CLI output says `(from macOS managed plist)` (or the other MDM signs the guides list), switch to that
  guide's MDM reference — don't probe the filesystem for it.

## Layout
- `guides/` — the step-by-step guides; `guides/reference/` — troubleshooting and MDM-Mac details
- `scripts/` — `preflight.sh` (read-only AWS checks), `passport-api.js` (Passport Cloud API helper)
- `templates/` — EC2 user-data and CloudFront files used by the AWS guide
