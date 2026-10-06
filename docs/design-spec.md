# Silo Android TV to Roku SceneGraph: design spec

Source root (I call it `ROOT` below): `<upstream>/silo-android`
TV UI code: `ROOT/androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/ui/` (I call it `UI/` below).

## 0. Unit conversion: read this first

- **Geometry.** The Android TV layout canvas is 960×540 dp. At 1080p, **1 dp = 2 px**. The code says so throughout ("tvOS 1920x1080 pt mapped at 0.5x").
- **Text is smaller than 2 px per sp.** `SiloTvTheme` applies `TvUiFontScale = 0.86f` to text only (`UI/theme/Theme.kt`). So **1 sp = 2 × 0.86 = 1.72 px** at 1080p.
  - Example: a 15 sp tab label is about 26 px, which matches the tvOS 26 pt token.
  - Example: the 44 sp marquee title is about 76 px.
- **The design is a port of the Apple tvOS app ("Skyline").** Many comments give the original tvOS point value. At 1920×1080 those points equal Roku pixels 1:1, so you can often use the tvOS number directly.
- **Reference screenshots at 1920×1080:** `ROOT/ui-validation/*.png` (home, For You, top menu, focus check, and others). They are slightly older than the code.
  - Search used to sit at the right; the code now puts it left of Home.
  - The For You dropdown order has since changed.

---

## 1. Theme

### 1.1 Colors (`UI/theme/Color.kt`): a monochrome, OLED-dark, tvOS-style palette

There is no chromatic accent. Every "accent" is white at some opacity.

| Token | Value | Use |
|---|---|---|
| DarkBackground | `#000000` | app/page background, settings background |
| DarkSurface | `#0A0A0A` | surface (player HUD card at 96% alpha) |
| DarkSurfaceVariant | `#0E0F12` | |
| DarkSurfaceElevated | `#15171C` | skeleton placeholders, elevated cards |
| SiloPrimary / SiloOnSurface (text primary) | `#EDEDED` | primary text; also the **focused fill** |
| SiloSecondaryText | `#EDEDED` @ 75% | secondary text, synopsis, metadata |
| Focused container / content | `#EDEDED` fill with `#000000` text/icon | the universal "inverted" focus state |
| SelectedContainer | white @ 12% | |
| ChromeSelectedFill / Border | white @ 14% / white @ 10% | selected-but-unfocused top tab capsule |
| SubtleSurface / GlassFill | white @ 8% | |
| DarkOutline / OutlineVariant | white @ 12% / 8% | |
| Focus glow (SiloBlueGlow) | white @ 28% | card focus glow, 12 dp elevation |
| SiloBlueBorderIdle | white @ 16% | |
| ProgressTrack / ProgressFill | white @ 20% / `#EDEDED` | resume bars (3 dp tall, i.e. 6 px) |
| CardShadow | black @ 55% | |
| Hero scrims | `#00000000` → black 40% → 75% → 95% | |
| ErrorRed | `#B00020` | Material error |
| SuccessGreen | `#34C759` | |
| Inactive tab text | `#EDEDED` @ 62% | |
| Offline pill | `#3A1F22` @ 94% | text "Offline mode - select to retry" |
| Panel chrome gradient (dropdowns) | `#23252C` @ 92% → `#141519` @ 95% (vertical), hairline white 22% → 5% | `UI/components/TvSkylinePanelChrome.kt`; corner 11 dp, shadows 4 dp / 20 dp black 35% / 55% |
| Settings pane header tile | `#3A3A3C` | |

**First-run / "marquee" colors** (`ROOT/android-shared/src/androidMain/kotlin/org/siloserver/silo/common/ui/marquee/MarqueeBackdrop.kt`, `object MarqueeColors`):

- Brand colors: BrandBlue `#0034FB`, BrandRed `#F50B4F`, BrandOrange `#FD7403`.
- Ink: Ink `#EDEDED`, InkSecondary Ink @ 62%, InkTertiary Ink @ 40%.
- Status: Error `#FF6961`, Live `#30D158`, Warning `#F4C869`.
- Surfaces: Hairline white @ 14%, Separator white @ 8%, GlassFill white @ 8%.

**Legacy XML colors** (`ROOT/androidTvApp/src/androidMain/res/values/colors.xml`):

- `dark_background #141417` is the pre-Compose window background.
- `silo_icon_background #010D9F` is the launcher icon background.
- The splash itself draws on pure `#000000`.
- The `silo_blue*` values are unused legacy.

### 1.2 Fonts (all in `ROOT/androidTvApp/src/androidMain/res/font/`)

- `inter_regular.otf` (400), `inter_medium.otf` (500), `inter_semibold.otf` (600), `inter_bold.otf` (700), `inter_black.otf` (900). These form the `InterFamily` used everywhere. License: `res/raw/inter_license.txt`.
- `inter_tight_black.ttf` is used only for the detail-page hero title.
- `outfit_semibold.ttf` and `outfit_extrabold.ttf` are shipped but unused. `OutfitFamily` is aliased to Inter.
- A monospace family is used for code tiles, the filter-count badge and group headers.

### 1.3 Type scale (`UI/theme/Type.kt`)

Letter spacing is 0 unless noted. Pixel values use 1 sp = 1.72 px.

| Style | Weight | sp / line height | ≈ px at 1080p |
|---|---|---|---|
| displayLarge | Black | 44 / 48 | 76 |
| displayMedium | Black | 36 / 40 | 62 |
| displaySmall | Black | 28 / 32 | 48 |
| headlineLarge / Medium / Small | SemiBold | 28 / 24 / 22 | 48 / 41 / 38 |
| titleLarge / Medium / Small | SemiBold | 22 / 20 / 18 | 38 / 34 / 31 |
| bodyLarge / Medium / Small | Regular | 20 / 18 / 16 (line height 28 / 24 / 22) | 34 / 31 / 27.5 |
| labelLarge / Medium / Small | SemiBold / SemiBold / Medium | 18 / 16 / 16 | 31 / 27.5 / 27.5 |
| heroDisplay (home fallback title) | Black | 58 / 64 | 100 |
| navRailLabel | SemiBold | 18 (tabs override to 15) | 26 |
| capsuleCaps | Black | 16, tracking 1.6 | 27.5 |

