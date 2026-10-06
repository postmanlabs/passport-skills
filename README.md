# postman-passport-setup

> **Note:** the AWS guide creates billable resources.

Set up a Postman Passport proxy and **prove it works end to end**: a client calls an API with only a
`{{vault:<uuid>}}` pointer, and the proxy injects the real secret in flight.

## Quick start (any AI coding agent)
```
git clone https://github.com/postmanlabs/postman-passport-setup
cd postman-passport-setup
# start your agent here (Claude Code, Codex, Cursor, Copilot, Gemini CLI, …) and type:
setup passport
```
The agent reads `AGENTS.md`, asks **local Docker or AWS**, and runs the matching guide.
No agent? Open the guide and follow it by hand.

| Guide | What it does |
|---|---|
| [`guides/local-docker.md`](guides/local-docker.md) | Proxy + disposable HashiCorp Vault in Docker on your machine |
| [`guides/aws-single-instance.md`](guides/aws-single-instance.md) | Proxy on one EC2 instance (stock Amazon Linux 2023), local Vault, CloudFront HTTPS management, read-only preflight, full cleanup |

## Prerequisites
- A Passport Cloud team and a **registry key** (Org Settings → Registry; needs admin).
- Docker (local) or an AWS account + CLI profile (AWS).
- `openssl`, `curl`, `jq`, `node`.

## Safety
Secrets never go in chat, user-data or logs; every AWS change is confirmed first; teardown only runs when you say so.

## Layout
```
AGENTS.md                 entry point for any agent (CLAUDE.md, GEMINI.md, .cursor/, .github/ are one-line shims)
guides/                   step-by-step guides + reference/ (troubleshooting, MDM Macs)
scripts/                  preflight.sh, passport-api.js
templates/                user-data, CloudFront
.claude-plugin/, skills/  optional Claude Code plugin wrapper (same files, no duplication)
```

## Claude Code plugin (optional)
```
/plugin marketplace add postmanlabs/postman-passport-setup
/plugin install passport-proxy-setup@passport-proxy-setup
```
