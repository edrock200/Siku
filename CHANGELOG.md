# Changelog

What changed in each version of Siku, in plain language. The newest version is at the top.
Each release on GitHub shows its section from this file.

## v0.1.13

- **Fixed:** no sound when the server repackaged a video as a stream (for example a Dolby
  Vision file on a Roku that reports no Dolby Vision, so the server keeps the HDR10 layer). The
  original Dolby Digital audio was copied into that stream and played silent on Roku. Siku now
  asks for AAC on that route, so you get sound. Files that play directly still send Dolby
  Digital and Dolby Digital Plus to your TV or receiver untouched.
- **For troubleshooting:** the `[siku-playback]` debug line also shows your Roku model and
  exactly what it reports about your TV (Dolby Vision, HDR10, HLG...).

## v0.1.12

- **Fixed:** videos no longer drop to 720p. Choosing Original, Auto or 4K in Settings used to
  leave an old 6 Mbps limit in place, so the server shrank everything to 720p. Those choices now
  remove the limit, and "Original" never sends one.
- **Fixed:** the quality no longer shows "at 6 Mbps" when you did not choose a limit.
- **Improved:** Siku now tells the server exactly what your Roku and TV can play: 4K, Dolby
  Vision (with its profiles), HDR10, HDR10+, HLG, HEVC 10-bit, and which surround formats
  (Dolby Digital, Dolby Digital Plus, DTS, TrueHD) your TV or receiver accepts as they are.
  The server can then send the original video and audio instead of converting them.
- **New:** Settings › Playback has the Android TV HDR options: Profile 7 HDR10 Fallback (under
  Dolby Vision) and Force HDR Passthrough. They appear when your TV supports them.
- **Fixed:** the player's info panel shows what is really playing: Direct Play, Remux or
  Transcode, the video format (for example HEVC · 4K · Dolby Vision) and the audio (for example
  E-AC3 5.1), plus the original file's details. The Video tab adds HDR and Dolby Vision switches.
- **New:** the buffering screen shows a percentage, and the progress bar shows how much is
  loaded ahead when the stream reports it.
- **Fixed:** Back now leaves Search from anywhere on the screen, and Up from the search box goes
  to the top bar.
- **Fixed:** long audio, subtitle and version lists scroll inside the screen instead of running
  off the bottom, with arrows when there is more.
- **For troubleshooting:** each video start writes one line to the Roku debug log
  (`telnet <roku-ip> 8085`) starting with `[siku-playback]`, listing what Siku told the server
  and what the server chose.

## v0.1.11

A full review of the app, fixing problems before they show up on your TV.

- **Fixed:** many places that could crash if your server sends a number as text (sign-in
  timers, video length, chapters and intro markers, episode and season numbers, resume
  positions, library counts, notification count, audiobook parts). They now read either form.
- **Fixed:** the highlighted card was also cut off at the top on the Calendar, a person's
  filmography and the Search results grid. It now shows in full, as on Home since v0.1.9.
- **Fixed:** on the Requests page, the Home banner could show through under the request banner.
- **Fixed:** the A to Z letters in libraries now scale to fit the rail.
- **Fixed:** buttons, chips and panels size correctly even when their width works out to a
  fraction of a pixel.
- **Fixed:** profile tiles on the Who's Watching screen can always take the remote's focus.
- **Changed:** long notification texts measure their height reliably, so rows don't overlap.

## v0.1.10

- **Fixed:** subtitles now turn on by themselves according to your Subtitles settings, the same
  way the Android TV app does it:
  - **Always:** the best track in your chosen language starts on every video.
  - **Auto:** subtitles start when the audio is in another language; with Show Forced Subtitles
    on, a forced track (signs and foreign dialogue) starts for audio in your language.
  - **Off:** no subtitles.
  A full track is preferred over forced or SDH ones. A subtitle you pick on the details page,
  or Off chosen there, still wins.
- **Note:** this applies to text subtitles (SRT and WebVTT), which are the kinds Roku can show.

## v0.1.9

- **Fixed:** the highlighted poster was cut off at the top of each row on Home, and in the cast,
  "More like this", search and request rows. The enlarged poster and its outline now show in
  full.

## v0.1.8

