# MDM-managed Macs (both setups)

On a Mac with a managed configuration profile, the Passport CLI is pinned to
the organisation's proxy: `passport login` auto-runs `setup` against the
managed endpoints, and `setup` silently ignores `--management-url` and
`--proxy-url`. There's no flag to turn this off. The fix isn't to bypass MDM on
the Mac; it's to run the CLI somewhere MDM doesn't reach: a plain Linux
container. A container has no macOS configuration profile, so the CLI never
detects "managed" and behaves normally.

## How to tell (check at the start: local step 1, AWS step 1)

Any one of these means MDM. Detect it from the CLI; don't probe the
filesystem for the profile.

- `passport daemon status` shows `routing source   managed`. This is
  read-only, and works only while the host's own daemon is running. Seen on an
  MDM Mac on 2026-10-08.
- CLI output says `(from macOS managed plist)` (`login`, `setup`).
- `passport login` auto-runs `setup` against endpoints you didn't choose, or
  `setup` ignores `--management-url`/`--proxy-url`.
- `setup` fails with `403 … teamId "org_…" is not authorized for this deployment`
  while your proxy logs no request.
- `passport whoami` says `Managed Passport credentials could not be verified`.

The host login that revealed it is harmless. On this path the host `passport`
is useful only for `auth status`; every other CLI command runs in the
container.

## What changes on this path

| | Normal | MDM Mac |
|---|---|---|
| The CLI | `passport` on the Mac | `pp-cli-linux` container (A.2). AWS: `cli` in `scripts/env.sh` runs it when `MDM=1` is recorded |
| Credentials folder (`$PASSPORT_DIR`, also read by `api`) | `~/.passport` | `~/passport-cli-dl/.passport` (bind-mounted into the container as `/cli/.passport`) |
| `passport setup` | installs the daemon | add `--no-daemon` |
| `passport ca install` | the user runs it (sudo) | not available on the Linux CLI: report it as "not applicable (MDM container path)" |
| The daemon | installed by setup | only as a container (A.5); otherwise "not applicable" |
| Certificate renewal | the daemon | the A.5 daemon, or re-run setup when `notAfter` passes |

The team still has to exist first (local 1.1 / AWS 1.1); create it in the web
UI if `login` says the session has no organization.

**Record the mode as soon as you detect it, before anything reads the team ID
or calls the API:**

- **AWS:** `st MDM 1; st PASSPORT_DIR ~/passport-cli-dl/.passport`. From then
  on `cli` runs in the container and `api` reads the container's login.
- **Local:** start every block that uses `api` (local 5.4, `after-setup.md`
  part 0) with `export PASSPORT_DIR=~/passport-cli-dl/.passport`.

Then do A.1–A.3 in place of the host login.

### A.1 Get a Linux build of the CLI

The public installer only serves macOS/Windows. You need a **Linux build of
the Passport CLI** (`passport` binary + `lib/`, arm64 or x64 to match
`docker run --rm node:20 uname -m`). Get it from your Passport admin or the
"Set up Passport" guide in your team (account menu → How-to), and unpack it
into `~/passport-cli-dl` so that `~/passport-cli-dl/passport` exists.
*Unverified:* a public Linux download location; ask the Passport team.

Don't try to build the CLI from source; it needs internal registry access.

### A.2 Run it in a container

Use `--network host`, not `--network pp-net`. The login workaround (A.3) needs
it, and for local Docker it's also what lets `localhost:8081`/`localhost:8443`
inside the container reach the proxy's published ports (a bridge-network
container has its own loopback and gets `ECONNREFUSED`).

```bash
docker run -d --name pp-cli-linux --network host \
  -v ~/passport-cli-dl:/cli -w /cli \
  node:20 sleep infinity
docker exec pp-cli-linux ./passport --version   # sanity check
```

### A.3 Log in: the OAuth redirect needs a forwarder

`passport login` tries to open a browser with `xdg-open`, which doesn't exist
in this image and crashes the process. Stub it, then launch `login` **fully
detached** (`docker exec -d`, output to a log file). The approval can take any
amount of time, and a `login` attached to a shell that times out gets killed,
leaving a dead listener on a stale port that silently breaks the callback.

