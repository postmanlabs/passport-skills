# MDM-managed Macs (local Docker)


If `passport login` auto-ran `setup` against endpoints you didn't choose, or
`setup` silently ignores `--management-url`/`--proxy-url`, this Mac has a
managed configuration profile that overrides the CLI's endpoints — with no
flag to turn it off. The fix isn't to bypass MDM on your real Mac; it's to
run the CLI somewhere MDM doesn't reach: a plain Linux container. A
container has no macOS configuration profile at all, so the CLI simply never
detects "managed" and behaves normally.

The team-creation step (1.1) still applies here — do that first, on your
real Mac's CLI or via the web UI, before setting up the container below.

### A.1 Get a Linux build of the CLI

The public installer (step 1) only serves macOS/Windows. You need a **Linux build of the
Passport CLI** (`passport` binary + `lib/`, arm64 or x64 to match `docker run --rm node:20 uname -m`).
Obtain it from your Passport admin or the "Set up Passport" guide in your team
(account menu → How-to) and unpack it into `~/passport-cli-dl` so that
`~/passport-cli-dl/passport` exists. *Unverified:* a public Linux download location — ask the
Passport team where to get one.

> Don't try to build the CLI from source — it needs internal registry access.

### A.2 Run it in a container alongside the proxy

**Use `--network host`, not `--network pp-net`.** This matters for two
separate reasons below: it's what lets `localhost:8081`/`localhost:8443`
inside the container reach the proxy's published ports (a bridge-network
container has its own isolated loopback and gets `ECONNREFUSED` instead),
and it's required for the login workaround in A.3.

```bash
docker run -d --name pp-cli-linux --network host \
  -v ~/passport-cli-dl:/cli -w /cli \
  node:20 sleep infinity
docker exec pp-cli-linux ./passport --version   # sanity check
```

### A.3 Log in — the OAuth redirect needs one manual step

`passport login` tries to open a browser via `xdg-open`, which doesn't exist
in this image and will crash the process. Stub it out first. Then launch
`login` **fully detached** (`docker exec -d`, output to a log file) rather
than attached to your terminal — the approval step can take an arbitrary
amount of time, and an attached process tied to a timed-out shell gets
killed, leaving a dead listener on a stale port that silently breaks the
callback (confirmed live: this is exactly what caused repeated failures
before switching to the detached form below):

```bash
docker exec pp-cli-linux bash -c "printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open && chmod +x /usr/local/bin/xdg-open"
docker exec -d -e PASSPORT_DIR=/cli/.passport pp-cli-linux sh -c "./passport login > /cli/login.log 2>&1"
sleep 2
docker exec pp-cli-linux cat /cli/login.log
```

The log prints a confirmation code and a URL. The final browser redirect
(to `http://127.0.0.1:<port>/auth/callback?code=...&state=...`) points at a
random port that only exists inside the container's network namespace, which
your Mac's browser can't reach (confirmed live: true even with
`--network host` — Docker Desktop doesn't forward the VM's loopback-only
binds to the Mac), and `passport login` has no flag to pin the port.

**Fix (confirmed live 2026-10-05): run a tiny callback forwarder on your Mac
*before* you approve in the browser.** It listens on the same port on your
Mac and relays the callback into the container, so you never copy/paste a URL:

```bash
# 1. Read the random port the container's login is listening on
PORT=$(docker exec pp-cli-linux sh -c "awk '\$4==\"0A\" && \$2 ~ /^0100007F:/{print \$2}' /proc/net/tcp" | head -1 | cut -d: -f2)
PORT=$((16#$PORT)); echo "callback port: $PORT"

# 2. Forward Mac 127.0.0.1:$PORT -> the container's listener
cat > /tmp/pp-local/cb-forward.js << EOF
const http=require('http'),{execFile}=require('child_process');
http.createServer((req,res)=>{
  execFile('docker',['exec','pp-cli-linux','curl','-s','http://127.0.0.1:$PORT'+req.url],(e,out)=>{
    res.writeHead(200,{'content-type':'text/html'});res.end(out||'forwarded');
  });
}).listen($PORT,'127.0.0.1',()=>console.log('listening on $PORT'));
EOF
nohup node /tmp/pp-local/cb-forward.js > /tmp/pp-local/cb-forward.log 2>&1 &
```

Now open the login URL from `login.log` in your browser and approve. The
redirect lands on the forwarder, and `cat /cli/login.log` (via
`docker exec pp-cli-linux cat /cli/login.log`) shows `Logged in successfully.`
Stop the forwarder afterwards: `pkill -f cb-forward.js`.

- **Order matters:** start the forwarder first, then approve. Each new
  `login` attempt may get a new port — re-run the two commands above.
- **Link says expired?** Approval links are short-lived. Recreate the
  container (A.2), run `login` again (it prints a fresh link), restart the
  forwarder, and approve promptly.
- **Expected after login:** `Error: No Passport proxy is configured for your
  team` / `Login succeeded, but Passport credentials were not refreshed.`
  Login's auto-setup ran before any proxy was registered. Nothing is wrong —
  it's fixed by steps 5.1 and A.4's `setup`.
