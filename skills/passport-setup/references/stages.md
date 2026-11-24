# Stages

Eleven steps in order; the script tracks the last two as one stage,
`handson`. Every stage message starts with the progress line from
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

## 2. Choose your setup — user

Menu, header "Setup type":

- **"Just me, on this machine"**: "The Proxy and a Secret Vault (HashiCorp) run in Docker
  here, for you and your agents on this machine."
- **"A team (coming soon)"**: "Hosted in the cloud and shared by the whole team."

A team: say it's coming soon and offer the same menu again with "Stop for now".
Just me: `passport-onboard mark setup-type`, then say: **"By the end you'll
have a Proxy and a Secret Vault (HashiCorp) running in Docker on this machine, the
Passport CLI signed in, secret resolution verified with a sample API, and
you'll have done one full cycle yourself: stored a secret, registered an API, and called it with only a
pointer."**

## 3. Check prerequisites — agent, the user approves installs

1. `passport-onboard doctor`. Show `data.checks` as a table: tool, why it's
   needed here, status. Never hide a row. Rows other than tools (a busy port,
   Passport Cloud unreachable) appear only when they fail.
2. All `ok`/`info`: go on. Otherwise menu, header "Missing":
   **"Install what's missing"** / **"I'll do it myself"**.
3. Install only after a yes. Run `brew install …` yourself. Anything with `sudo`,
   and the Passport CLI installer (it asks for the user's password), the user
   runs in their own terminal: give the exact `fix` command from the check.
   Never install Docker; give its link.
4. `conflict` (old community CLI from npm): ask before the user runs
   `npm uninstall -g @postman/postman-passport`.
5. Run `doctor` again until `data.ready` is true.

## 4. Sign in to the app — user

Menu, header "Account": **"Create a new account (recommended)"** /
**"Use an existing account"**.

- New: open `<PASSPORT_APP_URL>/signup?design=next&origin=agent` in the browser
  (`open` on macOS, `xdg-open` on Linux) and show the link too. A new signup
  makes them the admin of a new team.
- Existing: **"You need to be an admin of that team, or sign up fresh with a new
  team."** Send them to `<PASSPORT_APP_URL>`.

Wait until they say they're signed in, then `passport-onboard mark account`.

## 5. Start the Secret Vault — agent

Say first: **"I'm starting the Secret Vault (HashiCorp) in Docker on this machine. It holds
the real secret values; Passport Cloud never sees them."**

Run `passport-onboard vault up`. Report the container, the Secret Vault (HashiCorp) UI address
(`data.ui`) and that the demo secret is stored at `secret/demo-api-key`.

## 6. Deploy the Proxy — user and agent

1. Run `passport-onboard proxy prepare`. It makes the Proxy's two keys and two
   files the user fills in.
2. The API key, as its own short message. Say: **"Create an API key in the
   Passport app under Account → API keys (`<PASSPORT_APP_URL>/me/api-keys`).
   Paste it into `~/.passport/onboarding/api-key.env` after
   `PASSPORT_API_KEY=` and save. Don't paste it here."** Open the file for them
   (`open -t` on macOS, `xdg-open` on Linux).
3. When they say done: `passport-onboard key check`. On `not_admin`,
   `key_rejected` or `other_proxy_configuration`, show the hint and wait. On
   `me_unavailable`, stop: the team ID can't be read until
   `GET /public/v1/me` ships (see `troubleshooting.md`). When it passes, say:
   **"Your key works. One thing to know: keeping an API key in a file like this
   isn't safe — any program running as you, including me, can read it. That's
   the exact problem Passport solves. At the end, when you protect your first
   API, you'll move a new key into the Secret Vault (HashiCorp) and revoke this one."**
4. The Proxy Configuration. Say: **"In the Passport app, open Proxy
   Configuration and create one; pick any name. Copy its Proxy ID and
   registration token into `~/.passport/onboarding/proxy.env`, after
   `PASSPORT_PROXY_ID=` and `PASSPORT_PROXY_TOKEN=`. Everything else in that
   file is already filled in; read it to see how your Proxy is configured."**
   Open the file for them.
5. When they say done: `passport-onboard proxy start`. It waits up to 90 s for
   Passport Cloud to report the Proxy Healthy. Report `data.proxyUrl`. If
   `data.cloudStatus` is null, Passport Cloud couldn't be asked: read
   `data.logs`, say in one line whether the Proxy looks registered, and ask
   them to check it shows Healthy in the app. On an error that has
   `error.logs`, read them and tell the user in one or two lines what the
   Proxy says is wrong and what to change; never paste the logs. Then say:
   **"Your Proxy also has a console at `<data.consoleUrl>`. Its audit log lists
   every request the Proxy allowed or refused; the Proxy writes it to
   `~/.passport/onboarding/audit/audit.jsonl`. Sign in with:**

   ```text
   Username: admin
   Password: passport-local
   ```

   **`proxy.env` says how to change the password."**

## 7. Authenticate the CLI — agent, the user approves in the browser

Say first: **"Next I'll run `passport login`. It opens your browser to sign
in, finds your Proxy, and gets the client certificate your requests use. It
may also start the Passport daemon and set `HTTPS_PROXY`, so other tools on
this machine can route through the Proxy."**

Run `passport login`, wait for it to finish, then `passport-onboard cli check`.

## 8. Verify secret resolution with a sample API — agent, plan shown first

1. `passport-onboard demo plan`. Show the five objects as a table before
   creating anything. The Resource Group is named for the API
   (`Passport demo API`); the Endpoint is the method, host and path. The Access Request is for 7 days because this check is
   short-lived; say so in one line.
2. Menu, header "Sample API": **"Create these"** / **"Stop for now"**.
3. `passport-onboard demo apply`. Show one line per object: type, ID, and
   whether it was created or already there. If the Access Request isn't
   approved, show the hint and wait; never approve it yourself.
4. `passport-onboard demo verify`. Show the proof: HTTP status, the key the
   demo API received (`data.keyReceived`, masked) and its length (19), and
   `data.proxyRequestId`. Then say: **"Your request carried only
   `{{vault:<id>}}`. The Proxy checked your Access Grant, fetched the real key
   from the Secret Vault (HashiCorp) and sent it on. The sample API answered 200 because it
   received the real key."**

## 9. Walk through what was created — user

Say: **"Open `<PASSPORT_APP_URL>/setup` and click *Show me what was created*.
The app walks you through what the last step created. Skip the *Run the demo call
yourself* box for now; its command is outdated."**

Menu, header "Walkthrough": **"Continue"** / **"Stop for now"**. On Continue,
`passport-onboard mark tour`.

## 10. Protect your first API — the user builds it, the agent checks

Say: **"Now you do one full cycle yourself: store a key in the Secret Vault (HashiCorp),
register an API, and call it with only a pointer. The API is Passport's own
public API, so afterwards I can manage Passport for you without ever holding a
key."** Run `passport-onboard handson plan` for the values below.

1. **Store a new key.** "Remember the setup key in `api-key.env`? Any
   program running as you, me included, can read it. That's the problem
   Passport solves, so this time do it the right way: create a second API key
   in the app and store it in the Secret Vault (HashiCorp), where only the
   Proxy reads it. Open
   the Secret Vault (HashiCorp) UI at `<data.vault.ui>` and sign in with method *Token*.
   Your token is the `VAULT_TOKEN` value in `~/.passport/onboarding/proxy.env`,
   the same token the Proxy uses. Create a secret in `secret` at path
   `passport-api-key`. A secret is a set of key-value pairs: put your API key
   under the key named `value`."
2. **Create these in the app, in this order.** Name only the objects and
   values; the app's screens are changing.
   1. Namespace `passport-api`. It holds everything below.
   2. Resource Group `Passport public API`, for the API being protected.
   3. Secret Reference `passport-api-key`: vault type HashiCorp, path
      `passport-api-key`. It must exist before an Endpoint can send it.
   4. Endpoint: method `*`, host `<API host>`, path `/public/v1/*`, in that
      Resource Group, with an `Authorization` slot mapped to the Secret
      Reference `passport-api-key`. (The `Bearer ` prefix isn't set here; the
      request carries it: `Authorization: Bearer {{vault:<id>}}`.)
   5. Access Request on that Resource Group for 90 days, the longest there is,
      because this grant is what keeps my access to the Passport API working.
      As the admin, yours is approved automatically.
3. When they say done: `passport-onboard handson check`. Show each item as
   found or missing; repeat until `data.complete`.
4. `passport-onboard handson verify`: a call to the public API through the
   Proxy using only the Secret Reference. Show the namespaces it returned.

## 11. Revoke the setup key — user, the agent checks

1. Say: **"Now revoke your first API key in the app. It's been sitting in a
   file, which is exactly what Passport is meant to replace."** When they say
   done: `passport-onboard handson finish`. If the key still works, revocation
   can take about 45 seconds; wait and run it again. It deletes `api-key.env`.
2. Say: **"On `<PASSPORT_APP_URL>/setup`, tick *My request went through* to
   finish *Add your own API*."** Then: **"You're set up. To register more APIs,
   ask me to use the passport-public-api skill."**

## Coming back

When `status` shows `data.resume: true`:

1. Run `passport-onboard doctor` first; things change between sessions.
2. Show the progress line, then menu, header "Resume":
   **"Continue from <next stage>"** / **"Stop for now"**.
3. Everything done: show the check results and menu **"Re-run the sample API call"**
   (`demo verify`) / **"Done"**. Never just say "already set up".
4. Don't repeat the welcome or explain finished stages again; one line is
   enough. Something broken: `troubleshooting.md`, "Coming back to a broken
   setup".