```bash
docker exec pp-cli-linux bash -c "printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open && chmod +x /usr/local/bin/xdg-open"
docker exec -d -e PASSPORT_DIR=/cli/.passport pp-cli-linux sh -c "./passport login > /cli/login.log 2>&1"
sleep 3
docker exec pp-cli-linux cat /cli/login.log
```

The log prints a confirmation code and a URL. The final browser redirect goes
to `http://127.0.0.1:<port>/auth/callback?…`, a random port that only exists
inside the container. The Mac's browser can't reach it, even with
`--network host` (Docker Desktop doesn't forward the VM's loopback-only binds
to the Mac), and `login` has no flag to pin the port. **Start a tiny callback
forwarder on the Mac *before* the user approves.** Set `W` to the setup's work
folder, `/tmp/pp-local` or `/tmp/pp-aws`:

```bash
W=/tmp/pp-aws; mkdir -p $W          # local Docker: W=/tmp/pp-local
PORT=$(docker exec pp-cli-linux sh -c "awk '\$4==\"0A\" && \$2 ~ /^0100007F:/{print \$2}' /proc/net/tcp" | head -1 | cut -d: -f2)
PORT=$((16#$PORT)); echo "callback port: $PORT"
cat > $W/cb-forward.js << EOF
const http=require('http'),{execFile}=require('child_process');
http.createServer((req,res)=>{
  execFile('docker',['exec','pp-cli-linux','curl','-s','http://127.0.0.1:$PORT'+req.url],(e,out)=>{
    res.writeHead(200,{'content-type':'text/html'});res.end(out||'forwarded');
  });
}).listen($PORT,'127.0.0.1',()=>console.log('listening on $PORT'));
EOF
nohup node $W/cb-forward.js > $W/cb-forward.log 2>&1 &
```

Now give the user the login URL from `login.log` (on its own line, with the
code). After they approve, the redirect lands on the forwarder, and
`docker exec pp-cli-linux cat /cli/login.log` shows `Logged in successfully.`
Stop the forwarder: `pkill -f cb-forward.js`.

- **Order matters:** forwarder first, then approve. Each new `login` may get a
  new port, so re-run the forwarder block.
- **Link expired?** Recreate the container (A.2), run `login` again, restart
  the forwarder, and have the user approve promptly.
- **Expected after login:** `Error: No Passport proxy is configured for your
  team` / `Login succeeded, but Passport credentials were not refreshed.`
  Login's auto-setup ran before a proxy was registered. Nothing is wrong; A.4's
  `setup` fixes it.
- **Manual fallback** if the forwarder can't run: the user copies the failed
  `http://127.0.0.1:<port>/auth/callback?…` URL from the browser's address bar,
  and you run `docker exec pp-cli-linux curl -s "<that URL>"`.
- **Stale login:** `ECONNREFUSED` on a port other than the log's, or a callback
  404, means an older `login` is still bound. Find it with
  `docker exec pp-cli-linux pgrep -fl passport`, or recreate the container.
- **The team ID:** `docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport auth status | awk '$1=="org"{print $2}'`
  (AWS: `cli auth status`, which step 2 already uses).

### A.4 Setup and test

**Local Docker** (replaces local 6 and the CLI parts of 7):

```bash
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport setup \
  --management-url http://localhost:8081 --proxy-url https://localhost:8443 --no-daemon
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport whoami
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport request \
  "https://passport-demo.mock.postman.postman.dev" -H "x-demo-api-key: {{vault:$REF}}"   # expect "key":"sdfds…","key_length":19
```

For local 7's `curl`, use `D=~/passport-cli-dl/.passport`. The folder is
bind-mounted, so the Mac's `curl` can read `cert.pem` and `key.pem`.

**AWS:** steps 7 and 8 run as written: they call `cli` and `$PASSPORT_DIR`,
and step 7 adds `--no-daemon` when `MDM=1`. Skip `passport ca install` and the
`security verify-cert` check. `cli request "https://passport-demo.mock.postman.postman.dev" -H "x-demo-api-key: {{vault:$REF}}"`
is an extra check that works here.

**Found MDM after AWS step 3?** The instance was built with `ORG` from the host
CLI, which may be the wrong team. Record the mode (above), do A.1–A.3, then
compare `cli auth status` (`org` line) with `onhost 'cat /opt/passport/proxy.conf'`.
If they differ: `st ORG <the container's org>`, then
`onhost "sed -i 's/^ORG=.*/ORG=$ORG/' /opt/passport/proxy.conf"`, and have the
user run step 5 again (it restarts the proxy with the new team). Step 6 must use
the container's login, so run it only after this.

