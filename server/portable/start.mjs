import {randomBytes} from 'node:crypto';
import {existsSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

const config = fileURLToPath(new URL('./server/.env', import.meta.url));
if (existsSync(config)) process.loadEnvFile(config);
if (!process.env.GEMINI_API_KEY?.trim()) {
  console.error('Copy server/env.example to server/.env and set GEMINI_API_KEY first.');
  process.exitCode = 1;
} else {
  if (!process.env.JOT_ACCESS_TOKEN?.trim()) {
    process.env.JOT_ACCESS_TOKEN = randomBytes(32).toString('hex');
  }
  console.log('In Jot, open Capture → Gemini relay settings.');
  console.log('For an app on this computer, use http://localhost:' + (process.env.PORT || '8787'));
  console.log('Personal relay access token: ' + process.env.JOT_ACCESS_TOKEN);
  await import('./server/index.mjs');
}
