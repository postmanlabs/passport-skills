# Passport setup — instructions for AI coding agents

This repository is the **Postman Passport** skills, shipped as one `passport` plugin with two skills,
each self-contained in its own folder under `skills/`:
- `skills/passport-setup/` — set up Passport on this machine (a Proxy and HashiCorp Vault in Docker,
  macOS and Linux), verify it with a demo call, then a hands-on round.
- `skills/passport-public-api/` — once Passport is set up, register APIs and manage credentials (Secret
  References, bindings, access requests) through the Passport public API.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally"),
read `skills/passport-setup/SKILL.md` and follow it. In a clone, `$SKILL_DIR` in a skill means the
absolute path of that skill's folder.

When a task needs an API credential — registering APIs, creating Secret References or bindings,
requesting or approving access, or storing a key through Passport instead of a `.env` file — read
`skills/passport-public-api/SKILL.md` and follow it. It assumes Passport is already set up; if it isn't,
it points back to `passport-setup`.

## Maintaining this repo (when you edit it)
- **Each skill is self-contained in its own `skills/<name>/` folder.** `npx skills add` copies one skill
  folder, and the Claude Code, Codex and Cursor plugins load each skill from its folder. A file outside it
  is missing after an install — including the other skill, so skills reference each other by **name**
  (`the passport-public-api skill`), never by a relative path. Don't use symlinks to reach outside a skill
  folder: `skills update` doesn't notice changes behind them, and Windows checkouts turn them into text files.
- **Shared files live in `shared/`** (`concepts.md`, `urls.env`). Edit them there, then run
  `tools/sync-shared.sh` to copy them into each skill's `references/`. CI fails if a copy differs.
- **Plugin names.** The plugin is `passport` and the marketplace is `passport-skills` in every
  manifest: `.claude-plugin/` (Claude Code), `.cursor-plugin/` (Cursor), and
  `.agents/plugins/marketplace.json` + `.codex-plugin/plugin.json` (Codex). The README's install commands
  (`passport@passport-skills`) depend on these names, so renaming either one breaks every existing
  install. Keep `version` equal in the three `plugin.json` files and bump it when a skill changes, so
  plugin updates pick it up. CI checks all of this.
- **One home per fact.** Rules and the script's contract: `skills/passport-setup/SKILL.md`. Stage copy:
  `references/stages.md`. Vocabulary and the why: `shared/concepts.md`. Every URL, image and version:
  `shared/urls.env`. Symptoms and fixes: `references/troubleshooting.md`. What was tested and when:
  `references/verification.md` (not inline "verified on" notes). Link to the home instead of copying it.
- **The user only types real tools** (the Passport app, the HashiCorp Vault UI, `passport`, `docker`, an
  editor). `scripts/passport-onboard` is the agent's; never hand it to the user.
- **Point at a file and a heading or step**, and update every pointer when you rename. Paths inside a
  skill are relative to its folder. CI checks that every `references/`, `scripts/` and `templates/` path
  mentioned in a `.md` file exists in `skills/passport-setup/`.
- **Shell must run in bash 3.2** (macOS `/bin/bash`): no associative arrays, `mapfile` or `${x,,}`.
  Command blocks for agents must work in both bash and zsh. zsh skips `EXIT` traps when `set -e` fires
  inside a function, so don't rely on a trap for clean-up; end steps with `|| die …` instead.
