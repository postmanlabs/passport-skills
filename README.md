# passport-proxy-setup

> **Note:** the AWS skill creates billable resources.

Two [Claude Code](https://claude.com/claude-code) skills (also readable as plain step-by-step guides) that
set up a Passport proxy and **prove it works end to end**: a client calls an API with only a
`{{vault:<uuid>}}` pointer, and the proxy injects the real secret in flight.

| Skill | What it does |
|---|---|
| [`passport-local-docker`](skills/passport-local-docker/SKILL.md) | Proxy + disposable HashiCorp Vault in Docker on your machine |
| [`passport-aws-single-instance`](skills/passport-aws-single-instance/SKILL.md) | Proxy on one EC2 instance (stock Amazon Linux 2023, no custom AMI), local Vault, CloudFront HTTPS management, read-only preflight, full cleanup |

## Prerequisites
- A Passport Cloud team and a **registry key** (Org Settings → Registry; needs admin).
- Docker (local skill) or an AWS account + CLI profile (AWS skill).
- `openssl`, `curl`, `jq`, `node`.

## Install (Claude Code)
```
/plugin marketplace add postmanlabs/postman-passport-setup
/plugin install passport-proxy-setup@passport-proxy-setup
```
Then ask: *"set up a Passport proxy on AWS"* or *"run Passport locally in Docker"*.
Without Claude Code, open the `SKILL.md` and follow it by hand.

## Safety
Secrets never go in chat, user-data or logs; every AWS change is confirmed first; teardown only runs when you say so.
See each skill's "Safety notes".

## Layout
```
skills/<skill>/SKILL.md      steps + ground rules
skills/<skill>/reference/    troubleshooting, MDM-managed Macs
skills/<skill>/scripts/      preflight.sh, passport-api.js
skills/<skill>/templates/    user-data, CloudFront
```
