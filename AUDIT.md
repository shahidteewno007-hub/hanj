# Hanj — Phase One Audit

**Date:** 2026-09-03
**Commit audited:** `5a501a5` (Working recovered state, before audit)
**Scope:** read-only. No code was changed. This file is the only addition.

Environment verified: `flutter analyze` (202 issues, 0 errors), `flutter pub outdated`,
and a full read of `lib/` (86 files, ~44k lines), `functions/index.js`, and the Firebase
config. `flutter build web` was not run — the brief only requires it as a phase-two gate.

A note on method: where a finding depended on an external fact rather than on this
codebase, I verified it rather than asserting it. Three things that *looked* like bugs
turned out to be correct and are **not** reported as defects — see
[§9 Checked and cleared](#9-checked-and-cleared). I'd rather hand you a shorter list you
can trust than a longer one you have to re-check.

---

## 1. Architecture map

### Shape

Flutter app, feature-first layout, no state-management framework beyond `provider` for
two app-wide singletons. There is no repository layer and no DI: screens talk to
services directly, and most services are hand-rolled singletons
(`X._(); static final instance = X._();`).

```
main.dart ── Firebase init ─ Crashlytics hooks ─ FCM listeners ─ runApp
   └─ HanjApp (MultiProvider: ThemeProvider, AuthService)
        └─ AuthWrapper          authStateChanges()
             ├─ LoginScreen                        (signed out)
             ├─ EmailVerificationScreen            (unverified, non-Google)
             └─ _OnboardingGate                    (streams users/{uid})
                  ├─ OnboardingScreen              (onboardingComplete != true)
                  └─ MainScreen                    (5-tab NavigationBar)
```

`MainScreen` ([main_screen.dart:24-30](lib/features/main_screen.dart#L24-L30)) holds a
`const` list of the five tab roots and swaps them by index:

| Tab | Screen | Notes |
|---|---|---|
| HOME | `home_screen.dart` (2211 ln) | biggest screen; hub for Tomo/Loki, cards, calendar, import |
| DISCOVER | `discovery_screen.dart` (2019 ln) | seasonal grid + emotional categories, static cross-rebuild cache |
| PULSE | `pulse_screen.dart` (553 ln) | 3 tabs backed by `PulseService` |
| LIST | `my_list_screen.dart` (649 ln) | the user's `animeList` |
| PROFILE | `profile_screen.dart` (1273 ln) | stats, taste profile, ranking cards, founder card |

Everything else is pushed as a route from those five. `MaterialApp.routes` registers
only `/cards` and `/cadre`; every other navigation is an inline `MaterialPageRoute`.
**That asymmetry is the root of finding S2-1.**

`cadre/` is a self-contained subsystem (~5.6k lines: a card-battler with its own models,
rankings, bot, and six screens) reachable via `/cadre`. It has its own dev entry point,
`lib/cadre_dev.dart` (`flutter run -t lib/cadre_dev.dart`) — that file is unreferenced by
design, not an orphan.

### Where state lives

There are four distinct patterns, which is worth knowing before you edit anything:

1. **`provider`** — only `ThemeProvider` and `AuthService`, both app-wide.
2. **Per-screen `setState`** — the overwhelming default. Every screen is a
   `StatefulWidget` fetching into its own fields.
3. **Static caches on State subclasses** — e.g.
   [discovery_screen.dart:471-474](lib/features/discovery/discovery_screen.dart#L471-L474)
   (`_cachedCurrent`, `_cachedForSeason`) and `PulseService._memCache`. These survive tab
   switches, which matters because…
4. **…`MainScreen` does not preserve tab state.** `body: _screens[_selectedIndex]`
   rebuilds the tab root from scratch on every switch (no `IndexedStack`), so scroll
   position and in-flight loads are lost. The static caches in (3) are the workaround
   that makes this tolerable.

### Data reach

**Firestore** — `users/{uid}` is the hub, with subcollections `animeList`, `alerts`,
`activity`, `companion_chat`, `companion_meta`. Top-level collections: `arcs`
(+ `posts` + `replies`), `episodeDiscussions` (+ `votes`), `meta/founders`.
`FirestoreService` (451 ln) covers only `animeList` + activity; **social, arcs,
discussions, cards, and founders all talk to `FirebaseFirestore.instance` directly from
their screens.** There is no single place to change a collection name.

**AniList** — nominally `AnilistService` (GraphQL over `http`), with a shared static
throttle. In practice the throttle is bypassed in five places — see §4.

**Cloud Functions** — `functions/index.js` (1211 ln), v2 API, 10 exports: 6 scheduled,
2 Firestore triggers, 1 callable (`chatWithTomo`). `firebase.json` also declares a
second codebase, `aruku`, whose source directory **does not exist in this repo** (S2-5).

---

## 2. `flutter analyze` — triage

**202 issues: 0 errors, 48 warnings, 154 infos.**

| Bucket | Count | Verdict |
|---|---|---|
| Real bug | 0 | Nothing the analyzer flags is *itself* a live bug |
| Latent bug | 6 | `use_build_context_synchronously` ×4, `invalid_use_of_protected_member` ×2 |
| Recovery debris | 47 | dead code left behind by the reconstruction — diagnostically useful |
| Style noise | 149 | `deprecated_member_use` ×71, `unnecessary_underscores` ×50, etc. |

### Latent (worth fixing)

- **`use_build_context_synchronously` ×4** —
  [home_screen.dart:716](lib/features/home/home_screen.dart#L716) is the one that matters;
  it is analysed in full as **S3-5**. The other three
  ([home_screen.dart:2125, 2128](lib/features/home/home_screen.dart#L2125),
  [edit_profile_screen.dart:133](lib/features/profile/edit_profile_screen.dart#L133))
  are the weaker "guarded by an unrelated `mounted` check" variant — the guard is present
  and does work; the analyzer objects that the `mounted` being tested belongs to a
  different object than the `context` being used. Low risk, cheap to make explicit.
- **`invalid_use_of_protected_member` / `..._visible_for_testing_member`** —
  [email_verification_screen.dart:56](lib/features/auth/email_verification_screen.dart#L56)
  calls `notifyListeners()` on `AuthService` from outside the class. It works today, but
  it is reaching through the `ChangeNotifier` contract to force `AuthWrapper` to
  re-evaluate. If that call is ever dropped in a refactor, **verified users silently stay
  stuck on the verification screen**. Worth replacing with a real method on `AuthService`.

### Recovery debris — read this as evidence, not as lint

47 of the 48 warnings are unused declarations, and they cluster in a telling way:

| File | Dead declarations |
|---|---|
| `anime_detail_screen.dart` | `_selectStatus`, `_StatusTile`, `_StreamingButtons` |
| `hanj_card.dart` | `_PetalParticles`, 4 unused locals |
| `discovery_screen.dart` | `_FilterLabel`, `_PillChip`, `_genres` |
| `profile_screen.dart` | `_MiniBarChart`, `_HanjCardMini` |
| `onboarding_screen.dart` | `_WingMarkPainter` |
| `home_screen.dart` | `_getTimeOfDay` |
| `upcoming_anime.dart` | `_toggleAlert` |

These are **whole widgets that nothing calls** — a status tile, a streaming-links row, a
mini bar chart, a filter chip, a particle effect. That is the fingerprint the brief
predicted: the call sites were lost, the definitions survived. Each one is a hint about a
feature that used to render and now doesn't. **I would not delete a single one of these
until you have compared the app against your APK screenshots** — they are the cheapest
available map of what's missing. Listed as deletion candidates in §8, not acted on.

Five unused *imports* (`cadre_stats.dart`, `google_fonts`, `dart:typed_data` ×2,
`search_screen.dart` in `main_screen.dart`) are the same story: `main_screen.dart` still
imports `SearchScreen` but no longer has a search tab.

### Style noise (no action proposed)

`deprecated_member_use` ×71 is almost entirely `Color.withOpacity` → `.withValues`, plus
`dart:html` in [trailer_launcher_web.dart:2](lib/core/trailer_launcher_web.dart#L2).
Note that `.withOpacity` and `.withValues` coexist in this tree — `card_share.dart` uses
the old one, `main.dart` the new — so a mechanical sweep would touch a lot of files for
no behaviour change. Per the brief, I propose nothing. **`dart:html` is the one to keep an
eye on**: it is not merely deprecated but slated for removal, and when it goes, the web
trailer launcher stops compiling.

---

## 3. Correctness sweep

### S3-A · `setState` after `await` with no `mounted` guard — 18 sites

The single most common defect in the tree. The signature is distinctive:

```dart
// upcoming_anime.dart:152-160
if (_alertedIds.contains(anime.id)) {
  await ref.delete();
  setState(() => _alertedIds.remove(anime.id));   // ← no guard
  if (mounted) {                                   // ← guard, one line later
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
}
```

The snackbar is guarded and the `setState` immediately above it is not — in the same
block, by the same author. This is the "could not see the rest of the file" pattern, and
it repeats across 18 sites:

| File | Lines |
|---|---|
| [upcoming_anime.dart](lib/features/home/upcoming_anime.dart#L154) | 154, 173, 532, 542 |
| [arcs_screen.dart](lib/features/social/arcs_screen.dart#L461) | 461, 467 (+ the `catch` at 470) |
| [anime_calendar_screen.dart](lib/features/calendar/anime_calendar_screen.dart#L78) | 78, 89 |
| [staff_detail_screen.dart:39](lib/features/staff_detail/staff_detail_screen.dart#L39), [studio_detail_screen.dart:43](lib/features/staff_detail/studio_detail_screen.dart#L43) | 39, 43 |
| [social_screen.dart:67](lib/features/social/social_screen.dart#L67), [activity_feed_screen.dart:41](lib/features/social/activity_feed_screen.dart#L41), [soulmatch_screen.dart:87](lib/features/social/soulmatch_screen.dart#L87) | — |
| [taste_profile.dart:53](lib/features/profile/taste_profile.dart#L53), [tonight_watch.dart:219](lib/features/home/tonight_watch.dart#L219), [card_share.dart:102](lib/features/cards/card_share.dart#L102) | — |
| [cadre_clash_screen.dart:168](lib/cadre/screens/cadre_clash_screen.dart#L168), [anime_detail_screen.dart:396](lib/features/anime_detail/anime_detail_screen.dart#L396) | — |

**Failure mode:** tap "alert me", navigate back before the Firestore round-trip lands →
`setState() called after dispose()`. Crashlytics is wired in `main.dart`, so these are
being reported as **fatal** today. Worth checking the Crashlytics dashboard for
`setState() called after dispose` before you decide the priority — it will tell you which
of the 18 users actually hit.

**Fix:** add `if (!mounted) return;` after each await. Mechanical, ~18 lines, zero
behaviour change. This is the highest value-per-line item in the report.

### S3-B · Timers: all four are correctly cancelled

I checked every `Timer` in the tree, including the live episode countdown the brief
called out specifically.

| Timer | Cancelled in `dispose()`? |
|---|---|
| [anime_detail_screen.dart:162](lib/features/anime_detail/anime_detail_screen.dart#L162) — episode countdown | ✅ line 100, and the tick body opens with `if (!mounted) return;` |
| [discovery_screen.dart:488](lib/features/discovery/discovery_screen.dart#L488) — season countdown | ✅ line 510; `_computeCountdown` guards with `mounted` |
| [email_verification_screen.dart:44](lib/features/auth/email_verification_screen.dart#L44) — 4s poll | ✅ line 38, plus self-cancel on success |
| [email_verification_screen.dart:89](lib/features/auth/email_verification_screen.dart#L89) — resend cooldown | ✅ line 39, plus self-cancel at zero |

**The live countdown is clean.** One stylistic caveat: discovery uses
`late Timer _countdownTimer` (non-nullable), so if `initState` ever gains an early return
before line 488, `dispose()` throws `LateInitializationError`. It is assigned
unconditionally today, so this is a note, not a defect.

### S3-C · Firestore listeners started inside `build()` — 5 sites

`StreamBuilder(stream: query.snapshots())` where the query is constructed in `build()`
creates a **new stream object on every rebuild**, so the old listener is torn down and a
new one subscribed each time — spinner flash, duplicated reads, and a listener lifetime
tied to rebuild frequency rather than to the widget.

- [arcs_screen.dart:210-218](lib/features/social/arcs_screen.dart#L210-L218) (arc list),
  [:609](lib/features/social/arcs_screen.dart#L609) (posts),
  [:992](lib/features/social/arcs_screen.dart#L992) (replies) — all three, hence §5-D.
- [main.dart:266](lib/main.dart#L266) — `_OnboardingGate` streams `users/{uid}` from
  `build()`, and it sits under a `Consumer<AuthService>`, so **every `notifyListeners()`
  re-subscribes the user-doc listener.**
- [episode_discussion_screen.dart](lib/features/episode_discussions/episode_discussion_screen.dart) — one site.

`StreamSubscription` handling elsewhere is fine: the only manual one
([connectivity_service.dart:72](lib/services/connectivity_service.dart#L72)) is cancelled
in `dispose()`.

### S3-D · Unawaited future with no error handler → silent data loss

[home_screen.dart:718](lib/features/home/home_screen.dart#L718), in the status-picker
sheet:

```dart
onTap: () async {
  setLocal(() => selected = s.$1);
  await Future.delayed(const Duration(milliseconds: 180));
  Navigator.pop(ctx, s.$1);                                  // ← S3-5, below
  firestoreService.addAnimeToList(anime: anime, status: s.$1); // ← unawaited, uncaught
},
```

Two defects on adjacent lines:

1. **The write is fire-and-forget.** If it fails — offline, rules denial — the UI has
   already shown the new status and closed the sheet. The user believes the anime was
   added. It wasn't. There is no retry and no message.
2. **The failure is reported as a fatal crash.**
   [main.dart:38-41](lib/main.dart#L38-L41) installs
   `PlatformDispatcher.instance.onError` returning `true` with `fatal: true`. An
   unhandled async rejection from this call therefore lands in Crashlytics as a **fatal
   non-crash**. If your Crashlytics fatals look implausibly high, this is a strong
   candidate for why.

This is the only unawaited service write in the tree — everywhere else awaits — so it
reads as an oversight rather than a convention. The comment (`fire and forget — UI already
updated`) shows it was deliberate; the missing `.catchError` is what makes it a bug.

### S3-E · `Navigator.pop(ctx)` across an async gap

Same block, [home_screen.dart:716](lib/features/home/home_screen.dart#L716). `ctx` is the
bottom-sheet context, used after a 180 ms delay with no `mounted` check. If the user
swipes the sheet down during those 180 ms, the sheet is already gone and the `pop`
**operates on the route beneath it** — closing the screen the user is looking at. This is
the analyzer's strongest `use_build_context_synchronously` hit and it is a real
misnavigation, not a lint.

### S3-F · `null!` assertions that can genuinely be null

`FirestoreService` uses a getter that re-reads `currentUser` on every access:

```dart
CollectionReference? get _animeListRef {
  if (_uid == null) return null;
  return _firestore.collection('users').doc(_uid).collection('animeList');
}

// then, 18 times:
if (_animeListRef == null) return;
await _animeListRef!.doc(...).set(...);   // ← different evaluation of the getter
```

The null check and the `!` dereference **evaluate the getter twice**. If auth state flips
to signed-out between them (sign-out, token revocation, account deletion), the `!` throws.
Narrow window, but `delete_account_screen.dart` exists, which is exactly the flow that
signs a user out while list writes may be in flight. **Fix is one local variable per
method**, not a redesign: `final ref = _animeListRef; if (ref == null) return;`.

The analyzer separately flags 5 `unnecessary_non_null_assertion` — `!` on receivers that
*can't* be null ([stats_screen.dart:103,116](lib/features/stats/stats_screen.dart#L103),
[soulmatch_screen.dart:34](lib/features/social/soulmatch_screen.dart#L34),
[anime_detail_screen.dart:728](lib/features/anime_detail/anime_detail_screen.dart#L728),
[anilist_service.dart:141](lib/services/anilist_service.dart#L141)). Those are harmless
noise, the mirror image of the real problem above.

Also unguarded: `int.parse(widget.anime.id)`
([anime_detail_screen.dart:395](lib/features/anime_detail/anime_detail_screen.dart#L395))
and `int.parse(animeId)` in `AnilistService` — `Anime.id` is a `String`, and a
non-numeric id throws rather than returning null. AniList ids are always numeric today,
so this is latent only.

### S3-G · Startup can block on the notification permission prompt

[main.dart:63](lib/main.dart#L63):

```dart
await NotificationService.instance.init();   // ← awaited before runApp()
```

`init()` opens with `await _fcm.requestPermission(...)`
([notification_service.dart:35](lib/services/notification_service.dart#L35)) — the OS /
browser permission dialog. **That future does not complete until the user answers.** Until
it does, `runApp()` is never reached and the app shows a blank screen.

Contrast `ConnectivityService.init()` on the line above, which wraps its check in a
3-second timeout precisely to avoid this. The notification path has no timeout. Given the
brief mentions blank screens were a real bug here once, this is worth ruling in or out.

Two secondary issues in the same file: the permission prompt fires on **first app open**,
before the user has any context for it (worse conversion, and on iOS you only get one
shot); and `_saveToken` is invoked unawaited from three places in `auth_service.dart`
(same uncaught-rejection class as S3-D, lower stakes).

### S3-H · Unclosed HTTP clients

[anime_detail_screen.dart:174 and :217](lib/features/anime_detail/anime_detail_screen.dart#L174)
each call `http.Client().post(...)` — a fresh client per invocation, never `.close()`d.
Each leaks its connection pool until GC. Negligible on web; on mobile it holds sockets
open. Every other call site uses the top-level `http.post`, which manages its own client
correctly.

---

## 4. AniList integration — the throttle is bypassed in 5 places

The throttle itself
([anilist_service.dart:12-44](lib/services/anilist_service.dart#L12-L44)) is **correctly
implemented**. It is a static reservation queue: `_reserveSlot()` claims the next slot and
pushes `_nextSlotTime` forward by the gap, so concurrent callers queue rather than
collide; `backoff()` enters a 60 s slow window (2000 ms gap) on a 429 and honours
`Retry-After`. `_post()` retries twice. The logic is sound and the public
`AnilistService.throttle()` / `.backoff()` hooks exist specifically so direct callers can
join the same queue.

**The problem is that most direct callers don't use them.** There are 9 AniList POST sites
outside `AnilistService`:

| Site | `throttle()` | `backoff()` | timeout | Verdict |
|---|:---:|:---:|:---:|---|
| [pulse_service.dart:24](lib/services/pulse_service.dart#L24) | ✅ | ✅ | ✅ 15 s | **Correct — use as the reference** |
| [discovery_screen.dart:630](lib/features/discovery/discovery_screen.dart#L630) | ✅ | ✅ | ✅ | Correct |
| [home_screen.dart:1878](lib/features/home/home_screen.dart#L1878) | ✅ | ✅ | ✅ | Correct |
| [anime_detail_screen.dart:217](lib/features/anime_detail/anime_detail_screen.dart#L217) `_loadGalleryImages` | ✅ | ❌ | ✅ | Throttled, ignores 429 |
| **[anime_detail_screen.dart:174](lib/features/anime_detail/anime_detail_screen.dart#L174) `_fetchAiringHttp`** | ❌ | ❌ | ✅ 8 s | **Bypass — see below** |
| **[anime_calendar_screen.dart:113](lib/features/calendar/anime_calendar_screen.dart#L113)** | ❌ | ❌ | ❌ | **Bypass, and no timeout** |
| **[anilist_import_screen.dart:112](lib/features/import/anilist_import_screen.dart#L112)** | ❌ | ❌ | ❌ | **Bypass, and no timeout** |
| **[edit_profile_screen.dart:72](lib/features/profile/edit_profile_screen.dart#L72)** | ❌ | ❌ | ❌ | **Bypass, and no timeout** |
| **[cadre_roster_service.dart:197](lib/cadre/services/cadre_roster_service.dart#L197)** | ❌ | ❌ | ✅ 20 s | **Bypass** (does surface 429 to the user) |

**`_fetchAiringHttp` is the one to fix first.** It runs on *every* anime detail open, it
is the fetch that drives the live countdown the brief cares about, and it is completely
outside the queue. Open six anime in quick succession from a grid and you fire six
unthrottled requests that also steal capacity from the throttled ones — the exact
"blank screens under load" signature described in the brief. Two lines to fix
(`await AnilistService.throttle();` before the post, `AnilistService.backoff()` on a 429),
and the sibling method 40 lines below already shows the pattern.

The three no-timeout sites are a second concern in their own right: a hung AniList
connection leaves the import screen and the calendar spinning forever with no way out.

**Caches.** The brief refers to "in-memory caches" — worth being precise, because they are
not where you might expect. `AnilistService` itself has **no cache at all**; every call
hits the network. The caching lives in two other places: `PulseService._memCache` (2-hour
TTL, keyed per feed) and the static fields on `_DiscoveryScreenState` (seasonal lists,
keyed by season+year, no TTL — they persist for the process lifetime, so a user who leaves
the app open across a season boundary keeps seeing the old season until relaunch). There
is also `OfflineCacheService` backing `home_screen`'s detail opens. Adding a small
id-keyed cache inside `AnilistService.getAnimeById` would cut redundant traffic further,
but that's an enhancement, not a defect — flagging only.

---

## 5. Known parked issues

### A · Shareable cards — vertical centring on the 9:16 canvas

**Diagnosed. The cause is a single unbalanced spacer.**

`_ShareCanvas` ([card_share.dart:252-390](lib/features/cards/card_share.dart#L252-L390))
is a fixed 340 × 604 box (340 × 16/9 = 604.4 ✓) containing a
`Column(mainAxisAlignment: MainAxisAlignment.center)`. Measuring the children:

| Child | Height |
|---|---|
| rarity eyebrow (11 px) | ~14 |
| gap | 20 |
| card, 300 × 1.15 | 345 |
| gap | 22 |
| name block (fixed) | 62 |
| gap | 26 |
| divider | 1 |
| gap | 16 |
| "Hanj" wordmark (26 px) | ~34 |
| gap | 4 |
| "collect yours" (9.5 px) | ~12 |
| **trailing gap** | **26** |
| **total** | **~582** |

`MainAxisAlignment.center` centres all 582 px inside 604 px → 11 px above, 11 px below.
But the last 26 px is an **empty trailing `SizedBox`** with no counterpart at the top, so
the *visible* content (eyebrow → "collect yours", ~556 px) sits with **11 px above it and
37 px below it.** The artwork reads as roughly 13 px too high — which is exactly the
reported symptom.

**Proposed fix:** delete the trailing `const SizedBox(height: 26)` at
[card_share.dart:388](lib/features/cards/card_share.dart#L388), or balance it with an
identical leading spacer, depending on whether you want the content optically centred or
inset. One line either way.

**Related risk while you're in there:** 582 of 604 px are consumed, leaving 22 px of slack
and no `Flexible`/`Spacer` anywhere. If Google Fonts hasn't loaded when the canvas
rasterises, fallback metrics differ and the Column can overflow — which bakes a yellow-
and-black overflow stripe into the shared PNG. Also note `pixelRatio: 3.2`
([:95](lib/features/cards/card_share.dart#L95)) yields 1088 × 1933, not 1080 × 1920;
`pixelRatio: 1080/340 ≈ 3.176` would hit the exact story size.

### B · Pulse and Discover — SafeArea gap on device

**Diagnosed. There are two stacked causes, and it is invisible in `flutter run -d chrome`
— which is why it survived.**

**Cause 1 — the offline banner always occupies space.**
`OfflineBanner` ([connectivity_service.dart:110-149](lib/services/connectivity_service.dart#L110-L149))
is the body of every tab (`MainScreen`: `body: OfflineBanner(child: ...)`). Its build is:

```dart
Column(children: [
  SlideTransition(position: _slide, child: AnimatedContainer(...)),  // ~33 px tall
  Expanded(child: widget.child),
])
```

`SlideTransition` **translates; it does not remove layout space.** When online, the banner
slides out of view but its ~33 px (8 px padding × 2 + ~17 px content) stays reserved at
the top of every screen, permanently.

**Cause 2 — the top inset is then applied a second time.**
The banner `Column` starts at y=0 and never consumes `MediaQuery.padding`. So when
`PulseScreen` ([pulse_screen.dart:40](lib/features/pulse/pulse_screen.dart#L40)) and
`DiscoveryScreen` ([discovery_screen.dart:59](lib/features/discovery/discovery_screen.dart#L59))
apply `SafeArea(bottom: false)`, they insert the **full status-bar height again**, below
the invisible 33 px strip.

Net on an Android device: **~33 px of dead space plus a full status-bar inset** above the
header. On web `padding.top` is 0 and the banner is the only offender, so the dev loop
shows roughly a third of the problem.

The four tab roots each handle the inset differently, which is worth fixing together:

| Screen | Top-inset handling |
|---|---|
| Pulse, Discover | `SafeArea(bottom: false)` → doubled with the banner strip |
| Home | **none** — `CustomScrollView` with a fixed 16 px top pad; content runs under the status bar |
| My List | `MediaQuery.of(context).padding.top + 4` applied manually ([my_list_screen.dart:173](lib/features/my_list/my_list_screen.dart#L173)) — correct |
| Profile | `SafeArea` on an inner sheet only |

**Proposed fix (two parts, ~15 lines):** give the banner zero height when hidden — wrap it
in a `SizeTransition`, or animate the container's height to 0 — and then standardise on
one inset strategy. My List's manual `padding.top` is the right one to copy, since the
banner sits above the safe area by design.

### C · Missing screens — `wrapped`, `reviews`, `public_profile`, `splash`

**Confirmed absent, and the removal was clean:** there is not one dangling import or
reference to any of the four anywhere in `lib/`. Both the files and their call sites were
lost together, so restoring them means rebuilding entry points, not just files.

One exception, and it is a live bug rather than a missing feature:
[notification_service.dart:119](lib/services/notification_service.dart#L119) still routes
`weekly_recap` notifications to `nav.pushNamed('/wrapped')`. That route has no screen
behind it and is not registered — see **S2-1**, which this is a subset of. The `weeklyRecap`
Cloud Function is deployed and sending those notifications every Sunday at 11:00 UTC.

There is a fifth, unlisted casualty: `main_screen.dart` still imports `SearchScreen` but
has no search tab. `search_screen.dart` (963 ln) is intact and reachable only via the home
header icon. Worth confirming against your screenshots whether search used to be a
sixth tab.

### D · `arcs_screen` needs redoing — concrete reasons

Reading it, the case for a rewrite is structural rather than cosmetic:

1. **Membership is an array on the arc document.**
   `where('members', arrayContains: uid)`
   ([:214](lib/features/social/arcs_screen.dart#L214)) with `arrayUnion`/`arrayRemove` on
   join/leave. Every member is a string in one document — capped by the 1 MB document
   limit, and **every join rewrites the whole document**, so a popular arc serialises all
   joins through one hot doc. Membership belongs in a subcollection.
2. **Four client-maintained counters, all desyncable.** `memberCount`, `likeCount`,
   `postCount`, `replyCount` are all `FieldValue.increment` from the client.
3. **The like toggle reads stale state.** `_toggleLike`
   ([:701-717](lib/features/social/arcs_screen.dart#L701-L717)) branches on
   `data['likes']` from the snapshot the widget was *built* with, then issues
   `arrayUnion` + `increment(1)`. `arrayUnion` is idempotent; `increment` is not. **A
   double-tap adds the uid once and the counter twice** — reproducible, and permanent
   until someone recomputes it. The fix pattern already exists in this codebase:
   `_vote` in
   [episode_discussion_screen.dart:117-158](lib/features/episode_discussions/episode_discussion_screen.dart#L117-L158)
   does the same job correctly with a transaction and a per-user `votes` subcollection.
4. **All three `StreamBuilder`s build their query inside `build()`** (§3-C), so listeners
   churn on every rebuild.
5. **No `mounted` guards** in `_toggleMembership` (§3-A), and no error handling on
   `_toggleLike` at all.

**Recommendation:** this is a rewrite, not a patch, and it will exceed the 200-line limit
in the brief. Treat it as its own conversation. The one thing worth doing *now*,
independently and in ~10 lines, is making `_toggleLike` transactional — it is a live data-
corruption bug on a screen users can reach today.

### E · `episodeReminderPrecise` is written but never deployed

**The function itself is complete and looks correct** — `*/10 * * * *`, respects
`prefs.episode_reminder`, chunks AniList ids at 50/query, writes a `fired` marker to avoid
duplicates. Nothing in the code explains why it isn't live.

**I believe I found the reason, and it isn't in the function.**
[firebase.json:14-24](firebase.json#L14-L24) declares a second functions codebase:

```json
{ "source": "aruku", "codebase": "aruku", ... }
```

**There is no `aruku/` directory in this repo.** The Firebase CLI validates every declared
codebase before deploying any of them, so `firebase deploy --only functions` fails at
config-validation time — before it ever looks at `functions/index.js`. That would block
deployment of *all ten* functions, not just this one, which is consistent with a function
that was "written but never deployed" despite being finished.

This is a hypothesis I can't confirm without running a deploy, which the brief forbids
— and I have not run one. You can confirm it in one non-mutating command:

```
firebase.cmd deploy --only functions --dry-run
```

If that reproduces the codebase error, the fix is to remove the stale `aruku` block from
`firebase.json` (or restore the directory). **Two caveats before you deploy anything:**
`episodeReminderPrecise` reads **every user document plus each one's `alerts`
subcollection, 144 times a day** — at 1,000 users that is ~288k document reads/day from
this function alone, and it scales linearly. Consider a `collectionGroup('alerts')` query
or a denormalised index of alerted anime ids before turning it on. And deploying it will
immediately start sending notifications through
[`_handlePayload`](lib/services/notification_service.dart#L100), which crashes on tap —
**fix S2-1 first.**

---

## 6. Security

### S1-1 · Loki has no owner gate — in any layer

The brief states Loki is "meant to be restricted to a single owner UID and capped at 40
messages a day", and asks whether the gate is real and enforced server-side.

**The 40/day cap is real and server-side.** `chatWithTomo`
([functions/index.js:1145-1157](functions/index.js#L1145-L1157)) reads
`users/{uid}/companion_meta/usage`, compares against `TOMO_DAILY_CAP = 40`, and throws
`resource-exhausted`. That part is correct.

**The owner-UID restriction does not exist anywhere.** I searched for it in all three
places it could live:

| Layer | Gate |
|---|---|
| Cloud Function | `if (!uid) throw ...` — checks **authenticated**, never *which* user. No owner constant exists in `functions/index.js`. |
| `TomoService` (client) | None. |
| UI entry point | **None** — the Loki button is rendered unconditionally in the home header for every user ([home_screen.dart:277-280](lib/features/home/home_screen.dart#L277-L280)). |

So it is not "hidden in the UI" — there is no gate to hide. **Any user who can sign up can
use Loki, 40 messages per day each, and the cap is per-user, not global.** Each message
runs on `claude-sonnet-4-6` with server-side web search (`max_uses: 4`) against your
`ANTHROPIC_API_KEY`. Cost scales linearly with signups and is unbounded in aggregate.

**Fix (small, server-side, ~6 lines):** add an owner-UID constant to
`functions/index.js` and reject non-owners before the Anthropic call:

```js
const OWNER_UID = '<your uid>';
if (uid !== OWNER_UID) throw new HttpsError('permission-denied', 'Loki is not available yet.');
```

Then hide the button client-side for everyone else — **in that order**; the client change
is cosmetic, the function change is the actual control. Note this requires a deploy, which
the brief forbids me from doing.

**Secondary (lower priority):** the cap is a read-then-write with no transaction
([:1147-1157](functions/index.js#L1147-L1157)), so concurrent calls can each read
`count: 39` and all proceed. Worth a `runTransaction` if the owner gate is ever relaxed.

### S1-2 · `firestore.rules` is not in this repo

**I could not perform the requested rules audit, because the file does not exist.** I
searched the entire tree (excluding `build/` and `node_modules/`) for `*.rules` and found
nothing. Additionally, **`firebase.json` has no `firestore` section at all** — no `rules`
key, no `indexes` key.

The consequences are worth stating plainly:

- The rules exist only in the Firebase console. They are **unversioned, unreviewable, and
  not restorable** from this repo — which is a pointed risk for a codebase that has
  already survived one data-loss incident.
- Nobody can diff a rules change, and `firebase deploy` from this repo would never deploy
  them.
- **Every claim in the rest of this section is therefore about what the client code
  *requires* the rules to permit, not about what the rules actually say.**

**Recommended first action, before any fix work:** run
`firebase.cmd firestore:rules get` (read-only), commit the result as `firestore.rules`,
and add the `firestore` block to `firebase.json`. That is a prerequisite for auditing
S1-3 and S1-4 below, and it is cheap.

### S1-3 · Founder immutability cannot be enforced by rules as currently designed

`FounderService.claimFounderNumber`
([founder_service.dart:27-62](lib/services/founder_service.dart#L27-L62)) runs the claim
as a **client-side transaction**: it reads `meta/founders`, and writes both the
incremented counter and `{isFounder: true, founderNumber: n}` onto the user's own
document.

The transaction is correctly written — it is genuinely atomic, and it is idempotent for a
user who already has a number. **The problem is architectural, not a coding error:** the
legitimate client path requires exactly the write that abuse requires. For the real feature
to work, rules must let a client write `isFounder` and `founderNumber` on its own user doc
and bump `meta/founders`. Any rule permissive enough to allow that is permissive enough for
a user to set `isFounder: true, founderNumber: 1` directly.

There is no rule that distinguishes the two, because from Firestore's perspective they are
the same write. **Founder status is therefore self-assignable regardless of what the rules
say** — I can state this without reading them.

**Fix:** move the claim into a callable Cloud Function using the Admin SDK, and make the
rules deny all client writes to `isFounder`, `founderNumber`, `founderJoinedAt`, and
`meta/founders`. That is the only way to make the tier immutable. Roughly 40 lines of
function plus a small client change — and it needs a deploy, so it is your call.

### S1-4 · Likes and counters are client-written

Every social counter in the app is incremented directly by the client:
`likeCount`/`likes` ([arcs_screen.dart:706-716](lib/features/social/arcs_screen.dart#L706-L716)),
`memberCount`/`members` ([:456-467](lib/features/social/arcs_screen.dart#L456-L467)),
`postCount` ([:1468](lib/features/social/arcs_screen.dart#L1468)),
`replyCount` ([:911](lib/features/social/arcs_screen.dart#L911)).

The brief asks specifically about **reply likes**. Worth reporting precisely: **replies
have no like feature at all** in the recovered code. `_ReplyCard`
([:1076](lib/features/social/arcs_screen.dart#L1076)) renders body, author, and timestamp
only — there is no like control and no `likes` field written on reply documents. Either
that feature was lost with the missing screens, or the concern is about the `replies`
subcollection being writable generally. Without the rules file I can't tell you which, and
it is worth checking the console for a `replies` rule that grants broad `update` access to
a document shape the client no longer writes.

For post likes, rules can partially constrain this (require `likeCount` to change by
exactly ±1, and require the acting uid to be the only element added to `likes`), but the
robust fix is a counter that is derived rather than client-asserted. Note this overlaps
with the §5-D double-tap bug: the same write path is both a correctness bug and a soft
security issue.

### Not a concern

The FCM VAPID key in
[notification_service.dart:80](lib/services/notification_service.dart#L80) is a **public**
key by design; hardcoding it is correct. `firebase_options.dart` likewise contains public
client identifiers. Neither was touched.

---

## 6b. `firestore.rules` — the audit S1-2 blocked, now run (2026-09-04)

`firestore.rules` is now in the repo and `firebase.json` points at it, so the rules audit
the brief asked for in phase one can finally be done against source rather than guesswork.
**This section is report-only — no rule was changed.**

It supersedes the parts of §6 that were written while the file was unavailable. Where a
phase-one finding is now confirmed or refuted by the actual rules, that is called out.

### R1 · 🔴 Every user document is world-readable, and they contain email addresses

```
match /users/{userId} {
  allow read: if true;
```

`if true` is not "any signed-in user" — it is **unauthenticated**. Anyone who knows the
project id can read every user document without an account.

Those documents hold, from the writes in `lib/`: `email`, `displayName`, `username`,
`fcmToken`, `avatarImageUrl`, `notifPrefs`, `isFounder`, `founderNumber`,
`onboardingComplete`, `pinnedCards`. So this publishes **every user's email address and FCM
registration token** to the open internet.

The FCM token cannot be used to send pushes without the server key, but it is a stable
per-device identifier. The email address needs no qualification — that is a personal-data
leak in a shipped app.

The same `allow read: if true` also applies to `users/{uid}/animeList`
([:15](firestore.rules#L15)) and `users/{uid}/activity` ([:37](firestore.rules#L37)). Public
watch history may well be intended for social profiles, but it is worth being deliberate
about, and it does not need to extend to the parent document holding the email.

**Fix direction:** at minimum `allow read: if request.auth != null`, and better, split the
public-facing profile fields into their own document (or gate per-field via a function) so
`email` and `fcmToken` are never in a readable path.

### R2 · 🔴 Founder status is self-assignable — and a comment in the file says otherwise

This confirms **S1-3**, and it is worse than "unenforceable in principle": the rule that is
meant to prevent it does not.

```
allow update: if request.auth != null && request.auth.uid == userId && (
  !('founderNumber' in resource.data)
  || request.resource.data.founderNumber == resource.data.founderNumber
);
```

The rule freezes `founderNumber` **only once it already exists**. On a document that does
not yet have one, the first branch is true and the update is unconstrained — so any
authenticated user can write `{isFounder: true, founderNumber: 1}` to their own document
directly. Nothing requires `meta/founders` to have been read or incremented, nothing checks
uniqueness, and `isFounder` and `founderJoinedAt` are never constrained at all.

Lines 51–54 of the rules state:

> *"It may only ever be incremented by exactly 1 and never past 50, which is what makes
> client-side founder claiming safe — a tampered client cannot grant itself an arbitrary
> number or reset the count."*

**That claim is false.** The counter constraints are correct in themselves, but they only
bind writes *to the counter*. A tampered client simply skips the counter and writes the
badge onto its own user document. Worth correcting the comment as well as the rule, because
it is the kind of comment that stops the next person from looking.

**What the rule does get right:** once set, `founderNumber` genuinely cannot be changed, and
a `FieldValue.delete()` on it is denied too (the key goes missing and rule evaluation
errors, which denies). So the immutability half works. It is the *assignment* half that is
open.

**Fix direction:** as in S1-3 — move the claim into a callable Cloud Function using the
Admin SDK, and deny client writes to `isFounder`, `founderNumber`, `founderJoinedAt`
outright. Needs a deploy, so it is downstream of 4d.

### R3 · 🟠 The founder counter can be exhausted by anyone, for free

```
allow update: if request.auth != null
  && request.resource.data.count == resource.data.count + 1
  && request.resource.data.count <= 50;
```

Correctly capped and correctly +1-only — but **available to any authenticated user**, with
no requirement that the caller become a founder. Fifty writes from one throwaway account
takes the count to 50, after which `FounderService.claimFounderNumber` sees
`current >= maxFounders` and returns null for every genuine user forever.

The founder programme is a headline feature of the app. This is a denial of service on it
that costs an attacker fifty document writes.

### R4 · 🟠 Anyone can write to anyone else's follower graph

```
match /followers/{followerId} { allow read: if true; allow write: if request.auth != null; }
match /following/{followingId} { allow read: if true; allow write: if request.auth != null; }
```

These sit under `/users/{userId}/`, so the rule grants **any signed-in user write access to
any other user's followers and following subcollections** — adding entries, or deleting
them. The `{followerId}` wildcard is never compared to `request.auth.uid`.

Latent rather than live: the client never touches these collections (confirmed by grep —
`followers`/`following` appear only in `delete_account_screen`'s wipe list). But the rules
are deployed, so the hole is real the moment the feature ships, and it is the kind of thing
that gets forgotten precisely because the UI does not exercise it.

**Fix direction:** `allow write: if request.auth != null && request.auth.uid == followerId`
for `followers`, and `== userId` for `following`, depending on which side owns the edge.

### R5 · 🟠 Reviews and episode discussions: impersonation and unbounded vote counts

Both collections share a pattern, and both halves of it are loose.

**Create does not bind the author.** `allow create: if request.auth != null` — nothing checks
`request.resource.data.userId == request.auth.uid`. A client can post a review or a comment
carrying **someone else's uid**, and the rules will accept it. The victim then shows as the
author, and by the delete rule they are the only one who can remove it.

**Update restricts keys, not values.**

```
request.resource.data.diff(resource.data).affectedKeys()
  .hasOnly(['upvotes', 'downvotes', 'helpfulCount'])
```

`hasOnly` constrains *which* fields may change, not what they may change to. Any signed-in
user may set `upvotes` to any number they like, on anyone's content, as often as they like.
Contrast the arcs rules below, which get exactly this right by also requiring `± 1`.

**Vote documents are not scoped to their owner.** `match /votes/{voteId} { allow read,
write: if request.auth != null; }` — `{voteId}` is never compared to `request.auth.uid`, so
any user can overwrite or delete any other user's vote record.

`episodeDiscussions` is live in the app (`episode_discussion_screen.dart`). `reviews` is
not — `reviews_screen` is one of the four screens never recovered — so those rules currently
guard a feature with no client.

### R6 · 🟠 `companion_chat` has no rule at all, so Loki's history cannot load

Cross-referencing every collection the client touches against the rules turned up exactly
one gap, and it is a live one.

`TomoService.loadHistory()`
([tomo_service.dart:49-54](lib/features/companion/tomo_service.dart#L49-L54)) reads
`users/{uid}/companion_chat` from the client. **There is no `match` block for it.** Firestore
denies by default, so that read fails for everyone, including the owner.

The Cloud Function writes the same collection through the Admin SDK, which bypasses rules —
so messages are being stored correctly and simply never load back. Opening Loki shows an
empty conversation every time.

This is a functional bug, not just a hardening gap, and it is only visible by reading the
rules and the client together.

**Fix direction:** add `match /companion_chat/{msgId} { allow read: if request.auth != null
&& request.auth.uid == userId; allow write: if false; }` — writes stay function-only.
`companion_meta` needs no rule; only the function touches it.

### R7 · 🟡 Arc counters can be inflated

`isPostCountBump` ([:117](firestore.rules#L117)) lets a member add 1 to `postCount`, and
`isReplyCountBump` ([:163](firestore.rules#L163)) lets **any signed-in user** add 1 to
`replyCount` — neither is tied to a post or reply actually being created, and the reply one
is not even membership-gated. Repeated calls inflate the counters without limit. Cosmetic
rather than dangerous, but it is the same class of "counter the client asserts" the rest of
this file otherwise avoids.

### R8 · 🟡 Deleting an arc strands its posts permanently

Firestore does not cascade, so `allow delete` on an arc ([:140](firestore.rules#L140))
leaves `posts` and `replies` behind. The posts rules then resolve membership via
`get(/databases/$(database)/documents/arcs/$(arcId))` ([:145](firestore.rules#L145)). With
the parent gone that returns null, `arc().members` and `arc().createdBy` error, and rule
evaluation on error denies — so the orphaned posts become **unwritable and undeletable by
anyone**, while still being readable. They can only be cleared with the Admin SDK.

### R9 · 🟡 Account deletion does not remove Loki chat history

Not a rules defect, but it surfaced from the same cross-reference.
`_wipeUserData` ([delete_account_screen.dart:101-110](lib/features/auth/delete_account_screen.dart#L101-L110))
deletes an explicit list of subcollections: `animeList`, `alerts`, `cards`, `pinnedCards`,
`activity`, `followers`, `following`, `firedAlerts`. **`companion_chat` and `companion_meta`
are not in it**, so a user's conversations with Loki survive their account deletion. For a
feature that sends user data to a third-party API, that is worth closing.

### R10 · ⚪ Two rule blocks guard things that do not exist

- **`pinnedCards` as a subcollection** ([:24](firestore.rules#L24)) — the app stores pinned
  cards as an **array field on the user document** (`{'pinnedCards': updated}` via
  `set(..., merge: true)` in `card_collection_screen.dart`), not as a subcollection. The rule
  is dead; the real data is governed by the `/users/{userId}` update rule. Harmless, but the
  comments in both files claim `users/{uid}/pinnedCards`, so the next person will look in
  the wrong place.
- **`reviews`** — rules for a screen that was never recovered.

### Cleared — checked and correct

These are the ones the brief asked about specifically, and they hold up.

- **Reply likes are properly constrained.** `isReplyLikeToggle`
  ([:199-210](firestore.rules#L199-L210)) requires the acting uid to be the only element
  added or removed **and** `likeCount` to move by exactly ±1. Post likes
  ([:150-161](firestore.rules#L150-L161)) are identical. This is the pattern R5 is missing.
- **`arcs` create/join/leave are tight.** Members array, `memberCount` and `postCount` are
  all pinned on create; join and leave each permit only the caller's own membership to
  change, with `hasOnly` limiting the blast radius.
- **`cards` and `firedAlerts` are correctly function-only** for writes, with owner read and
  owner delete for account wipe.
- **`meta/founders` cannot be deleted** — no `allow delete`, so the default denial applies.
- **`founderNumber` is genuinely immutable once set**, including against `FieldValue.delete()`.
- **Loki's owner gate is not a rules problem.** `chatWithTomo` is a callable function;
  Firestore rules cannot gate it. **S1-1 stands unchanged** — the owner check still does not
  exist in any layer.

### One phase-two item this reclassifies

`PHASE-TWO.md` and `BATCH-FOUR.md` both carry the arcs like-toggle forward as *data
corruption*: "a double-tap permanently inflates `likeCount`". **The rules make that
impossible.**

A second tap sends `arrayUnion([uid])` — which is a no-op, the uid is already present — plus
`increment(1)`. `isLikeToggle` requires either (uid absent before **and** present after
**and** count +1) or the mirror for removal. After a first tap the uid is present in both
states, so neither branch matches and **the write is rejected**.

So the counter cannot drift. What actually happens is that `_toggleLike`
([arcs_screen.dart:701-717](lib/features/social/arcs_screen.dart#L701-L717)) has **no
try/catch**, so the `permission-denied` surfaces as an unhandled async error — which
`PlatformDispatcher.onError` reports to Crashlytics as **fatal** (AUDIT §3-D).

It is still worth the ~15 lines, but it is a crash-on-double-tap fix, not a data-integrity
one, and the transaction is no longer the important part — the error handling is.

---

## 6c. Batch 4a — the key sweep (2026-09-04)

Branch `fix/sliver-keys`. Swept every dynamic sliver and child list in `lib/features` and
`lib/widgets` for the defect found on Home: children built from a collection, conditionally
inserted, or reordered, matched positionally because `Element.canUpdate()` returns true for
two widgets of the same `runtimeType` with null keys.

**Method.** Rather than eyeball 159 loop/spread sites, I scoped it to the combination that
can actually cause harm: **a child set that changes at runtime × a child that holds state.**
Enumerated all 71 `StatefulWidget` classes, then found which are constructed inside an
`itemBuilder` or a `.map()`. Stateless children were checked separately and are listed as
not needing keys — an index match simply rebuilds them with the right data.

### Fixed

| Site | Set changes because | What went wrong | Key |
|---|---|---|---|
| [home_screen.dart:401](lib/features/home/home_screen.dart#L401) `_ContinueCard` | list is sorted by `lastWatched`; "+1 episode" reorders it | **wrong episode number shown, and written** — see below | `animeId` |
| [home_screen.dart](lib/features/home/home_screen.dart#L256) sliver list, 13 entries | import banner dismissal removes a sliver near the top; recommendations arrive later | `TonightWatchCard`'s `AnimationController` and mood state remount; horizontal lists' scroll offsets swap between sections | section name |
| [home_screen.dart:595](lib/features/home/home_screen.dart#L595) `_TrendingCard` (recommendation rows) | rows are rebuilt from `_recommendationRows` | `_hovered` carries to another title | `genre` + media id |
| [profile_screen.dart](lib/features/profile/profile_screen.dart#L201) sliver list, 11 entries | the founder placeholder **disappears entirely** for a non-founder once status resolves; stats and genre slivers appear when the list stream delivers | everything below shifts by one, including the live `HanjCard` and `TasteProfileCard` | section name |
| [discovery_screen.dart:831](lib/features/discovery/discovery_screen.dart#L831) `_HypeMeterRow` | `activeList` swaps wholesale when `_showNext` toggles season | row stays **expanded and mid-animation** over a different anime (`AnimationController` + `_expanded`) | media id |
| [discovery_screen.dart:419](lib/features/discovery/discovery_screen.dart#L419) `_AnimeCard` | grid replaced on category change | `_hovered` on the wrong card | media id |
| [search_screen.dart:399](lib/features/search/search_screen.dart#L399) `_AnimeCard` | results replaced on every query | state lands on a different result | media id |

**The one that matters.** `_ContinueCard` is not a cosmetic case. `_ContinueCardState`
holds `_current`, the episode number on the card, and its `didUpdateWidget` resyncs only
when the incoming value differs from the **previous widget's** value:

```dart
if (incoming != previous) _current = incoming;
```

When two shows sit on the same episode, that comparison is false and the resync is skipped.
Bump B from 5 to 6, the list reorders, and **A's card now reads episode 6** — persistently,
not for a frame. Worse, `_bump` computes `next = _current + 1` from the displayed value, so
tapping "+1" on that card writes **7** to A's document, silently skipping an episode.

That is the "app is a bit glitchy sometimes" symptom the brief predicted, except it reaches
Firestore.

### Already correct — no change made

- **[episode_discussion_screen.dart:278, 291](lib/features/episode_discussions/episode_discussion_screen.dart#L278)** —
  comments and replies already carry `key: ValueKey(comment.id)` and `ValueKey(r.id)`, and
  the list genuinely is sorted. This is the pattern the rest of the sweep copied.
- **[anime_detail_screen.dart](lib/features/anime_detail/anime_detail_screen.dart#L677)** —
  `_TabContent` carries `key: ValueKey(_selectedTab)`, deliberately forcing a remount on tab
  change.
- **Home's Upcoming sliver** — keyed in batch 2.

### Checked, keys not needed — and why

Recording these so nobody keys them defensively later.

| Site | Why it is safe |
|---|---|
| `emotional_categories.dart:144` `_CategoryRow` | `_categories` is a **`const` list** — fixed at compile time, never filtered or reordered. The child holds real state (`_anime`, `_expanded`, `_hasFetched`) but the set cannot change, so index matching is stable permanently. |
| `emotional_categories.dart:340` `_AnimeCard` | that row's `_anime` grows from empty exactly once when its fetch resolves. Appending never shifts existing indices, and it is not reordered afterwards. |
| `staff_detail.dart:316, 436` and `studio_detail.dart:134` `HoverAnimeCard` | built from `_staffData!['staffMedia']`/`characterMedia`, set once after load. Neither screen has a tab, filter or sort (no `TabController`, no `_filter`), so the set never changes again. |
| `anime_detail_screen.dart:1186` `_RelatedCard` | `_relatedAnime` is loaded once and never reordered. |
| `anime_detail_screen.dart:2015` `_ZoomableImage` | `_galleryImages` is loaded once. |
| `tomo_screen.dart:299` chat list | messages only ever append, and the typing bubble occupies the final index. Appending never shifts earlier indices. |
| `card_collection_screen.dart:295` `_HanjCardTile` | the rarity filter **does** change `grid.length`, but the tile is a `StatelessWidget` with no controller — an index match rebuilds it correctly from `item`. Keys would be pure noise. |
| `home_screen.dart:493` `_TrendingRow` | stateless. |
| `my_list_screen.dart:169` slivers | three entries, no conditionals at sliver level. |
| `anime_detail_screen.dart` hero column | its many conditionals produce `Text`/`Container` children, and the conditions depend on `anime`, which is fixed after load. |

### Device verification — done

`debugPrint('PERFMOUNT UpcomingAnimeRow')` in `_UpcomingAnimeRowState.initState`, profile
build on the CPH2573, with every key in this batch in place. Instrumentation reverted
afterwards; `git status` clean against HEAD.

| Phase | `UpcomingAnimeRow` mounts |
|---|---|
| cold Home load | **1** |
| returning to the Home tab | **1** |
| *before the fix* | *2 per single load* |

One mount per load, which is what the fix predicts. This is consistent with batch 2's
independent measurement of AniList requests dropping 3 → 2 on both cold load and tab
return.

*(This took three attempts: the phone dropped off USB twice, and one build compiled but
never installed — the earlier run was reading a stale APK from before the fixes, which is
why its first result was empty rather than wrong. Worth knowing the install can fail
silently while `flutter run` still reports success.)*

---

## 7. Dependencies (`flutter pub outdated`) — flagging only

Direct dependencies with a newer major available. **Per the brief, I propose no upgrades
and have not touched `pubspec.yaml`.**

| Package | Current | Latest | Note |
|---|---|---|---|
| `share_plus` | 10.1.4 | **13.3.0** | 3 majors behind — the widest gap. Used by `card_share.dart`; the `shareXFiles` API has changed across these. |
| `youtube_player_flutter` | 9.1.3 | **10.0.1** | Powers the trailer player, which also depends on the deprecated `dart:html` path. |
| `connectivity_plus` | 6.1.5 | **7.3.1** | `onConnectivityChanged` list-vs-single semantics changed in a recent major — `_isConnected(List<...>)` would need checking. |
| `cached_network_image` | 3.4.1 | **4.0.0** | Used app-wide for posters. |
| `shimmer` | 3.0.0 | **4.0.0** | Loading skeletons. |

Firebase packages are all 1–8 minors behind but on their current majors and mutually
consistent — the safest group, and the least urgent.

Non-breaking patch bumps available with no major change: `gal` 2.3.2→2.3.3,
`google_fonts` 8.1.0→8.2.1, `intl` 0.20.2→0.20.3.

**Nothing here is unmaintained or abandoned** — every package has a recent release. There
is no security-driven reason to upgrade anything right now. The one I would watch is
`youtube_player_flutter`, since its web path rides on `dart:html`, which is slated for
removal rather than merely deprecated.

Cloud Functions deps (`functions/package.json`): `firebase-functions` ^5.0.0 with
`firebase-admin` ^12.0.0 and `@anthropic-ai/sdk` ^0.100.1 — all current-major and
consistent. Node 20 runtime.

---

## 8. TODO/FIXME sweep, and orphans

### TODO/FIXME/HACK/XXX: **zero**

I swept `lib/` for `TODO`, `FIXME`, `HACK`, `XXX`, and `BUG:`. Two matches, both false
positives: `/// Footer row — № XXXX left` ([hanj_card.dart:997](lib/features/cards/hanj_card.dart#L997))
and `hintText: 'XXXXXXXX'` ([soulmatch_screen.dart:178](lib/features/social/soulmatch_screen.dart#L178)).

An empty TODO sweep on a 44k-line codebase is itself a data point: the reconstruction
recovered *code*, not the working notes around it. **Nothing in this tree marks its own
unfinished edges** — which is a good argument for keeping this document current, since it
is currently the only such record.

### Deletion candidates — listed, not deleted, per the brief

**Nothing in this section was removed. Do not act on it without checking your APK
screenshots first.**

| Candidate | Evidence | Confidence it's safe to delete |
|---|---|---|
| [core/trailer_player_screen.dart](lib/core/trailer_player_screen.dart) (125 ln) | Never imported; `TrailerPlayerScreen` is **also defined** in [trailer_launcher.dart:23](lib/core/trailer_launcher.dart#L23), which is the one actually used. A genuine duplicate. | High — but it is the only *standalone* copy, so archive it rather than delete. |
| 12 unused widgets/methods (§2 table) | Analyzer `unused_element` | **Low — these are the missing-feature map. Keep.** |
| 5 unused imports | Analyzer `unused_import` | High, and harmless either way. |

Explicitly **not** orphans, despite having no importer:
[lib/cadre_dev.dart](lib/cadre_dev.dart) (alternate entry point, run with
`flutter run -t`) and [lib/main.dart](lib/main.dart) (the entry point).

---

## 9. Checked and cleared

Things that look like defects, or that the brief flags as suspicious, which I verified are
actually **correct**. Recording these so nobody re-spends the time:

- **`claude-sonnet-4-6` is a valid current model id** ([functions/index.js:1055](functions/index.js#L1055)).
  I checked it against current Anthropic model documentation rather than assuming. Not a typo, not retired.
- **`web_search_20260209` is the current web-search tool version**
  ([:1183](functions/index.js#L1183)), and Sonnet 4.6 is on its supported-model list. Correct as written.
- **`const Anthropic = require('@anthropic-ai/sdk')` is correct for v0.100.1.** I ran it
  against the installed package: the CJS export *is* the constructor (`typeof === 'function'`,
  `new Anthropic({...})` yields a working client). The `.default`/`.Anthropic` unwrapping
  that other SDKs need is not required here.
- **`setPreference` does not clobber sibling preferences**
  ([notification_service.dart:150](lib/services/notification_service.dart#L150)).
  `SetOptions(merge: true)` deep-merges nested maps in Firestore, so writing
  `{'notifPrefs': {key: value}}` preserves the other keys.
- **FCM tokens are saved.** `saveTokenForCurrentUser()` looks uncalled from `main.dart`,
  but `auth_service.dart` invokes it at all three sign-in paths (lines 54, 77, 112).
- **The live episode countdown timer is correctly cancelled and guarded** — see §3-B.
- **`_castVote`'s `rethrow` is handled.** `_vote` rethrows
  ([episode_discussion_screen.dart:156](lib/features/episode_discussions/episode_discussion_screen.dart#L156)),
  and the caller catches it to roll back the optimistic arrow ([:635](lib/features/episode_discussions/episode_discussion_screen.dart#L635)).
- **`PulseService` is a correct AniList client** — throttle, backoff, timeout, TTL cache. Use it as the template.

---

## 10. Ranked table — what to fix first

Effort assumes someone who knows this codebase. "Lines" is changed lines, for the
brief's 200-line batch limit.

| # | Sev | What it is | Files | Lines | Notes |
|---|---|---|---|---|---|
| **S1-1** | 🔴 Critical | **Loki has no owner gate in any layer** — every signed-up user can spend your Anthropic key, 40 msg/day each | [functions/index.js:1135](functions/index.js#L1135), [home_screen.dart:277](lib/features/home/home_screen.dart#L277) | ~10 | Server change needs a deploy — **yours to run** |
| **S1-2** | 🔴 Critical | **`firestore.rules` absent from repo**; `firebase.json` has no `firestore` block. Rules unversioned and unrestorable | [firebase.json](firebase.json) | ~8 | `firestore:rules get` first — **prerequisite for auditing S1-3/S1-4** |
| **S2-1** | 🟠 High | **Notification taps crash.** 4 of 5 routes (`/anime-detail`, `/social`, `/wrapped`, `/home`) unregistered; no `onGenerateRoute` | [notification_service.dart:106-126](lib/services/notification_service.dart#L106-L126), [main.dart:211](lib/main.dart#L211) | ~25 | `/wrapped` needs the missing screen; the rest are route entries |
| **S2-2** | 🟠 High | **Duplicate FCM handlers** — `main.dart` and `NotificationService.init()` both register `onMessageOpenedApp` + `getInitialMessage`; card-unlock opens the collection screen twice | [main.dart:157-176](lib/main.dart#L157-L176), [notification_service.dart:65](lib/services/notification_service.dart#L65) | ~20 | Pick one owner. Fix with S2-1 |
| **S2-3** | 🟠 High | **`_fetchAiringHttp` bypasses the AniList throttle** — runs on every detail open | [anime_detail_screen.dart:174](lib/features/anime_detail/anime_detail_screen.dart#L174) | **2** | Best value in the report. Pattern is 40 lines below it |
| **S2-4** | 🟠 High | **Founder status is self-assignable** — client-side claim; no rule can prevent it | [founder_service.dart:27](lib/services/founder_service.dart#L27) | ~40 | Needs a callable function + deploy |
| **S2-5** | 🟠 High | **`firebase.json` declares codebase `aruku` with no directory** — likely blocks *all* function deploys, incl. `episodeReminderPrecise` | [firebase.json:14](firebase.json#L14) | ~10 | Confirm with `deploy --dry-run`; **fix S2-1 before deploying reminders** |
| **S3-1** | 🟡 Med | **18 × `setState` after `await` with no `mounted` guard** → `setState() after dispose`, reported as fatal | 14 files, §3-A | ~18 | Mechanical. Check Crashlytics first to rank it |
| **S3-2** | 🟡 Med | **Pulse/Discover SafeArea gap** — banner reserves ~33 px permanently + inset applied twice | [connectivity_service.dart:110](lib/services/connectivity_service.dart#L110), pulse/discovery/home | ~15 | Invisible on web; test on device |
| **S3-3** | 🟡 Med | **Share-card centring** — unbalanced trailing 26 px spacer pushes art ~13 px high | [card_share.dart:388](lib/features/cards/card_share.dart#L388) | **1** | Fully diagnosed; see §5-A |
| **S3-4** | 🟡 Med | **Arc like double-tap inflates `likeCount`** — stale read + non-idempotent increment | [arcs_screen.dart:701](lib/features/social/arcs_screen.dart#L701) | ~15 | Do this standalone; copy `_vote`'s transaction |
| **S3-5** | 🟡 Med | **Unawaited list-write + `Navigator.pop` across async gap** — silent data loss; can pop the wrong route | [home_screen.dart:711-718](lib/features/home/home_screen.dart#L711-L718) | ~8 | Two bugs, adjacent lines |
| **S3-6** | 🟡 Med | **Startup blocks on the notification permission prompt** (no timeout before `runApp`) | [main.dart:63](lib/main.dart#L63), [notification_service.dart:35](lib/services/notification_service.dart#L35) | ~10 | Candidate for the blank-screen reports |
| **S3-7** | 🟡 Med | **3 AniList calls with no throttle *and* no timeout** — calendar/import/edit-profile spin forever on a hung connection | calendar, import, edit_profile | ~12 | Same fix as S2-3 |
| **S4-1** | 🟢 Low | `_animeListRef!` — 18 × check-then-deref of a re-evaluating getter | [firestore_service.dart](lib/services/firestore_service.dart) | ~20 | One local per method |
| **S4-2** | 🟢 Low | Firestore listeners rebuilt inside `build()` (5 sites, 3 in arcs) | arcs ×3, [main.dart:266](lib/main.dart#L266), episode_discussions | ~15 | Hoist to `initState` |
| **S4-3** | 🟢 Low | `notifyListeners()` called from outside `AuthService` | [email_verification_screen.dart:56](lib/features/auth/email_verification_screen.dart#L56) | ~6 | Fragile: breaking it strands verified users |
| **S4-4** | 🟢 Low | 2 × unclosed `http.Client()` | [anime_detail_screen.dart:174,217](lib/features/anime_detail/anime_detail_screen.dart#L174) | ~4 | Use top-level `http.post` |
| **S4-5** | 🟢 Low | Tab state lost on switch (no `IndexedStack`) | [main_screen.dart:36](lib/features/main_screen.dart#L36) | ~5 | Behaviour change — confirm it's wanted |
| **S4-6** | 🟢 Low | 47 dead declarations from the recovery | 12 files | 0 | **Keep as the missing-feature map** (§2) |
| **S4-7** | 🟢 Low | `dart:html` deprecated → scheduled for removal | [trailer_launcher_web.dart:2](lib/core/trailer_launcher_web.dart#L2) | ~20 | Not urgent; will eventually stop compiling |
| **—** | ⚪ Defer | **`arcs_screen` rewrite** — array membership, 4 client counters, listener churn | [arcs_screen.dart](lib/features/social/arcs_screen.dart) (1534 ln) | **>200** | Exceeds the batch limit by design. Needs a conversation. Extract S3-4 and do it now |
| **—** | ⚪ Defer | **`episodeReminderPrecise` read amplification** — full user scan every 10 min (~288k reads/day @ 1k users) | [functions/index.js:194](functions/index.js#L194) | ~60 | Address before deploying it |

### Suggested batches

1. **`fix/notification-routing`** — S2-1 + S2-2. Highest user-visible impact; both live in
   the same two files. ~45 lines.
2. **`fix/anilist-throttle`** — S2-3 + S3-7. Directly targets the blank-screen class. ~14 lines.
3. **`fix/mounted-guards`** — S3-1 + S4-1. Mechanical, mostly-mechanical review. ~38 lines.
4. **`fix/layout-parked`** — S3-2 + S3-3. The two parked visual bugs, both diagnosed. ~16 lines.
5. **`fix/arc-like-race`** — S3-4 alone, extracted from the deferred rewrite. ~15 lines.

S1-1 and S1-2 sit outside the batches: both need decisions and a deploy that are yours to
make, and S1-2 gates the rest of the security review.

---

*End of phase one. No code was changed. Awaiting direction on which items to take.*
