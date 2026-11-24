# Welcome (show this before any action)

Show the text below to the user as written, in one message, before running
anything except `passport-onboard status`. Then ask the setup-type question
(`stages.md`, Setup type).

---

Passport lets you and your AI agents call APIs without ever holding the real
key. Your request carries a pointer like `{{vault:3f2a…}}`. The Passport Proxy
swaps it for the real key on the way out, and only for APIs you've been granted.

```text
┌─ YOUR MACHINE ───────────────────────────┐
│                                          │
│   You or your agent                      │
│       │  request with {{vault:<ref>}}    │
│       ▼                                  │
│   Passport CLI + its daemon              │
│       │                                  │
└───────┼──────────────────────────────────┘
        │  sent with your client certificate
┌───────┼─ YOUR NETWORK (VPC) ─────────────┐     ┌─ PASSPORT CLOUD ─────────┐
│       ▼                                  │     │                          │
│   Passport Proxy (data plane) ◀─ rules ──┼─────┤ Passport Control Plane   │
│       │      ▲                           │     │ who may use which secret │
│       │      │  real key                 │     │ on which API, for which  │
│       │   Secret Vault                   │     │ operation                │
│       │                                  │     │                          │
└───────┼──────────────────────────────────┘     │ never sees a secret      │
        │  request with the real key             └──────────────────────────┘
        ▼
    Target API
```

- **Passport CLI** (`passport`): runs where you work. It signs you in and
  sends your requests to the Proxy with your client certificate, which says
  who you are. Its daemon can also route other tools' HTTPS traffic there.
- **Passport Proxy**: the data plane, in your network next to the Secret
  Vault. It checks each request against the rules, swaps the pointer for the
  real key, sends the request on, and writes an audit log. Real keys never
  leave your network except to the API they're for.
- **Secret Vault**: holds the real keys; only the Proxy reads them. Passport
  works with HashiCorp Vault, AWS Secrets Manager and Google Secret Manager.
  This setup runs HashiCorp Vault in Docker, shown as Secret Vault (HashiCorp).
- **Passport Control Plane**: Passport Cloud, which you manage in the Passport
  app. It holds your team, your APIs and the rules, and sends the rules to the
  Proxy. It never sees a secret.

Four more words you'll see along the way:

- **Secret Reference**: the pointer, `{{vault:<id>}}`, that your requests carry.
- **Namespace**: a group of APIs and who may call them.
- **Endpoint**: one method, host and path that Passport protects, such as
  `GET api.example.com/v1/orders`. A **Resource Group** holds the Endpoints of
  one API.
- **Access Grant**: your permission to call Endpoints, for a number of days.

The steps:

- **Setup type**: who this Passport is for.
- **Machine check**: the tools it needs.
- **Account**: sign up in the Passport app.
- **Local Vault**: I start the Secret Vault (HashiCorp).
- **Proxy**: you create an API key and a Proxy Configuration in the app; I
  start the Proxy.
- **CLI sign-in**: I run `passport login`; you approve it in the browser.
- **Demo**: I create a demo API in Passport and call it with only a pointer.
- **Tour**: the app shows you what the demo made.
- **Hands-on**: you store a key in the Secret Vault (HashiCorp), register
  Passport's own API, and call it with only a pointer.

You can stop after any step and pick up later by saying "set up passport"
again.
