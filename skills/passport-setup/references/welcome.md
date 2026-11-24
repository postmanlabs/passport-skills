# Welcome (show this before any action)

Show the text below to the user as written, in one message, before running
anything except `passport-onboard status`. Then ask the setup-type question
(`stages.md`, Setup type).

---

Passport lets you and your AI agents call APIs without ever holding the real
key. Your request carries a pointer like `{{vault:3f2a…}}`. The Passport Proxy
swaps it for the real key on the way out, and only for APIs you've been granted.

```text
┌─ THIS MACHINE ─────────────────────────────┐     ┌─ PASSPORT CLOUD ──────────┐
│                                            │     │                           │
│   You or your agent                        │     │   Passport app            │
│         │                                  │     │                           │
│         │  request with {{vault:<ref>}}    │     │   · your team             │
│         ▼                                  │     │   · your APIs             │
│   Passport CLI                             │     │   · who may call what     │
│         │                                  │     │                           │
│         │  sent with your certificate      │     │   never sees a secret     │
│         ▼                                  │     │                           │
│   Passport Proxy ◀─────────────────────────┼─────┤   sends the rules         │
│         │      ▲                           │     │                           │
│         │      │  real key                 │     └───────────────────────────┘
│         │      │                           │
│         │    HashiCorp Vault               │
│         │                                  │
└─────────┼──────────────────────────────────┘
          │  request with the real key
          ▼
     Target API
```

Six words you'll see along the way:

- **Proxy**: runs on this machine and swaps the pointer for the real key.
- **HashiCorp Vault**: runs on this machine and holds the real keys.
- **Secret Reference**: the pointer, `{{vault:<id>}}`, that your requests carry.
- **Namespace**: a group of APIs and who may call them.
- **Endpoint**: one API method and path that Passport protects.
- **Access Grant**: your permission to call Endpoints, for a number of days.

**By the end** you'll have a Proxy and HashiCorp Vault running on this machine,
a working demo call, and you'll have done one full cycle yourself: stored a
secret, registered an API, and called it with only a pointer.

You can stop after any step and pick up later by saying "set up passport"
again.