**Per-component sizes in actual use:**

- **Card captions:**
  - Title: 15.5 sp SemiBold (about 27 px), white 78%, white 100% when focused.
  - Year / second line: 14 sp (about 24 px), white 70–75%.
- **Section (row) header:** 18 sp SemiBold white (about 31 px). Optional leading icon 18 dp; 22 dp on progress rows.
- **Home marquee:**
  - Title fallback: 44 sp Black (about 76 px).
  - Meta: 14 sp Medium.
  - Synopsis: 16 sp with line height ×1.35.
  - Detail line: 14 sp at 70%.
  - Badges: 10.5 sp SemiBold, tracking 0.55.
- **Detail hero title:** Inter Tight Black, 42 sp / 46 sp (about 72 px), shadow black 55% with y 4 and blur 16.
- **Top-bar tabs:** 15 sp. SemiBold when selected or focused, Medium otherwise.

### 1.4 Corner radii

| Element | Radius |
|---|---|
| Material shapes | extraSmall 8, small 12, medium 12, large 18, extraLarge 28 dp |
| Poster / episode cards | 8 dp (16 px) |
| Squared controls (`TvControlCorner`) | 4 dp |
| Settings rows | 7 dp |
| Dropdown panels | 11 dp |
| Cascade rows | 7 dp |
| Profile dropdown rows | 8 dp |
| Player HUD | 16 dp |
| Marquee card | 20 dp |
| Marquee text field | 8 dp |
| Capsules (tabs, pills, chips, filter pills) | fully round (50% / 999 dp) |

### 1.5 Focus treatment (`UI/theme/FocusModifier.kt`)

- **Cards** (`siloCardDefaults`): scale **1.10**, border **2 dp `#EDEDED`**, glow white @ 28% at 12 dp elevation.
- **Generic focusables** (`siloFocus`): scale 1.06, 2 dp white border, 6 dp corners, 14 dp black-55% shadow, spring damping 0.72 / stiffness 380.
- **Tabs, menu rows, pills and settings rows:** no scale. They **invert to a solid `#EDEDED` fill with black text**. This is the dominant focus idiom.
- **Hero primary pill (Play):**
  - At rest: fill white @ 76% with black text.
  - Focused: solid white with an outward 1.25 dp white ring 1.5 dp outside the pill, plus a glow.
- **Circular action buttons** (`TvSquareToggleButton`, 38–40 dp):
  - At rest: white @ 10% fill with a white @ 34% 1.4 dp border.
  - Focused: white fill. The button widens into a capsule that shows a 13 sp label ("Watchlist", "More", "Start Over").
- **Profile avatar tiles:** scale 1.12, 3 dp Ink ring drawn 6 dp outside the circle, 18 dp shadow.
- **Episode rail cards:** 3 dp white @ 90% border when focused; the current episode gets a 2 dp white @ 70% ring.
- **Rail scrolling:** the focused card is pinned to the row's start padding (Netflix/tvOS style), with 100 ms FastOutSlowIn steps. Vertical scroll is ease-in-out at 620 ms.

### 1.6 Spacing and safe area (`UI/theme/Spacing.kt`, `TvSkyline`)

- **Scale:** xs 4, sm 8, md 12, lg 18, xl 24, xxl 30, xxxl 40 dp.
- **Horizontal safe area:**
  - `Spacing.safeArea` = **40 dp (80 px)**.
  - Skyline chrome uses `TvSkyline.safeAreaX` = **44 dp (88 px)**.
  - The detail page inset is **50 dp (100 px)**.
- **Vertical safe area:** `safeAreaVertical` = 24 dp (48 px).
- **Top bar:** `barTopInset` 28 dp (56 px) and `barHeight` 32 dp (64 px). Root content starts at **`contentTopInset` = 94 dp (188 px)**.
- **Rows:** section spacing 30 dp. Home rail item spacing **20 dp (40 px)**.

---

## 2. Logo, icon and splash assets

> **Legal:** `ROOT/androidTvApp/src/androidMain/res/NOTICE` says the Silo logo, wordmark and icons are trademarks of Silo Media L.L.C. They are **not** covered by the AGPL. A redistributed or forked Silo-branded app needs written permission (see `ROOT/TRADEMARK.md`). Confirm you have the rights before reusing them on Roku.

**All brand art is raster PNG.** The only vector drawables in the project are the TMDB logo and the picture-in-picture icons. The upstream source is `silo-wordmark-white.svg`, generated by silo-branding's `derive.py`; it is not in this repo.

| Asset | Path | Notes |
|---|---|---|
| Wordmark / lockup | `ROOT/androidTvApp/src/androidMain/res/drawable/silo_wordmark.png` | 764×400 RGBA, transparent. Stacked mark on the left (blue play triangle, then blue, red and orange "film" bars) plus **white** "Silo" text. Top bar: 24–26 dp tall (about 50 px), width by aspect ratio 1.91. First-run screens: 75 dp wide. A copy is also in `ROOT/androidApp/.../drawable/`. |
| TV launcher banner | `.../res/drawable/tv_banner.png` | 320×180. Blue gradient with the mark and white "Silo". A good base for the Roku focus/side posters. |
| Launcher icon | `.../res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` | 80 to 320 px square. |
| Adaptive icon foreground | `.../mipmap-*/ic_launcher_foreground.png` | 108 to 432 px. Background colour `#010D9F` (`mipmap-anydpi-v26/ic_launcher.xml`). |
| Generic icon | `ROOT/assets/icon.png` | 256×256 RGBA. |
| Startup splash video | `ROOT/android-shared/src/androidMain/res/raw/startup_splash.mp4` (720p30), `startup_splash_hd.mp4` (1080p60) | Played muted, centered in a **16:9 box, width = min(25% of screen, 220 dp)**, i.e. 440×248 px on pure black. Ends when the video ends or after **4 s**, whichever is first. See `MainTvActivity.kt` around line 180. |
| Splash Lottie | `.../res/raw/startup_splash_lottie.json` | 3840×2160, 60 fps, 240 frames (4 s). Usable for frame extraction. |
| TMDB logo | `ROOT/android-shared/src/androidMain/res/drawable/tmdb_logo.xml` | vector |

