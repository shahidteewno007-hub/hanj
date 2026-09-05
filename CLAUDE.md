# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Hanj** — an anime tracker. Flutter (web + Android), Firebase (Auth, Firestore, Cloud
Functions v2), AniList GraphQL API. Package `com.anitrack.anime_tracker`, Firebase project
`anime-tracker-275cc`. The README is the untouched Flutter stub; ignore it.

## Read this before changing anything

**`lib/` was reconstructed after a data-loss incident** — reassembled file by file from a
Recycle Bin export and matched against screenshots of a working APK. It runs and matches
the last known-good build, but that history explains what you will notice: some screens are
missing entirely, some code looks like it was written by someone who could not see the rest
of the file, and there are orphans.

Two rules follow from that, and they are not negotiable:

- **Never delete a file.** If something looks dead, report it as a deletion candidate and
  leave it. A file that looks orphaned may be the only surviving copy of a screen. The ~47
  unused declarations the analyzer reports (whole widgets nothing calls — `_StatusTile`,
  `_StreamingButtons`, `_MiniBarChart`, `_PetalParticles`, …) are the cheapest available map
  of features that used to render. Keep them.
- **Never restructure.** No renaming files, no moving code between files, no reorganising
  folders, no "cleaning up" the architecture. The current shape is the output of a careful
  reconstruction and needs to stay recognisable.

Also standing: no refactoring of working code, no reformatting files you aren't otherwise
changing, no new dependencies, no edits to `pubspec.yaml` versions, no touching
`firebase_options.dart`, the keystore, or anything credential-shaped, and **never run
`firebase deploy`**.

Existing analysis lives in `AUDIT.md` (correctness/security) and `PERF.md` (performance,
device-measured). Check them before re-investigating something.

**Run `git status` at the start of every batch, and flag anything you did not do.**
Something outside the Claude session has modified the working tree at least once:
`discovery_screen.dart` was overwritten mid-batch in a way that stripped already-committed
`ValueKey`s, turned a settable `_PillChip` default into a constructor initialiser, and left
`_HanjFilterSheet` syntactically invalid (`) : genre = null : format : year;`). It read like
an automated quick-fix or formatter, not a hand edit. Under investigation.

So: do not assume the tree matches what you last wrote. If you find changes you did not
make, **preserve a copy and the diff before touching them, then say so** — do not silently
revert, and do not silently build on top.

## Commands

```bash
flutter run -d chrome              # the normal dev loop
flutter analyze                    # baseline: 202 issues, 0 errors (48 warnings, 154 infos)
flutter build web                  # must be clean before calling a change done
```

Device work (target is an Oppo **CPH2573**, arm64, Android 16, 90 Hz → **11.1 ms** frame budget):

```bash
flutter devices                                              # get the device id
flutter run --profile -d <device-id>                         # profile, never debug, for timings
flutter run --profile --trace-startup --no-resident -d <id>  # writes build/start_up_info.json
flutter build apk --profile --target-platform android-arm64
```

- **Profile, not debug, for any measurement** — debug timings are meaningless.
- **Always pass `adb -s <serial>`.** The phone enumerates twice on wireless debugging —
  once as the plain wireless endpoint (`192.168.123.36:42611`) and once as the mDNS TLS
  entry (`adb-<id>-<suffix>._adb-tls-connect._tcp`) — so a bare `adb` command fails with
  `adb: error: failed to get feature set: more than one device/emulator`. Get the serial
  from `adb devices` and put `-s` on every call, the `dumpsys` check below included:

  ```bash
  adb devices                                    # pick the serial
  adb -s <serial> shell dumpsys package com.anitrack.anime_tracker | grep lastUpdateTime
  ```

  `flutter run -d <device-id>` is unaffected — it takes its own device flag.
- **Verify the install landed before trusting any reading.** `flutter run` exits 0 on a
  build that compiled but never installed (it happens when the phone drops off USB
  mid-run), and you will then be measuring the *previous* APK. Always check:

  ```bash
  adb -s <serial> shell dumpsys package com.anitrack.anime_tracker | grep lastUpdateTime
  ```

  If that timestamp predates the build, the reading is from stale code — rebuild and
  reinstall before reading anything into it. This has already produced one misleading
  measurement.
