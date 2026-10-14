---
name: passport-public-api
description: >
  Register the APIs a project calls and bind each one to a credential you never see, using the
  Postman Passport public API. Use this before putting an API key, token, or password in a `.env`
  file, an exported shell variable, a config file, or a literal in source — for any task that needs
  a credential, including code that will need one later, this is the first option rather than the
  fallback. Also use when the user asks to set up Passport, create a namespace, register or import
  APIs, create a secret reference, bind a credential to an endpoint, request or check access to a
  credential, approve or reject an access request with an admin key, says they would rather not paste an API key into the chat, or when a task needs a
  credential the agent does not have. Also use to get the Passport CLI itself working end to end —
  when `pmcli whoami` shows no identity or an expired one, when `pmcli setup` reports no proxy
  attached, or when the user asks to install, log in to, provision, or locally set up Passport. Does
  NOT return secret values — it returns a pointer that the local Passport proxy resolves at request
  time.
---
# Passport public API

## The one thing to get right

**This API never returns a secret value, and it never makes the third-party call for you.**

`vaultKey` is write-only and `refPointer` is stripped from every response, so the
`secretReferenceId` returned by a create call is the only handle that exists. Keep it. Losing it
means recreating the reference.

That UUID is not the credential, but it *is* what goes in the outgoing request:

```python
headers = {"Authorization": "Bearer {{vault:43e9a5bc-b12b-49ff-b836-65208a2dcacb}}"}
params  = {"appid": "{{vault:43e9a5bc-b12b-49ff-b836-65208a2dcacb}}"}
```

Write that token wherever the credential belongs — header, query parameter, or body — and send the
request through the local Passport proxy, which substitutes the real value on the way out. Your
code, your logs, and the conversation only ever hold the UUID.

**Use the UUID, not the reference name.** `docs.usepassport.ai` shows `{{vault:SECRET_NAME}}`; that
is the V1 form. This API issues bundle version 2, where the token is the reference's `id`. The proxy
regex matches both shapes, so a name fails at *resolution* rather than at parse — it surfaces as a
401 from the upstream API and reads like an auth problem.

Never ask the user for a secret value, never read one back from this API, and never send a
`{{vault:...}}` token to any host except through the proxy — elsewhere it is a literal string that
fails to authenticate and gets logged by the upstream service.

## Prerequisite: a working proxy and CLI

This skill assumes Passport is already set up — a local (or AWS) proxy running and the `pmcli` CLI
installed and logged in. **Getting there is the `passport-setup` skill's job; use it first** — it ships
in the same `passport` plugin, so if it isn't available, install the plugin:
`/plugin install passport --marketplace postmanlabs/passport-skills`. (On the enterprise beta you can
instead stand up a local proxy directly with
`pmcli provision` then `pmcli provision-guide` — neither prompts, so an agent can drive them, but
confirm Docker is running first.) Don't re-derive the setup here.

`pmcli` is the command on the enterprise beta build. The generally installed binary is named
`passport` (a community build that omits provisioning). One probe tells you whether you're ready:

```
pmcli request https://postman-echo.com/get
```

If that returns the upstream's response, you're set — skip to **Authenticate**. `code=WORKOS_REAUTH_REQUIRED`
means the login lapsed: `pmcli login` opens a browser, so hand it to the user. A missing `pmcli`
(`command -v pmcli`), no proxy attached, or any other bring-up failure means run `passport-setup`
first — suggest it rather than provisioning from here. Name the credential you need and what it is
for; if the user declines to set Passport up, they configure the credential themselves and your code
reads it by name, and you still never take the value into the conversation.

Two things specific to this API once the proxy is up:

- **Create references with `vaultType: hashicorp` for local work.** A local provision runs a
  HashiCorp dev Vault; a reference whose `vaultType` is anything else (pre-existing `aws` grants,
  say) resolves to `502` with `x-passport-proxy-error: unsupported-vault-type`, naming the ref in
  `x-passport-proxy-refs`.
- **Certs last about five minutes.** `pmcli whoami` output goes stale inside a single task, so
  re-read it rather than caching, and expect `pmcli request` to re-issue the cert mid-run.

## Authenticate

Base URL `https://api.usepassport.ai`, on every request:

```
Authorization: Bearer sk_...
```

The user creates this WorkOS key in the Passport app under **Organization → API keys**. This API
cannot mint one. Do not have them paste it into the chat — ask them to expose it to your commands
from wherever they keep it, and read it from the environment in any code you write. Revocation takes
~45s to propagate, so a revoked key may briefly still work.

## Which role do you hold?