**Roku suggestion:**

- Splash: a 1920×1080 black image with the logo centered at about 440 px wide. Or render a frame from the mp4.
- Channel posters: derive them from `tv_banner.png`.

---

## 3. Navigation shell: the top bar

Code: `UI/shell/TvTopMenuBar.kt`, `TvMainShell.kt`, `TvMediaDestinations.kt`, `TvLibraryTabType.kt`, `TvLibraryPill.kt`, `UI/components/TvCascadeSelector.kt`.

### 3.1 Layout (1080p px)

- **Bar row:** full width, `top = 56 px`, height 64 px. All items are vertically centered in it.
- **Leading:** `silo_wordmark.png` at x = 88 px, about 52 px tall.
- **Center cluster** (centered on screen, 8 px gaps): **[Search icon] · Home · Movies · Series · Music · Audiobooks · For You · Calendar · Requests**, then an invisible 56 px spacer the size of the search button so the tabs stay centered.
  - A library-type tab appears only if the profile can see a library of that type.
  - Audiobooks is opt-in in Settings and hidden by default.
  - Requests appears only when the server enables it.
  - Order rule: Home, library types in the fixed order Movies, Series, Music, Audiobooks, then For You, Calendar, Requests.
- **Trailing:** profile avatar circle, 56 px, at right inset 88 px.

**Tab capsule:**

- Height 60 px, horizontal padding 29 px, text 15 sp (about 26 px).
- **Focused:** solid `#EDEDED` capsule with black text.
- **Selected, not focused:** white @ 14% fill, 1 dp white @ 10% border, `#EDEDED` text.
- **Resting:** no fill, text `#EDEDED` @ 62%.
- No scale on focus.

**Search button:** a 56 px circle with a 38 px outlined magnifier. Focused: white circle with a black glyph. At rest: glyph at 62%.

**Avatar:**

- Image or initials (14 sp Bold) on white @ 18%.
- 1 dp white @ 18% ring at rest; **2 dp `#EDEDED` ring when focused**.

**Dimming:**

- The whole bar sits at **70% opacity while focus is in the content area** and returns to 100% when the bar is focused (200 ms).
- The bar can also slide up and fade out on scroll.

### 3.2 Behavior

**Up from the top content row** moves focus to the **currently selected tab**, not the geometrically nearest item.

**Left / Right** move along the whole bar: search, tabs, avatar.

**Dwell (resting focus on a tab):**

- On a library-type tab or For You for **180 ms** (80 ms if a panel is already open), a dropdown "cascade" panel opens as a preview under the tab.
- Moving to a tab without a panel closes it.
- Dwelling on the avatar opens the profile dropdown.

**Select (OK, acts on key-up):**

- Home / Calendar / Requests / For You: navigates to that page.
- A library-type tab: commits that tab's landing page ("Recommended").
- Search: opens the Search page.

**Down:**

- On a library or For You tab: enters the cascade panel.
- On the avatar: enters the profile menu.
- On Home, Calendar, Requests or Search: moves into content.

**Cascade panel** (top 132 px; column width 460 px; flyout 300 px; max total width 778 px; 22 px left-aligned under the tab and clamped to the safe area):

- **Level 1, libraries:**
  - Header like "MOVIE LIBRARIES": 14 sp Medium, tracking 1.5, at 38% opacity.
  - Rows: 18 px icon plus library name. The current library shows ✓; the others show ›.
- **Level 2, sections flyout** (Right enters it):
  - Movies / Series: **Recommended · Browse · Collections**.
  - Music: Recommended · Browse · Genres.
  - Audiobooks: Recommended · Browse · Authors · Series · Collections · A-Z.
  - A single-library tab skips level 1.
- **Footer hint** (14 sp at 52%): "Press opens the library · → jumps to a section · Menu closes". Single-library variant: "Press opens the section · Menu closes".
- **Focused row:** inverted white capsule.

**For You dropdown:**

- Header "FOR YOU", then rows **Recommendations** (sparkle icon), **Favorites** (heart), **Watchlist** (bookmark).
- Footer "Press opens the section · Menu closes".

**Profile dropdown** (480 px wide, anchored under the avatar, same panel chrome):

- **Header:** 64 px avatar, name (15 sp SemiBold), and an uppercase subtitle "ROLE · SERVER" (13 sp at 38%).
- Divider.
- **Rows:** Switch Profile · Watchlist · Favorites · History · (Watch Party, experimental only).
- Divider.
- **Rows:** Settings · Switch Server · Sign Out.
- Each row has a 32 px icon and 15 sp text. Focused rows invert to a white capsule with 16 px radius.
- Focus is trapped inside the dropdown; only Back closes it.

### 3.3 Back key (`TvShellFocusState.onBack`, `handleShellBack`)

Back is handled in this order:

1. **Panel open:** close it and leave focus on its tab, without re-previewing.
2. **Profile menu open:** close it and focus the avatar.
3. **Focus in content on a root tab:** move focus to the selected tab in the bar. This does not open its cascade.
4. **Bar focused on a tab other than Home:** go to Home with the bar focused.
5. **Bar focused on Home:** exit the app.
6. **Secondary screens** (Search, detail and similar): pop the stack.
   - Search first returns focus to its text field once, then pops.
   - Settings has its own two-stage Back: pane, then rail, then out.