- `--analyze-size` only works on **release** builds; it errors on profile.
- Driving the device over adb: the nav bar sits at `y=2978`, tab x-centres are
  144 / 431 / 719 / 1007 / 1295. **Swipes that end low trigger gesture navigation and throw
  the app to the launcher** — keep them ending above `y≈900`.

**There are no tests.** `test/` is empty, so there is no single-test command to give. Don't
claim a change is verified by tests; verify with `flutter analyze`, `flutter build web`, and
device measurement where it's a performance claim.

### Build environment (Windows)

- JDK 17 portable at `C:\Users\ABC\Dev\jdk17`.
- `GRADLE_USER_HOME=C:\g` — set for Windows path-length reasons. **Do not change it.**
- `android/local.properties` points `sdk.dir` at `C:\Users\ABC\AppData\Local\Android\sdk`
  (note: a second SDK also exists at `C:\Users\ABC\Dev\android-sdk`; gradle uses the
  `local.properties` one).
- Firebase CLI is `firebase.cmd` — and deploys are off-limits regardless.

## Architecture

Feature-first layout. No state-management framework beyond `provider` for two app-wide
singletons; no repository layer and no DI. Screens talk to services directly, and most
services are hand-rolled singletons (`X._(); static final instance = X._();`).

```
main.dart ── Firebase init ─ Crashlytics hooks ─ FCM listeners ─ runApp
   └─ HanjApp (MultiProvider: ThemeProvider, AuthService)
        └─ AuthWrapper                    authStateChanges()
             ├─ LoginScreen                          (signed out)
             ├─ EmailVerificationScreen              (unverified, non-Google)
             └─ _OnboardingGate                      (streams users/{uid})
                  ├─ OnboardingScreen                (onboardingComplete != true)
                  └─ MainScreen                      (5-tab NavigationBar)
```

`MainScreen` (`lib/features/main_screen.dart`) holds the five tab roots — Home, Discover,
Pulse, List, Profile — and swaps them by index. **It does not use `IndexedStack`**, so every
tab switch destroys and rebuilds the tab root; screens compensate with static caches (see
below). Everything else is pushed as an inline `MaterialPageRoute`.

**`MaterialApp.routes` registers only `/cards` and `/cadre`.** Notification deep links in
`notification_service.dart` push `/anime-detail`, `/social`, `/wrapped` and `/home`, none of
which exist — see `AUDIT.md` S2-1 before adding anything that relies on named routes.

`lib/cadre/` is a self-contained subsystem (~5.6k lines — a card-battler with its own models,
rankings, bot and six screens) reached via `/cadre`. It has its own dev entry point:
`flutter run -t lib/cadre_dev.dart`. That file is unreferenced **by design** — not an orphan.

### Where state lives

Four distinct patterns coexist; know which one you're in before editing:

1. `provider` — only `ThemeProvider` and `AuthService`.
2. Per-screen `setState` — the overwhelming default.
3. **Static caches on `State` subclasses** (`_DiscoveryScreenState._cachedCurrent`,
   `UpcomingAnimeRow._cachedThis`, `PulseService._memCache`). These survive tab switches and
   exist because of the `IndexedStack` gap above.
4. `OfflineCacheService` — memory → `SharedPreferences` (1 h TTL) → network, with stale
   fallback. Well built but only wired to one feed.

**Important:** the static caches in (3) are **display caches, not request caches.** They seed
state to avoid a blank flash and then fetch anyway — they never short-circuit the network
call. Returning to the Home tab re-fires the same 3 AniList requests. Don't assume a cache
hit means no request.

### Data reach

- **Firestore** — `users/{uid}` is the hub, with subcollections `animeList`, `alerts`,
  `activity`, `companion_chat`, `companion_meta`. Top-level: `arcs` (+`posts`, +`replies`),
  `episodeDiscussions` (+`votes`), `meta/founders`. `FirestoreService` covers only
  `animeList` + activity; **social, arcs, discussions, cards and founders all call
  `FirebaseFirestore.instance` directly from their screens**, so there is no single place to
  change a collection name.
