# Stages

Ten stages in order. Every stage message starts with the progress line from
`passport-onboard status --line`. Values in `<angle brackets>` come from
`references/urls.env` or from the script's JSON output. The script is always
`"$SKILL_DIR/scripts/passport-onboard"`; the user never runs it.

Words in **bold quotes** are copy to show as written. Everything else is
guidance for you.

## 1. Welcome — agent

1. Run `passport-onboard status`. On `unsupported_os`, show its hint and stop.
   If `data.resume` is true, follow **Coming back** at the end of this file.
2. Show `references/welcome.md` as written.
3. `passport-onboard mark welcome`.

## 2. Setup type — user

Menu, header "Setup type":

- **"Just me, on this machine"**: "The Proxy and HashiCorp Vault run in Docker
  here, for you and your agents on this machine."
- **"A team (coming soon)"**: "Hosted in the cloud and shared by the whole team."

A team: say it's coming soon and offer the same menu again with "Stop for now".
Then `passport-onboard mark setup-type`.

## 3. Machine check — agent, the user approves installs

1. `passport-onboard doctor`. Show `data.checks` as a table: tool, why it's
   needed here, status. Never hide a row.
2. All `ok`/`info`: go on. Otherwise menu, header "Missing":
   **"Install what's missing"** / **"I'll do it myself"**.
3. Install only after a yes. Run `brew install …` yourself. Anything with `sudo`,
   and the Passport CLI installer (it asks for the user's password), the user
   runs in their own terminal: give the exact `fix` command from the check.
   Never install Docker; give its link.
4. `conflict` (old community CLI from npm): ask before the user runs
   `npm uninstall -g @postman/postman-passport`.
5. Run `doctor` again until `data.ready` is true.

## 4. Account — user

Menu, header "Account": **"Create a new account (recommended)"** /
**"Use an existing account"**.

- New: open `<PASSPORT_APP_URL>/signup?design=next&origin=agent` in the browser
  (`open` on macOS, `xdg-open` on Linux) and show the link too. A new signup
  makes them the admin of a new team.
- Existing: **"You need to be an admin of that team, or sign up fresh with a new
  team."** Send them to `<PASSPORT_APP_URL>`.

Wait until they say they're signed in, then `passport-onboard mark account`.

## 5. Local Vault — agent

Say first: **"I'm starting HashiCorp Vault in Docker on this machine. It holds
the real secret values; Passport Cloud never sees them. Its data lives on a
Docker volume, and it unlocks itself whenever it starts."**

Run `passport-onboard vault up`. Report the container, the Vault UI address
(`data.ui`) and that the demo secret is stored at `secret/demo-api-key`.

## 6. Proxy — user and agent

1. Run `passport-onboard proxy prepare`. It makes the Proxy's two keys and two
   files the user fills in.
2. The API key. Say: **"Create an API key in the Passport app under Account →
   API keys (`<PASSPORT_APP_URL>/me/api-keys`), as a team admin. Paste it into
   `~/.passport/onboarding/api-key.env` after `PASSPORT_API_KEY=` and save.
   Don't paste it here."** Open the file for them (`open -t` on macOS,
   `xdg-open` on Linux) and add: **"Keeping an API key in a file like this
   isn't safe — any program running as you, including me, can read it. That's
   the exact problem Passport solves. In the hands-on step you'll move a new key
   into HashiCorp Vault and revoke this one."**
3. When they say done: `passport-onboard key check`. On `not_admin`,
   `key_rejected` or `other_proxy_configuration`, show the hint and wait. On
   `me_unavailable`, stop: the team ID can't be read until
   `GET /public/v1/me` ships (see `troubleshooting.md`).
4. The Proxy Configuration. Say: **"In the Passport app, open Proxy
   Configuration and create one; pick any name. The app shows a one-time
   registration token: it proves this Proxy belongs to your team, which is why
   you create it there and I can't. Paste it into
   `~/.passport/onboarding/proxy.env` after `PASSPORT_PROXY_TOKEN=`, and the
   Proxy ID after `PASSPORT_PROXY_ID=` if the app shows one. Everything else in
   that file is already filled in; read it to see how your Proxy is
   configured."** Open the file for them.