The **Settings** route hides the top bar.

---

## 4. Screens

### 4.0 First-run "marquee" family: server connect, sign-in, profile picker

Code: `UI/components/marquee/TvMarquee.kt`, `MarqueeBackdrop.kt`.

**Background:**

- Animated "brand light": a 3×3 mesh of dimmed brand blue, red and orange over black, slowly drifting (13 s / 19 s sine), drawn from a 48×32 bitmap and upscaled. Grain noise at 4.5%.
- The mesh shifts by stage: server choice is a cool blue pool, sign-in adds all three colors, profiles are warmer and lower.
- A left-weighted black scrim sits on top (horizontal 80% → 55% → 20% → 10% → 30%).
- For Roku, a pre-rendered 1920×1080 gradient image is acceptable.

**Layout (`TvMarqueeScreen`):**

- Padding 90 px horizontal, 60 px vertical.
- **Top row**, 64 px tall: wordmark 150 px wide on the left; on the right an optional status chip, e.g. "📺 <TV name>".
- **Body row**, vertically centered:
  - Left copy column, **900 px** wide.
  - 80 px gap.
  - Right glass card, **640 px** wide: fill `#1F1F1F` @ 72%, 1 dp hairline, 40 px radius, 52 px padding, centered content.

**Text styles:**

- Headline: 44 sp ExtraBold, tracking −1, line height 48.
- Body: 14 sp, Ink @ 62%.
- Errors: 14 sp in `#FF6961`.

**Buttons (`TvMarqueeButton`):**

- Capsule, 76 px tall, 40 px horizontal padding, 14.5 sp SemiBold.
- Variants:
  - Primary and Glass: white @ 8% glass fill with hairline border.
  - Plain: bare text at 62%.
- **Focused (all variants):** solid Ink `#EDEDED` with black text, **scale 1.06**, 12 dp shadow.

**Text field (`TvMarqueeField`):**

- 84 px tall, 16 px radius, 15 sp.
- At rest: white @ 8% fill with a white @ 12% border.
- **Focused:** fills Ink with black text.

**Status chip:** 60 px capsule, glass fill, 14 sp at 62%, optional spinner.

#### 4.0.1 Server connect (`screens/auth/TvServerSetupScreen.kt`)

**Page 1, phone setup (default):**

- Left column:
  - Chip "Looking for a phone or tablet…" with spinner.
  - Headline "Set up with\nyour phone".
  - Body "It's the easiest way. There's nothing to type with the remote."
  - Caption "No phone nearby?".
  - Glass button **"Enter server address"** (initial focus).
- Right column (`TvMarqueeSetupSteps`, 700 px wide), three steps, each with a 168 px rounded tile illustration and a 52 px numbered badge, step titles 19 sp Bold:
  1. "Open Silo on your phone"
  2. "Tap Set up"
  3. "Finish on your phone"

**Page 2, address entry:**

- Headline "Enter your\nserver address".
- Body "Type the address you use for Silo."
- Field, 760 px wide, placeholder "media.example.com", with shortcut chips `https://`, `http://`, `.com`.
- Note: "Secure HTTPS is tried automatically." For http addresses it reads instead: "This address uses unencrypted HTTP. Fine on a trusted home network; avoid it on public Wi-Fi."
- Buttons: **"Connect"** ("Connecting…" while working) and **"Back"** (Plain).
- Right card "Easier with a phone".
- HTTP confirmation dialog: title "Connect without encryption?", buttons Connect / Cancel.

#### 4.0.2 Sign-in (`screens/auth/TvLoginScreen.kt`, strings in `res/values/strings.xml`)

**Default screen, device code / QR (the "Quick Connect" equivalent):**

- Left column:
  - Server card: 80 px mark, name 17 sp Bold, address 14 sp, and a "SECURE" or "HTTP" pill.
  - Headline **"Sign in to %s"**.
  - Body: "Scan the code with your phone's camera, or go to <host>/activate and enter it. Approve on your phone and this TV signs in by itself."
  - Hint: "Have Silo on your phone? Open it on the same Wi‑Fi to sign in this TV."
  - One action row:
    - [Try again / Show a new code], only when needed.
    - **"Sign in with a password"** (Glass).
    - **"Change server"** (Plain).
- Right card:
  - **QR code**: 340 px, dark on a white rounded tile, 20 px quiet padding.
  - **Code tiles**: per character up to 84 px wide × 1.24 tall, monospace Bold, glass tiles with 16 px radius.
  - Status line with spinner: "Getting a sign-in code…", "Waiting for approval", "Continue on your phone", "Signed in as %s", and so on.
- There is no countdown; the code renews in place.

**Optional network sign-in** (for example Tailscale): a primary "Continue as %s" with "via %s" beneath, then "Or sign in with your phone".

**Password form:**

- Headline "Sign in with\na password".
- Body "Use your <server> username and password."
- Fields: placeholders "Username" and "Password", 760 px wide, with an eye toggle (Show / Hide password).
- Primary **"Sign in"** ("Signing in…" while working).
- Plain buttons: "Create Account" (if signup is enabled), **"Use your phone instead"**, "Change server".
- The form is top-anchored so the on-screen keyboard does not cover it.
- Errors: "Username is required", "Password is required", "Invalid username or password", etc. (`strings.xml`).

#### 4.0.3 Profile picker (`screens/profiles/TvProfileSelectionScreen.kt`)

- **Header**, centered on the brand light (warm stage):
  - **"Who's watching?"** 32 sp Bold, tracking −0.8.
  - "Signed in as %s", 14 sp.
  - 72 px gap below.
- **Grid**, centered, up to **6 columns**:
  - Avatar circle 220 px; column width 256 px; column gap 28 px; row gap 60 px.
  - Name below the avatar: 15 sp SemiBold, Ink when focused, 62% otherwise.
  - Focused tile: scale 1.12, ring, and the name drops to a 44 px offset.
  - Last tile is "Add profile": a dashed circle with a plus.