### A.5 Daemon on an MDM Mac (plain `curl` from the user's terminal)

The container CLI can run the daemon, but the daemon listens on its
container's own `127.0.0.1`, which the Mac can't reach. So it runs in its own
container, and a small forwarder publishes it on the Mac's **loopback only**.

```bash
cat > ~/passport-cli-dl/daemon-fwd.js << 'EOF'
require('net').createServer(c=>{const u=require('net').connect(10144,'127.0.0.1');c.pipe(u).pipe(c);c.on('error',()=>u.destroy());u.on('error',()=>c.destroy());}).listen(10145,'0.0.0.0',()=>console.log('fwd 10145->10144'));
EOF
```

**Local Docker:** the daemon shares the **proxy's** network, where
`localhost:8443` is the proxy.

1. Re-create the proxy with one extra port: local 4.4's `docker run`, plus
   `-p 127.0.0.1:10144:10145`. The keys and the Vault are unchanged, so
   references keep working.
2. Start the daemon:
   ```bash
   docker run -d --name pp-daemon --restart unless-stopped --network container:pp-proxy-local -v ~/passport-cli-dl:/cli:ro -w /cli node:20 \
     sh -c "umask 077; mkdir -p /root/.passport && cp /cli/.passport/passportrc /root/.passport/passportrc; export PASSPORT_DIR=/root/.passport; ./passport setup --management-url http://localhost:8081 --proxy-url https://localhost:8443 --no-daemon > /root/setup.log 2>&1; node /cli/daemon-fwd.js & exec ./passport daemon start --foreground"
   docker exec -e PASSPORT_DIR=/root/.passport pp-daemon ./passport daemon status     # upstream localhost:8443 (reachable)
   ```
3. Re-create `pp-daemon` whenever you re-create `pp-proxy-local`.

**AWS:** the proxy is on EC2, so the daemon runs on a normal bridge network.

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
docker run -d --name pp-daemon --restart unless-stopped -p 127.0.0.1:10144:10145 -v ~/passport-cli-dl:/cli:ro -w /cli node:20 \
  sh -c "umask 077; mkdir -p /root/.passport && cp /cli/.passport/passportrc /root/.passport/passportrc; export PASSPORT_DIR=/root/.passport; ./passport setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443 --no-daemon > /root/setup.log 2>&1; node /cli/daemon-fwd.js & exec ./passport daemon start --foreground"
docker exec -e PASSPORT_DIR=/root/.passport pp-daemon ./passport daemon status     # upstream <PROXY_HOST>:8443 (reachable)
```

*Unverified on EC2.* The Mac's public IP must be in the 8443 rule. If the
daemon reports the upstream as unreachable, check the security group first.

**Both:**

- **The daemon gets its own private credentials folder** (`/root/.passport`,
  inside its container), seeded with a copy of your login. Don't share
  `~/passport-cli-dl/.passport` with it: Docker Desktop reports shared sockets
  as `0755`, the CLI then refuses (`Passport daemon ownership state has unsafe
  permissions`), marks the credentials inactive, and the daemon answers `502`.
  With a private folder, `setup` in `pp-cli-linux` never interferes.
- **Refresh the daemon's login** (if renewal fails after the login expires):
  `docker restart pp-daemon`.
- **AWS 8.3 and 8.4 line 4:** use the `pp-daemon` status command above.
- **The block to give the user** for a new terminal window (macOS
  `/usr/bin/curl` honours `SSL_CERT_FILE`):
  ```bash
  export HTTPS_PROXY=http://127.0.0.1:10144
  export SSL_CERT_FILE=~/passport-cli-dl/.passport/ca.pem
  curl -sS -H "x-demo-api-key: {{vault:<REF>}}" https://passport-demo.mock.postman.postman.dev; echo
  ```

## Cleanup (with the setup's own cleanup, only when the user asks)

```bash
docker rm -f pp-daemon pp-cli-linux
pkill -f cb-forward.js
rm -rf ~/passport-cli-dl          # only if the user no longer needs the Linux CLI build
```
