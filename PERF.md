# Hanj — Performance and Typography Report (Phase One)

**Date:** 2026-09-04
**Commit profiled:** `2489f0a` (working tree byte-identical — verified with `git diff` after reverting instrumentation)
**Companion to:** `AUDIT.md`

---

## 0. What was measured, and how

You said device runs were yours to do. When I checked, the CPH2573 was connected and
authorised, so I asked, and you said go ahead. **Almost everything below is measured on
the target device**, not inferred and not extrapolated from Chrome.

| | |
|---|---|
| **Device** | CPH2573, Android 16 (API 36), arm64, 1440×3168 @ density 640 (DPR 4.0) |
| **Renderer** | Impeller / Vulkan (confirmed in logs) |
| **Refresh rate** | 90 Hz panel → **frame budget 11.1 ms** (all "over budget" counts below use 11.1 ms) |
| **Build** | `flutter build apk --profile --target-platform android-arm64`, run via `flutter run --profile` |
| **Flutter** | 3.44.0 / Dart 3.12.0 |

Temporary instrumentation was added to `main.dart` (startup phase stopwatch +
`SchedulerBinding.addTimingsCallback`) and `anilist_service.dart` (request counter),
measured, then **reverted**. `git diff` against `2489f0a` is empty and no `PERFPROBE`
string remains anywhere in `lib/`. Nothing was committed.

**Honest split:** every number in §1–§4 is device-measured. §5 (images), parts of §6
(fonts), and everything marked *Suspected* is analysis without a timing, and says so.
Web was used only for bundle size (§4.3) — per your own point, web timings would not
have told us anything useful here, and the device was available.

**Repro commands** for everything are in §8 so you can re-run any of it yourself.

---

## 1. Startup — measured

`--trace-startup` on the device, three runs.

| Metric | Run 1 (cold) | Run 2 | Run 3 (warm) |
|---|---|---|---|
| Time to first frame | **1,964 ms** | **1,879 ms** | — |
| Flutter framework init | 190 ms | 126 ms | — |
| Everything after framework init | 1,775 ms | 1,753 ms | — |

So ~90% of startup is **Dart `main()` running before `runApp()`**. Instrumenting each
await gave the breakdown:

| Phase | Run 2 | Run 3 | Share of pre-`runApp` |
|---|---|---|---|
| `WidgetsFlutterBinding.ensureInitialized` | 0 ms | 0 ms | — |
| `Firebase.initializeApp` | **673 ms** | 207 ms | 36% / 16% |
| `ConnectivityService.init` | 85 ms | 1 ms | 5% / 0% |
| **`NotificationService.init`** | **989 ms** | **1,106 ms** | **53% / 84%** |
| → `runApp` called at | 1,747 ms | 1,314 ms | |

### S1-1 · `NotificationService.init()` costs ~1.0 s of startup and blocks first paint — **measured**