- **Bottom buttons** (Glass): "Manage" / "Done", "Change server", "Sign out".
- **Manage mode:** avatars at 60% with a pencil overlay; a "Delete" button under each non-primary profile.
- **PIN dialog** (`components/TvPinEntryDialog.kt`): "Enter your PIN" ("Checking…" while verifying), a 3×4 keypad (1–9, 0, backspace), and "Cancel".

### 4.1 Home: the "Skyline" layout

Code: `screens/home/TvHomeScreen.kt`, `components/TvSkylineSectionFeed.kt`, `TvRootHeroBackdrop.kt`, `TvFocusMarquee.kt`, `TvMediaRow.kt`, `TvMediaCard.kt`, `TvEpisodeCard.kt`.

The page is not a scrolling stack of a static hero and rows. It has three layers, all keyed to the **focused card**.

**1. Ambient backdrop (full screen)**

- The focused item's backdrop is anchored **top-right at 64% width × 70% height** (about 1229×756 px). It is crisp, not blurred.
- Two masks fade it out:
  - Horizontal: transparent at 0, opaque from 0.68.
  - Vertical: opaque to 0.58, transparent at 1.0.
- Under it, a diagonal wash from top-right to bottom-left uses the image's **average color, clamped to luminance 0.22**, at alpha stops 1.0 → 0.5 → 0.18.
- Crossfade 500 ms, cubic-bezier(0.42, 0, 0.58, 1). The first frame snaps in without fading.

**2. Focus marquee (non-focusable)**

- Bottom-left anchored at x = 88 px, sitting just above the row band, max width 880 px.
- Contents, top to bottom:
  - **Title logo** (max 880×168 px), or the title text at 44 sp Black, up to 2 lines.
  - **Badges + meta line:** outlined badges (white 8% fill, 0.5 dp white 24% border, 6 px radius), e.g. "4K", "HDR", "EAC3", "TV‑MA". Then a dot-joined meta line in 14 sp at 75%, e.g. "2025 · Science Fiction · 1h 59m", or "S2 E8 · Exodus · 52 min · 18m left".
  - **Synopsis:** 16 sp at 75%, 2 lines (1 line if the title wraps), max width 780 px.
  - **Detail line:** 14 sp at 70%, e.g. "Aired Mar 30, 2026 · Cast…".
  - Optional spec badges.
- Spacing 12 px between elements.
- Updates after the focus rests for about 150 ms, with a 500 ms crossfade.
- On Home, the marquee and row band are shifted down 56 px.

**3. Row band (bottom)**

- Height is derived from the cards: about **540 px**, capped at 58% of the screen.
- Vertically scrolling list of rows, 28 px apart, with a 48 px peek of the next row's header.
- Each row:
  - Header: optional icon (▶ circle on progress rows) and title, 18 sp SemiBold white.
  - 24 px gap.
  - Horizontal rail: start padding 88 px, end padding 80 px, **40 px between cards**, 14 px above and below.

**Rows** come from the server, in server order, filtered by the user's "Home Sections" setting. Typical rows:

- **Continue Watching** and **Next Up**:
  - Backdrop style, using `TvEpisodeCard`, **16:9 at 180×101 dp (360×203 px)**, scaled by the poster-size preference.
  - Bottom gradient to black 60%.
  - Progress bar 6 px, white on white @ 20%.
  - Optional "S2 · E8" overlay chip.
  - Caption: line 1 is the series title (15.5 sp); line 2 is "S02E08 • Episode title" (14 sp at 75%).
  - Audiobook items are split out into a separate "Continue Listening" poster row.
- **All other rows** (Recently Added, genres, For You, …):
  - **Dense poster**, 2:3 at **88×132 dp (176×264 px)**.
  - Caption: title 15.5 sp, then year 14 sp. A 22 px gap separates the poster from the title.
- **Poster-size preference:** Compact ×0.86, Standard ×1, Large ×1.2.

**Card badges and states:**

- **Watched badge:** white circle with a black check, at the top-right. Size is 24% of the card width, clamped to 20–32 dp; inset 6% of the width.
- **Long-press menu** (`TvMediaCardActions.kt`): "Play" / "Resume", "Mark as Watched" / "Mark as Unwatched", "Add to Favorites" / "Remove from Favorites", "Add to Watchlist" / "Remove from Watchlist", "Remove from Continue Watching".

**Select:**

- Continue Watching resumes directly to the item's detail page (episodes open the series page with that season and episode selected).
- Other cards open their detail page.
- "See all" (18 sp at 75%, with a chevron) appears only on the For You row.

**Empty state:** "Nothing to watch yet" / "Add media to your libraries or start watching to see it here." / button "Refresh".

**Library tab landing ("Recommended")** uses the same Skyline feed, scoped to the chosen library.

### 4.2 Library grid ("Browse"), Collections, and personal lists

Code: `screens/library/TvLibraryDetailScreen.kt`, `TvLibraryBrowseControls.kt`.

**Grid:**

- **6 fixed columns** (Compact 7, Large 5, never fewer than 3).
- Column gap 40 px; row gap 60 px.
- Padding: start 80 px, end 24 px, top **216 px** when the controls row is shown (188 px otherwise), bottom 80 px.
- Cells are `TvMediaCard` posters, 2:3, about 135 dp (about 270×405 px), with title and year captions.
- Paging loads more within 6 items of the end. If paging fails, a retry footer appears.

**Controls row** (first full-width item; pill capsules 14 sp Medium, 28 px horizontal padding, 14 px vertical padding):

- **"Sort · <Title|Date Added|Release Date|Year|Rating|Runtime|Resolution…>"** with a direction label.
- **"Filter"** with a monospace count badge.
- "Clear filters" (shown when filters are active).
- "Shuffle".
- Pill states:
  - At rest: white @ 8%.
  - Active: white @ 22%.
  - Focused: white @ 94% with black text, scale 1.04.