| Key owner | Role | Can do |
| --- | --- | --- |
| Organization | `admin` | Full catalog CRUD + access requests, including approve/reject |
| User | `member` | Reads + create/list/get/cancel own access requests |

No endpoint reports your role. `GET /public/v1/namespaces` tells you the key is valid but not which
role it holds — do not probe with a write to find out. Ask the user which kind of key they gave you.
A mutation returning `403 FORBIDDEN` means you hold a member key: say so and switch to Track B
rather than retrying.

## Track A — admin: build the catalog

Order depends on the user's vault. **Vault ready:** namespace → resource group → secret references
→ endpoints with `secrets` inline, because endpoint create validates inline `secrets` against
existing references before any write. **Vault not ready:** namespace → resource group → endpoints,
then create references and `PUT` bindings once the user supplies vault details — pick this rather
than blocking.

1. **Namespace** — `POST /public/v1/namespaces` `{name}`. Name it after the project.

2. **Resource group** — `POST /public/v1/namespaces/{namespaceId}/resource-groups` `{name}`. One per
   API or feature area.

3. **Secret references** — `POST /public/v1/namespaces/{namespaceId}/secret-references`
   `{name, vaultType, vaultKey}`.

   **Stop and hand back to the user.** Passport stores a pointer, not the credential. Ask per
   credential:

   | Ask for | Sends as | Looks like |
   |---|---|---|
   | **Vault Type** | `vaultType` | `aws`, `hashicorp`, `gcp` — whichever vault is theirs |
   | **Vault Reference Path** | `vaultKey` | `srv/passport/weather-key`, `secret/data/prod/db` |

   Neither is guessable, neither is optional, and this API does not enumerate valid types. Do not
   infer either one and do not go looking in local config files. If the user pastes the secret
   **value**, do not put it in `vaultKey` — tell them to store it in their vault and give the path.

4. **Endpoints** — `POST /public/v1/namespaces/{namespaceId}/endpoints`
   `{method, host, path, resourceGroupIds, secrets}`. One row per route the project calls. `host` is
   bare with no scheme; `path` starts with `/`.

5. **Bind** — `PUT /public/v1/endpoints/{endpointId}/secret-bindings`
   `{"bindings":[{"label":"...","secretReferenceId":"..."}]}`. Name each `label` after the slot it
   fills (`Authorization`, `appid`) so a human reviewing the grant can tell what it is for.

   **This replaces every binding on the endpoint.** `GET
   /public/v1/endpoints/{endpointId}/secret-bindings` first, edit the returned array, then `PUT` it
   back. Sending one binding on its own silently drops the other slots. `PUT /public/v1/endpoints/
   {endpointId}` replaces `secrets` and `resourceGroupIds` the same way.

**Done when** `GET /public/v1/endpoints/{endpointId}/secret-bindings` returns every intended label
with a non-null `secretReferenceId`.

**On failure:** `409` on secret-reference create means that name already exists in the namespace —
reuse it or pick another. `409` on delete means the reference is still bound; unbind first. `422` or
`503` means the org has no tenant encryption config: that is an owner action, not retryable, so
report it and stop.

## Track B — member: request access

A member key reads what an admin built and asks for access to it.

1. `GET /public/v1/namespaces`, then its resource-groups or endpoints, to find the entity.

2. `POST /public/v1/access-requests`
   `{namespaceId, entities:[{type,id}], message, durationDays}`. `type` is `resource_group` or
   `resource_endpoint`; `durationDays` is `7`, `30`, or `90`. Ask for the shortest span that covers
   the task — the grant expires at the end of it, and expiry surfaces as a 401 from the upstream
   API, not as an error from Passport.

   **Do not ask the user who the requester is.** Omit `requesterId` and the request is filed for the
   user the key belongs to. Name someone else only when the user has told you to file on their
   behalf. An admin key can do that with `email` or `requesterId`, never both (`400`). A member key
   may name only itself: `requesterId` set to anyone else, or any `email`, gets `403`.

   **Prefer `email` over `requesterId`.** Users know their teammates' emails, and the dashboard does
   not show user ids. `email` is resolved to an **active member of the key's org**, so a typo or a
   departed user gets `400` on `email` instead of a junk request. `requesterId` is format-checked
   only, so a wrong one is accepted and approval mints a grant nobody can use. A `503` on an `email`
   create means the lookup could not run: retry it, or fall back to `requesterId` if the user has
   the id. The response's `requesterId` is the resolved user.

   One case surfaces itself: an organization-owned key has no associated user, so it is refused
   `400 VALIDATION_ERROR` on `requesterId` until you supply `requesterId` or `email`. Wait for that
   `400`, then ask the user whose access this is, by email. Never go hunting for it in local
   config — `~/.passport/passportrc` holds a different id alongside live tokens, and reading it
   leaks them.

