<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# Playback error numbers

When Siku can't play something, the error screen starts with a four-digit number, for example:

> **#3001** This Roku couldn't play the stream. Try another version or a lower quality. **(Roku -5)**

The number stays on screen until you press **OK** (Try again / Close) or **Back**. Please include
it when you ask for help, together with the Siku version, your Roku model and whether playback
failed straight away or after it had been playing. A photo of the screen is enough. Never share
tokens or stream links.

The number in brackets, such as `(Roku -5)`, is the error code the Roku's own video player gave.
It tells us what the Roku reported, not that the file, the network or the decoder alone is at
fault. Common Roku codes: `-1` the stream could not be downloaded, `-2` a download timed out,
`-3` unknown, `-4` empty stream, `-5` the Roku couldn't decode or open the format, `-6` DRM.

The numbers follow the scheme of [ManavA/silo-roku](https://github.com/ManavA/silo-roku), so a
number means the same thing in both Roku apps. Numbers Siku does not use (1002, 1003, 1005) are
left free rather than reused.

| Number | What happened | What to check |
| --- | --- | --- |
| 1001 | The title lists no playable file, even after Siku read it a second time | The library scan, the profile's access to the library, the right episode or movie |
| 1004 | The title's details couldn't be loaded | Connection to the server, signing in again, whether the title still exists |
| 2001 | The server couldn't prepare playback and gave no more specific reason (or the request failed) | Server connection and the server's playback log |
| 2002 | The server has no playable source for this title | The file on disk and the server's scan |
| 2003 | No other version of this title can play | Other versions of the title, conversion settings |
| 2004 | The server can't prepare this HDR or Dolby Vision format | Dolby Vision profile, tone-mapping support on the server |
| 2005 | The server can't prepare this audio format | The audio track, the server's conversion tools |
| 2006 | The server can't prepare these subtitles | The subtitle format; try another subtitle or Off |
| 2007 | The server's playback protocol isn't supported (it needs playback protocol v3) | Update the server |
| 2008 | The server sent a stream format Roku can't play | Server version; report it with the `[siku-playback]` line |
| 2009 | Video conversion is turned off for this playback | The account's or server's transcoding setting |
| 2010 | A conversion tool the server needs is unavailable | The server's transcoder (ffmpeg) installation |
| 2011 | The server needs more information about the file's format | Re-scan or re-probe the file |
| 2012 | The server couldn't read the file | Storage, mounts and permissions on the server |
| 2013 | The server can't meet the bitrate limit | Settings › Playback › Maximum Bitrate |
| 2014 | The server has no other way left to play the title | Conversion settings, other versions |
| 2015 | No playback route was found for this Roku | Roku software update, server conversion settings |
| 2016 | The server couldn't start converting the title | The server's transcoder and its log |
| 3001 | The Roku's player failed and there was no other way to try | The `(Roku …)` code, the file's format, the TV/receiver |
| 3002 | Playback didn't start, or stopped moving, for too long and there was no other way to try | Network speed; try a lower quality |
| 3003 | Siku asked the server for other ways to play the title and none worked | The last reason in the console line, other versions |
| 3004 | The playback session changed or disappeared on the server | Start playback again |

## What Siku tries before showing 3001, 3002 or 3003

When the Roku's player reports an error, or the picture has not moved for 60 seconds while
playing (120 seconds while it is still starting), Siku does not give up at once:

1. It asks the server for another way to play the same thing (a "failure recovery"). The server
   skips the route that just failed.
2. If your quality is **Auto**, it then steps down: 1080p, then 720p, then 480p, using only the
   qualities the server offers for this title and only ones below what failed.
3. After that it stops and shows the number.

A quality or audio/subtitle track you picked yourself is kept: Siku tries another route once but
does not lower a quality you chose. Each attempt tells the server which routes were already
tried and how many attempts were made, so the server can refuse instead of repeating itself.

When a title lists no playable file, Siku reads the title once more before showing 1001 (the
server may still have been writing it).

## Automatic reports

If your server supports it (it lists `playback_route_diagnostics`), Siku sends **one** short
report to **your own server** when playback fails for good: `POST /api/v2/playback/route-events`.
The error screen appears first and works normally while the report is sent. Only when the server
confirms it accepted the report does the screen add **"Report sent to your server."** This means
the server stored it, not that anyone has looked at it yet.

The report contains only:

- the error number (`error_code`, e.g. `3001`);
- a fixed reason name (`reason` and `failure_classification`, e.g. `decoder_failure`,
  `buffering_timeout`, or the server's own terminal reason such as `transcoding_disabled`);
- the Roku's error code (`error_code_name`, e.g. `roku_native_-5`);
- the Roku model number (`device_model`, e.g. `3820X`);
- the playback attempt, session and plan identifiers the server needs to match the report to
  your playback.

It never contains stream links, titles, file paths, tokens or the Roku's raw error text. Siku
waits at most 3 seconds, does not retry and does not refresh its sign-in for it; if the report
can't be sent, the number on screen is still there for you to pass on.

Errors in the 1000s (the title's details or files) and failed requests have no playback attempt
on the server, so they are not reported automatically. 3004 is not reported either: the session
it would refer to is gone.

## For developers

- Numbers: `components/player/PlaybackErrors.brs` (`PlaybackError_show`, `PlaybackError_report`).
  Recovery: `components/player/PlaybackRecovery.brs` (`Recovery_*`).
- The console prints `[siku-playback] error #<n> reason=… roku=… delivery=… recoveries=…
  plan_keys=… report=…`, then `[siku-playback] error report #<n> status=… accepted=…`. Each
  recovery prints `recovery <n> classification=… quality=… attempt_count=…` and `recovery <n>
  mounted …` or `answered outcome=…`; the watchdog prints `no progress for <s> s`.
- Simulator: the Video node never plays there. Deep link `debugVideoError=<code>` fakes that Roku
  error 4 s after each plan is mounted; `debugStallSeconds=<n>` sets the watchdog limit (`off`
  disables it for long simulator runs). Mock switches: `native_recovery=1`,
  `recovery_terminal=1`, `route_events=accept|reject|bad_receipt`, `empty_inventory=once|always`,
  `start_terminal=<reason>` (see `tools/mock_server.py`).