- **`firestore.rules` is not in this repo** and `firebase.json` has no `firestore` section.
  The rules live only in the console — unversioned and unreviewable. Recover them with
  `firebase.cmd firestore:rules get` before making any security claim.
- **Cloud Functions** — `functions/index.js` (v2, Node 20, 10 exports). `firebase.json` also
  declares a second codebase `aruku` whose directory **does not exist**, which likely blocks
  all function deploys.

## Domain rules

These are deliberate and settled. Do not "improve" them.

### AniList — everything goes through the throttle

`AnilistService` (`lib/services/anilist_service.dart`) owns an adaptive reservation-based
throttle: **350 ms** between requests normally, **2 s** for a 60 s cooldown after a 429,
honouring `Retry-After`. `AnilistService.throttle()` and `.backoff(seconds)` are public
precisely so direct `http.post` callers can join the same queue.

**Any new AniList call must `await AnilistService.throttle()` and call `.backoff()` on a 429.**
A call that bypasses the queue causes blank screens under load — that was a real bug here.
`PulseService._query` is the reference implementation (throttle + backoff + timeout + TTL
cache); copy it. Five call sites currently bypass the throttle — see `AUDIT.md` §4.

**Never weaken the throttle, shorten a backoff, drop a `mounted` check, or remove error
handling to save a frame.** The stale-while-revalidate fallbacks are what keep screens
populated when AniList rate-limits; add caching *in front of* them, never in place of them.

### Design system

Palette — background `#0D0B09`, coral `#E8624A`, ivory `#F3EEE7`. Defined in
`lib/core/theme/app_theme.dart`.

Type roles — **Playfair Display** for headings, **DM Sans** for body, **Space Grotesk** for
numerals and mono. These three are the app's identity: they're on the store listing and in
the shareable cards people post. **Do not propose replacing them, adding a fourth family, or
substituting anything "cleaner".** Improving typography here means improving how these three
are used.

> **Known drift:** the code currently ships **six** families. `AppTheme.sans()` and the whole
> `TextTheme` body/title tier resolve to `GoogleFonts.inter`, not DM Sans, across 224 call
> sites, while 84 sites call `GoogleFonts.dmSans` directly. Space Mono (9 sites, all in
> `hanj_card.dart`) and Noto Serif JP (4 sites, `tomo_screen.dart`) are also unaccounted for.
> This is a known open decision — see `PERF.md` S6-1. Don't quietly "fix" it either way.

Also settled: **the six card rarity tiers** — `enum CardRarity { common, rare, epic,
legendary, seasonal, secret }` in `lib/features/cards/hanj_card.dart`. The collection screen
filters on all six (`ALL, COMMON, RARE, EPIC, LEGENDARY, SEASONAL, SECRET`); the tab strip
scrolls, so only the first few are visible at once.

### Loki (the AI companion)

`chatWithTomo` in `functions/index.js`, fronted by `TomoService` and `tomo_screen.dart`
(internally still named Tomo).

**Loki is meant to be restricted to a single owner UID and capped at 40 messages/day.** The
daily cap is real and enforced server-side. **The owner gate is not implemented in any
layer** — the function checks only that the caller is authenticated, and the entry button
renders unconditionally in the home header for every user. Any signed-up user can spend the
owner's Anthropic API key. This is a known, deliberately deferred item (it needs a deploy and
a policy decision); see `AUDIT.md` S1-1. Treat owner-gating as the intended design when
touching this code.

## Gotchas

- **Web hides device-only bugs.** `MediaQuery.padding.top` is 0 in a desktop browser, which
  is how a double-`SafeArea` inset survived for months. Anything layout- or
  performance-related must be checked on device.
- **Crashlytics reports unhandled async errors as fatal** (`PlatformDispatcher.onError`
  returns `true` with `fatal: true` in `main.dart`). An unawaited Firestore write that fails
  offline becomes a fatal crash report.
- `speech_to_text` and `flutter_tts` are pinned to `any` in `pubspec.yaml`.
- `cupertino_icons` is declared but its font isn't bundled — web builds warn, and any
  Cupertino icon renders as a blank box.