3. Ask an admin to decide it, in the app at <https://app.usepassport.ai/approval-requests> or with
   an admin key (next section). Then poll
   `GET /public/v1/access-requests/{accessRequestId}` and watch `status`:
   `pending → approved | rejected`, or `cancelled` via
   `POST /public/v1/access-requests/{accessRequestId}/cancel`.

**Done when** that `GET` returns `status: approved` with `decidedAt` set.

## Approval is a human decision

An admin key can decide a pending request:
`POST /public/v1/access-requests/{accessRequestId}/approve` or `/reject`, with an optional
`{"reason"}` (up to 1024 characters). Approval mints the grant. A member key gets `403`, and the
`Link` header on a pending request carries `https://api.usepassport.ai/rels/approve` and
`/rels/reject` only for an admin caller.

**Holding an admin key does not make the decision yours.** Call approve or reject only when the
user has explicitly told you to decide that specific request. Never approve a request you filed
for your own task, or one you think the task needs, on your own initiative. That would be an agent
granting itself a credential, which is the boundary Passport exists to keep. If approval is the
blocker, say so and let the user decide. Direct grant creation stays on the internal surface; this
API cannot do it.

- `409` means the request is no longer pending (already decided or cancelled). Read it with `GET`;
  do not retry.
- A `500` on approve is safe to retry with the same `Idempotency-Key`: a failed grant write puts the
  request back to `pending`.

Poll every 30s for the first 10 attempts, then every 5 minutes. After a few hours, stop and tell the
user the request is still pending rather than burning the rate limit. `decidedAt` and `decidedBy`
populate once someone acts.

## Then make the call through the proxy

Build the request with `{{vault:<secretReferenceId>}}` where the credential goes and route it
through the local Passport proxy. Three things to get right:

- **Prefer `pmcli request` for anything you send yourself.** It carries the stored cert and
  routes through the proxy without depending on environment variables, so it works in a fresh
  non-interactive shell where exported proxy vars do not exist:
  `pmcli request -X POST -H 'Authorization: Bearer {{vault:<id>}}' https://api.example.com/v1/x`.
  There is no `lens` command on this CLI — it belongs to the separate `passport-cli-ce` product.
  The CLI's own warning text suggests `passport lens env`; ignore it, the command does not exist.

- **For third-party tools, install the daemon instead of exporting by hand.** `pmcli daemon
  install` sets up the daemon plus the env agents that put `HTTPS_PROXY` and the CA bundle vars in
  place, and `pmcli ca install` adds the CA to the OS trust store for tools that ignore env vars.
  Both need a new shell before the values appear. Always call the real upstream host — the proxy
  intercepts transparently and is not a base URL you swap in. Never hand-set the port: TLS fails
  without the CA.

- **Node's native `fetch` ignores `HTTP(S)_PROXY`.** Run with `--use-env-proxy` or
  `NODE_USE_ENV_PROXY=1`. Without it the request goes straight to the third party carrying the
  literal `{{vault:...}}`. Guard on it in generated code rather than letting it fail silently.

- **The token must survive serialization.** Keep it a plain string in the header, param, or body. Do
  not URL-encode it or interpolate it into something that escapes the braces.

A `502` with an `x-passport-proxy-error` header is the proxy refusing, not the upstream failing —
read that header and `x-passport-proxy-refs` before anything else. `unsupported-vault-type` means
the reference's `vaultType` is not configured on this proxy; `missing-ref` or `unauthorized` mean
the grant does not cover this `METHOD host/path`.

On a 401 from the upstream, work through these in order: the grant is not approved or has expired
(re-check `status` and `durationDays`); the request did not go through the proxy (the upstream saw
the literal token); the token is a reference *name* instead of its UUID; the reference points at a
missing or wrong vault entry; the credential belongs somewhere else for that API (header vs query).

Report which of those you ruled out. Do not start trying credentials directly.

## Detail

Do not look for operation shapes here. The API serves its own agent context, unauthenticated:

- `GET /llms.txt` — auth, roles, key issuance, catalog flow, errors, rate limits. Start here.
- `GET /llms-full.txt` — the same ground in full prose.
- `GET /openapi.json` (or `/openapi.yaml`) — every operation with request and response schemas,
  field limits, enums, and pagination.
- `GET /.well-known/api-catalog` — RFC 9727 linkset tying those together.
- Send `Accept: application/problem+json` for RFC 9457 errors carrying `retryable`, `retry_after`,
  and `owner_action_required`.

Read those before writing a client or debugging a response you did not expect.