- **New:** Settings now matches the Android TV app. The General, Playback, Subtitles and
  Server pages hold the same groups and rows: Home Sections (hide and reorder rows), Cards &
  Posters (preset, poster size, captions, Only This Device), Show title art, Show Audiobooks,
  Metadata Language, Quality (with bandwidth presets), Audio Language, Dolby Vision, Auto-Play
  Next Episode, Show Next Up, Skip Intros, Skip Credits, Rewind on Resume, Still Watching
  Prompt, Skip Back / Skip Forward, Reset Playback Overrides, subtitle Language, Behavior and
  Show Forced Subtitles, the custom subtitle appearance (font, colors, opacity, outline,
  background, position) and the server details.
- **New:** most of these settings are saved on your Silo server for your profile, so a choice
  made on Siku is used by your other Silo apps and the other way round. Siku shows what the
  server resolves and falls back to the values saved on the Roku when the server is unreachable.
- **Changed:** the player follows those settings: streaming quality and bandwidth cap, skip
  intervals, intro and credits skipping, auto-play, when the Up Next card appears, rewinding a
  few seconds when you resume, and pausing auto-play after several episodes in a row. Home
  honours the hidden rows, their order and "hide watched items"; cards follow the poster size
  and caption choice; title art can be turned off.
- **Note:** the subtitle appearance choices are saved for your other devices, but on Roku
  captions keep the style set in your Roku's own Settings › Accessibility › Captions style.

## v0.1.7

- **Fixed:** the empty white circles in the top bar. The tabs now show their names (Home,
  Movies, Series and so on) and the highlight follows the selected tab.
- **Fixed:** the empty buttons in Search now show their labels.
- **Fixed:** the highlight in the subtitle menu now moves with your selection.
- **Fixed:** the same cause was also affecting the player's settings menu, the More menu on
  detail pages, the side panels and action menus, the Calendar day strip and the A to Z rail;
  they now all show the right text and highlight the right row.

## v0.1.6

- **Fixed:** the subtitle menu in the player now names tracks by language ("English") instead
  of showing the file format ("SUBRIP").
- **Changed:** every piece of on-screen text now gets its own font setup. This was an attempt
  to fix the empty white circles in the top bar and the empty buttons in Search. It did not
  fix them; a diagnostic to find the real cause is in progress.

## v0.1.5

- **Fixed:** crashes that would have hit the profile menu and the Shuffle feature on a real
  Roku, caused by two words Roku's language treats as reserved.
- **Fixed:** the app no longer trips over movie or show details the server sends in an
  unexpected form (for example a runtime stored as text instead of a number).
- **Fixed:** the login details sent with each video stream now use the exact format Roku
  documents, so streams start reliably.
- **Changed:** switching servers or signing out now clears cached playback details, so the
  first video on a new server starts without an extra round trip.

## v0.1.4

- **Fixed:** the app hung on the splash screen. Version 0.1.3 measured text with a tool that
  Roku only allows in background tasks, not on screen. Text is now measured in a way Roku
  permits everywhere.

## v0.1.3

- **Fixed:** opening any movie, show or episode froze the app. The code that built the web
  address for the item used a component Roku does not allow on screen.
- **Attempted:** a fix for the white circles in the top bar (the real cause was still unknown).

## v0.1.2

- **Fixed:** the app would not install on a Roku because of a line of code Roku's compiler
  rejects. Twelve similar lines were corrected at the same time.

## v0.1.1

The first build that installs on a Roku. Everything below had only ever run in a simulator.

- **Connect** to a Silo server by typing its address, with HTTPS tried first.
- **Sign in** by scanning a QR code or typing a code on your phone, or with a password.
- **Profiles:** pick who is watching; profiles with a PIN ask for it.
- **Home:** a backdrop that follows the highlighted title, Continue Watching with progress
  bars, and the rows your server provides (Recently Added, Trending, and so on).
- **Browse** your libraries with sort and filters, collections, favorites, watchlist and
  history. Audiobooks also offer Authors, Series and an A to Z rail.
- **Details** for movies, shows (seasons and episodes), episodes and people, with Play,
  Resume, Watchlist, Favorite and a More menu (mark watched, shuffle).
- **Player** with a seek bar, skip back and forward, audio and subtitle menus, Skip Intro,
  Up Next with auto play, and server-side shuffle.
- **Subtitle tools:** search and download subtitles, AI translation, sync to audio and a
  delay adjustment, each shown only when your server supports it.
- **Audiobooks and music:** detail pages and a now-playing screen with chapters and a sleep
  timer. Music depends on the Silo server adding music support.
- **For You, Calendar, Search, Requests, Notifications and Settings.**
