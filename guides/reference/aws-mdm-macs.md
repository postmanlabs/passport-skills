# MDM-managed Macs (AWS single instance)


If `passport login` auto-ran `setup` against endpoints you didn't choose, or
`setup` silently ignores `--management-url`/`--proxy-url`, this Mac has a
managed configuration profile that overrides the CLI's endpoints — with no
flag to turn it off. The fix isn't to bypass MDM on your real Mac; it's to run
the CLI somewhere MDM doesn't reach: a plain Linux container.

The team-creation step (1.1) still applies — do that first, via the web UI.
Steps 3–6 (AWS + API) don't use the CLI and work from the host as written, with
`PASSPORT_DIR=~/passport-cli-dl/.passport`.

### A.1 Get a Linux build of the CLI

The public installer (step 1) only serves macOS/Windows. You need a **Linux build of the
Passport CLI** (`passport` binary + `lib/`, arm64 or x64 to match `docker run --rm node:20 uname -m`).
Obtain it from your Passport admin or the "Set up Passport" guide in your team
(account menu → How-to) and unpack it into `~/passport-cli-dl` so that
`~/passport-cli-dl/passport` exists. *Unverified:* a public Linux download location — ask the
Passport team where to get one.

> Don't try to build the CLI from source — it needs internal registry access.

### A.2 Run it in a container

```bash
docker run -d --name pp-cli-linux --network host \
  -v ~/passport-cli-dl:/cli -w /cli \
  node:20 sleep infinity
docker exec pp-cli-linux ./passport --version   # sanity check
```

### A.3 Log in — the OAuth redirect needs one manual step

`passport login` tries `xdg-open`, which doesn't exist in this image. Stub it,
then launch `login` **fully detached** so it isn't tied to a timeout:

```bash
docker exec pp-cli-linux bash -c "printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open && chmod +x /usr/local/bin/xdg-open"
docker exec -d -e PASSPORT_DIR=/cli/.passport pp-cli-linux sh -c "./passport login > /cli/login.log 2>&1"
sleep 3
docker exec pp-cli-linux cat /cli/login.log
```

The log prints a confirmation code and a URL. The final browser redirect goes
to `http://127.0.0.1:<port>/auth/callback?...`, a random port that only exists
inside the container, which your Mac's browser can't reach. **Run a tiny
callback forwarder on your Mac *before* approving:**

```bash
mkdir -p /tmp/pp-aws
PORT=$(docker exec pp-cli-linux sh -c "awk '\$4==\"0A\" && \$2 ~ /^0100007F:/{print \$2}' /proc/net/tcp" | head -1 | cut -d: -f2)
PORT=$((16#$PORT)); echo "callback port: $PORT"
cat > /tmp/pp-aws/cb-forward.js << EOF
const http=require('http'),{execFile}=require('child_process');
http.createServer((req,res)=>{
  execFile('docker',['exec','pp-cli-linux','curl','-s','http://127.0.0.1:$PORT'+req.url],(e,out)=>{
    res.writeHead(200,{'content-type':'text/html'});res.end(out||'forwarded');
  });
}).listen($PORT,'127.0.0.1',()=>console.log('listening on $PORT'));
EOF
nohup node /tmp/pp-aws/cb-forward.js > /tmp/pp-aws/cb-forward.log 2>&1 &
```

Now open the login URL from `login.log` in your browser and approve. The
redirect lands on the forwarder, and `docker exec pp-cli-linux cat /cli/login.log`
shows `Logged in successfully.` Stop the forwarder afterwards:
`pkill -f cb-forward.js`.

- **Order matters:** forwarder first, then approve. Each new `login` may get a
  new port — re-run the two commands.
- **Link expired?** Recreate the container (A.2), run `login` again, restart the
  forwarder, approve promptly.
- **Expected after login:** `Error: No Passport proxy is configured for your
  team` / `Login succeeded, but Passport credentials were not refreshed.` —
  nothing is wrong; it's fixed by step 6 and A.4's `setup`.
- The team ID: `docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport auth status | awk '$1=="org"{print $2}'`.

### A.4 Setup and test (replaces steps 7 and 8's CLI calls)

The API helper (`api`) reads this container's login. Record it once, so every
`. "$REPO/scripts/env.sh"` uses it:
`st PASSPORT_DIR ~/passport-cli-dl/.passport`.

```bash
REPO=<repo>; . "$REPO/scripts/env.sh"
pp() { docker exec -e PASSPORT_DIR=/cli/.passport pp-cli-linux ./passport "$@"; }   # a function, not a string: zsh won't split a stored command
pp setup --management-url https://$CF_DOMAIN --proxy-url https://$PROXY_HOST:8443 --no-daemon
pp whoami
pp request "https://passport-demo.mock.postman.postman.dev" -H "x-demo-api-key: {{vault:$REF}}"   # expect "key":"sdfds…","key_length":19
```

For the explicit `curl` (steps 8.2 and 10), use `~/passport-cli-dl/.passport` in
place of `~/.passport`. The folder is bind-mounted, so your Mac's `curl` can read
`cert.pem` and `key.pem`.

**What doesn't apply on this path:**
- **`passport ca install` and the daemon.** The container CLI is Linux, which
  supports neither. In step 8.5, report lines 3–4 as "not applicable (MDM
  container path)", not ✅. Requests use the explicit form.
- **Renewal.** Nothing renews `cert.pem` in the background. Re-run
  `pp setup … --no-daemon` when `notAfter` passes.
