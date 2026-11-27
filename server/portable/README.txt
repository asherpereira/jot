Jot Gemini relay

Install Node.js 22 or later, then extract this whole folder. Dependencies are included.

1. Make a copy of server/env.example named server/.env and set GEMINI_API_KEY to your Google AI Studio API key.
2. Double-click Start.command on Mac or Start.cmd on Windows, or run node start.mjs in this folder. Keep the terminal open.
3. In Jot, open Capture → Gemini relay settings. Enter http://localhost:8787 on the same computer, and the relay access token displayed in the terminal.
4. Choose Use for this session, then Parse with Gemini. Plain local capture works with the relay turned off.

The launcher generates a fresh relay access token each time unless you set JOT_ACCESS_TOKEN in server/.env. Keep your Google key on the relay computer. A device on a different computer or a physical iPhone needs an HTTPS relay address reachable from that device. An Android phone connected via USB can use adb reverse tcp:8787 tcp:8787 and then http://localhost:8787. An Android Studio emulator can reach its host at http://10.0.2.2:8787.
