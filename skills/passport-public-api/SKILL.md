---
name: passport-public-api
description: >
  Register the APIs a project calls and bind each one to a credential you never see, using the
  Postman Passport public API. Use this before putting an API key, token, or password in a `.env`
  file, a shell variable, a config file, or source — for any task that needs a credential, including
  code that will need one later, this is the first option, not the fallback. Also use to create a
  Namespace, Resource Group or Endpoint, create a Secret Reference, bind a credential, request or
  approve access, when the user would rather not paste a key into the chat, or when a task needs a
  credential the agent does not have. Returns a pointer the local Passport Proxy resolves at
  request time, never the secret value. If Passport isn't set up on this machine yet, use the
  passport-setup skill first.
---

# Passport public API

Read `references/concepts.md` first: the glossary and the rules below depend
on it. URLs come from `references/urls.env` (`PASSPORT_API_URL`,
`PASSPORT_APP_URL`); never hardcode a host.

## The one thing to get right

**This API never returns a secret value, and it never makes the third-party
call for you.** A Secret Reference create returns an `id`; that UUID is the
only handle, and it's what goes in the outgoing request:

```python
headers = {"Authorization": "Bearer {{vault:43e9a5bc-b12b-49ff-b836-65208a2dcacb}}"}
```

Send that request through the Passport Proxy, which swaps in the real value.
Your code, logs and the conversation only ever hold the UUID. Use the UUID,
never the Reference's name. Never ask the user for a secret value, and never
send a `{{vault:…}}` token anywhere except through the Proxy.

## Before you start

One probe: `passport whoami`. It fails, or `passport` is missing → use the
passport-setup skill; don't set Passport up from here. `WORKOS_REAUTH_REQUIRED`
→ the user runs `passport login`.

## Authenticate: through the Proxy, never with a key in hand

You call this API exactly the way any Passport user calls an API: with a
Secret Reference, through the Proxy. The passport-setup skill's hands-on step
creates it (Namespace `passport-api`, Secret Reference `passport-api-key`):

```bash
. "$SKILL_DIR/references/urls.env"   # $SKILL_DIR = this skill's folder
REF=$(jq -r '.handson.ref // empty' ~/.passport/onboarding/state.json)
passport request -H "Authorization: Bearer {{vault:$REF}}" -H 'Accept: application/json' \
  "$PASSPORT_API_URL/public/v1/namespaces"
passport request -X POST -H "Authorization: Bearer {{vault:$REF}}" \
  -H 'Content-Type: application/json' -d '{"name":"weather-app"}' \
  "$PASSPORT_API_URL/public/v1/namespaces"
```

- No `state.json`, or no `handson.ref`: ask the user for the ID of the Secret
  Reference that holds their Passport API key. Never ask for the key itself,
  and never fall back to a raw key in an env variable or file.
- A `401`, or `x-passport-proxy-error: unauthorized`, on these calls usually
  means the Access Grant on `passport-api` expired (7, 30 or 90 days). You
  can't renew it through the API it guards: the user requests access again in
  the app.
- After any grant change, `passport refresh`.

## Which role do you hold?

| Key owner | Role | Can do |
|---|---|---|
| A team admin's user key | `admin` | Full catalog create, read, update, delete, and access requests including approve/reject |
| A team member's user key | `member` | Reads, and create/list/get/cancel their own access requests |

No endpoint reports your role. A mutation returning `403 FORBIDDEN` means a
member key: say so and switch to Track B rather than retrying.

## Track A — admin: build the catalog

Create in dependency order: Namespace → Resource Group → Secret References →
Endpoints with `secrets` inline (Endpoint create checks them against existing
References). If the user's vault isn't ready, create the Endpoints first and
`PUT` the bindings once they give you the vault details.

1. **Namespace** — `POST /public/v1/namespaces` `{name}`. Name it after the
   project.
2. **Resource Group** — `POST /public/v1/namespaces/{namespaceId}/resource-groups`
   `{name, source:"manual"}`. One per API host. It's what makes Endpoints
   visible in the app.
3. **Secret Reference** — `POST /public/v1/namespaces/{namespaceId}/secret-references`
   `{name, vaultType, vaultKey}`. **Stop and ask the user** for the vault type
   and the path; neither is guessable. On the local setup it's `hashicorp` and a
   path under `secret/` (`weather-key`, not `secret/data/weather-key`) whose
   value sits under the key `value`; the user stores it in the HashiCorp Vault
   UI. If they paste the secret value instead, don't use it: they store it in
   the vault and give you the path.
4. **Endpoints** — `POST /public/v1/namespaces/{namespaceId}/endpoints`
   `{method, host, path, resourceGroupIds, secrets:[{label, secretReferenceId}]}`.
   `host` is bare (no scheme, no port); `path` starts with `/`. Method `*` and a
   trailing `*` in the path cover a whole API.
5. **Bind later** — `PUT /public/v1/endpoints/{endpointId}/secret-bindings`
   **replaces every binding**: `GET` first, edit the array, `PUT` it back.
   `PUT /public/v1/endpoints/{endpointId}` replaces `secrets` and
   `resourceGroupIds` the same way.

**Done when** `GET /public/v1/endpoints/{endpointId}/secret-bindings` lists
every intended label with a non-null `secretReferenceId`.

**Failures:** `409` on a Reference create = the name exists in that Namespace
(reuse it). `409` on a delete = still bound; unbind first. `422`/`503` = the
team has no encryption config: an owner action, not retryable; stop and report.

## Track B — member: request access

1. Find the entity: `GET /public/v1/namespaces`, then its resource-groups or
   endpoints.
2. `POST /public/v1/access-requests`
   `{namespaceId, entities:[{type, id}], message, durationDays}`; `type` is
   `resource_group` or `resource_endpoint`; `durationDays` 7, 30 or 90. Ask for
   the shortest that covers the task. Omit `requesterId` and `email`: the
   request is filed for the key's owner.
3. An admin decides it in the app (`<app>/approval-requests`). Poll
   `GET /public/v1/access-requests/{accessRequestId}` every 30 s for 10 tries,
   then every 5 minutes; after a few hours, stop and tell the user.

## Approvals

An admin's request for themselves is approved by the service; read the
returned status and grant. **Holding an admin key doesn't make a decision
yours.** Call `…/approve` or `…/reject` only when the user explicitly tells you
to decide that specific request. Never approve a request you filed, or one you
think the task needs: that would be an agent granting itself a credential.

## Make the call through the Proxy

- **`passport request`** for anything you send yourself:
  `passport request -X POST -H 'Authorization: Bearer {{vault:<id>}}' https://api.example.com/v1/x`.
- **Code and other tools** go through the CLI's daemon (`HTTPS_PROXY`), in a
  shell started after `passport login`. Call the real upstream host; the Proxy
  isn't a base URL.
- **Node's built-in `fetch`** ignores `HTTPS_PROXY` without `--use-env-proxy`
  or `NODE_USE_ENV_PROXY=1`. Guard for it in code you write.
- **Keep the token a plain string**; don't URL-encode it.

A `502` with `x-passport-proxy-error` is the Proxy refusing, not the upstream:
read it and `x-passport-proxy-refs` first. A `401` from the upstream: work
through `references/concepts.md`, "Errors that look like auth problems", and
report which causes you ruled out. Never start trying credentials directly.

## Detail

The API serves its own agent context, unauthenticated, at `PASSPORT_API_URL`:
`/llms.txt` (start here), `/llms-full.txt`, `/openapi.json`. Send
`Accept: application/problem+json` for errors with `retryable` and
`owner_action_required`. Read them before writing a client.
