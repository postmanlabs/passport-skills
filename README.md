# postman-passport-setup

> **Note:** the AWS guide creates billable resources.

Set up a Postman Passport proxy and **prove it works end to end**: a client calls an API with only a
`{{vault:<uuid>}}` pointer, and the proxy injects the real secret in flight.

## Install
Pick the line for your agent, then type **`setup passport`**. It asks **local Docker or AWS** and runs
the matching guide.

| Agent | Install |
|---|---|
| Claude Code | `/plugin install passport --marketplace postmanlabs/postman-passport-setup` |
| Codex | `codex plugin marketplace add postmanlabs/postman-passport-setup`, then `codex plugin add passport@postman-passport-setup` (or pick it in `/plugins`); start a new session |
| Any agent with skills (Claude Code, Codex, Cursor, Copilot, Gemini CLI, …) | `npx skills add postmanlabs/postman-passport-setup` |

If your Claude Code doesn't recognise `--marketplace`, use
`/plugin marketplace add postmanlabs/postman-passport-setup` and then
`/plugin install passport@postman-passport-setup`.

### Or run it from a clone
```
git clone https://github.com/postmanlabs/postman-passport-setup
cd postman-passport-setup
# start your agent here and type:
setup passport
```
The agent reads `AGENTS.md`, which points it at the skill. No agent? Open the guide and follow it by hand.

| Guide | What it does |
|---|---|
| [`guides/local-docker.md`](skills/passport-setup/guides/local-docker.md) | Proxy + disposable HashiCorp Vault in Docker on your machine |
| [`guides/aws-single-instance.md`](skills/passport-setup/guides/aws-single-instance.md) | Proxy on one EC2 instance (stock Amazon Linux 2023), local Vault, CloudFront HTTPS management, read-only preflight, full cleanup |
| [`guides/after-setup.md`](skills/passport-setup/guides/after-setup.md) | Shared by both: the handoff and adding your own API |

## Prerequisites
- A Passport Cloud team and a **registry key** (Org Settings → Registry; needs admin).
- Docker (local) or an AWS account + CLI profile (AWS).
- `openssl`, `curl`, `jq`, `node`.

## Safety
Secrets never go in chat, user-data or logs; every AWS change is confirmed first; teardown only runs when you say so.

## Layout
```
skills/passport-setup/    the skill, self-contained (installs copy only this folder)
  SKILL.md                rules and entry point
  guides/                 local-docker.md, aws-single-instance.md, after-setup.md (shared post-setup)
                          + reference/ (shared: concepts, troubleshooting, MDM Macs, verification log)
  scripts/                preflight.sh, env.sh, aws-resources.sh, passport-api.js
  templates/              user-data, CloudFront, operator-iam-policy.json
AGENTS.md                 entry point in a clone + rules for editing this repo
                          (CLAUDE.md, GEMINI.md, .cursor/, .github/ are one-line shims)
.claude-plugin/           Claude Code marketplace + plugin "passport"
.agents/plugins/, .codex-plugin/   Codex marketplace + plugin "passport"
```