**Sort panel:** header "SORT BY".

**Filter panel:**

- Headers "FILTER BY" / "FILTER". Match "All selected filters" / "Any selected filter". Options "Reset filters", "Done".
- Facets: Genre, Decade, Watch Status (Unwatched / In Progress / Watched / Favorited / Watchlist), Content Rating, Resolution, Dynamic Range (HDR / Dolby Vision), Studio, Network, Country, Audio Language, Subtitle Language, Original Language. Audiobooks add Author, Narrator, Series.

**Alphabet rail** (`components/TvAlphabetRail.kt`, used for A‑Z):

- Right edge, 36 px collapsed, 192 px expanded.
- Entries "All", "#", A–Z.

**Personal lists** (`screens/personal/TvPersonalScreens.kt`):

- Same 6-column grid.
- Titles "Favorites", "Watchlist", "Watch History".
- Empty states: "No favorites yet", "Your watchlist is empty", "No watch history yet".

### 4.3 Movie / Series / Episode detail

Code: `screens/detail/TvItemDetailScreen.kt`, `TvDetailHero.kt`, `components/TvSquaredButtons.kt`.

The page background is opaque: the sampled tint at 42% over black (default `rgb(0.04, 0.12, 0.14)`). The page scrolls vertically.

**Hero (height = 690/1080 of the screen, i.e. 690 px)**

- **Backdrop:** top-right, 64% of width × (width × 9/16 × 0.70).
  - Horizontal mask: transparent → opaque at 0.68.
  - Vertical mask: opaque to 0.38, then 0.88 / 0.58 / 0.24, transparent at 0.90.
- **Editorial column:** top-left at x = 100 px, y = 116 px, max width 1080 px, 18 px spacing between blocks.
  - Logo image (max 650×160 px), or the title in Inter Tight Black 42 sp (about 72 px) with a shadow.
  - Series pages: series title plus an episode title line (20 sp, tracking 0.75).
  - Metadata row: source tokens joined with "·" (14 sp, white 92%) plus an outlined rating chip (0.75 dp white 70% border, 2.5 dp radius).
  - Tagline.
  - Overview: 3 lines, expandable.
  - Facts line: e.g. "Starring …", director (14 sp at 88%).
- **Action row** (18 px gaps; focus entering the row always lands on Play):
  1. **Primary pill** "Play", or "Resume 1:23:45". Series: "Play S2:E3" / "Resume S2:E3"; season pages: "Play E4". Height 76 px, 54 px horizontal padding, play glyph. Fixed 340 px wide on series pages.
  2. **Start Over** (⏮), a circle shown only when a resume point exists.
  3. **Version / Audio / Subtitles selectors.** Circles that widen on focus. The menus have headers "VERSION", "AUDIO", "SUBTITLES", entries "Auto", "Off", "Start without subtitles", "Use your subtitle preferences", and so on.
  4. **Watchlist** (bookmark, filled when active), label "Watchlist".
  5. **More** (⋯). Opens the "More Actions" dialog:
     - Shuffle Series / Shuffle Season N.
     - Add to / Remove from Favorites.
     - Mark Movie / Series / Episode Watched (or Unwatched).
     - Mark Season N Watched.
     - Go to Season N, Go to Series.

**Body sections** (top to bottom, 64 px gaps, page bottom padding 140 px):

1. **Series only, "Episodes":**
   - **Season row**: capsule chips, 52 px tall, 24 px horizontal padding, 14 sp. A "Show" chip first, then "Specials" / "Season 1" …. Selected chip: white fill with black text. Focused: translucent fill.
   - **Episode rail**: 16:9 stills, 360 px wide, 40 px gaps, with a progress bar (10 px) and a watched check.
   - Episode card text: eyebrow "S1 · E1" (11 sp), title 18 sp, a 14 sp meta line, and a 3-line synopsis at 16 sp.
   - The current episode has a ring and is centered.
   - OK on a card plays that episode on the series page (combined Series page). On season/episode pages it opens the episode.
   - Messages: "Loading episodes…", "Press again to retry", "No episodes available".
2. **"Cast & Crew"**: circles of 200 px, 44 px gaps. Name 14 sp, role 14 sp at a lower alpha. Select opens the person page.
3. **"Trailers & More"**: YouTube thumbnails.
4. **"Related Movies"** (movies) or **"Recommended Series"** (series): a poster rail.
5. **"Details"**: a focusable facts table. Focused: white @ 6% fill with 36 px radius.
   - Facts: Director, Writer / Written by, Studio, Network, Country, Genres, Released / Aired / First Aired / Last Aired.

**Episode detail** uses the same template in its compact-series form: the hero shows series and episode titles, and the rail shows the season with the current episode ringed.

**Audiobooks** add "Parts", "Chapters", "Alternate Narrations", "More by Author", "Related".

### 4.4 Person detail (`screens/people/TvPersonDetailScreen.kt`)

- **Header row** (48 px gap):
  - Portrait 300 px wide, 12 px radius.
  - Name 36 sp Bold.
  - Badges (born, died, birthplace) as 999-radius pills, 14 sp.
  - Biography: 15 sp / 20, clamped to 7 lines, max 1060 px, focusable. OK opens a full-bio modal (36 px radius).
  - If empty: "No biography or personal details are available yet."
- **"Filmography"** heading (18 sp), then filter chips **All / Movies / Series**.
- **Poster grid:** 6 columns, top 48 px, bottom 72 px.
- Empty state: "No titles found."

### 4.5 Search (`screens/search/TvSearchScreen.kt`)

**There is no custom on-screen keyboard.** The app uses the stock Android IME. On Roku, use a `KeyboardDialog` or a `Keyboard` node.

**Layout**, pinned at the top, y = 164 px, left at the safe area:

- **Text field:** 1040×104 px, 28 px radius, leading 40 px search icon.
  - Placeholder: "Search movies and series" (built as "Search <media names>").
  - Unfocused: fill white @ 5.5%, border white @ 12%.
  - Focused: fill `#15171C` @ 80%, border white @ 94%.