5. When they say done: `passport-onboard proxy start`. It waits up to 60 s for
   the Proxy to register. Report `data.proxyUrl`. If `data.cloudStatus` is
   null, ask them to check the Proxy shows Healthy in the app.

## 7. CLI sign-in — agent, the user approves in the browser

Say first: **"Next I'll run `passport login`. It opens your browser to sign
in, finds your Proxy, and gets the certificate your requests use. It may also
set up a small background helper and `HTTPS_PROXY`, so other tools on this
machine can route through the Proxy."**

Run `passport login`, wait for it to finish, then `passport-onboard cli check`.

## 8. Demo — agent, plan shown first

1. `passport-onboard demo plan`. Show the five objects as a table before
   creating anything.
2. Menu, header "Demo": **"Create these"** / **"Stop for now"**.
3. `passport-onboard demo apply`. Show one line per object: type, ID, and
   whether it was created or already there. If the Access Request isn't
   approved, show the hint and wait; never approve it yourself.
4. `passport-onboard demo verify`. Show the proof: HTTP status, the key the
   demo API received (`data.keyReceived`, masked) and its length (19), and
   `data.proxyRequestId`. Then say: **"Your request carried only
   `{{vault:<id>}}`. The Proxy checked your Access Grant, fetched the real key
   from HashiCorp Vault and sent it on. The demo API answered 200 because it
   received the real key."**

## 9. Tour — user

Say: **"Open `<PASSPORT_APP_URL>/setup` and click *Show me what was created*.
The app walks you through what the demo made. Skip the *Run the demo call
yourself* box for now; its command is outdated."**

Menu, header "Tour": **"Continue"** / **"Stop for now"**. On Continue,
`passport-onboard mark tour`.

## 10. Hands-on — the user builds it, the agent checks

Say: **"Now you do one full cycle yourself: store a key in HashiCorp Vault,
register an API, and call it with only a pointer. The API is Passport's own
public API, so afterwards I can manage Passport for you without ever holding a
key."** Run `passport-onboard handson plan` for the values below.

1. **Store a new key.** "Create a second API key in the app. Then open
   HashiCorp Vault's UI at `<data.vault.ui>` and sign in with method *Token*.
   Your token is the `VAULT_TOKEN` value in `~/.passport/onboarding/proxy.env`,
   the same token the Proxy uses. Create a secret in `secret` at path
   `passport-api-key`. A secret is a set of key-value pairs: put your API key
   under the key named `value`."
2. **Create these in the app, in this order.** Name only the objects and
   values; the app's screens are changing.
   1. Namespace `passport-api`. It holds everything below.
   2. Resource Group for the host `<API host>`, the API being protected.
   3. Secret Reference `passport-api-key`: vault type HashiCorp, path
      `passport-api-key`. It must exist before an Endpoint can send it.
   4. Endpoint: method `*`, host `<API host>`, path `/public/v1/*`, in that
      Resource Group, with an `Authorization` slot sent as `Bearer ` followed by
      the Secret Reference.
   5. Access Request on that Resource Group for 90 days. As the admin, yours is
      approved automatically.
3. When they say done: `passport-onboard handson check`. Show each item as
   found or missing; repeat until `data.complete`.
4. `passport-onboard handson verify`: a call to the public API through the
   Proxy using only the Secret Reference. Show the namespaces it returned.
5. Say: **"Now revoke your first API key in the app. It's been sitting in a
   file, which is exactly what Passport is meant to replace."** When they say
   done: `passport-onboard handson finish`. If the key still works, revocation
   can take about 45 seconds; wait and run it again. It deletes `api-key.env`.
6. Say: **"On `<PASSPORT_APP_URL>/setup`, tick *My request went through* to
   finish *Add your own API*."** Then: **"You're set up. To register more APIs,
   ask me to use the passport-public-api skill."**

## Coming back

When `status` shows `data.resume: true`:

1. Run `passport-onboard doctor` first; things change between sessions.
2. Show the progress line, then menu, header "Resume":
   **"Continue from <next stage>"** / **"Stop for now"**.
3. Everything done: show the check results and menu **"Re-run the demo call"**
   (`demo verify`) / **"Done"**. Never just say "already set up".
4. Don't repeat the welcome or explain finished stages again; one line is
   enough. Something broken: `troubleshooting.md`, "Coming back to a broken
   setup".
