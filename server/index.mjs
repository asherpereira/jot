import {createServer} from 'node:http';
import {createHash, timingSafeEqual} from 'node:crypto';
import {validInput, parseCapture} from './capture.mjs';

const {GEMINI_API_KEY: key, GEMINI_MODEL: model = 'gemini-3.5-flash-lite',
  JOT_ACCESS_TOKEN: token, HOST: host = '127.0.0.1', PORT: port = '8787'} = process.env;
if (!key?.trim() || !token?.trim()) throw new Error('Set GEMINI_API_KEY and JOT_ACCESS_TOKEN in server/.env.');
const digest = value => createHash('sha256').update(value).digest();
const expected = digest('Bearer ' + token);
function reply(res, status, data) {
  res.writeHead(status, {'content-type': 'application/json', 'cache-control': 'no-store'});
  res.end(JSON.stringify(data));
}
let active = 0;
createServer({requestTimeout: 30000}, async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/v1/capture') return reply(res, 404, {error: 'unknown route'});
  if (!timingSafeEqual(expected, digest(req.headers.authorization ?? ''))) return reply(res, 401, {error: 'access denied'});
  if (active >= 4) return reply(res, 429, {error: 'busy'});
  active++;
  try {
    const chunks = [];
    let bytes = 0;
    for await (const chunk of req) {
      bytes += chunk.length;
      if (bytes > 16384) return reply(res, 413, {error: 'capture too large'});
      chunks.push(chunk);
    }
    let input;
    try { input = JSON.parse(Buffer.concat(chunks).toString()); }
    catch { return reply(res, 400, {error: 'invalid JSON'}); }
    if (!validInput(input)) return reply(res, 400, {error: 'invalid capture'});
    const draft = await parseCapture(input, {key, model});
    reply(res, 200, draft);
  } catch {
    reply(res, 502, {error: 'Gemini could not produce a complete capture'});
  } finally { active--; }
}).listen(Number(port), host, () => console.log('Jot capture relay listening on ' + host + ':' + port));
