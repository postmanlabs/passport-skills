---
name: passport-setup
description: Set up and verify a Postman Passport proxy end to end, either locally in Docker or on a single AWS EC2 instance with CloudFront. Use when asked to "setup passport", set up or deploy a Passport proxy, or run Passport locally/on AWS.
---

# Passport setup

This is a thin wrapper. The logic lives in plain markdown at the plugin/repo root so every agent tool can use it.

1. Read `AGENTS.md` at the repository (plugin) root — two directories above this file — and follow it.
2. Ask: local Docker or AWS single instance? Then follow `guides/local-docker.md` or `guides/aws-single-instance.md`.
