# Changelog

What changed in each version of Siku, in plain language. The newest version is at the top.
Each release on GitHub shows its section from this file.

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
