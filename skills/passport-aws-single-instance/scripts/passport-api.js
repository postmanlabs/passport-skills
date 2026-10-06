'use strict';
const fs = require('fs'), os = require('os'), path = require('path');
const dir = process.env.PASSPORT_DIR || path.join(os.homedir(), '.passport');
const api = (process.env.PASSPORT_API || 'https://api.usepassport.ai').replace(/\/$/, '');
const [method, urlPath, rawBody] = process.argv.slice(2);
const rc = JSON.parse(fs.readFileSync(path.join(dir, 'passportrc'), 'utf8'));
const token = rc.login._profiles[0].workos.accessToken;
const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
if (claims.exp * 1000 < Date.now()) { console.error('token expired; run: passport auth status'); process.exit(1); }
if (!claims.org_id) { console.error('session has no organization (step 1.1)'); process.exit(1); }
let body;
if (rawBody) { body = rawBody.startsWith('@') ? fs.readFileSync(rawBody.slice(1), 'utf8') : rawBody; JSON.parse(body); }
fetch(api + urlPath, { method, headers: { authorization: 'Bearer ' + token, 'content-type': 'application/json', accept: 'application/json' }, body })
  .then(async (r) => { const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; }
    console.log(JSON.stringify({ status: r.status, org: claims.org_id, body: j }, null, 1)); process.exit(r.ok ? 0 : 1); })
  .catch((e) => { console.error(e.message); process.exit(1); });