- OK opens the keyboard; the IME's Search action submits.

**Filter chips** below (24 px gap): **All · Movies · Series · (Audiobooks)**.

- Capsule, 40 px horizontal and 20 px vertical padding.
- Selected: white fill with black text.
- At rest: transparent with a white @ 12% border.
- Focused: white.

**Results:**

- Optional "People" row: 200 px circular portraits.
- Poster grid: adaptive cells, minimum 264 px, horizontal gap 28 px, vertical gap 40 px.
- Status line: "Searching…" / "About N results" / "No results".
- Optional "Available to request" row.

**Empty / error states:**

- "Search your library" / "Find … in one place."
- "No matches for “q”" / "Try a shorter title or a different filter."
- "Search is unavailable" with "Try again".

**Back** closes the keyboard first, then moves focus to the field, then leaves the page.

### 4.6 For You (`screens/recommendations/TvRecommendationsScreen.kt`)

- Same Skyline feed as Home (backdrop, marquee, row band) driven by `/recommendations/discover`.
- The Watchlist and Favorites variants are chosen from the top-bar dropdown and render as 6-column grids embedded in the page.
- Empty state: "Not enough data yet" / "Watch and rate more content to unlock personalized recommendations." / button "Check again".
- Fallback caption: "No recommendations yet — showing your saved titles."

### 4.7 Calendar (`screens/calendar/TvCalendarScreen.kt`)

- **Segmented capsule:** **Following | Trending | All** in one container; the selected segment is filled.
- **Week strip:**
  - ‹ and › chevrons ("Previous week" / "Next week").
  - 7 day cells: weekday "EEE", day number, and an event dot.
  - A **"Today"** jump button.
  - A trailing month label, e.g. "June 2026".
  - Selecting a day scrolls to that day's shelf.
- **Day shelves**, vertical:
  - Heading: "Today" or "Monday, June 9".
  - A horizontal row of posters at **248×372 px**, 36 px gaps.
  - Poster badges: "PREMIERE", "NEW SEASON", "FINALE"; watched check.
  - Caption: "S5 · E14 · Title" or "Movie".
  - Empty days show "Nothing scheduled".
- **Empty week:**
  - Titles: "Nothing from shows you follow" / "Nothing trending this week" / "Nothing scheduled this week".
  - Links to the other two filters.
- **Error:** "Press the week arrows to try another week." with a "Refresh" button.

### 4.8 Requests tab (`screens/requests/TvRequestsPage.kt`)

- Skyline layout.
- Rows: "Waiting for your approval" (admins), "Your requests", "Failed requests", then "Discover" carousels.
- The marquee shows status, a stage track, and "Requested <date>".
- Long-press actions: "Cancel Request", "Approve", "Decline", "Retry".
- Empty state: "Nothing here yet" / "Use Search to find a movie or series to request".

### 4.9 Settings (`screens/settings/TvSettingsScreen.kt`)

- Full screen, no top bar, black background.
- Padding: start and end 88 px, top 80 px, bottom 80 px.

**Left rail, 490 px:**

- Title **"Settings"** (24 sp Black).
- Account row.
- Categories, 100 px rows, each with a 34 px icon, a 15 sp title, and a 14 sp description:
  - General: "App and navigation"
  - Playback: "Quality and episodes"
  - Subtitles: "Language and appearance"
  - Diagnostics: "Reports and support" (hidden for kids profiles)
  - Server: "Connection and version"
- Rail row states: selected white @ 14% with a 1 dp white @ 10% border; focused inverts to white.
- Rail footer: "Sign Out" row and "Silo <version>" (14 sp).
- Focusing a category swaps the right pane immediately.

**Right pane** (52 px gap from the rail, rows max 1080 px wide):

- Rows are 76 px tall, 14 px radius, 15 sp text: a label on the left and the value with a chevron on the right. Focused rows invert.
- Groups have a 14 sp uppercase SemiBold header with tracking 1.
- **General:** Home Sections; Cards & Posters (Preset, Poster Size, Captions, Only This Device); Top Menu (Show Audiobooks); Profile; Metadata (Metadata Language); Experimental.
- **Playback:** Streaming (Quality, Audio Language); Episodes (Show Next Up, Skip Intros = Never / Ask to skip / Skip automatically, Rewind on Resume, Still Watching Prompt); Reset.
- **Subtitles:** Behavior, Language, Font Size, Font Family, Font Color, Text Opacity, Outline Color, Background Style, Background Opacity, Background Color, Position.
- **Server:** Active Server; About.

### 4.10 Player (`screens/player/TvPlayerScreen.kt`, `TvPlayerScrubber.kt`, `TvPlayerTransportCluster.kt`, `TvPlayerHud.kt`)

**Clean playback (controls hidden):**

| Key | Action |
|---|---|
| Left / Right | skip back / forward (profile intervals, default 10 s / 30 s) |
| Play/Pause | toggle |
| Down | open the HUD on its Audio or Subtitles tab |
| Menu | open the HUD on its Video tab |
| Any other key (e.g. OK) | reveal the controls |

Skip feedback shows for 1.2 s. Controls **auto-hide after 5 s**; any key re-arms the timer.

**Controls overlay:**

