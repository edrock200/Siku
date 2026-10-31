# Changelog

What changed in each version of Siku, in plain language. The newest version is at the top.
Each release on GitHub shows its section from this file.

## v0.1.30

One change from Silo's Android TV app (October 30, 2026).

**Changed**
- **Back from "More Like This" takes two presses, not twenty.** Following one title after another from a page's Related Movies or Recommended Series row no longer piles up pages: Back returns to the title you started from, then to wherever you opened it. Picking that first title again from the row takes you back to it, and pressing OK twice on a card opens it only once. It also keeps fewer pages in the Roku's memory.

**Needs testing on a real Roku:** a long More Like This chain followed by Back.

## v0.1.29

One subtitle fix from Silo's Android TV app (October 30, 2026).

**Fixed**
- **AI subtitles start much sooner.** "Translate with AI" now tells the server which video you are watching, so it works from where you are in short pieces and the progress moves within seconds. Before, it prepared the whole file first and sat at "0% · Preparing audio" for minutes. If the server has lost track of your video, Siku asks once more the old way, so the subtitles still arrive.

**Needs testing on a real Roku:** a "Translate with AI" or transcribe job against a real Silo server, to see the progress start moving within seconds. The debug log `telnet <roku-ip> 8085` prints `[siku-playback] ai subtitle session not found (404); sending again without it` when the fallback is used.

## v0.1.28

Two phone-control fixes from Silo's Android TV app (October 28, 2026).

**Fixed**
- **Phone hand-off stays on your home network.** When your phone reaches your server at its internet address and hands a title to a Roku on your home network, the Roku now connects to the server at its own home-network address (or another address the phone offers) instead of failing or streaming over the internet. It checks each address is really the same server first.
- **Phones find Rokus signed in with an older Siku.** A Roku first signed in with an older Siku now shows up in the phone app's remote list even when the phone reaches your server at a different address.

**Needs testing on a real Roku and phone:** a phone on your server's internet address (or Tailscale) handing a title to a Roku on your home network, and an iPhone on another address finding the Roku. The debug log `telnet <roku-ip> 8085` shows `[siku-cast] handoff address own|phone|endpoint`.

## v0.1.27

Brings Siku up to date with Silo's Android TV app as of October 28, 2026.

**New**
- **Explore all.** Rows on Home and on library pages show up to 20 titles and end with an **Explore all** card that opens the whole row as its own page. A Movies or Series view of a mixed library keeps that filter there. On newer Silo servers, Home and library pages ask only for the titles a row shows, so they load less; older servers work as before.
- **Show artwork for episodes.** On servers that send it, episodes fill the Home banner, the episode page and the Up Next screen with their show's artwork, even when spoiler protection hides episode pictures. Episode posters in grids show the season or show poster instead of a stretched episode picture.

**Fixed**
- **Mark as Watched tells the truth.** If marking a card watched or unwatched fails, the card goes back to how it was and a message says why, instead of claiming it worked.

**Needs testing on a real Roku:** the Explore all card's look and the screen reader reading it, show artwork from a real server (and on the Up Next screen), and that a long "Couldn't mark as watched" message wraps instead of being cut off.

## v0.1.26

Fixes from a full review of Siku, plus a library fix from Silo's Android TV app (October 27, 2026).

**Fixed**
- **Titles and playback on a Roku.** A line added in v0.1.23 is refused by Roku's own compiler, which could stop title pages and the player from opening on a real Roku. If v0.1.23–v0.1.25 couldn't open titles for you, this is the fix. Releases now check for this automatically.
- **Library filters work again.** Unwatched, Watched, In Progress, Favorited and Watchlist showed "Something went wrong" with current servers.
- **No more frozen player.** Opening a title from the Roku home screen, search or the mobile app while something plays no longer leaves a dead player behind when you press Back.
- **You stay signed in.** A temporary server or network problem no longer signs you out; Siku only asks you to sign in again when your session has really expired.
- **Next episode.** Starting the next episode quickly can no longer be disturbed by the previous episode's late answers, and its subtitles no longer carry over. A show's page moves "Play" to the right episode after you watch one or mark it watched.
- **Phone control.** Signing out or changing server while a phone's profile is playing now sticks (your old account no longer comes back), signing out disconnects every phone, and phones see the TV as ready as soon as they connect.
- **Smaller fixes:**
  - Up Next waits until an open menu is closed.
  - A paused stream stays paused after a far jump.
  - The connection speed test works on PIN-protected profiles.
  - "Change server" on the sign-in screen cancels the pending sign-in code.
  - A setting you just changed no longer flips back.
  - If a show's episodes fail to load, there's a Retry button you can reach with the remote, and a failed "load more" no longer pops up an error on every button press.
  - Home opens instantly more often (large Homes and non-English titles are now saved), and switching profiles no longer leaves the previous profile's Home behind.
  - A seventh phone is told "too many devices" (when pairing is off), the TV keeps announcing itself after its network address changes, and Siku ignores oversized or repeated network messages.
  - Connect a Phone now says plainly that, without pairing, any device on your network that names your server can connect.

