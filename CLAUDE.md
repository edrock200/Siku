# Siku — project rules for Claude Code

Siku is a Roku SceneGraph/BrightScript channel that ports the Silo **Android TV** client
(`androidTvApp` module of https://github.com/Silo-Server/silo-android) to Roku. It should look
and behave like that app. Start with `docs/ARCHITECTURE.md`; it links the design spec and the
API spec.

## Scope (non-negotiable)
- Port only the Android TV app, not the phone app. No phone-only features.
- No downloads, offline playback, or any local-media-storage features. Android TV has none either.
- Silo **v2 API only** (`/api/v2/...`). `ApiTask` refuses other paths. Never call `/api/v1` or `/health`.
- Watch Party is out of scope (experimental and off in Android TV release builds).
- The app is named **Siku** everywhere a user can see it. The Silo name and logo are Silo Media's
  trademarks; use our own logo (`images/logo_*.png`) and refer to Silo only as what we connect to.
- License: AGPL-3.0-or-later. Every new source file starts with an
  `' SPDX-License-Identifier: AGPL-3.0-or-later` comment (or the XML equivalent).

## Build, lint, test
- `npm install` once, then `npm run lint` (BrighterScript, must report 0 errors) and
  `npm run package` (writes `out/siku.zip`, the side-loadable channel).
- Before finishing any change: lint clean, then run the affected screen in the simulator against
  the mock server. See the `roku-brightscript` skill for the exact commands.
- Pushes to the default branch publish a GitHub Release automatically when `build_version` in
  `manifest` changes. To ship a build: bump `build_version` AND add a `## vX.Y.Z` section to
  `CHANGELOG.md` written for users in plain language (what they will notice, not how it was
  done). The release page shows that section as its notes; the workflow warns if it is missing.
- Every release also updates `.claude/skills/roku-brightscript/SKILL.md`: add what the build
  taught (a new device pitfall, a verification step, a tool quirk) and append a line to its
  "Release log" section naming the version and the lesson. The workflow warns when a released
  version is absent from the skill. A release that taught nothing new still gets a one-line entry.

## The one rule that matters most
Code that passes lint and runs in the simulator can still crash a real Roku. Several did.
Before considering BrightScript done, read `.claude/skills/roku-brightscript/SKILL.md`,
which lists the known real-device pitfalls, and check your diff against them.
