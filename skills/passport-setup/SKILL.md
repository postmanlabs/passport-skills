---
name: passport-setup
description: Set up and verify Postman Passport for one developer on their machine (local Docker) or for a team (AWS EC2 with CloudFront). Use when asked to set up Passport locally or for a team. Once a proxy is running, the companion passport-public-api skill registers APIs and manages credentials (secret references, bindings, access requests) through the Passport public API.
---

# Passport setup — instructions for AI coding agents

This skill sets up and verifies a **Postman Passport proxy**, end to end. Everything it needs is in
this folder (`guides/`, `scripts/`, `templates/`), whether it was installed as a plugin, installed as a
skill, or run from a clone of the repo.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally",
"deploy Passport on AWS"):

1. Ask whether this is for **one developer on this machine** or **a team**:
   - **One developer** → follow `guides/local-docker.md`
   - **Team deployment on AWS** → follow `guides/aws-single-instance.md`
2. Follow that guide **literally**. Do agent steps yourself and hand the
   marked browser, token and secret-entry steps to the developer. The ground rules below apply to both
   guides; each guide's agent section adds only what's specific to it. Paths like `guides/…` are
   relative to this folder, and `$SKILL_DIR` in the guides means its absolute path (the folder
   containing this `SKILL.md`).

## After setup: help the user see the value of Passport
The person running this is usually **evaluating Passport, often as a potential customer**. A
working proxy is the start, not the finish line. Once the e2e test passes, your job is to help
them see, on their own APIs, what Passport does for them, and to help as much as you can.

Everything after the e2e test is in **`guides/after-setup.md`** (shared by both setups):

1. **Send the short handoff** (part 1): value first, one proof command, one next step.
2. **For local setup, show the app's “See what was created” step**, then offer
   to add their own API. The developer can have you create it or use the app's
   guided flow. Follow their choice; check existing objects before creating
   anything, so the two paths do not create duplicates. Never ask for the
   secret value in chat. Give both `curl` forms when testing their API: with
   explicit proxy/cert flags and, if verified, with the daemon environment.
3. **Suggest next steps that fit what they told you:**
   - their own script or SDK, via the daemon env vars;
   - an AI agent calling an API without holding the key;
   - more endpoints for a teammate;
   - **ongoing API and access work** — use the **`passport-public-api`** skill
     when they want the agent to register more APIs, manage secret references,
     access requests, or credential bindings. It uses the selected app and API
     destination. The first own-API walkthrough remains in
     `guides/after-setup.md` part 2.

Keep it concrete: use their real host, path and reference UUIDs, and say what each result proves
in one plain sentence. Don't oversell: only claim what the step you ran just showed. Cleanup
still waits until they say so.

## Ground rules (apply to everything here)
- **Use only this skill's files** (`guides/`, `scripts/`, `templates/`) as the source. If something is
  missing, ask the user — don't search elsewhere.
- **Discover before asking.** Check installed tools, profiles, regions, login state and existing resources
  first; infer routine choices and state them; ask only for what's genuinely missing, in one go.
- **Ask before every AWS infrastructure change, naming every resource.** Show a table of exactly what will be created or
  deleted (type, name, ID, account, region) plus the full commands, and get one yes per block. Read-only
  commands run freely. A "yes"/"go ahead" approves that block: run it, verify it, report, all in that turn.
- **Passport API and CLI calls are yours when the developer chooses the agent path.** Create and delete
  namespaces, resource groups, references, endpoints and grants, and run
  `passport setup`/`whoami`/`request`/`daemon`/`ca status` yourself. In the local
  setup, the developer creates the named proxy in the app and types its one-time
  token in their own terminal; the proxy registers itself. If they choose the
  app path for their own API, guide and verify instead of creating duplicates.
  The AWS guide retains its existing agent-run registration flow.
- **Create references for the right proxy.** Passport encrypts each new
  reference for the default proxy in its zone. In the local flow, confirm the
  named proxy is that zone's only proxy and is default; stop if it is not.
  The AWS guide handles its existing default-proxy procedure separately.
- **The human types into their own terminal.** You can't type into theirs and they can't type into yours.
  For anything needing sudo, a password, a browser or a secret value: give the exact commands in a code
  block, say what they should see, wait for "done", then verify it yourself. Show login links on their own
  line, as a full `https://` URL with the confirmation code. Never ask for a secret's value in chat.
- **Don't call it done early.** "An explicit curl works" is not "CLI and daemon fully configured"; report
  each check separately (AWS step 8.4, "Success checklist").
- **Never print or paste secrets:** registry keys (AWS path), private keys, proxy or Vault tokens, login tokens, API credentials.
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
