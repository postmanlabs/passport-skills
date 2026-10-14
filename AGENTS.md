# Passport setup — instructions for AI coding agents

This repository is the **Postman Passport** skills, shipped as one `passport` plugin with two skills,
each self-contained in its own folder under `skills/`:
- `skills/passport-setup/` — set up and verify a Passport proxy (local Docker or a single AWS EC2 instance).
- `skills/passport-public-api/` — once a proxy is running, register APIs and manage credentials (secret
  references, bindings, access requests) programmatically via the Passport public API.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally",
"deploy Passport on AWS"), read `skills/passport-setup/SKILL.md` and follow it. In a clone, `$SKILL_DIR`
in its guides means the absolute path of `skills/passport-setup/`.

When a task needs an API credential — registering APIs, creating secret references or bindings,
requesting or approving access, or storing a key through Passport instead of a `.env` file — read
`skills/passport-public-api/SKILL.md` and follow it. It assumes a proxy is already set up; if one isn't,
it points back to `passport-setup`.

## Maintaining this repo (when you edit it)
- **Each skill is self-contained in its own `skills/<name>/` folder.** `npx skills add` copies one skill
  folder, and the Claude Code, Codex and Cursor plugins load each skill from its folder. A file outside it
  is missing after an install — including the other skill, so skills reference each other by **name**
  (`the passport-public-api skill`), never by a relative path. Don't use symlinks to reach outside a skill
  folder: `skills update` doesn't notice changes behind them, and Windows checkouts turn them into text files.
- **Plugin names.** The plugin is `passport` and the marketplace is `passport-skills` in every
  manifest: `.claude-plugin/` (Claude Code), `.cursor-plugin/` (Cursor), and
  `.agents/plugins/marketplace.json` + `.codex-plugin/plugin.json` (Codex). The README's install commands
  (`passport@passport-skills`) depend on these names, so renaming either one breaks every existing
  install. Keep `version` equal in the three `plugin.json` files and bump it when the skill changes, so
  plugin updates pick it up. CI checks all of this.
- **One home per fact.** Rules: `skills/passport-setup/SKILL.md`. Setup steps: the two guides. The why:
  `concepts.md`. Symptoms and fixes: `troubleshooting.md`. What was tested and when: `verification.md`
  (not inline "verified on" notes). Link to the home instead of copying it.
- **Point at a file and a heading or step**, and update every pointer when you renumber. Paths inside
  the skill are relative to `skills/passport-setup/`. CI checks that every `guides/`, `scripts/` and
  `templates/` path mentioned in a `.md` file exists there.
- **Command blocks must work in both bash and zsh** (macOS agents run zsh). Note that zsh skips `EXIT`
  traps when `set -e` fires inside a function, so don't rely on a trap for clean-up; end steps with
  `|| die …` instead (see AWS step 6).