**Needs testing on a real Roku:** that titles and the player open (the compile fix), staying signed in through a server restart (`[siku-auth]` lines in `telnet <roku-ip> 8085`), Up Next and subtitles between episodes, and signing out while a phone's title plays.

## v0.1.25

Brings Siku up to date with Silo's Android TV app as of October 27, 2026, with two more ideas from [ManavA/silo-roku](https://github.com/ManavA/silo-roku).

**New**
- **Voice control while watching or listening.** Say "pause", "resume", "stop", "fast forward", "rewind", "replay" or "skip ahead 2 minutes" to your Roku voice remote. Skips move by the same amounts as your remote's skip buttons. While a video is loading or changing quality, Siku turns the request down instead of ignoring it. Works for audiobooks and music too.
- **Home opens instantly.** Siku remembers your Home rows from last time and shows them straight away, then updates them once your server answers, without moving you off the card you were on. Pictures appear with the update. The saved Home is cleared when you sign out or switch server or profile.

**Changed**
- **Every card shows its title.** As in Silo's Android TV app, the "Captions" and "Preset" choices are gone from Settings › General › Cards & Posters; every card shows its title and details, and Poster Size is still yours to choose.
- **The screen reader reads the player's panel.** With Roku's screen reader on, the player's Info, Video, Audio and Subtitles panel and the choices it opens are read out: the option, whether it is selected, and its position.

**Needs testing on a real Roku:** voice commands (the debug log `telnet <roku-ip> 8085` should show `[siku-voice] transport events enabled=true`, then one line per command), whether the saved Home survives restarting the channel (`[siku-home] cache hit` on the second launch), and the player panel's speech.

## v0.1.24

