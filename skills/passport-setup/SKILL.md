---
name: passport-setup
description: Set up and verify a Postman Passport proxy end to end, either locally in Docker or on a single AWS EC2 instance with CloudFront. Use when asked to "setup passport", set up or deploy a Passport proxy, or run Passport locally/on AWS. Once a proxy is running, the companion passport-public-api skill registers APIs and manages credentials (secret references, bindings, access requests) programmatically via the Passport public API.
---

# Passport setup — instructions for AI coding agents

This skill sets up and verifies a **Postman Passport proxy**, end to end. Everything it needs is in
this folder (`guides/`, `scripts/`, `templates/`), whether it was installed as a plugin, installed as a
skill, or run from a clone of the repo.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally",
"deploy Passport on AWS"):

1. Ask which target they want — one question:
   - **Local Docker** → follow `guides/local-docker.md`
   - **AWS single EC2 instance** → follow `guides/aws-single-instance.md`
2. Follow that guide **literally and do every step yourself**. The ground rules below apply to both
   guides; each guide's agent section adds only what's specific to it. Paths like `guides/…` are
   relative to this folder, and `$SKILL_DIR` in the guides means its absolute path (the folder
   containing this `SKILL.md`).

## After setup: help the user see the value of Passport
The person running this is usually **evaluating Passport, often as a potential customer**. A
working proxy is the start, not the finish line. Once the e2e test passes, your job is to help
them see, on their own APIs, what Passport does for them, and to help as much as you can.

Everything after the e2e test is in **`guides/after-setup.md`** (shared by both setups):

1. **Send the short handoff** (part 1): value first, one proof command, one next step.
2. **Offer to add their own API** (part 2). Ask what they want to call and
   how it takes the credential. Never ask for the secret value; they store it themselves. Give
   both full `curl` forms: with the proxy and cert flags, and the env-var/daemon form.
3. **Suggest next steps that fit what they told you:**
   - their own script or SDK, via the daemon env vars;
   - an AI agent calling an API without holding the key;
   - more endpoints for a teammate;
   - **registering APIs, secret references, access requests, or binding credentials
     programmatically** — for their own code or agents, or in bulk — with the **`passport-public-api`**
     skill, which drives the Passport public API (`api.usepassport.ai`). Point them there whenever the
     task is about *using* credentials in code rather than a one-off demo call; the manual flow in
     `guides/after-setup.md` part 2 is the by-hand equivalent.

Keep it concrete: use their real host, path and reference UUIDs, and say what each result proves
in one plain sentence. Don't oversell: only claim what the step you ran just showed. Cleanup
still waits until they say so.

## Ground rules (apply to everything here)
- **Use only this skill's files** (`guides/`, `scripts/`, `templates/`) as the source. If something is
  missing, ask the user — don't search elsewhere.
- **Discover before asking.** Check installed tools, profiles, regions, login state and existing resources
  first; infer routine choices and state them; ask only for what's genuinely missing, in one go.
- **Ask before every cloud change, naming every resource.** Show a table of exactly what will be created or
  deleted (type, name, ID, account, region) plus the full commands, and get one yes per block. Read-only
  commands run freely. A "yes"/"go ahead" approves that block: run it, verify it, report, all in that turn.
- **Passport API and CLI calls are yours.** Register the proxy, create and delete namespaces, resource groups,
  references, endpoints and grants, and run `passport setup`/`whoami`/`request`/`daemon`/`ca status`
  yourself. Don't ask permission and don't ask the user to run them; report what you did. The only Passport
  steps for the human are browser approvals, `sudo` (`passport ca install`) and typing secret values.
- **Secret references are encrypted for the team's *default* proxy.** Make yours the default while creating
  references, then restore the previous default (the guides show how). Never register as non-default and
  create references; they won't decrypt.
- **The human types into their own terminal.** You can't type into theirs and they can't type into yours.
  For anything needing sudo, a password, a browser or a secret value: give the exact commands in a code
  block, say what they should see, wait for "done", then verify it yourself. Show login links on their own
  line, as a full `https://` URL with the confirmation code. Never ask for a secret's value in chat.
- **Don't call it done early.** "An explicit curl works" is not "CLI and daemon fully configured"; report
  each check separately (AWS step 8.4, "Success checklist").
- **Never print or paste secrets:** registry key, private keys, Vault tokens, login tokens, API credentials.
  Public keys, IDs and sha256s are fine; compare sha256s instead. Never print an API response that could
  contain a secret, and never put a secret in user-data, a commit, or chat.
- **Never tear anything down** until the user explicitly says so.
- **Check existing state first** and reuse it; record every resource you create so cleanup is exact.
- **Detect an MDM-managed Mac at the start** (step 1 of either guide): `passport daemon status` showing
  `routing source managed`, CLI output saying `(from macOS managed plist)`, or the other signs in
  `guides/reference/mdm-macs.md`. Then follow that file; don't probe the filesystem for the profile. On
  AWS this must be settled before step 2, because the instance is built for the team the CLI reports.
- **Long waits are not failures.** Some AWS waits take 3–15 minutes. If your command tool has a time
  limit, give them a longer timeout or run them in the background, and re-run only the wait.

## Layout (relative to this folder)
- `guides/` — `local-docker.md`, `aws-single-instance.md`, and `after-setup.md` (shared by both)
- `guides/reference/` — shared by both setups: `concepts.md` (the why: default-proxy rule, endpoints,
  certificates, daemon), `troubleshooting.md`, `mdm-macs.md`, `verification.md` (what has been tested, when)
- `scripts/` — `preflight.sh` (read-only AWS checks + free name), `env.sh` (shared helpers), `aws-resources.sh`
  (what exists / what cleanup would delete, tag-checked), `passport-api.js` (Passport Cloud API helper)
- `templates/` — EC2 user-data, CloudFront files, and `operator-iam-policy.json` (the AWS permissions the guide needs)
