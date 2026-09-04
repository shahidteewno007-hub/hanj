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
| **Rendered** | Flutter boots and paints in headless Chrome at all five widths — but see below |
| **Could NOT measure** | Any signed-in screen at any width; real TTI; iOS Safari; browser back; scroll feel |

**Why the width screenshots are not in this report.** I served the release build locally and
drove headless Chrome at 390 / 768 / 1024 / 1440 / 1920. All five rendered the app
background `#0D0B09` and nothing else. That is `AuthWrapper`'s waiting branch
([main.dart:236](lib/main.dart#L236)) — Flutter booted and painted, but the app never left
the auth-resolution state, because `--virtual-time-budget` fast-forwards timers without
waiting for the Firebase network round-trip. Raising the budget to 90 s changed nothing
(byte-identical screenshot).

**And even with a working headless browser I could not have got further: Google sign-in is
broken on web (§2.3), and I have no credentials.** So every width finding below is from
reading layout code, not from seeing it. **Marked *Suspected* throughout.** Confirming them
needs a signed-in browser session, which is yours to run — commands in §7.

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

### 1.3 Stretch — *Suspected*

With 8 `MediaQuery` reads and 2 `LayoutBuilder`s across ~25 screens, the app is
width-unaware by construction. Expected at ≥ 1024 px, in descending confidence:

- **Body text spanning full viewport.** The synopsis on the detail screen and every arc post
  body are unconstrained `Text` in a full-width `Column`. At 1920 px that is a ~1900 px
  measure — three to four times a readable line length.
- **Two-column grids becoming two enormous columns.** The card collection grid is
  `crossAxisCount: 2` with `childAspectRatio: 200/300`
  ([card_collection_screen.dart:288-292](lib/features/cards/card_collection_screen.dart#L288)).
  At 1920 px each cell is ~950 px wide, so each card renders ~950 × 1425. The aspect ratio
  holds; the scale is absurd.
- **Horizontal rails with 140 px cards** leaving most of the width empty while the rail
  scrolls.
- **The 5-tab `NavigationBar`** stretched across the full width with five icons marooned in
  the middle.

### 1.4 Broken — *Suspected, and the least certain section here*

I have no rendered evidence of overflow. Flutter overflow errors are runtime and only appear
when a fixed-height box cannot fit its children — most likely at **390 px and below**, not at
desktop widths, and most likely where fixed heights meet text that wraps to more lines than
the author assumed (`height: 196` poster cards with two-line titles; the 62 px fixed name
block in `card_share.dart`, which `PERF.md` §5-A already flagged as having only 22 px of
slack in a 604 px canvas).

**Do not treat this section as findings.** It is a list of where to look first when you run
the widths yourself.

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

**What a first-time visitor actually experiences**, from code: browser blank → Flutter splash
(`#0D0B09`) → **`AuthWrapper` waiting state, which is a bare dark `Scaffold` with no spinner,
logo or text** ([main.dart:236-239](lib/main.dart#L236)) → login. On a phone connection that
is several seconds of a screen indistinguishable from a failed load. On Android this state is
brief and hidden behind the native splash; on web it is the first impression.

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
3. **4.05 MB gzipped before first paint** (§3), landing on a blank dark screen with no spinner.
   Plus six font families fetched at runtime, one of which exists only for six call sites on
   the login screen.
4. **No offline shell** (§4). The service worker that looks like one deletes itself. And on
   iOS, episode reminders cannot work at all without an install flow that does not exist.
5. **The responsive layer already exists and is unused** (§1.2). One screen imports it. That
   is the phase-two starting point, though its values cap at tablet width.

Nothing in this file has been acted on. Phase two — the desktop layout proposal — awaits your
review.
