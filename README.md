![Postman Passport](assets/logo.svg)

# passport-skills

> **Note:** the AWS guide creates billable resources.

Set up a Postman Passport proxy and **prove it works end to end**: a client calls an API with only a
`{{vault:<uuid>}}` pointer, and the proxy injects the real secret in flight.

One `passport` plugin, two skills:

| Skill | Use it to | Starts when |
|---|---|---|
| [`passport-setup`](skills/passport-setup/SKILL.md) | Set up and verify a proxy — local Docker or a single AWS EC2 instance | you say **`setup passport`** |
| [`passport-public-api`](skills/passport-public-api/SKILL.md) | Register APIs and manage credentials (secret references, bindings, access requests) programmatically via the Passport public API | a task needs an API credential instead of a `.env` file |

`passport-public-api` assumes a proxy is already set up; if one isn't, it points back to `passport-setup`.

## Install
Pick the line for your agent. Installing the plugin gets **both** skills. Then type **`setup passport`**
to stand up a proxy (it asks **local Docker or AWS**), or just describe an API-credential task to use
`passport-public-api`.

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
latest). `passport-public-api` arrived in 0.3.0.

### Or run it from a clone
```
git clone https://github.com/postmanlabs/passport-skills
cd passport-skills
# start your agent here and type:
setup passport
```
The agent reads `AGENTS.md`, which points it at the right skill. No agent? Open the guide and follow it by hand.

| Guide | What it does |
|---|---|
| [`guides/local-docker.md`](skills/passport-setup/guides/local-docker.md) | Proxy + disposable HashiCorp Vault in Docker on your machine |
| [`guides/aws-single-instance.md`](skills/passport-setup/guides/aws-single-instance.md) | Proxy on one EC2 instance (stock Amazon Linux 2023), local Vault, CloudFront HTTPS management, read-only preflight, full cleanup |
| [`guides/after-setup.md`](skills/passport-setup/guides/after-setup.md) | Shared by both: the handoff and adding your own API |

## Prerequisites
- A Passport Cloud team and a **registry key** (Org Settings → Registry; needs admin).
- Docker (local) or an AWS account + CLI profile (AWS).
- `openssl`, `curl`, `jq`, `node`.
- For `passport-public-api`: a running proxy (from `passport-setup`) and a WorkOS **API key**
  (Organization → API keys).

## Safety
Secrets never go in chat, user-data or logs; every AWS change is confirmed first; teardown only runs when you say so.

## What the skills run and connect to
The plugin has no hooks, MCP servers or background processes. Everything below is a step in a skill's
guide that the agent runs in your terminal once that skill is in use.

- **Installs:** the Passport CLI from `dl-passport.pstmn.io` (the macOS `.pkg` with `sudo installer`,
  or the Windows build). The
  AWS guide also installs the AWS CLI v2 from `awscli.amazonaws.com` and the Session Manager plugin
  from `s3.amazonaws.com` if they're missing.
- **Docker images:** the Passport proxy from `ociregistry.usepassport.ai` (after `docker login` with
  your registry key), `hashicorp/vault` for the local Vault, and `node:20` for the CLI daemon on MDM Macs.
- **Passport services:** `app.usepassport.ai` and `api.usepassport.ai`, for sign-in, the public API, and
  proxy registration.
- **AWS (AWS guide only):** in the account and region you choose, it creates one EC2 instance, an
  Elastic IP, a security group, an IAM role and instance profile, and a CloudFront distribution and
  function. `checkip.amazonaws.com` is used to find your public IP for the security group.
- **Verification calls:** a demo API at `passport-demo.mock.postman.postman.dev` and, optionally,
  `api.github.com/user` as the "add your own API" example, both sent through your proxy.
- **Secrets:** you keep them out of the chat. The registry key goes to `docker login` through stdin.
  The WorkOS API key is read from an environment variable you set, and is sent only to
  `api.usepassport.ai`. Vault secret values are typed at a hidden prompt (`read -s`) in your own
  terminal.

## Layout
```
skills/                   two skills, each self-contained (installs copy a skill's own folder)
  passport-setup/         set up and verify a proxy
    SKILL.md              rules and entry point
    guides/               local-docker.md, aws-single-instance.md, after-setup.md (shared post-setup)
                          + reference/ (shared: concepts, troubleshooting, MDM Macs, verification log)
    scripts/              preflight.sh, env.sh, aws-resources.sh, passport-api.js
    templates/            user-data, CloudFront, operator-iam-policy.json
  passport-public-api/    register APIs and manage credentials via the public API
    SKILL.md              the whole skill (no guides/scripts/templates)
AGENTS.md                 entry point in a clone + rules for editing this repo
                          (CLAUDE.md, GEMINI.md, .cursor/, .github/ are one-line shims)
.claude-plugin/           Claude Code marketplace "passport-skills" + plugin "passport"
.cursor-plugin/           Cursor marketplace + plugin "passport"
.agents/plugins/, .codex-plugin/   Codex marketplace + plugin "passport"
assets/                   the Passport logo
```

## License
[Apache-2.0](LICENSE)