**The number:** 989 ms and 1,106 ms across two runs. It is the single largest startup
phase, larger than Firebase, and it is `await`ed before `runApp()`
([main.dart:63](lib/main.dart#L63)).

Note both figures are the *fast* path — notification permission was already granted on
this device. `init()` opens with `await _fcm.requestPermission(...)`
([notification_service.dart:35](lib/services/notification_service.dart#L35)), which on a
first install does not complete until the user answers the dialog. This is the same code
path as **S3-6 in `AUDIT.md`**; what's new is that we now know it costs a second even when
nothing blocks.

`ConnectivityService.init()` one line above wraps its work in a 3-second timeout for
exactly this reason. The notification path has no timeout.

**Proposed fix:** move the `NotificationService.init()` call after `runApp()` (fire it
from the first authenticated screen, or unawaited with `.catchError`). Nothing in the
first frame depends on it — FCM tokens are saved separately from `auth_service.dart` on
sign-in, which `AUDIT.md` §9 already confirmed. **Expected: ~1.0 s off time-to-first-frame,
i.e. roughly 1,879 ms → ~880 ms.** Effort: ~10 lines.

**Also worth knowing:** `Firebase.initializeApp` costs 673 ms cold and 207 ms warm. That is
largely unavoidable, but it does not need to be serialised ahead of connectivity — the two
are independent and could run under `Future.wait`. Saves ~85 ms cold, which is real but
much smaller than the notification win. Do the notification one first and re-measure
before bothering.

---

## 2. Frame timing — measured, per screen

Captured with `addTimingsCallback` (frames where build **or** raster exceeded 8 ms), while
driving the device over adb. `build` = UI thread, `raster` = GPU thread. Budget 11.1 ms.

| Screen / action | frames >8 ms | worst **build** | worst **raster** | build over budget | raster over budget | verdict |
|---|---|---|---|---|---|---|
| Home — first mount | 5 | **38.3 ms** | 19.1 ms | 4 | 2 | UI thread |
| Home — scroll | **0** | — | — | 0 | 0 | **clean** |
| Discover — open + scroll | 1 | 17.1 ms | 13.7 ms | 1 | 1 | mild |
| Pulse — open | 4 | 24.7 ms | 17.8 ms | 2 | 2 | mild |
| List — open | 2 | 19.7 ms | 6.8 ms | 2 | 0 | UI thread |
| **Profile — open** | 6 | 30.7 ms | **40.1 ms** | 4 | 5 | **raster** |
| Home — return to tab | 3 | 28.7 ms | 15.8 ms | 2 | 1 | UI thread |
| Anime detail — open | 19 | **44.0 ms** | 31.5 ms | — | — | both |
| **Anime detail — 15 s idle** | **15** | 19.8 ms | 5.8 ms | — | — | **UI thread, 1/sec** |
| Card collection — open | 10 | 34.0 ms | 30.1 ms | 1 | 5 | raster |
| **Card collection — scroll** | **183** | 9.9 ms | **20.4 ms** | **0** | **26** | **raster** |

Two things stand out immediately, and they have opposite causes.

### S2-1 · The anime detail countdown rebuilds the whole screen once per second — **measured**

This is the one you predicted, and it reproduces exactly.

I opened One Piece (status **ON AIR**, so the countdown is live), then **touched nothing
for 15 seconds**. Result: **15 janky frames, one per second, like clockwork:**

```
08:12:56.732  build=12.1ms raster=5.7ms
08:12:57.749  build=19.8ms raster=5.1ms
08:12:58.739  build=17.9ms raster=4.9ms
08:12:59.752  build=19.4ms raster=5.6ms
08:13:00.739  build=19.8ms raster=5.4ms
08:13:01.739  build=18.2ms raster=5.3ms
08:13:02.747  build=18.0ms raster=5.5ms
08:13:03.737  build=16.8ms raster=5.8ms
08:13:04.747  build=16.7ms raster=5.6ms
08:13:05.743  build=18.4ms raster=5.1ms
08:13:06.727  build= 9.7ms raster=4.9ms
08:13:07.737  build=10.4ms raster=4.9ms
08:13:08.726  build= 8.8ms raster=2.7ms
08:13:09.743  build=11.7ms raster=5.6ms
08:13:10.739  build=16.6ms raster=4.4ms
```

Timestamps are 1.00 s apart. Median build **≈17 ms against an 11.1 ms budget**. Raster is
flat at ~5 ms throughout — so this is **purely UI-thread work**, i.e. widget rebuilding,
not painting.

**Cause.** `_countdownTimer`
([anime_detail_screen.dart:162](lib/features/anime_detail/anime_detail_screen.dart#L162))
calls `setState` on `_AnimeDetailScreenState`. That state object's `build()`
([:453](lib/features/anime_detail/anime_detail_screen.dart#L453)) is the root of a
2,190-line screen — `_HeroPanel`, the sliver tab bar, and whichever of `_OverviewTab` /
`_EpisodesTab` / `_CastTab` / `_RelatedTab` is active. All of them are `StatelessWidget`s
constructed inline (not `const`), so none can be skipped. The value being updated,
`_timeUntilAiring`, is consumed in exactly **one** place: passed to `_HeroPanel` at
[:686](lib/features/anime_detail/anime_detail_screen.dart#L686).

So: one `Duration`, used once, rebuilds the entire screen 60 times a minute.

**Proposed fix:** lift the ticking value out of the screen's state. A small
`ValueNotifier<Duration>` on the state, with a `ValueListenableBuilder` wrapped around
just the countdown text inside `_HeroPanel`, confines the rebuild to the text. The timer
keeps running exactly as it does now — no correctness change, no change to the throttle
or the `mounted` guards. **Expected: idle jank goes to zero; ~17 ms of UI-thread work per
second reclaimed while any airing title is open.** Effort: ~25 lines.

This is the highest-value fix in the report: the cost is continuous, it happens on a
screen users sit on to read, and the fix is small and self-contained.

### S2-2 · Card collection scroll is raster-bound — **measured**

**The number:** scrolling the collection (33 cards, 15 unlocked) produced **183 frames
over 8 ms, of which 26 exceeded the 11.1 ms budget** — and the split is unambiguous:

- worst **build**: 9.9 ms — **zero** frames over budget on the UI thread
- worst **raster**: 20.4 ms — **26** frames over budget

Worst raster frames during the scroll: `30.1, 20.4, 17.7, 17.2, 16.8, 15.5, 14.6, 14.1 ms`.

The UI thread is entirely healthy here. This is GPU/paint cost, so widget-level
optimisation would do nothing — it needs a painting fix.

**Cause.** Each grid cell is a full `HanjCard`, and `hanj_card.dart` paints through
`MaskFilter.blur`, which forces a real blur pass per painted path:

- [hanj_card.dart:895](lib/features/cards/hanj_card.dart#L895) and
  [:903](lib/features/cards/hanj_card.dart#L903) — `_GlowBorderPainter` (this is the
  visible rarity glow; on screen the RARE cards' blue halo is exactly this)
- [hanj_card.dart:1174](lib/features/cards/hanj_card.dart#L1174) — `_DashedBorderPainter`

On top of that, **there is no `RepaintBoundary` anywhere in the app for performance
purposes.** All eight in the tree exist to support `toImage()` screenshot capture
([card_share.dart:187](lib/features/cards/card_share.dart#L187),
[ranking_cards.dart:170/397/671](lib/features/profile/ranking_cards.dart#L170),
[share_card.dart:135](lib/widgets/share_card.dart#L135)). Grid cells share one layer, so
any repaint re-runs every card's blur.

**Proposed fix, in order:** wrap each `_HanjCardTile` in a `RepaintBoundary`
([card_collection_screen.dart:295](lib/features/cards/card_collection_screen.dart#L295)) —
about 3 lines, and it caches each card's painted output so scrolling stops re-blurring.
Re-measure. If that isn't enough, the glow is a static decoration per rarity and could be
pre-rendered once per tier rather than blurred per card per frame.

**No design change is implied** — the rarity glow stays exactly as it looks now. Effort:
~5 lines for the boundary, and measure before doing anything more.

### S2-3 · Profile has the single worst raster frame in the app (40.1 ms) — **measured**

Opening Profile produced a **40.1 ms raster frame** — 3.6× budget — plus 4 build frames
over budget.

**Cause:** the Profile screen renders a **live, full `HanjCard`** at 0.52 scale
([profile_screen.dart:469-479](lib/features/profile/profile_screen.dart#L469-L479)) — the
LEGENDARY card visible on screen — carrying the same `MaskFilter.blur` painters as S2-2,
again with no `RepaintBoundary`, and additionally being scaled.

**Proposed fix:** same `RepaintBoundary` treatment. Because this card is static once
built, it benefits even more than the grid. Effort: ~3 lines. Fix S2-2 and S2-3 together
and re-measure both.

### S2-4 · Mount cost, not scroll cost, is what hurts — **measured**

Worth stating plainly because it redirects effort: **scrolling is mostly fine.** Home
scroll produced *zero* frames over 8 ms. The expensive moments are all **first mount** of
a screen — Home 38.3 ms build, detail open 44.0 ms, collection open 34.0 ms, Profile
30.7 ms.

And mount cost is paid more often than it should be, because `MainScreen`
([main_screen.dart:36](lib/features/main_screen.dart#L36)) swaps `_screens[_selectedIndex]`
directly instead of using an `IndexedStack`, so every tab switch destroys and rebuilds the
tab root. The measurement confirms it: **returning to Home cost another 28.7 ms build
frame and re-fired 3 AniList requests** (§3).

**Proposed fix:** `IndexedStack`. This is a behaviour change (tabs would keep their scroll
position and state), so it is your call rather than an obvious win — but it removes the
repeated mount cost and the repeated network fetches in one move. Effort: ~5 lines.
Flagged in `AUDIT.md` as S4-5; the measurement is what upgrades it.

---

## 3. Network — measured

Instrumented `AnilistService` with a request counter, then drove a **cold** app process
through every tab.

| Action | AniList requests |
|---|---|
| Home — first mount | **3** |
| Home — scroll | 0 |
| Discover — open + scroll | 0 |
| Pulse — open | 0 |
| List — open | 0 |
| Profile — open | 0 |
| **Home — return to tab** | **3** |
| Anime detail — open | **2** |
| *Whole tour total* | *6 via `AnilistService` + 6 external throttled calls* |

### S3-1 · The AniList caches seed the UI but never suppress a request — **measured**

You asked whether the caching is working or just present. **It is present and it is not
working** — and it is a precise, structural distinction rather than a vague one:

> The static caches are **display caches, not request caches.** They exist to prevent a
> blank flash on rebuild. Not one of them short-circuits the fetch.

The proof is in the table: **returning to the Home tab fired the same 3 requests again.**
Nothing had changed and the data was already in memory.

The code says the same thing. In `upcoming_anime.dart`, `initState` seeds display state
from the static cache ([:43-50](lib/features/home/upcoming_anime.dart#L43-L50)) —
then calls `_loadAnime()` unconditionally ([:52](lib/features/home/upcoming_anime.dart#L52)).
`_loadAnime` only ever *writes* `_cachedThis`/`_cachedNext`
([:98](lib/features/home/upcoming_anime.dart#L98),
[:119](lib/features/home/upcoming_anime.dart#L119)); it never reads them to decide whether
to skip. The second widget in the same file
([:486-500](lib/features/home/upcoming_anime.dart#L486-L500)) does exactly the same, and
`discovery_screen.dart` ([:471-504](lib/features/discovery/discovery_screen.dart#L471-L504))
follows the identical pattern.

There is no TTL and no in-flight de-duplication anywhere in this layer.

**There is also a duplicate.** `UpcomingAnimeRow._loadAnime` calls
`getSeasonal(currentSeason, year)` ([:96](lib/features/home/upcoming_anime.dart#L96)) and
the widget at [:499](lib/features/home/upcoming_anime.dart#L499) calls
`getSeasonal(currentSeason, year)` with **identical arguments** on the same screen.
`AnilistService` has **no cache of its own**, so both hit the network. One of Home's three
requests is redundant on every single mount.

**Proposed fix:** give `AnilistService` a small keyed in-memory cache with a TTL —
one `Map<String, (DateTime, List<Anime>)>` in front of `_post`, keyed on the query +
variables. This fixes the duplicate, the tab-return refetch, and every other caller at
once, without touching the throttle, the backoff, or any screen. **Expected: Home's 3
requests per mount → 0 on any mount within the TTL; the identical-argument duplicate
eliminated permanently.** Effort: ~30 lines in one file.

Do **not** fix this by deleting the fetches — the stale-while-revalidate behaviour is
deliberate and it is what keeps the screens populated when AniList rate-limits. Add the
cache in front; leave the refresh path alone.

### S3-2 · `OfflineCacheService` works, but only one feed uses it — **measured + read**

You asked whether it is genuinely serving reads. **It is** — Home's trending feed was
served from it (that is why the cold-start count is 3 and not 4; `getTrending` hit the
1-hour `SharedPreferences` cache and made no request). The service itself is well built:
memory → disk with TTL → network, with stale fallback on both empty responses and
exceptions.

The problem is reach. It is called from exactly **two** places for reads
([home_screen.dart:60](lib/features/home/home_screen.dart#L60) and
[:2120](lib/features/home/home_screen.dart#L2120)), while **twelve** screens instantiate
`AnilistService()` directly and bypass it entirely. It exposes `getPopular`, `getTopRated`
and `getSeasonal` that almost nothing calls — `getSeasonal` in particular is exactly what
the three uncached seasonal fetches in S3-1 need.

**Proposed fix:** point `upcoming_anime.dart` and `discovery_screen.dart` at
`OfflineCacheService.getSeasonal` instead of `AnilistService.getSeasonal`. That reuses
working, tested code rather than adding anything. It overlaps with S3-1 — do whichever
you prefer, not both. Effort: ~10 lines.

One small real cost inside it: `getCachedAnimeDetail`
([offline_cache_service.dart:52](lib/services/offline_cache_service.dart#L52)) has **no
memory layer and no TTL**, so every anime detail open does a `SharedPreferences` disk read
plus a JSON decode, and `cacheAnimeDetail` writes on every open
([anime_detail_screen.dart:65](lib/features/anime_detail/anime_detail_screen.dart#L65)).
Small, but it is on the path of the 44.0 ms detail-open frame.

### S3-3 · Anime detail fires 2 AniList requests on open, one of them unthrottled — **measured**

Measured 2 requests on open, matching the two call sites: `_fetchAiringHttp`
([:174](lib/features/anime_detail/anime_detail_screen.dart#L174)) and `_loadGalleryImages`
([:217](lib/features/anime_detail/anime_detail_screen.dart#L217)).

The first **bypasses the throttle entirely** — this is **S2-3 in `AUDIT.md`**, and it is
worth restating here because the performance framing makes it worse than it looked: it is
not an occasional call, it fires on *every* detail open, and detail opens are the most
common navigation in the app. Two lines to fix, and the method 40 lines below already
shows the correct pattern.

### S3-4 · Firestore — no calls inside `build()` on the hot path

You asked specifically about Firestore or AniList calls inside `build()`. **There are no
AniList calls in any `build()`.** There are five Firestore listeners constructed in
`build()` — `arcs_screen.dart` ×3, `main.dart` `_OnboardingGate`, and
`episode_discussion_screen.dart` — which re-subscribe on every rebuild. That is
`AUDIT.md` S4-2; none of them is on a hot path and none showed up in these measurements,
so I am not raising its priority on performance grounds.

**One over-fetch worth noting**, from reading rather than timing: Home awaits both
`getAnimeByStatus('WATCHING').first` and `getAnimeList().first`
([home_screen.dart:62-66](lib/features/home/home_screen.dart#L62-L66)). The second returns
the whole list, which already contains every WATCHING document — so the WATCHING subset is
fetched twice, in two separate queries, on every Home mount. Filtering the full list
locally would remove one Firestore query. *Suspected* — Firestore's local cache may already
absorb most of the cost; measuring it needs a cold-cache device run with Firestore logging.

---

## 4. Images, lists, and size

### S4-1 · 47 network-image sites, none with any decode sizing — **counted, impact unmeasured**

Every network image in the app is decoded at full source resolution:

| | count |
|---|---|
| `CachedNetworkImage` | 38 |
| `Image.network` | 9 |
| **with `memCacheWidth` / `cacheWidth` / `ResizeImage`** | **0** |

**But I want to be careful here, because the obvious conclusion is wrong on this device.**

The usual failure — full-res art decoded into small thumbnails — depends on the image
being *larger* than its display box. On the CPH2573 it often isn't. The screen is 1440
physical px at DPR 4.0, so a 2-column grid cell is roughly **680 physical px wide**, while
AniList's `coverImage { large }` is about **450 px**. In the card grid the covers are being
*upscaled*, not downscaled. Adding `memCacheWidth` there would save nothing and would make
the art softer.

Where it genuinely does apply is the small stuff — avatars and list-row thumbnails
(`_Avatar` in [anime_detail_screen.dart:1145](lib/features/anime_detail/anime_detail_screen.dart#L1145),
staff and character rows, activity feed rows) — which request `image { medium }` or
`coverImage { large }` and paint them into boxes a fraction of that size.

**This is why I am not ranking it.** The measurements do not support it being a top cost:
Home scroll was completely clean, and the one screen that *is* raster-bound (card
collection, S2-2) is bound by blur, not by image decode — its cards mostly show glyphs and
gradients, not cover art.

**Proposed action: measure before changing anything.** Add `memCacheWidth` to the *small*
thumbnail sites only, and re-measure the specific screens they appear on. Do not do a
sweeping 47-site change on theory. *Suspected, not measured.*

### S4-2 · `shrinkWrap: true` defeats lazy building in several nested lists — **read, unmeasured**

47 lazy builders vs 14 eager lists overall, which is healthy. But `shrinkWrap: true`
combined with `NeverScrollableScrollPhysics` forces a `.builder` list to lay out **all**
its children immediately, which cancels the laziness:

- [staff_detail_screen.dart:306](lib/features/staff_detail/staff_detail_screen.dart#L306)
  and [:426](lib/features/staff_detail/staff_detail_screen.dart#L426) — two grids fed by
  AniList queries with `perPage: 50`, so up to **100 cells built eagerly**, each with a
  network image
- [anime_detail_screen.dart:844](lib/features/anime_detail/anime_detail_screen.dart#L844),
  [:976](lib/features/anime_detail/anime_detail_screen.dart#L976),
  [:1047](lib/features/anime_detail/anime_detail_screen.dart#L1047),
  [:1175](lib/features/anime_detail/anime_detail_screen.dart#L1175) — four in the tabs of
  the screen that already showed a 44.0 ms open frame

The detail-open cost is measured; **attributing it to these lists is not** — I did not
isolate them. Staff detail I never opened at all.

**To confirm:** open a staff page for a prolific director on the device and watch the
build times; if they spike on open and not on scroll, these grids are the cause. Command
in §8.

### S4-3 · Bundle sizes — measured

| Artifact | Size |
|---|---|
| Profile APK, arm64 only | **39.6 MB** |
| Web release `main.dart.js` | **4.03 MB** |
| Web release `build/web` total | 42.6 MB (37 MB of it CanvasKit) |
| Web profile `main.dart.js` | 13.1 MB (profile builds are not comparable — noted so nobody quotes it) |

No action proposed; these are the baseline for judging the font change in §6.

**One build warning worth a look**, surfaced by both web builds:

```
Expected to find fonts for (MaterialIcons, packages/cupertino_icons/CupertinoIcons),
but found (MaterialIcons).
```

`cupertino_icons` is declared but its font is not bundled. Any Cupertino icon used
anywhere will render as a blank box. Costs nothing to leave, but it means the dependency
is either unused (removable) or quietly broken.

---

## 5. Checked and cleared

Things that looked like performance problems, or that the brief flagged as suspects, which
I measured or read and found **fine**. Recorded so nobody spends time on them:

- **The particle painter does not over-repaint.** You asked specifically. `_ParticlePainter.shouldRepaint`
  ([card_unlock_overlay.dart:329](lib/features/cards/card_unlock_overlay.dart#L329)) is
  `old.progress != progress` — correct. The static card painters all return `false`
  ([hanj_card.dart:924, 948, 1085, 1101, 1119, 1142, 1178](lib/features/cards/hanj_card.dart#L924)).
  The blur cost in S2-2 is from painting them *at all*, not from repainting them needlessly.
- **Scrolling is not a problem.** Home scroll: 0 frames over 8 ms. The jank is at mount.
- **Search is properly debounced** — 600 ms with a timestamp guard
  ([search_screen.dart:148-160](lib/features/search/search_screen.dart#L148-L160)). No
  request-per-keystroke.
- **The AniList throttle itself is correctly implemented** — reservation queue, adaptive
  backoff, `Retry-After` honoured. `AUDIT.md` §4 covers the callers that bypass it; the
  mechanism is sound and **must not be weakened** for any fix in this report.
- **`PulseService` is the model network client** — throttle, backoff, timeout, 2-hour TTL
  cache. It made **zero** requests when Pulse was opened during the tour, because the cache
  worked. This is the pattern S3-1 should follow.
- **No AniList calls inside any `build()`.**
- **`OfflineCacheService` genuinely serves reads** (S3-2) — it is under-used, not broken.
- **Timers are all cancelled correctly** (`AUDIT.md` §3-B). S2-1 is about rebuild *scope*,
  not a leak.

---

## 6. Typography

### S6-1 · The app ships **six** font families, not three — **counted**

This is the finding that matters most, and it cuts across both halves of the brief.

| Family | Call sites | In the design system? |
|---|---|---|
| DM Sans | 84 | ✅ body |
| Playfair Display | 55 | ✅ headings |
| Space Grotesk | 44 | ✅ numerals/mono |
| **Inter** | **35** | ❌ **not in the system** |
| **Space Mono** | **9** | ❌ **not in the system** |
| **Noto Serif JP** | **4** | ❌ **not in the system** |

And it goes deeper than stray call sites — **the theme itself is wrong.**
`AppTheme.sans()`, the app's body-text helper, resolves to **`GoogleFonts.inter`**
([app_theme.dart:68-79](lib/core/theme/app_theme.dart#L68-L79)). So does the entire
`TextTheme` body and title tier — `titleLarge`, `titleMedium`, `titleSmall`, `bodyLarge`,
`bodyMedium`, `bodySmall` are all Inter
([app_theme.dart:111-122](lib/core/theme/app_theme.dart#L111-L122)).

**DM Sans does not appear in `app_theme.dart` at all.**

So the app is in a split state: the design system says DM Sans for body, the theme
implements Inter, and 84 call sites across the screens bypass the theme to use DM Sans
directly. Both fonts ship. `AppTheme.sans` is called **224 times**, so Inter is not a
fringe case — it is arguably the app's dominant body font today.

I am **not** proposing a fourth family or any substitution — the opposite. This is a
recommendation to make the code match the three families you already chose.

**Proposed fix:** repoint `AppTheme.sans()` and the six `TextTheme` entries from
`GoogleFonts.inter` to `GoogleFonts.dmSans`. That is **7 lines** and it converts 224 call
sites to DM Sans at a stroke, eliminating Inter from the app.

**This changes how most of the app looks** — DM Sans and Inter have different metrics — so
it wants your eyes on it, on device, before it lands. It is not a silent refactor.

Space Mono (9 sites) is confined to `hanj_card.dart` — the collectible card, which is a
deliberate artefact people share, so there is a real argument for it as part of the card's
identity rather than the app's. Noto Serif JP (4 sites) is in `tomo_screen.dart` for
Japanese glyphs. **Your call on both; I am flagging, not proposing.** They matter mainly
because of §6-4.

### S6-2 · 61 distinct font sizes across three roles — **counted**

Catalogued all 706 text styles in the app. Excluding the share/card canvases (which are
rasterised at 3.2× and legitimately use small values):

| Role | Distinct sizes | Values |
|---|---|---|
| Serif (Playfair) | **23** | 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 48, 50, 56, 72, 120 |
| Sans (DM Sans / Inter) | **16** | 9, 10, 11, 11.5, 12, 12.5, 13, 13.5, 14, 14.5, 15, 16, 17, 18, 20, 22 |
| Mono (Space Grotesk) | **22** | 7, 8, 9, 9.5, 10, 11, 12, 13, 13.5, 14, 15, 16, 17, 18, 20, 22, 26, 27, 28, 30, 52, 54 |

The half-point values — 9.5, 11.5, 12.5, 13.5 — and pairs like 26/27/28 are the signature
of per-screen nudging rather than a scale. Roughly a third of all text styles (231 of 706)
bypass the `AppTheme` helpers and call `GoogleFonts` directly, which is how the sprawl got
in.

**Proposed consolidated scale**, derived from what is actually in use (not invented):

| Token | Family | Size | Weight | Replaces |
|---|---|---|---|---|
| `display` | Playfair | 36 | w700 | 34–44 |
| `headline` | Playfair | 28 | w600 | 26–32 |
| `title` | Playfair | 20 | w600 | 20–24 |
| `subtitle` | DM Sans | 16 | w600 | 15–18 |
| `body` | DM Sans | 14 | w400 | 13.5–15 |
| `caption` | DM Sans | 12 | w400 | 11.5–13 |
| `label` | Space Grotesk | 11 | w500 | 9.5–13 |
| `numeral` | Space Grotesk | 20 | w700 | display numerals |

The outliers at 120, 72, 56, 52 are hero moments (the Profile "165 Titles" counter is one)
and should stay as deliberate one-offs, not be forced into the scale.

Effort: the scale itself is ~40 lines in `app_theme.dart`. Migrating 706 call sites is
**far** beyond a 200-line batch and should not be attempted in one go — land the scale,
then migrate per screen as you touch each one.

### S6-3 · Readability — **counted**

- **Playfair Display below 18 px: 20 live-UI sites.** It is a display serif with fine
  hairlines; below ~18 px on a phone the thin strokes break up. Worst offenders at **13 px**:
  [anime_detail_screen.dart:774](lib/features/anime_detail/anime_detail_screen.dart#L774),
  [home_screen.dart:2021](lib/features/home/home_screen.dart#L2021). Then 15 px in
  [tonight_watch.dart:458](lib/features/home/tonight_watch.dart#L458) and
  [arcs_screen.dart:780](lib/features/social/arcs_screen.dart#L780), and eleven at 16 px
  (Pulse, Discover, Social, Soulmatch ×4, Taste Profile, Edit Profile).
  **Proposed:** anything under 18 px that is not a heading should be DM Sans. Playfair
  earns its place at 18 px and up.
- **Body text below 14 px: 174 live-UI sites** — 1 at 9 px, 12 at 10 px, 23 at 11 px,
  61 at 12 px, 68 at 13 px. The 12–13 px band is defensible for metadata; **the 9–11 px
  band (36 sites) is too small for anything a user needs to read** on a phone.
- **Line height:** `AppTheme.sans` and `AppTheme.serif` both take `height` as an *optional*
  parameter defaulting to null, so most text inherits the font's default leading. The
  `TextTheme` body entries do set sensible values (1.6 / 1.5 / 1.4), but only text that
  actually reads from the theme gets them — and per §6-1 most does not. Long description
  text set in Playfair with default leading is the specific combination to look at.

### S6-4 · Bundling the fonts — **the answer is "not yet, and here is why"**

You asked me to measure which weights are actually used before bundling, and to tell you
if the result exceeds ~1.5 MB rather than assume. **It does, and by a lot — so I have not
proposed the change as specified.**

Measured weight requirements across the codebase:

| Family | Weights in use | Files needed |
|---|---|---|
| Playfair Display | 400, 600, 700, 800, 900 | 5 |
| DM Sans | 400, 500, 600, 700 | 4 |
| Space Grotesk | 400, 500, 600, 700 | 4 |
| Inter | 400, 500, 600, 700 | 4 |
| Space Mono | 400, 700 | 2 |
| Noto Serif JP | 700 | 1 |
| | | **20 files** |

**Two things make this fail the 1.5 MB test as things stand:**

1. **Six families, 20 files.** Latin static TTFs run roughly 100–200 KB each, so the five
   Latin families alone land around **1.5–2.5 MB** — at or over your line before Noto
   Serif JP is counted.
2. **Noto Serif JP is a CJK font.** A full-coverage static TTF is **several megabytes on
   its own** — it would dominate the APK. Bundling it for **4 call sites** is not a
   sensible trade at any size.

**So the sequencing matters, and it is the actual recommendation:**

- **Do S6-1 first** (repoint `AppTheme.sans` to DM Sans, ~7 lines). That removes Inter —
  4 files — and takes the bundle to three families.
- **Then decide on Space Mono and Noto Serif JP.** If Noto Serif JP stays, it stays
  network-loaded; do not bundle it.
- **Then bundle** Playfair (400/600/700 — the 800/900 weights are 3 call sites total and
  could be dropped), DM Sans (400/500/600/700), Space Grotesk (400/500/600/700) =
  **11 files, estimated ~1.2–2.2 MB.** Variable-font versions would be smaller still and
  are worth pricing first.

**I have deliberately not given you a precise MB figure**, because I could not measure one
— the font files are fetched at runtime by `google_fonts` and cached in the app's private
storage, which a profile build does not let me read. The ranges above are estimates from
typical file sizes and are **labelled as such**. §8 has the one command that produces the
real number once the files are downloaded.

The underlying problem you described is real and worth fixing — on a cold start with poor
connectivity, text paints in a fallback and reflows when six families' worth of font files
arrive. **Six families makes that reflow worse than three would.** Which is the same
conclusion as S6-1, arrived at from the other direction.

---

## 7. Ranked by measured impact

Ranked by what was measured, not by ease. Everything in the top group has a number
attached.

| # | Impact | Finding | Measurement | Files | Effort |
|---|---|---|---|---|---|
| **P1** | 🔴 **~17 ms UI-thread work every second, on an idle screen** | Countdown `setState` rebuilds the whole 2,190-line detail screen | 15 janky frames in 15 s idle, exactly 1/s, median build 17 ms vs 11.1 ms budget | [anime_detail_screen.dart:162, 453, 686](lib/features/anime_detail/anime_detail_screen.dart#L162) | ~25 ln |
| **P2** | 🔴 **~1.0 s of a 1.9 s startup** | `NotificationService.init()` awaited before `runApp()` | 989 ms / 1,106 ms across two runs; 53–84% of pre-`runApp` time | [main.dart:63](lib/main.dart#L63) | ~10 ln |
| **P3** | 🟠 **26 over-budget raster frames per scroll** | Card grid re-blurs every cell; no `RepaintBoundary` for paint isolation | 183 frames >8 ms, worst raster 20.4 ms, **0** build frames over budget | [card_collection_screen.dart:295](lib/features/cards/card_collection_screen.dart#L295), [hanj_card.dart:895](lib/features/cards/hanj_card.dart#L895) | ~5 ln |
| **P4** | 🟠 **Worst single frame in the app, 40.1 ms** | Profile renders a live blurred `HanjCard`, unisolated | 5 raster frames over budget on open | [profile_screen.dart:469-479](lib/features/profile/profile_screen.dart#L469-L479) | ~3 ln |
| **P5** | 🟠 **3 redundant AniList requests per Home mount** | Static caches seed display but never suppress the fetch; one request is an exact duplicate | 3 on first mount, **3 again on tab return**; 0 needed | [upcoming_anime.dart:52, 96, 499](lib/features/home/upcoming_anime.dart#L52), [anilist_service.dart](lib/services/anilist_service.dart) | ~30 ln |
| **P6** | 🟡 **1 unthrottled request per detail open** | `_fetchAiringHttp` bypasses the throttle (= `AUDIT.md` S2-3) | 2 requests measured on open, 1 outside the queue | [anime_detail_screen.dart:174](lib/features/anime_detail/anime_detail_screen.dart#L174) | 2 ln |
| **P7** | 🟡 **Repeated mount cost + repeated fetches** | `MainScreen` rebuilds tab roots instead of `IndexedStack` | Home return: 28.7 ms build + 3 requests | [main_screen.dart:36](lib/features/main_screen.dart#L36) | ~5 ln |
| **P8** | 🟡 **Design-system drift** | `AppTheme.sans` + whole `TextTheme` use Inter, not DM Sans; 6 families ship | 35 Inter sites, 224 `AppTheme.sans` calls, 6 families counted | [app_theme.dart:68-122](lib/core/theme/app_theme.dart#L68-L122) | ~7 ln |
| **P9** | 🟡 **Readability** | Playfair <18 px ×20; body <14 px ×174 (36 of them 9–11 px) | Counted across 706 styles | many | per screen |

### Suspected — no number yet

| Finding | What would confirm it | Files |
|---|---|---|
| Unsized image decode on **small** thumbnails (47 sites have no sizing, but grid covers are *upscaled* on this device — see S4-1) | Add `memCacheWidth` to avatar/list-row sites only, re-measure those screens | 47 sites |
| `shrinkWrap` grids building up to 100 cells eagerly | Open a prolific director's staff page on device, watch build times on open vs scroll | [staff_detail_screen.dart:306, 426](lib/features/staff_detail/staff_detail_screen.dart#L306) |
| Home fetches the WATCHING subset twice | Cold-cache device run with Firestore query logging | [home_screen.dart:62-66](lib/features/home/home_screen.dart#L62-L66) |
| `getCachedAnimeDetail` disk read + JSON decode on every detail open | Instrument around the call; it is on the 44 ms open path | [offline_cache_service.dart:52](lib/services/offline_cache_service.dart#L52) |
| Exact bundled-font size | Command in §8 | `pubspec.yaml` |

### Suggested batches

1. **`perf/countdown-rebuild-scope`** — P1 alone. Biggest measured win, self-contained. Re-measure the 15 s idle test.
2. **`perf/startup-defer-notifications`** — P2 alone. Re-measure with `--trace-startup`.
3. **`perf/card-repaint-boundaries`** — P3 + P4 together, same root cause. Re-measure both scroll and Profile open.
4. **`perf/anilist-request-cache`** — P5 + P6. **Do not weaken the throttle or the stale fallbacks.**
5. **`type/dm-sans-body`** — P8 alone. Needs your visual sign-off on device before landing.

P7 and P9 are judgement calls rather than clear wins — P7 changes tab behaviour, P9 is a
per-screen migration. Neither belongs in a batch until you have decided.

---

## 8. Repro commands

Everything above, so you can re-run any of it — and so phase two has a before/after
procedure.

**Startup (the P2 measurement):**
```
flutter run --profile --trace-startup --no-resident -d 92cd8b21
type build\start_up_info.json
```
Read `timeToFirstFrameMicros`. Baseline: **1,964,334 µs** cold / **1,878,892 µs**.

**Per-screen frame timings (P1, P3, P4):** re-add the temporary callback in `main()` —
```dart
SchedulerBinding.instance.addTimingsCallback((timings) {
  for (final t in timings) {
    final b = t.buildDuration.inMicroseconds / 1000.0;
    final r = t.rasterDuration.inMicroseconds / 1000.0;
    if (b > 8 || r > 8) debugPrint('PERFFRAME build=$b raster=$r');
  }
});
```
then `adb logcat -v time | grep PERFFRAME`. **Remove it before committing.**

**The P1 idle test — the cleanest single check:**
```
adb shell am start -n com.anitrack.anime_tracker/.MainActivity
```
Open any title showing **ON AIR**, then do not touch the screen for 15 seconds.
Before: 15 janky frames, one per second, ~17 ms build. After the fix: expect 0.

**Driving the device over adb** (nav bar is at `y=2978`; tab x-centres 144 / 431 / 719 /
1007 / 1295). Keep swipes ending above `y≈900` — swiping into the bottom gesture zone
sends the app to the launcher, which cost me one measurement run.

**Card collection scroll (P3):**
```
adb logcat -c
```
Profile tab → Collection → scroll 4 times. Baseline: 183 frames >8 ms, 26 over 11.1 ms,
worst raster 20.4 ms.

**AniList request count (P5):** add to `AnilistService._post`, before the `http.post`:
```dart
debugPrint('PERFNET anilist_post');
```
Baseline: 3 on Home first mount, **3 again on returning to the Home tab**, 2 on detail open.

**Exact bundled-font size (S6-4):** once you have the `.ttf` files in `assets/fonts/`:
```
du -sh assets/fonts
flutter build apk --release --analyze-size --target-platform android-arm64
```
Compare against the current profile APK baseline of **39.6 MB**. Note `--analyze-size`
only works on release builds — it errors on profile.

---

## 9. A note on phase two

Your two performance rules are the right ones and I want to be explicit that I have
respected them here:

- **Nothing in this report trades correctness for speed.** No proposed fix weakens the
  throttle, shortens a backoff, drops a `mounted` check, or removes error handling. P5
  explicitly adds a cache *in front of* the existing stale-while-revalidate behaviour
  rather than replacing it, precisely because that behaviour is what stops blank screens
  when AniList rate-limits.
- **Every fix has a before-number and a re-measure step**, listed in §8. If a change does
  not move its number, it should be reverted rather than kept on the theory that it ought
  to help.

Two proposals are **not** silent wins and should not be batched without you looking at
them: **P7** (`IndexedStack`) changes tab behaviour, and **P8** (DM Sans) changes how most
of the app's text looks.

---

*End of phase one. No application code was changed — instrumentation was added, measured,
and reverted; `git diff` against `2489f0a` is empty. Awaiting direction on which items to take.*