- Bottom gradient, 480 px tall: transparent → black 30% at 0.4 → black 55% at the bottom.
- **Title** at bottom-left (x 160 px, bottom 392 px): titleMedium white with a shadow, plus an episode tag like "S2·E8" at 62%.
- Bottom column: horizontal padding 160 px, bottom padding 80 px, 32 px gap.
  - **Scrubber**: a glass capsule.
    - Track 7 px tall, 12 px while scrubbing.
    - Puck 30 px, 42 px when focused or scrubbing.
    - Played fill in white. Chapter ticks as 2–3 dp white verticals. Intro, credits and recap ranges are marked.
    - Time labels, with remaining time shown as "-1:23:45".
    - Tap Left/Right: ±10 s.
    - Hold Left/Right: auto-seek with a rate ladder; a "2x" chip appears.
    - OK commits. Down moves focus to the transport row.
    - **No thumbnail (trickplay) previews.**
  - **Transport row**, 88 px circles with 40–44 px glyphs, 10 px gaps.
    - Left group: skip-back (shows the interval number), **Play/Pause**, skip-forward.
    - Right group: Up Next (⏭, when available), Subtitles (CC quick picker), **Tune** ("Info and options", opens the HUD), Close (✕).
    - At rest: black @ 35% with a white glyph. Focused: white with a black glyph. No scale.

**HUD (info panel):**

- Floats top-center; width 74% of the screen, max 1440 px; height 312–600 px.
- Fill `#0A0A0A` @ 96%, 32 px radius, 40 px padding, 0.5 dp white 14% border.
- No full-screen dim.
- **Tab pills** above the card (76 px tall, 16 sp): **Info · Stats · Video · Audio · Subtitles · Chapters**. Tabs with no data are hidden.
- **Panes:**
  - **Info:** "Now Playing", title, S·E, stream route.
  - **Video:** Version, Quality, Speed, Aspect (Letterbox / Zoom (crop) / Stretch), Output (HDR passthrough, Dolby Vision), Automation (Auto-play next, Sleep timer).
  - **Audio:** Track, Delay (PCM only), Codec, Output.
  - **Subtitles:** Track, Delay, Timing ("Sync to audio" / "Reset timing"), Size, Font, Text Opacity, Background, Opacity, Outline, Position, "Search subtitles", "Translate with AI".
  - **Stats:** codec, resolution, bitrate, dropped frames, …
  - **Chapters:** list, or "No chapters in this title".
- Rows show a label plus value with a chevron and invert when focused. Selecting a row opens a centered picker dialog with a ✓ on the current value.

**Skip Intro pill** (`TvIntroAutoSkipBanner.kt`):

- Bottom-right: 64 px from the right edge; bottom 400 px while controls are up, 112 px when hidden.
- Black @ 65% capsule, 56 px radius, 2 px border (white 25% at rest, white when focused).
- Label **"Skip Intro"**, 18 sp, 64 px × 36 px padding.
- A fill sweeps left to right as the offer times out.
- Auto-skip mode shows the caption "Intro skipped" above a **"Watch Intro"** button.

**Up Next overlay** (end of an episode):

- The video shrinks into a 16:9 pane on the left with an 8 dp radius and a white 16% border. Horizontal padding 160 px; 96 px gap to the info panel.
- Right panel:
  - Eyebrow (uppercase): "UP NEXT", "PLAYING NEXT", "UP NEXT AT RANDOM", "MORE TO WATCH" or "FINISHED".
  - Series title.
  - "S2·E9", episode title (fallback "Next Episode"), "NN min".
  - Overview.
  - Buttons: **"Play Now"** (440 px, with a countdown ring), "Pick Another" (shuffle only), "Keep Watching" (520 px), "Back" (320 px).
  - Toggle chip "Auto-play is On" / "Auto-play is Off" and "Stop shuffling" (shuffle only).
  - If nothing follows: "End of playback" or "Almost finished", plus "No next episode is available."
- This overlay replaces the "Still watching?" prompt.

---

## 5. Key strings (exact wording)

| Context | Strings |
|---|---|
| Navigation | Home, Movies, Series, Music, Audiobooks, For You, Calendar, Requests, Search |
| Cascade | Recommended, Browse, Collections, Genres, A-Z, Recently Added, Authors; library headers like "MOVIE LIBRARIES" |
| For You menu | FOR YOU, Recommendations, Favorites, Watchlist |
| Profile menu | Switch Profile, Watchlist, Favorites, History, Watch Party, Settings, Switch Server, Sign Out |
| Home rows (server-provided titles) | e.g. "Continue Watching", "Next Up"; the client adds "Continue Listening"; "See all" |
| Card / detail actions | Play, Resume, "Resume 1:23:45", "Play S2:E3", Start Over, Watchlist, More, More Actions, "Mark as Watched" / "Mark as Unwatched", "Add to Favorites" / "Remove from Favorites", "Add to Watchlist" / "Remove from Watchlist", "Remove from Continue Watching", Shuffle Series, Go to Series, Go to Season N |
| Detail sections | Episodes, Cast & Crew, Trailers & More, Related Movies, Recommended Series, Details, Season N, Specials |
| Setup | "Set up with your phone", "Enter server address", "Enter your server address", Connect, Connecting…, Back, "Easier with a phone" |
| Sign-in | "Sign in to %s", "Sign in with a password", "Sign in", "Signing in…", "Use your phone instead", "Change server", "Create Account", Username, Password, "Show a new code", "Try again", "Waiting for approval" |
| Profiles | "Who's watching?", "Signed in as %s", "Add profile", Manage, Done, "Sign out", "Enter your PIN" |
| Player | Skip Intro, Watch Intro, Intro skipped, Up Next, Play Now, Keep Watching, Pick Another, Paused, Buffering, Subtitles, "Info and options", "Close player" |
| General | "Loading…", "Something went wrong", Retry, Cancel, "Offline mode - select to retry" |

The full string list is in `ROOT/androidTvApp/src/androidMain/res/values/strings.xml` (172 lines; mostly auth and pairing). Most other labels are hard-coded in the Kotlin files listed above.

---

## 6. Two things that are easy to miss

1. **Text size:** remember the 0.86 font scale. Convert text at 1.72 px per sp; geometry stays at 2 px per dp.
2. **Focus style:** almost every control signals focus by **inverting to `#EDEDED` with black content**. Only cards (scale 1.10, 2 dp white border, white glow) and avatar tiles (scale 1.12 plus a ring) scale up. Use this consistently on Roku for the same look.