- Node is needed on the Mac for the forwarder (already required by step 7).
- Manual fallback if you can't run the forwarder: copy the failed
  `http://127.0.0.1:<port>/auth/callback?...` URL from your browser's address
  bar and run
  `docker exec pp-cli-linux curl -s "<that URL>"`.

Since the login process was detached, it keeps running no matter how long
the approval takes — there's no timeout to race against, and no need to
restart `login` and get a new confirmation code/URL if the user takes a
while to respond. If you ever do see a `ECONNREFUSED` on a *different* port
than what's in the log, or the callback 404s, a stale `login` process from
an earlier attempt is still bound to the old port — `docker exec pp-cli-linux
pgrep -fl passport` to find it, or just recreate the container (A.2) for a
clean slate.

### A.4 Setup, test, cleanup

From here it's the same as the main flow, just prefixed with `docker exec
-e PASSPORT_DIR=/cli/.passport pp-cli-linux`:

```bash
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport setup \
  --management-url http://localhost:8081 --proxy-url https://localhost:8443 --no-daemon
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport whoami
docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport request \
  "https://passport-demo.mock.postman.postman.dev" -H "x-demo-api-key: {{vault:$REF}}"   # expect "key":"sdfds…","key_length":19
```

For the step 7 `curl`, use `D=~/passport-cli-dl/.passport`. The folder is
bind-mounted, so your Mac's `curl` can read `cert.pem` and `key.pem`.

### A.5 Daemon on an MDM Mac (plain `curl` from your own terminal)

The container CLI can run the daemon (`passport daemon start`), but the daemon
listens on the container's own `127.0.0.1`, which your Mac can't reach. So:
- run the daemon in a sidecar that shares the **proxy's** network, where
  `localhost:8443` is the proxy;
- publish its port on your Mac's **loopback only**, through a small forwarder.

1. **Re-create the proxy with one extra port.** Use the step 4.4 `docker run`,
   adding `-p 127.0.0.1:10144:10145`. The keys and Vault are unchanged, so
   references keep working.
2. **Start the daemon sidecar:**
   ```bash
   cat > ~/passport-cli-dl/daemon-fwd.js << 'EOF'
   require('net').createServer(c=>{const u=require('net').connect(10144,'127.0.0.1');c.pipe(u).pipe(c);c.on('error',()=>u.destroy());u.on('error',()=>c.destroy());}).listen(10145,'0.0.0.0',()=>console.log('fwd 10145->10144'));
   EOF
   docker run -d --name pp-daemon --restart unless-stopped --network container:pp-proxy-local -v ~/passport-cli-dl:/cli:ro -w /cli node:20 \
     sh -c "umask 077; mkdir -p /root/.passport && cp /cli/.passport/passportrc /root/.passport/passportrc; export PASSPORT_DIR=/root/.passport; ./passport setup --management-url http://localhost:8081 --proxy-url https://localhost:8443 --no-daemon > /root/setup.log 2>&1; node /cli/daemon-fwd.js & exec ./passport daemon start --foreground"
   docker exec -e PASSPORT_DIR=/root/.passport pp-daemon ./passport daemon status     # upstream localhost:8443 (reachable)
   ```

   - **The daemon gets its own private credentials folder** (`/root/.passport`, inside its
     container), seeded with a copy of your login. Don't share `~/passport-cli-dl/.passport` with it:
     Docker Desktop reports shared sockets as `0755`, the CLI then refuses (`Passport daemon
     ownership state has unsafe permissions`), marks the credentials inactive, and the daemon
     answers `502`. With a private folder, `passport setup` in `pp-cli-linux` never interferes.
   - **Refresh the daemon's login** (if renewal fails after your login expires): `docker restart pp-daemon`.

3. **The block to give the user** for a new terminal window:
   ```bash
   export HTTPS_PROXY=http://127.0.0.1:10144
   export SSL_CERT_FILE=~/passport-cli-dl/.passport/ca.pem
   curl -sS -H "x-demo-api-key: {{vault:<REF>}}" https://passport-demo.mock.postman.postman.dev; echo
   ```
   macOS `/usr/bin/curl` (8.7) honours `SSL_CERT_FILE`.

- **The sidecar shares the proxy's network,** so re-create `pp-daemon` whenever
  you re-create `pp-proxy-local`.
- **Cleanup:** add `docker rm -f pp-daemon`.

> **Verified 2026-10-07** on an MDM Mac. The block above, in a clean shell,
> returned `"key":"sdfds**************","key_length":19`. Without the `export`
> lines, the API got the pointer unchanged (`"{{vau…",46`).
> After the first 5-minute certificate expired, the same command still worked:
> the daemon minted a new certificate on that request, so you never re-run setup.

Clean up the extra pieces alongside step 8's cleanup:

```bash
docker rm -f pp-daemon pp-cli-linux
rm -rf ~/passport-cli-dl
```