Improvements inspired by another Roku client for Silo, [ManavA/silo-roku](https://github.com/ManavA/silo-roku), adapted to Siku.

**New**
- **Find servers on your network.** The server screen now lists servers found on your home network. Pick one and confirm it; Siku checks the server is the one it claims to be before connecting. You can still type an address while it searches, and it tells you when none were found.
- **Original picture with sound on newer servers.** On servers updated after October 26, 2026, titles the server repackages can keep their original video (including 4K, HEVC and HDR10) instead of being converted to H.264. Jumping far ahead or back in such a title asks the server to restart the stream there. Dolby Vision profile 7 files play as their HDR10 picture. If these titles play without sound or fail on your Roku, turn off **Settings › Playback › Experimental: MPEG-TS Copy**.
- **Screen reader.** With Roku's screen reader on, Siku reads out buttons, tabs, settings, the PIN pad and the profile picker as you move between them. It never reads passwords or PINs.

**Changed**
- **Playback recovers by itself.** When a video fails or keeps stalling, Siku asks your server for another way to play it, and on Auto quality steps down 1080p → 720p → 480p. A quality you picked yourself is kept.
- **Numbered errors.** Playback errors show a number, such as "#3001 … (Roku -5)", so a report can say exactly what failed, and Siku tells your server what went wrong.
- A title that shows no playable file is checked once more before Siku gives up.
- Siku copes better when your Roku runs low on memory: screens you are not looking at let go of their pictures and reload them when you come back. Pictures also load at the size they are shown.
- Phone remote control and phone sign-in are steadier on busy networks: a slow phone can no longer hold up the TV.
- Roku now measures Siku's start-up correctly: it ends when Home is on screen, and time spent signing in or choosing a profile doesn't count.

**Fixed**
- Home's background picture could go black after a picture reloaded.
- Numbers a server sends as text are read correctly.
- Siku ignores oversized or malformed answers from devices on the network, double-checks secure (https) connections, and refuses server addresses crafted to reach anything but the server's current API.
- The device console no longer shows audio stream links.

**Needs testing on a real Roku:** Find servers (the debug log `telnet <roku-ip> 8085` prints `[siku-lan] mdns step` and `discovery complete` lines), whether repackaged titles play with sound (`[siku-playback]` shows `tscopy=true` and `seg=mpegts`), playback recovery (`recovery <n>` lines), the screen reader, and low-memory behaviour.

## v0.1.23

Brings Siku up to date with Silo's Android app as of October 26, 2026.

**New**
- **Control Siku from your phone.** In Silo's app on your phone, tap the cast button and pick this Roku, or scan the code in Siku under **Profile › Connect a Phone**. You can start a title, pause, seek, change audio and subtitles, or mute, and the phone shows what's playing. If the phone uses another profile, Siku plays as that profile and switches back afterwards. Remote Control can be turned off in Connect a Phone; by default only a phone that scanned the code can connect.
- **Sign Siku in from your phone.** While Siku shows its server or sign-in screen, Silo's phone app offers to set up this Roku. Allow it on the TV and confirm the code on the phone.
- **Seek previews.** While you move along the seek bar, a picture of that moment appears above it (when your server has made previews for the video).
- **Fast-scan with a preview.** Hold Left or Right while watching to scan faster and faster with a preview; tap Left/Right to change speed, OK to jump there, Back to cancel. A quick tap still skips as before.

**Changed**
- Audio and subtitle choices you make in the player or on a title's page now apply to the whole series (or the movie) and to your profile's other devices. Choosing Auto on the title page goes back to your profile's defaults.
- Subtitle appearance and the subtitle delay now follow your profile to every device. Turn on **Only on This Device** to keep a separate style and delay on this Roku.
- With subtitles Off and "Show Forced Subtitles" on, forced subtitles for foreign-language dialogue still appear.
- The **Trailer** button has a film-strip icon, so it no longer looks like the Version button.

**Fixed**
- Changing quality no longer leaves you on the old file when the server switches to another version of the title. If that version doesn't have your subtitles, they turn off for now and the next episode picks them again.

**Needs testing on a real Roku:** phone discovery and remote control (the debug log `telnet <roku-ip> 8085` prints `[siku-lan]`, `[siku-cast]` and `[siku-pair]` lines), seek previews (`[siku-trickplay]`), and holding Left/Right to scan.

## v0.1.22

- **New:** a **Trailer** button next to Play on movies and shows that have a trailer. It plays the server's own trailer, or opens the YouTube trailer when there isn't one. Other extras (featurettes, deleted scenes) stay in the Trailers & More row further down the page.

## v0.1.21

Brings Siku up to date with Silo's Android TV app as of October 24, 2026.

**New**
- **Trailers & More** on movie and show pages: the server's own trailers, featurettes and deleted scenes play right away. YouTube trailers open in the YouTube channel; if your Roku can't open it, Siku shows the link and a QR code to watch on your phone.
- **Who's watching?** Siku can ask for a profile when it starts: Settings › General › Profile Selection (Automatic, Every Time, After 1 Hour, After 12 Hours). A new Roku asks every time and offers to remember the first profile you pick.
- **Spoilers** settings (Settings › Playback): hide the pictures and descriptions of episodes you haven't started.
- **Theme music** on movie and show pages, if you turn it on (Settings › General › Theme Music, with Loop). It plays at your TV's volume and stops when a video starts.
- **Up Next** now shows the next episode's picture and an **On Deck** row of other things you're watching.
- **Lower quality when buffering** (Settings › Playback): when a video keeps buffering, Siku can lower the quality by itself, ask first, or never; you can restore it, and Settings shows and resets any speed limit it learned. Settings can also test your connection speed.
- Descriptions translated by AI are marked "Translated by AI".

**Changed**
- Playback settings have **Resolution** and **Maximum Bitrate** instead of one Quality list. "Original" is gone, because Auto already plays the original file whenever it can.
- The player's Quality menu lists Auto first, shows each quality's bitrate, and ticks the quality that's actually playing.
- Libraries you hid in the server's web settings no longer appear in Siku.
- Library browsing remembers your sort and filters for each library and profile ("Preserve sort & filters" in the Filter panel turns it off).
- Approving and declining requests now happens only in the server's web admin; the Requests tab shows your own requests.
- Next Up cards say "Remove from Next Up", and removing one clears that whole show from your rows.
- Episode cards read "S01E02 · Title" with the air date and runtime underneath.
- Titles without artwork show a soft Siku-coloured glow with a film, TV or headphones mark instead of a blank tile.
- Artwork is requested at the size Siku draws it, on servers that support it, so posters and backdrops look sharper.
- The sign-in code is shown in large, easy-to-read digits.
- AI subtitles say whether they are a translation or a transcription. On servers without AI translation, the AI dialog makes subtitles in the spoken language instead of failing.
- Automatically chosen subtitles prefer a track inside the video over an external file, and the subtitle menu says where each track comes from.

**Fixed**
- If an administrator ends what you are watching, Siku stops playback and tells you, instead of carrying on.
- If an administrator changes your access, Siku returns to "Who's watching?" so you can pick your profile again, instead of every screen failing to load.
- An empty library says "This library is empty" instead of "No titles match".
- In a library that mixes movies and series, the Movies and Series views recommend only that type and no longer offer a Shuffle that mixes them.
- Skip Intro and Skip Credits use the markers of the version you are actually watching.

**Needs testing on a real Roku:** the YouTube hand-off, theme music sound, lowering quality when buffering, the speed test, and subtitles inside converted streams. The debug log (`telnet <roku-ip> 8085`) prints `[siku-trailer]`, `[siku-theme]` and `[siku-playback]` lines for each.

## v0.1.20

- **Changed:** the Progressive Remux experiment is marked as failing on the Streaming Stick 4K
  (tested); it stays available, off by default, for anyone testing another Roku model.
- **For troubleshooting:** when the Roku's player reports an error, the error code and message
  are now also written to the debug log as `[siku-playback] video error …`.

## v0.1.19

- **New (experiment):** Settings › Playback › **Experimental: Progressive Remux**. Offers the
  Silo server a second way to keep the original video and convert only the audio: one MP4 stream
  over plain HTTP instead of HLS. Roku may not play it; turn it off if videos stop starting.
- **New (diagnostic):** a hidden stream-test screen. Launch it with
  `curl -d '' "http://<roku-ip>:8060/launch/dev?debugScreen=StreamTestScreen"`. It plays
  Apple's public HLS samples (HEVC and H.264 fragmented MP4 with separate audio, and MPEG-TS),
  the last stream Siku played from your server, or a URL given as `&debugUrl=...`, and reports
  the Roku's player state and the audio tracks it finds (also printed as `[siku-streamtest]`).

## v0.1.18

- **Changed:** when Force Dolby Audio Passthrough makes the server send a Dolby track your TV
  did not ask for, the player says so once, so silence is understood as the TV refusing Dolby
  rather than a Siku fault.

## v0.1.17

- **Fixed:** choosing a non-default audio track on the details page no longer forces the server
  to repackage or convert the file. Siku now tells the server it can switch tracks inside a
  directly played file (Roku can, for MKV and MP4), so the file direct-plays and the chosen track
  is selected on the Roku.
- **For troubleshooting:** the debug line shows the requested audio and subtitle tracks and the
  server's selection (`audio_req=`, `sub_req=`, `sel_audio=`, `sub_mode=`).

## v0.1.16

- **Fixed:** after switching the audio track during playback, the Audio menu kept showing the old
  track name. It now shows the new track (with "Applying…" while the server switches over).
- **Changed:** when the Roku's audio output is set to 5.1 surround, Dolby Digital is treated as
  playable even if the Roku's own check says otherwise. Jellyfin's Roku app does the same because
  some receivers report it wrongly.

## v0.1.15

- **New:** Settings › Playback › **Force Dolby Audio Passthrough**. Some TVs do not tell the Roku
  that they accept Dolby Digital / Digital Plus, so the Roku reports "stereo only" and the server
  converts every Dolby track to AAC. This switch tells the server the Roku can take Dolby, so the
  original track is sent untouched. A Roku app cannot change the HDMI audio output itself: if you
  get no sound with it on, turn it off. The debug line now shows `forcedolby=` and `forcehdr=`.

## v0.1.14

- **Fixed:** silent video. When the Silo server repackages a file as a stream ("remux"), Roku
  plays the picture but not the sound: Roku's HLS player does not accept audio mixed into
  fragmented-MP4 segments, which is how Silo packages remuxes. Siku now tells the server to use
  that route only for H.264 conversions (which Silo packages as MPEG-TS, with sound) and keeps
  HEVC, 4K and Dolby Vision for direct play. If a remux still arrives, Siku asks the server once
  for another route, and says so if none exists. The full fix needs a change in the Silo server;
  the request is written up in `docs/upstream/silo-server-roku-hls-audio.md`.
- **Fixed:** Dolby Vision profile 8 files can now direct-play as HDR10 when the TV or receiver
  does not take Dolby Vision, instead of being repackaged.
- **New:** the Audio menu lists the file's audio tracks from the server when the stream only
  carries one, and switching asks the server for that track. Image-based or styled subtitle
  tracks (PGS, VobSub, ASS) are listed with a note that Roku cannot show them.
- **Fixed:** the Roku's audio and HDR abilities are checked again at every playback start, so
  turning a soundbar or receiver on or off, or changing the Roku's HDMI audio mode, takes effect
  on the next video.
- **Fixed:** an error printed in the debug log while listing the display's properties.

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
