# Passport setup — instructions for AI coding agents

This repository sets up and verifies a **Postman Passport proxy**, end to end. It is packaged as one
skill, `skills/passport-setup/`, and everything the setup uses lives in that folder.

## Trigger
When the user says **"setup passport"** (or similar: "set up the Passport proxy", "run Passport locally",
"deploy Passport on AWS"), read `skills/passport-setup/SKILL.md` and follow it. In a clone, `$SKILL_DIR`
in its guides means the absolute path of `skills/passport-setup/`.

## Maintaining this repo (when you edit it)
- **Everything the skill uses stays inside `skills/passport-setup/`.** `npx skills add` copies only that
  folder, and the Claude Code, Codex and Cursor plugins load the skill from it. A file outside it is missing after
  an install. Don't use symlinks to reach outside it: `skills update` doesn't notice changes behind them,
  and Windows checkouts turn them into text files.
- **Plugin names.** The plugin is `passport` and the marketplace is `passport-proxy-setup` in every
  manifest: `.claude-plugin/` (Claude Code), `.cursor-plugin/` (Cursor), and
  `.agents/plugins/marketplace.json` + `.codex-plugin/plugin.json` (Codex). The README's install commands
  depend on these names. `.claude-plugin/marketplace.json` also lists the plugin under its old name,
  `passport-proxy-setup`, so `/plugin install passport-proxy-setup@passport-proxy-setup` keeps working;
  don't remove that entry or rename the marketplace. Keep `version` equal in the three `plugin.json` files
  and bump it when the skill changes, so plugin updates pick it up. CI checks all of this.
- **One home per fact.** Rules: `skills/passport-setup/SKILL.md`. Setup steps: the two guides. The why:
  `concepts.md`. Symptoms and fixes: `troubleshooting.md`. What was tested and when: `verification.md`
  (not inline "verified on" notes). Link to the home instead of copying it.
- **Point at a file and a heading or step**, and update every pointer when you renumber. Paths inside
  the skill are relative to `skills/passport-setup/`. CI checks that every `guides/`, `scripts/` and
  `templates/` path mentioned in a `.md` file exists there.
- **Command blocks must work in both bash and zsh** (macOS agents run zsh). Note that zsh skips `EXIT`
  traps when `set -e` fires inside a function, so don't rely on a trap for clean-up; end steps with
  `|| die …` instead (see AWS step 6).
