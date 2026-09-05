# Hanj — web audit (phase one)

**Date:** 2026-09-04
**Commit:** `e1c6624` (main)
**Companion to:** `AUDIT.md` (correctness/security), `PERF.md` (Android performance)

Phase one only. **No code was changed** — `git status` is clean apart from this file.
Phase two (the desktop layout proposal) is not started and awaits your review of this.

---

## 0. What I measured, and what I could not

| | |
|---|---|
| **Measured** | Bundle and transfer sizes (release build, raw + gzip); every hardcoded dimension in `lib/`; routing and URL behaviour from source; the Google sign-in failure, **verified against the installed plugin source**; `web/` contents; service worker behaviour; font family count |
| **Observed** | **25 signed-in screenshots** — home, discover, pulse, list, profile at 390 / 768 / 1024 / 1440 / 1920, captured in Chrome DevTools (§1.3–1.5) |
| **Could NOT measure** | Real TTI; iOS Safari; browser back; scroll feel; any screen outside the five captured |

**Update, 2026-09-04.** §1.3 and §1.4 were originally *Suspected*, written from layout code
because headless Chrome could not get past `AuthWrapper`. **They have now been resolved
against the screenshots** and are marked accordingly: stretch is confirmed and worse than
predicted, the "broken" category came back empty, and one prediction was wrong. §1.5 records
what the captures still could not settle. Everything below §2 is unchanged.

*For the record on the headless attempt, since it may come up again:* serving the release
build and driving headless Chrome at all five widths produced only the app background
`#0D0B09`. That is `AuthWrapper`'s waiting branch ([main.dart:236](lib/main.dart#L236)) —
Flutter booted and painted, but never left auth resolution, because `--virtual-time-budget`
fast-forwards timers without waiting for the Firebase network round-trip. A 90 s budget gave
a byte-identical screenshot. Headless is not a route to signed-in captures here; a real
browser session is.

**I cannot test iOS Safari at all.** No iOS device, and Safari does not exist on Windows.
Every iOS statement here is derived from documented platform behaviour and from this
codebase, never from observation, and is labelled as such. Given iPhone is the entire point
of this workstream, that is the biggest gap in this audit.

---

## 1. What breaks with width

### 1.1 Hardcoded dimensions — measured, and better than expected

Every `width:`/`height:` numeric literal in `lib/` excluding `cadre/`:

| | count |
|---|---|
| Total fixed dimension literals | **1,174** |
| Of those, **≥ 200 px** | **13** |
| `MediaQuery` width reads | **8** |
| `LayoutBuilder` uses | **2** |

The headline is the second row. The distribution is dominated by 8, 4, 12, 20, 16 px — icon
sizes, gaps, border widths, avatar diameters. Those are **genuinely fixed by design** and
should stay fixed; scaling them with viewport width is how apps end up with 40 px icons on a
monitor. This is not 1,174 problems.

The 13 that are ≥ 200 px are the phone assumptions, and they cluster:

| Site | Value | Reading |
|---|---|---|
| [home_screen.dart:394](lib/features/home/home_screen.dart#L394) | `height: 310` | Hero card strip |
| [home_screen.dart:455](lib/features/home/home_screen.dart#L455), [:603](lib/features/home/home_screen.dart#L603) | `height: 260` | Horizontal poster rails |
| [home_screen.dart:1017-1018](lib/features/home/home_screen.dart#L1017), [:1308](lib/features/home/home_screen.dart#L1308), [:1319-1320](lib/features/home/home_screen.dart#L1319), [:1463](lib/features/home/home_screen.dart#L1463), [:1477-1478](lib/features/home/home_screen.dart#L1477) | `width: 140`, `height: 196/200` | Poster card size, repeated 5× |
| [discovery_screen.dart:1028](lib/features/discovery/discovery_screen.dart#L1028) | `height: 180` | Row height |
| [emotional_categories.dart:336](lib/features/discovery/emotional_categories.dart#L336), [:373](lib/features/discovery/emotional_categories.dart#L373) | `height: 200`, `width: 120` | Category tiles |
| [trailer_launcher.dart:160](lib/core/trailer_launcher.dart#L160), [:173](lib/core/trailer_launcher.dart#L173) | `height: 220/200` | Trailer thumbnail |
| [card_unlock_overlay.dart:161-162](lib/features/cards/card_unlock_overlay.dart#L161) | `280 × 280` | Unlock animation |
| [card_share.dart:254-255](lib/features/cards/card_share.dart#L254) | `340 × 604` | **Legitimately fixed** — the 9:16 share canvas. Do not touch. |

`width: 140` repeated five times for poster cards is the single most consequential number in
the app for this work: it is what makes every horizontal rail look like a phone rail on a
2560 px monitor.

### 1.2 There is already a responsive layer, and it is orphaned — measured

`lib/core/responsive.dart` exists (65 lines): `isMobile/isTablet/isDesktop` at **600 / 1024**,
plus helpers for grid columns, card width, padding, avatar size, nav height.

**It is imported by exactly one screen** — `search_screen.dart` — and used there only for
grid columns and padding. Every other screen ignores it.

Two things follow, and both matter for phase two:

- The "shared layer vs per-screen branching" question you raise in phase two **is already
  answered in the codebase**; the layer just was never adopted. That is a much better
  starting point than a blank page.
- Its values are themselves phone-shaped. `getGridColumns` returns **3 at every width above
  1024**, and `getCardWidth` caps at 160. Adopting it unchanged would make a 1920 px screen a
  slightly wider tablet. The breakpoints are reusable; the values need rethinking.

### 1.3 Stretch — **CONFIRMED** against screenshots (2026-09-04)

Resolved against `screenshots/` — home, discover, pulse, list, profile at 390 / 768 / 1024 /
1440 / 1920, signed in, captured in Chrome DevTools.

**Confirmed, and worse than predicted.** Every captured screen stretches. The pattern is
consistent: a fixed-size element pinned to the left, a control pinned to the right, and
hundreds of pixels of dead space between them.

| Screen | What stretches at 1920 |
|---|---|
| **Home** | The `TONIGHT'S DROP` hero: poster stays ~150 px while the card spans ~1,900 px, leaving ~1,700 px empty beside the Continue button. The "Find your next anime" banner: Discover button flung to the far right. **Trending rows: the bookmark icon sits ~1,800 px from the title it belongs to.** |
| **Discover** | Nine "Hidden Gems / Hype Machine / …" category cards, each full-width with an icon at the far left and a chevron at the far right. **~90% of each card is empty.** The worst case in the set. |
| **Profile** | Founder card full-width with the `#6` watermark pushed to the far right; Collection card the same; Hanj Cards and Cadre rows the same. |
| **List** | Search field spans the full width. |
| **Pulse** | Tab strip and empty state, both anchored left in a full-width column. |
| **All five** | The 5-tab `NavigationBar` spread across the full width, exactly as predicted. |

**Two-column grid → two enormous columns: CONFIRMED**, though not where I expected. Profile's
stat tiles (`EPISODES` / `AVG RATING`, `WATCH TIME` / `COMPLETED`) are a real 2-column grid,
and at 1920 px each tile is **~965 px wide** to hold the number `0`. The card collection grid
was not captured — it sits behind the Hanj Cards row — so that specific instance stays
unverified, but the pattern is proven.

**One prediction was wrong.** I expected the dominant failure to be *horizontal rails of
140 px cards* leaving width empty. On the captured Home viewport there are no rails — the
content is a **full-width vertical list**. The `width: 140` poster cards are below the fold or
on other rows. The real failure mode is the full-width row with a fixed thumbnail at one end
and an icon at the other, which is a different fix: constrain the container, not the card.

**Width does help the content, which is the encouraging part.** At 390 px the trending titles
truncate ("That Time I Got Reincarn…"); at 768 px most fit; at 1920 px all of them fit. The
app is not badly designed for width — it is simply unconstrained. A max-width wrapper plus a
column layout at the top end would fix most of what these screenshots show.

**No breakpoint response, confirmed twice over.** Visually, 390 / 768 / 1920 are structurally
identical, only wider. In code, four of the five captured screens have **zero** width-aware
references, and Discover has one:

| Screen | width-aware references |
|---|---|
| home_screen | 0 |
| discovery_screen | 1 |
| pulse_screen | 0 |
| my_list_screen | 0 |
| profile_screen | 0 |

The only `MediaQuery` uses in these five files are `padding.top` and `removePadding` — safe
area, not width.

### 1.4 Broken — **resolved: nothing found**

**No overflow, no clipped content, no unreachable control on any of the 25 captures**,
including at 390 px where I thought it most likely. The `height: 196` poster cards and the
fixed-height rows all hold. This category is empty for these five screens.

One thing that looked like a finding and is not: at 390 px the Pulse tab strip shows
`UPCOMING` cut off at the viewport edge. That is **by design** — `pulse_screen.dart:100-103`
sets `isScrollable: true` with `tabAlignment: TabAlignment.start`, so the strip scrolls
horizontally, the same pattern `CLAUDE.md` records for the card-collection rarity tabs.
Verified in code before reporting it. Not a bug.

Still unverified, because the screens were not captured: overflow risk in the 62 px fixed name
block in `card_share.dart` (`PERF.md` §5-A), and on the anime detail screen.

### 1.5 What the screenshots could not resolve

Recorded so this is not mistaken for full coverage.

- **The captures use a different account from the Android device** — "Shahid", Founder #6,
  **0 titles**, joined 2026-09-04, against Founder #1 with 165 titles on the CPH2573. So List
  and Profile render empty states. **List-with-content stretch is unverified**, which matters
  because a populated list is the screen most likely to benefit from a desktop two-pane.
  Home still shows real content because trending data is global rather than per-user.
- **Body-text line length is unverified.** The detail-screen synopsis and arc post bodies are
  the cases I flagged as worst, and neither screen is in the set. The code position is
  unchanged: both are unconstrained `Text` in a full-width `Column`.
- **The card collection grid is unverified** (behind the Hanj Cards row).
- **A rendering artefact, not a bug:** the 390 px and 768 px captures show faint nav icons
  near the top of the page. That is DevTools compositing the fixed bottom bar into a
  full-page screenshot, not the app drawing the bar twice.

---

## 2. Web-specific behaviour

### 2.1 URLs — the whole app lives at one address. Measured, from source

| | |
|---|---|
| URL strategy configured | **None** → Flutter's default hash strategy, so URLs look like `/#/` |
| Named routes registered | **2** (`/cards`, `/cadre`) — [main.dart:216-219](lib/main.dart#L216) |
| `pushNamed` call sites | **5** — all in `notification_service.dart`, all pushing routes that do not exist (`AUDIT.md` S2-1) |
| Inline `MaterialPageRoute` pushes | **60** |
| `onGenerateRoute` / `Router` / `go_router` | **None** |

So: **60 of the app's 62 navigations do not change the URL.** No anime, card, arc or profile
has an addressable link.

For a phone app that is invisible. For this app it is a product limitation, because the
shareable card is a core feature: someone posts a card, a friend clicks, and lands on the
home screen — or the login screen — with no way to reach the thing they were shown. The
share image is the only artefact that survives the trip.

Fixing it means adopting a router. That is a real piece of work and it is the one thing in
this audit that changes the app's architecture rather than its layout.

### 2.2 Browser back — *Suspected*

Flutter registers a browser history entry per `Navigator` push, so back should pop routes.
I could not test it. Two things I would specifically check, because they are the usual
failure modes:

- **Back at the root** exits the app entirely rather than doing nothing.
- **Tab switches are not routes.** `MainScreen` swaps `_screens[_selectedIndex]` with
  `setState` ([main_screen.dart:36](lib/features/main_screen.dart#L36)), so moving Home →
  Discover → Pulse creates **no history entries**. Back from Pulse will not return to
  Discover; it will leave the app. On a phone that is standard; in a browser it is the
  single most common way a Flutter web app feels broken, and it is exactly the case your
  brief calls out.

### 2.3 🔴 Google sign-in does not work on web — measured, verified from plugin source

**This is the most important finding in the audit**, because the stated purpose of this
workstream is that iPhone users get in through the web.

`auth_service.dart` calls, with no `kIsWeb` branch anywhere in the auth path:

```dart
await GoogleSignIn.instance.initialize(serverClientId: _googleServerClientId);  // :42-44
final googleUser = await GoogleSignIn.instance.authenticate(...);               // :92
```

Against `google_sign_in_web-1.1.3`, both lines fail. From the installed source:

**`initialize()` fails first** — [`google_sign_in_web.dart:116-127`]:

```dart
final String? appClientId = params.clientId ?? autoDetectedClientId;
assert(appClientId != null,
  'ClientID not set. Either set it on a <meta name="google-signin-client_id" ...>'
  ' tag, or pass clientId when initializing GoogleSignIn');
assert(params.serverClientId == null, 'serverClientId is not supported on Web.');
```

- The app passes **`serverClientId`, not `clientId`** → second assert fires.
- `web/index.html` has **no `google-signin-client_id` meta tag** (verified: 0 occurrences),
  so `autoDetectedClientId` is null → first assert fires.
- **Asserts are compiled out in release.** In a release web build it gets past both and dies
  at line 134 on `clientId: appClientId!` — a null-check throw instead. It fails either way,
  just with a less helpful message in the build you would actually ship.

**`authenticate()` is not implemented on web at all** — [`:157`, `:163-169`]:

```dart
bool supportsAuthenticate() => false;

Future<AuthenticationResults> authenticate(AuthenticateParameters params) async {
  throw UnimplementedError(
    'authenticate is not supported on the web. '
    'Instead, use renderButton to create a sign-in widget.');
}
```

So this is **not a config fix**. Even with a correct `clientId`, the programmatic call can
never work: Google Identity Services requires the rendered-button flow, and the plugin
exposes it as a widget. The login screen needs a web-specific branch rendering
`renderButton`, plus a web OAuth client ID.

**Not everything is broken:** email/password sign-in goes through `firebase_auth_web` and
should work normally. So web is not fully locked out — but the one-tap path most users take
is dead, and on a fresh phone-shaped browser that is likely to read as "the app is broken".

### 2.3a W1 — the web sign-in fix (implemented, not yet verified end to end)

Branch `fix/web-google-signin`. Android's path is untouched.

**What changed.** Three small pieces, no refactor of the working flow:

- `auth_service.dart` — `_ensureGoogleInitialized()` branches on `kIsWeb`: web passes
  `clientId`, Android keeps passing `serverClientId`. The Firebase sign-in tail was extracted
  to `completeGoogleSignIn(user)` so both platforms share one code path and cannot drift.
  `signInWithGoogle()` now throws a readable message on web instead of reaching the plugin's
  `UnimplementedError`.
- `google_button_web.dart` / `google_button_stub.dart` — conditional import, matching the
  `gal_mobile`/`gal_stub` idiom already in the codebase. Web renders `web_only.renderButton`;
  mobile returns a `SizedBox.shrink()` and keeps its own custom button.
- `login_screen.dart` — on web only, shows Google's button and listens to
  `GoogleSignIn.instance.authenticationEvents`, because the rendered button returns no
  credential. On Android neither the listener nor the button branch runs.

**How far the button can be styled toward Hanj's identity: barely.** That is the honest
answer. `GSIButtonConfiguration` exposes exactly: `type` (standard/icon), `theme` (outline /
filledBlue / filledBlack), `size`, `text`, `shape` (rectangular/pill), `logoAlignment`,
`minimumWidth` (max 400 px), and `locale`. **No custom colour, no custom font, no custom
radius.** The coral `#E8624A` and DM Sans cannot be applied. I chose `outline` + `pill`
because that is the closest of the three themes on a dark background, but a Google-styled
button in an otherwise Hanj-styled screen is the unavoidable outcome of using GIS at all.

**Client ID — needs your input.** The brief said a Web application client ID would be
supplied; it did not arrive with the message, so the code currently uses the project's
**existing** `client_type == 3` (Web) entry from `google-services.json`:

```
572595796065-gu6s6tq1hv5s1rhp25bfegqateqlgo6o.apps.googleusercontent.com
```

That is a deliberate default rather than a placeholder: it is the same client Android already
passes as `serverClientId`, so the idToken audience matches what Firebase expects. If your new
client is different, change the single constant `_googleWebClientId` in `auth_service.dart`.

**Authorised JavaScript origins to add** — in Google Cloud Console → APIs & Services →
Credentials → the Web client → *Authorized JavaScript origins*. Scheme, host and port, **no
trailing slash and no path**:

| Origin | For |
|---|---|
| `http://localhost:5000` | local dev — run `flutter run -d chrome --web-port=5000` so the port is stable, otherwise Flutter picks a random one each time and none of them will be authorised |
| `https://anime-tracker-275cc.web.app` | Firebase Hosting default |
| `https://anime-tracker-275cc.firebaseapp.com` | Firebase Hosting alternate |
| your custom domain, if any | production |

*Authorized redirect URIs* are **not** needed — the GIS button is a JavaScript flow, not a
redirect flow.

**Verified with the origins live (2026-09-04).** Served the release build at
`http://localhost:5000` and drove headless Chrome over CDP, waiting on **real** time rather
than `--virtual-time-budget` — which is what finally got past `AuthWrapper` (§0). Result:

- **The Google button renders.** GIS accepted the client ID at the authorised origin. The
  console shows `Creating policy: gis-dart` — the SDK loading — and **no
  `origin is not allowed` error**, which is the failure this would have produced if the
  console entries had not propagated.
- All six Firebase services initialise on web (core, auth, firestore, functions, analytics,
  messaging).
- `flutter build web --release` and `flutter build apk --profile` both compile.
  `flutter analyze`: 0 errors, 198 issues against a 202 baseline (four style infos removed in
  the code I rewrote, none added — diffed to confirm).

**One thing the render changed.** I had configured the `outline` theme as the closest to the
app's palette. Seeing it, that was wrong: `outline` is a **white** button, and on the
near-black login screen it reads as a foreign element pasted on top. Re-rendered with
`filledBlack`, which is dark with the Google G in a white circle and sits with the glass card
instead of fighting it. **Changed on the evidence, not on taste.** It remains a Google button —
this is choosing the least-bad of three fixed themes, not styling.

**Web sign-in confirmed end to end (yours, 2026-09-05):** signed in and landed on Home with
the real account (Founder #1, 165 titles), so the idToken audience is correct and the
existing project Web client is the right one to use.

**Android must-not-regress — verified on device (2026-09-05).** Wireless debugging, install
confirmed by `lastUpdateTime` before anything was read. Signed out, tapped Continue with
Google, chose the account, landed on Home with the real library intact.

Three things that check specifically:

- The Android login screen renders **the app's own custom button**, not Google's — so the
  conditional import resolved to `google_button_stub.dart` and the web branch did not leak
  into the mobile build.
- `com.google.android.gms/...GoogleSignInActivity` launched, meaning
  `initialize(serverClientId:)` still succeeds and `authenticate()` still runs the GMS flow
  on mobile.
- The account chooser was correctly branded *"to continue to Hanj"*, and sign-in restored
  the full library.

**Still not verified:** **Firefox** and **the blocked-popup case** on web — both need a human
driving a real browser.

**A note for the next person who tries to screenshot this app headlessly:** plain
`chrome --headless --screenshot --virtual-time-budget=N` will only ever capture the blank
`AuthWrapper` state, however large N is. Virtual time does not wait for Firebase's network
round-trip. Driving CDP and sleeping on real time works. The script is in the scratchpad as
`cdpshot.mjs`.

### 2.4 Desktop affordances — measured

| | count | consequence on desktop |
|---|---|---|
| `GestureDetector` | **136** | tap targets with no hover feedback |
| `InkWell` | **3** | almost nothing gives a ripple or highlight |
| `MouseRegion` | 29 (in 8 files) | some cursor handling exists — a starting point, not coverage |
| `Tooltip` | **0** | every icon-only button is unlabelled on hover |
| `SelectableText` | **0** | **no text anywhere can be selected or copied** |
| `Scrollbar` | **0** | no explicit scrollbars |
| `BouncingScrollPhysics` | 4 | iOS rubber-band feel under a mouse wheel |

Two of these are worth separating from the rest.

**Text selection (0 sites).** You cannot select or copy anything — not an anime synopsis, not
a friend code, not your own founder number. The friend code in soulmatch is the sharpest case:
users are asked to exchange an 8-character code they cannot copy.

**Find-in-page will not work regardless.** CanvasKit paints text into a canvas, so there is no
DOM text for Ctrl+F to search. That is a renderer property, not something `SelectableText`
fixes. Worth knowing before anyone files it as a bug.

---

## 3. Load — measured

Release build, `flutter build web --release`. Gzip is what actually crosses the wire.

| Asset | Raw | Gzipped |
|---|---:|---:|
| `index.html` | 3.5 KB | 1.4 KB |
| `flutter.js` | 9.3 KB | 3.6 KB |
| `flutter_bootstrap.js` | 9.7 KB | 3.8 KB |
| **`main.dart.js`** | **4,132 KB** | **1,201 KB** |
| **`canvaskit.wasm`** | **7,060 KB** | **2,841 KB** |
| `skwasm.wasm` (alt) | 3,497 KB | 1,501 KB |
| `skwasm_heavy.wasm` (alt) | 5,051 KB | 2,227 KB |
| Bundled fonts | 24.7 KB (MaterialIcons only) | — |
| `build/web` total on disk | **42.6 MB** | — |

`flutter_bootstrap.js` contains `"renderer":"canvaskit"`, so the 2,841 KB variant is the one
being fetched; the skwasm files ship but are not selected.

**Cold first load ≈ 4.05 MB gzipped** (1.21 MB app + 2.84 MB renderer) **before a single
pixel of Hanj appears** — and then the font fetches start.

**Fonts are all fetched at runtime.** The only font in the bundle is MaterialIcons. `pubspec.yaml`
declares no `fonts:` section, so `google_fonts` pulls every family from `fonts.gstatic.com` on
first paint. Current count on `main`:

| Family | Call sites |
|---|---:|
| DM Sans | 113 |
| Playfair Display | 55 |
| Space Grotesk | 44 |
| Space Mono | 9 |
| **Inter** | **6** |
| Noto Serif JP | 4 |

**Six families, and Inter is the one that matters here.** Batch 4b is still queued, so the six
remaining Inter sites are in `login_screen.dart` and `onboarding_screen.dart` — **the first
screens a web visitor ever sees.** A cold web visitor downloads a whole extra font family to
render the login screen, for six call sites. 4b was framed as tidying; on web it is on the
critical path.

**TTI is not measured** and I could not measure it — the app never leaves the auth-resolution
state under headless. §7 has the command for you to run.

**What a first-time visitor used to experience**, from code: browser blank → Flutter splash
(`#0D0B09`) → **`AuthWrapper` waiting state, a bare dark `Scaffold` with no spinner, logo or
text** ([main.dart:236-239](lib/main.dart#L236)) → login. Several seconds indistinguishable
from a failed load. On Android that state is brief and hidden behind the native splash; on
web it was the first impression.

> **W2 — fixed (2026-09-04).** `web/index.html` now carries a loading shell that paints
> before Flutter boots: the Hanj mark as inline SVG, the wordmark in a **system serif** (never
> a webfont — fetching one would add to the very wait it covers), and a coral `#E8624A`
> indeterminate bar, all on `#0D0B09` so the handover to Flutter has no flash. Everything is
> inline: no image request, no external CSS, nothing that can itself be slow.
>
> Verified over CDP against the release build, with the network throttled to 1.6 Mbps and the
> cache disabled:
>
> | Elapsed | State |
> |---|---|
> | 600 ms | shell visible, Flutter not yet mounted |
> | 2.5 s / 8 s / 20 s | shell still holding the screen |
> | 3 s *(unthrottled)* | **shell removed**, Flutter mounted |
>
> Handover is on Flutter's own `flutter-first-frame` event. **No timeout fallback, on
> purpose:** a timer that removed the shell early would reintroduce the blank screen on
> exactly the slow connection this exists for. If Flutter never boots, a stuck loading state
> is more honest than an empty page.
>
> Two things came out of looking at the captures rather than the code. The `outline` Google
> button was replaced with `filledBlack` (§2.3a), and the progress bar's `ease-in-out` became
> `linear` — an eased sweep lingers at both extremes where the segment sits mostly off-track,
> so the indicator read as stalled for a noticeable slice of every cycle.
>
> This does not make the bundle smaller. §3's numbers are unchanged. It makes the wait
> legible, which is most of the perceived problem.

---

## 4. PWA readiness

### What exists

**`web/manifest.json` — better than boilerplate.** Real name, description, `#0D0B09`
background, `#E8624A` theme, `display: standalone`, and four icons including both maskable
sizes. Someone configured this deliberately.

**`web/index.html` — partly configured.** Has `mobile-web-app-capable`,
`apple-mobile-web-app-status-bar-style`, `apple-mobile-web-app-title`, an `apple-touch-icon`,
a manifest link and an SVG favicon.

### What is missing or wrong

| Item | State |
|---|---|
| **Offline shell** | **None.** See below — this is the significant one. |
| `<meta name="theme-color">` in `index.html` | **Absent.** The manifest has `theme_color`, but iOS Safari reads the meta tag. |
| `apple-touch-icon` size | Only the **192 px** icon is offered; iOS wants **180×180** and will rescale. |
| Viewport | `maximum-scale=1.0, user-scalable=no` — **pinch-zoom disabled**. An accessibility failure, and iOS Safari honours it. |
| `orientation` | `portrait-primary` — wrong for a surface whose whole point is a desktop layout. |
| `screenshots` / `shortcuts` | Absent. Not required, but they are what make an install prompt look like an app. |
| Firebase Hosting | **No `hosting` block in `firebase.json`** — see §6. |

**The offline shell is the real gap, and it is not what it looks like.** `build/web` does
contain `flutter_service_worker.js`, so it appears a service worker is present. Read it —
all 815 bytes — and its entire job is to **delete itself**:

```js
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    ...
```

Current Flutter ships a self-unregistering stub, not a caching worker. So **there is no
precaching and no offline capability**: every load re-fetches ~4 MB unless the HTTP cache
happens to hold it. The only real service worker is `firebase-messaging-sw.js`, which handles
background push and does not cache the shell.

One portability bug in that registration: `index.html` registers it at the absolute path
`/firebase-messaging-sw.js`. Hosted anywhere other than a domain root, that 404s and web push
silently stops working.

### iOS push — what it means for episode reminders

Episode reminders are a core feature. On iPhone, via web, here is the chain — **derived from
documented platform behaviour, not observed**, per §0:

1. **Web push on iOS requires the PWA to be installed to the Home Screen.** In a normal Safari
   tab there is no push, at all.
2. **iOS shows no install prompt.** The user must find Share → Add to Home Screen. Nothing in
   the app tells them to, and there is no code for an install affordance.
3. **Permission must come from a user gesture inside the installed PWA.** Hanj requests it from
   `NotificationService.init()`, called unawaited from `main()` — **not a user gesture**. On
   iOS that request cannot succeed even after installing.

**So an iPhone user gets zero episode reminders**, and nothing in the product tells them why or
what to do about it. The manifest's `display: standalone` is right, which is the precondition —
but the flow around it does not exist.

That is a product decision, not a bug to fix in passing: it needs an install prompt, a
gesture-driven permission request, and honest messaging for users who decline. Worth deciding
before promising reminders to web users.

---

## 5. Screen inventory and ranking

25 feature screens outside `cadre/` (itself 7,331 lines, reached via `/cadre`). Ranked by
**value × effort**, not size.

### Tier 1 — fix these first

| Screen | Lines | Why | Work |
|---|---:|---|---|
| **Login / onboarding** | 715 / 674 | The only door, and **Google sign-in is broken** (§2.3). Also where the stray Inter fetch lives. | Auth fix first; layout is simple |
| **Home** | 2,247 | Landing screen; holds 7 of the 13 oversized fixed dimensions and every horizontal rail | High |
| **Anime detail** | 2,204 | Where users spend time; the unconstrained synopsis is the worst line-length case | High |
| **Card collection** | 1,101 | 2-column grid that becomes absurd at width; the shareable-card feature is the reason web matters | Medium — grid columns |
| **My list** | 649 | Core loop, list-shaped, benefits most from a desktop two-pane | Medium |

### Tier 2 — after the pattern is proven

Discovery (2,026), Profile (1,319), Search (966 — already uses `Responsive`), Pulse (553),
Stats (828), My list detail views.

### Tier 3 — leave alone for now

Arcs (1,534 — a rewrite is already queued), Soulmatch (622), Episode discussions (663), Tomo
(628), Import (591), Calendar (462), Staff/studio detail (632/235), Taste profile (888),
Ranking cards (1,017), Edit profile (710), Activity feed (393), Card share (465 — fixed
canvas by design), Cadre (7,331 — self-contained, own navigation).

**`card_share.dart` should be explicitly excluded from responsive work.** Its 340 × 604 canvas
is a deliberate 9:16 output format, not a layout.

---

## 6. Hosting and the public bundle

**`firebase.json` has no `hosting` block** — only `firestore` and `functions`. So Firebase
Hosting is *not* configured in this project, contrary to the brief's assumption. Before
anything can be published, `firebase.json` needs a `hosting` section pointing at `build/web`,
plus a SPA rewrite so deep links (once they exist) do not 404.

I did not add it — that is a config change and this phase changes nothing.

**Dry run, when you want it** (I have not run any deploy or dry run this phase):

```
firebase.cmd deploy --only hosting --dry-run
```

Expect it to fail on the missing `hosting` block rather than on the `aruku` codebase, since
`aruku` is scoped to the functions target — but that is a prediction, not a result.

**What the web bundle exposes, checked.** The Firebase **web** API key `AIzaSyAn3syfkn…`
appears in `web/index.html` and `web/firebase-messaging-sw.js`. It is a different key from the
Android/iOS one (`AIzaSyBi…`), and it is already present in `lib/firebase_options.dart` as the
`web` entry, so **the bundle leaks nothing that is not already in the shipped source.**
Firebase web API keys are public by design — they identify the project, they do not authorise
access; your Firestore rules do that, and those are the ones just hardened in 5a/5b.

Two things that *are* worth knowing before publishing:

- A web bundle is far easier to inspect than an APK. Anyone can read the AniList query
  shapes, the collection names and the VAPID key. None of that is secret, but it makes the
  rules the only thing standing between a curious visitor and your data — which is an argument
  for finishing 5d before going public, not after.
- `index.html` initialises Firebase **a second time** via the gstatic JS SDK (v10.7.1) for FCM,
  independently of the Flutter `firebase_core` init. Two SDK copies, two configs to keep in
  step. It works, but it is a maintenance edge worth noting.

---

## 7. How to close the gaps in this audit

The three things I could not measure, and the cheapest way to get each.

**Widths, signed in.** Build, serve, and step through the widths in a real browser:

```bash
flutter build web --release
cd build/web && npx --yes serve -l 8777
# then Chrome DevTools device toolbar at 390 / 768 / 1024 / 1440 / 1920
```

Sign in with **email/password** — Google will not work (§2.3). Watch for red overflow stripes
at 390 px and for line length at 1440+.

**Load timing.** Same server, then DevTools → Lighthouse, mobile preset, cold cache
(Application → Clear storage first). The numbers to record are FCP, LCP and TTI, against the
4.05 MB baseline in §3.

**iOS Safari.** Needs a real device. The specific things to check, in priority order:
does the app load at all; does email sign-in work; Add to Home Screen, then whether
notification permission can be granted from inside the installed PWA (§4).

---

## 8. Summary — the five things that matter

1. **Google sign-in is broken on web** (§2.3). Verified from plugin source. The workstream's
   premise is that iPhone users get in this way, and they currently cannot. Not a config fix —
   needs a web branch using `renderButton`, plus a web client ID.
2. **The whole app has one URL** (§2.1). 60 of 62 navigations do not change the address bar.
   For a shareable-card app that is a product limitation, and fixing it means adopting a router.
3. **4.05 MB gzipped before first paint** (§3). ~~Landing on a blank dark screen with no
   spinner~~ — **W2 fixed the blank screen**; the bytes are unchanged and still the real
   problem. Plus six font families fetched at runtime, one of which exists only for six call
   sites on the login screen (W3).
4. **No offline shell** (§4). The service worker that looks like one deletes itself. And on
   iOS, episode reminders cannot work at all without an install flow that does not exist.
5. **The responsive layer already exists and is unused** (§1.2). One screen imports it. That
   is the phase-two starting point, though its values cap at tablet width.

**And, from the screenshots (§1.3):** every captured screen stretches, four of the five have
*zero* width-aware code, and nothing overflows — so this is an additive layout problem, not a
repair job. The app is not badly built for width; it is unconstrained. A max-width wrapper and
a column layout at the top end would fix most of what the captures show, which is a better
starting position than the code alone suggested.

Nothing in this file has been acted on. Phase two — the desktop layout proposal — awaits your
review.
