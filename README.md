![Postman Passport](assets/logo.svg)

# passport-skills

Set up Postman Passport on your machine and **prove it works end to end**: a client calls an API with
only a `{{vault:<uuid>}}` pointer, and the Passport Proxy injects the real secret in flight. macOS and
Linux; Windows isn't supported yet.

One `passport` plugin, two skills:

| Skill | Use it to | Starts when |
|---|---|---|
| [`passport-setup`](skills/passport-setup/SKILL.md) | Set up a Passport Proxy and a Secret Vault (HashiCorp) in Docker on your machine, verify secret resolution with a sample API, then protect your first API | you say **`setup passport`** |
| [`passport-public-api`](skills/passport-public-api/SKILL.md) | Register APIs and manage credentials (Secret References, bindings, access requests) through the Passport public API | a task needs an API credential instead of a `.env` file |

`passport-public-api` assumes Passport is already set up; if it isn't, it points back to `passport-setup`.

## Install
Pick the line for your agent. Installing the plugin gets **both** skills. Then type **`setup passport`**,
or just describe an API-credential task to use `passport-public-api`.

| Agent | Install |
|---|---|
| Claude Code | `/plugin install passport --marketplace postmanlabs/passport-skills` |
| Codex | `codex plugin marketplace add postmanlabs/passport-skills`, then `codex plugin add passport@passport-skills` (or pick it in `/plugins`); start a new session |
| Cursor | Add it as a marketplace: **Customize → Browse Marketplace → Add Marketplace → Import from GitHub**, paste `https://github.com/postmanlabs/passport-skills`, then install **passport** (CLI: `agent plugin marketplace add https://github.com/postmanlabs/passport-skills`, then `/plugin`). Or clone it as a local plugin: `git clone https://github.com/postmanlabs/passport-skills ~/.cursor/plugins/local/passport`, then run **Developer: Reload Window** |
| Any agent with skills (Claude Code, Codex, Cursor, Copilot, Gemini CLI, …) | `npx skills add postmanlabs/passport-skills` |

If your Claude Code doesn't recognise `--marketplace`, use
`/plugin marketplace add postmanlabs/passport-skills` and then
`/plugin install passport@passport-skills`.

**Already have it installed?** Marketplace manifests are cached, so refresh before updating:
`/plugin marketplace update postmanlabs/passport-skills`, then `/plugin update passport` (Codex:
`codex plugin marketplace update postmanlabs/passport-skills`; `npx skills add` re-run pulls the
latest). 0.4.0 replaces the old step-by-step guides and drops the AWS path.

**Coming from 0.3.x:**
- Set up on AWS? 0.4.0 can't remove it. Use the old guide's
  [cleanup step](https://github.com/postmanlabs/passport-skills/blob/c301a87/skills/passport-setup/guides/aws-single-instance.md#10-cleanup-only-when-the-user-explicitly-asks-approval-block-d).
- 0.4.0 makes a new local setup. It doesn't take over a Proxy you already run: if your team has a
  Proxy Configuration, setup stops and asks you to delete it in the app first.
- Finish passport-setup first. passport-public-api now calls the API through the Proxy.

### Or run it from a clone
```
git clone https://github.com/postmanlabs/passport-skills
cd passport-skills
# start your agent here and type:
setup passport
```
The agent reads `AGENTS.md`, which points it at the right skill. The stage-by-stage flow is in
[`references/stages.md`](skills/passport-setup/references/stages.md).

## Prerequisites
- macOS or Linux with Docker (Docker Desktop, OrbStack, Colima, or Docker Engine).
- `curl`, `jq`, `openssl`. The skill checks for them and the Passport CLI, and offers the install command
  for anything missing.
- A Passport account; the skill helps you sign up. You need to be a team admin; a new signup is one.

## Safety
Secrets never go in the chat: you paste them into files on your machine or into the Secret Vault (HashiCorp) UI.
The skill never reads the CLI's `passportrc`, never approves its own access requests, shows its plan
before creating anything, and never deletes anything it didn't make.

## What the skills run and connect to
The plugin has no hooks, MCP servers or background processes of its own. Everything below is a step the
agent runs in your terminal once a skill is in use.

- **Installs, with your OK:** the Passport CLI with the official installer (you run it; it asks for your
  password), and `curl`, `jq` or `openssl` from your package manager if they're missing.
- **Docker:** `hashicorp/vault` and the Passport Proxy image, pulled anonymously (exact tags in
  [`references/urls.env`](skills/passport-setup/references/urls.env)). Containers `passport-vault` and
  `passport-proxy`, network `passport-net`, volume `passport-vault-data`, all on `127.0.0.1` only.
- **Files:** `~/.passport/onboarding/` holds setup state, the Proxy's settings and keys, and the Secret Vault (HashiCorp) unseal key and root token, all readable only by you.
- **Passport services:** the Passport app and API for sign-in, the public API, and Proxy registration.
  The exact hosts are in `references/urls.env`.
- **Verification calls:** a demo API (`references/urls.env`) and the Passport public API itself, both
  sent through your Proxy.

## Layout
```
shared/                   concepts.md (glossary + invariants) and urls.env — the single source,
                          copied into each skill's references/ by tools/sync-shared.sh (CI checks it)
skills/                   two skills, each self-contained (installs copy a skill's own folder)
  passport-setup/
    SKILL.md              rules, the script's contract, the stage list
    references/           welcome, stages, troubleshooting, verification (+ the shared copies)
    scripts/              passport-onboard, the agent's helper (the user never runs it)
    templates/            proxy.env, api-key.env, Secret Vault (HashiCorp) config and start script
  passport-public-api/
    SKILL.md              the whole skill
    references/           the shared copies
tools/                    sync-shared.sh
AGENTS.md                 entry point in a clone + rules for editing this repo
                          (CLAUDE.md, GEMINI.md, .cursor/, .github/ are one-line shims)
.claude-plugin/           Claude Code marketplace "passport-skills" + plugin "passport"
.cursor-plugin/           Cursor marketplace + plugin "passport"
.agents/plugins/, .codex-plugin/   Codex marketplace + plugin "passport"
assets/                   the Passport logo
```

## License
[Apache-2.0](LICENSE)
