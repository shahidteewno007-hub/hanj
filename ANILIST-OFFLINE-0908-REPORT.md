# ANILIST-OFFLINE-0908 — findings

> **Correction — 2026-09-30** (branch `fix/anilist-copy`). Everything below this block is
> the original 2026-09-09 report, unchanged.
>
> **What the 403 was.** AniList suspended API access under its documented stability
> policy — the body quoted below says "temporarily disabled due to severe stability
> issues", and `docs.anilist.co/guide/rate-limiting` still carries a degraded-state warning
> (30 requests/minute against the normal 90) as of 2026-09-30. The suspension let
> Referer-bearing traffic through, which is why the web build kept working: a browser
> attaches a Referer to its requests, the Android app's `http` client does not. It later
> lifted with no change on our side; the Android app fetches live data again.
>
> **Both earlier conclusions were incomplete.**
>
> 1. *Global outage* — this report's framing. The 403 was real and correctly captured, but
>    it was not global; it exempted browser traffic. The "Chrome `User-Agent` → same 403"
>    check below (and in Part E) varied the User-Agent only and never sent a Referer, so it
>    could not have seen the exemption. Part E's "none of it caused anything" holds for
>    User-Agent and was never tested for Referer.
> 2. *Missing-header bug* — the diagnosis that followed, not previously written down in this
>    repo: that the Android app's missing Referer was a Hanj defect. The header decided which
>    clients the suspension caught; it was not the cause. Nothing on our side changed and
>    the 403s stopped. Sending a Referer from the native app to get through would have been
>    a way round a deliberate suspension, not a fix.
>
> **What held up regardless.** None of this depends on why the 403 happened — any non-200
> exercises it:
>
> - *Silent stale-serving* (Part C) — predicted here from source, then confirmed by the
>   2026-09-09 device capture (`eebcc6c`): Home trending, Discovery seasonal and title
>   detail rendered full content with nothing on screen saying it was not live.
> - *The signal* — `AnilistService.isUnavailable` / `noteStatus()` (`fad89c2`) and the
>   SAVED DATA marker that reads it (`eebcc6c`).
> - *The retry fix* — Home airing now retries a 429 the way the service and Discovery do
>   (`40f2614`).
> - The Part A inventory and the Part B/C analysis of which sites fall back and which go
>   empty.
>
> **Copy.** "AniList returned 403. Try again." (Part A #10, §F.4) and the Pulse/VIBES line
> added in `67cc334` named a cause the app cannot verify. `885ae7d` replaced both with
> "Fresh data can't load right now."

**Date:** 2026-09-09
**HEAD:** `c245f6f` on `fix/arcs-like-toggle`
**Mode:** report only. Nothing changed, no branch, no commit, no build, no deploy. This
report is the only file added.

**Outage confirmed live, twice, from the host** — 2026-09-09 **07:09:38Z** and **07:39:19Z**:

```
HTTP/1.1 403 Forbidden        Server: cloudflare      CF-RAY: a3845e5ceb7afe4b-LHE
{"errors":[{"message":"The AniList API has been temporarily disabled due to severe
stability issues.","status":403,"locations":[{"line":1,"column":1}]}],"data":null}
```

Also live-verified: an identical request with a Chrome `User-Agent` returns the **same 403**
(so it is not our UA), `https://anilist.co/` returns **200** (the site is up, only the API is
off), and `GET https://graphql.anilist.co/` returns 404 (POST-only, as expected).

**Every claim below is marked `[LIVE]` or `[SRC]`.** `[LIVE]` means verified against a real
403 during this window. `[SRC]` means read from source and not yet observed running. The
phone is off USB, so **nothing in this report was observed on a device** — §F lists what
that costs.

---

## Part A — inventory

> **Verdict `[SRC]`: ten call sites. Eight render a silent empty view; two already surface a
> legible error. Nothing from any of them reaches Crashlytics, and only one prints anything
> at all.**

Ten `.post(` sites across nine files. `anime_detail_screen.dart` holds two, both via
`http.Client().post`. There are **no `collectionGroup`-style surprises**: `:2133` in that
file is an `http.get` image download, not AniList.

| # | `file:line` | Fetches | Surface | On non-200 | User sees | Crashlytics |
|---|---|---|---|---|---|---|
| 1 | [anilist_service.dart:49](lib/services/anilist_service.dart#L49) | all `AnilistService` queries | search, trending, popular, top-rated, seasonal, staff, staff detail, recommendations, `getAnimeById` | `print('AniList HTTP …')`, `return []` (`:173-176`); other methods `return null` | empty list / empty section | none |
| 2 | [pulse_service.dart:24](lib/services/pulse_service.dart#L24) | Pulse card batches | Pulse: For You, Trailers, Airing, Upcoming | `return null` (`:44`) | Pulse empty state | none |
| 3 | [discovery_screen.dart:632](lib/features/discovery/discovery_screen.dart#L632) | seasonal media, current + next | Discovery seasonal hub | **stale `SharedPreferences` fallback**, else `[]` (`:644-655`) | stale data, or empty | none |
| 4 | [home_screen.dart:1955](lib/features/home/home_screen.dart#L1955) | next-airing batch for watching list | Home airing countdowns | `return out` — empty map (`:1967`) | no countdowns | none |
| 5 | [anime_detail_screen.dart:179](lib/features/anime_detail/anime_detail_screen.dart#L179) | `nextAiringEpisode` | title detail countdown | `return null` (`:184`) | no countdown | none |
| 6 | [anime_detail_screen.dart:222](lib/features/anime_detail/anime_detail_screen.dart#L222) | `coverImage.extraLarge`, `bannerImage` | title detail gallery | falls through; `_galleryImages` never set (`:227`) | gallery keeps low-res | none |
| 7 | [anime_calendar_screen.dart:113](lib/features/calendar/anime_calendar_screen.dart#L113) | weekly airing schedule | Calendar | `throw Exception('Failed')` (`:122`) → caught `:173`, discarded | empty calendar, no message | none |
| 8 | [anilist_import_screen.dart:112](lib/features/import/anilist_import_screen.dart#L112) | AniList user list | Import | `throw Exception('Failed to connect to AniList.')` (`:118`) → `_error` (`:87`) → **rendered `:343-358`** | **"Failed to connect to AniList."** | none |
| 9 | [edit_profile_screen.dart:72](lib/features/profile/edit_profile_screen.dart#L72) | characters for a title | avatar picker | else branch (`:101-103`) | empty picker | none |
| 10 | [cadre_roster_service.dart:197](lib/cadre/services/cadre_roster_service.dart#L197) | roster by title/id | Cadre lobby + pool | **typed `CadreRosterException`** per status (`:212-224`) → caught [cadre_lobby_screen.dart:118](lib/cadre/screens/cadre_lobby_screen.dart#L118), [cadre_pool_screen.dart:84](lib/cadre/screens/cadre_pool_screen.dart#L84), `:127` | **"AniList returned 403. Try again."** | none |

The brief's four known cases are **confirmed**: `anilist_service.dart:173-176` prints and
returns `[]`; `home_screen.dart:1967` returns the accumulator; `anime_detail_screen.dart:184`
returns null; `discovery_screen.dart:644` takes an empty branch — though that branch tries a
stale cache first, which the brief did not record.

**Visible to the user: 2 of 10.** Import (#8) and Cadre (#10). The other eight are
indistinguishable from "there is nothing here".

**Crashlytics: none of 10.** `recordError` appears only in `main.dart:41` (the global
handler) and `arcs_screen.dart:767` (added on this branch). Every AniList failure is caught
locally by `catch (_)` or a discarding `catch (e)`, so `PlatformDispatcher.onError` never
sees one. An upstream outage produces **zero** telemetry.

**Logging: one line, in one path.** `print('AniList HTTP ${response.statusCode}')` at
[anilist_service.dart:174](lib/services/anilist_service.dart#L174), and
`print('AniList error: $e')` at `:178`. Both emit as `I flutter` in logcat. Sites 2-10 print
nothing.

### Trigger type

| Background (fires without the user asking) | User-triggered |
|---|---|
| #1 partly (trending/popular on Home **and on the login screen**, [login_screen.dart:114-115](lib/features/auth/login_screen.dart#L114-L115)), #2 Pulse, #3 Discovery, #4 Home airing | #1 partly (search, detail), #5 #6 detail, #7 Calendar, #8 Import, #9 avatar picker, #10 Cadre |

The split matters as the brief says: background sites should degrade to stale-with-a-note;
user-triggered ones should say what went wrong, because the user is waiting on an answer.

### Retry shape

> **Verdict `[SRC]`: no site retries a 403. The brief's concern about amplification does not
> apply.**

| Site | Retry |
|---|---|
| #1 `anilist_service.dart:47-67` | 3 attempts, **429 only** — `if (response.statusCode != 429) return response;` (`:59`). Backoff honours `Retry-After`, else 3/6/9s |
| #3 `discovery_screen.dart:630-642` | 3 attempts, **429 only** — `if (res.statusCode != 429) break;` (`:637`). Same backoff shape. **Matches #1** |
| #4 `home_screen.dart:1961-1966` | **single attempt**; 429 backs off and returns. Does *not* loop — differs from #1 and #3 |
| #2, #5, #6, #7, #8, #9, #10 | single attempt, no retry |

So `discovery_screen.dart:637` matches `anilist_service.dart` as the brief expected;
**`home_screen.dart:1961` does not** — it backs off correctly but never retries, so a
transient 429 loses that cycle's countdowns entirely. That is a difference, not a defect,
and it is the safer direction.

**Five sites bypass the shared throttle** — #7, #8, #9, #10 and #5 — confirming `AUDIT.md`
§4's count of five. #3, #4, #6 call `AnilistService.throttle()` despite issuing their own
HTTP.

---

## Part B — the three states

> **Verdict `[SRC]`: this is not one change. Only 1 of the 10 post sites lives inside
> `AnilistService`; the other 9 issue their own HTTP and would each need one line to opt in.**

`AnilistService` is where a shared signal belongs, but it does not currently see most
traffic. Of the ten sites, exactly one — [anilist_service.dart:49](lib/services/anilist_service.dart#L49) —
is inside the service. The remaining nine call `http.post` / `http.Client().post` directly
and never touch the service's response handling.

That said, **the precedent for the fix already exists in this file and works**:
`AnilistService.throttle()` (`:35`) and `.backoff(seconds)` are static, service-owned, and
already called from four external sites (#2, #3, #4, #6). A status signal of the same shape
— static, opt-in, one line per call site — is the mechanism that fits this codebase without
restructuring anything.

The three states map onto available evidence like this:

| State | How it is already distinguishable | Gap |
|---|---|---|
| 1. AniList unavailable | `statusCode != 200`, or the GraphQL `errors` array. Both are in hand at every site | Nothing records it anywhere shared |
| 2. No usable network | `ConnectivityService.instance.isOnline` exists and is already consulted (`home_screen.dart:60` region) | Not consulted at the other nine sites |
| 3. Legitimately empty | `statusCode == 200` with an empty `data` list | Currently collapses into the same `[]` as states 1 and 2 |

All three are separable **today** with information the sites already have; nothing new needs
to be fetched. What is missing is somewhere to put the answer.

---

## Part C — the caches

> **Verdict `[SRC]`: three surfaces have disk-backed data that survives a cold start and
> could be shown during an outage. The rest are in-memory only and die with the process. So
> "serve stale with a note" is possible for exactly those three, and nowhere else.**

| Surface | Cache | Survives cold start? | Stale fallback on failure? |
|---|---|---|---|
| **Home trending** | `OfflineCacheService` — memory → `SharedPreferences`, 1h TTL ([offline_cache_service.dart:12](lib/services/offline_cache_service.dart#L12)), used at [home_screen.dart:61](lib/features/home/home_screen.dart#L61) | **yes** | **yes** — `:148-150`, *"Network returned empty — use stale rather than showing blank"* |
| **Discovery seasonal** | its own `SharedPreferences` cache, 1h TTL ([discovery_screen.dart:583-598](lib/features/discovery/discovery_screen.dart#L583-L598)) | **yes** | **yes** — `:644-655` and `:659-665` |
| **Title detail** | `OfflineCacheService.cacheAnimeDetail` / `getCachedAnimeDetail` ([anime_detail_screen.dart:69](lib/features/anime_detail/anime_detail_screen.dart#L69), `:94`, [home_screen.dart:2197](lib/features/home/home_screen.dart#L2197)) | **yes** | partial — detail body only, not staff/recs/gallery |
| Discovery in-memory | `_cachedCurrent` / `_cachedNext` (`:473-476`) | no | n/a |
| Home "upcoming" row | `_cachedThis` / `_cachedNext` ([upcoming_anime.dart:28-29](lib/features/home/upcoming_anime.dart#L28-L29)) | no | no |
| **Pulse** | `_memCache` ([pulse_service.dart:15](lib/services/pulse_service.dart#L15)) | **no** | no |
| Calendar, search, staff, recommendations, avatar picker, Cadre roster | none | no | no |

**This is the single most important finding for the fix.** `OfflineCacheService` at
`:148-150` falls back to stale data when the fetcher **returns empty** — and during this
outage `AnilistService` returns exactly that, `[]`, because it treats a 403 as "no results".
So Home trending is very likely serving stale cached data right now **with nothing telling
the user it is stale**. That is the behaviour to make legible, and it is already half-built.

It also means an outage is *worse* than invisible on those surfaces: it looks like the app
is working normally on yesterday's data.

**`[NEEDS DEVICE]`** — I have not observed this running. I saw Home and List populated on
2026-09-08 at 04:52Z, but I did not test AniList at that moment, so I cannot claim that was
stale-serving during an outage. It is a prediction from source, not an observation.

---

## Part D — the minimal cut

> **Verdict: ~85 lines for the first cut across four files plus one new widget; ~155 lines
> for full coverage. Under the 200-line ceiling either way, but I would still stage it,
> because the second half touches Home and the login screen.**

### First cut — make an outage legible where the traffic is

| File | Change | Lines |
|---|---|---|
| `lib/services/anilist_service.dart` | a static `AnilistStatus { ok, unavailable, offline }` plus `lastOutcome` and `lastOkAt`, set inside `_post` from the status code; a one-line `noteResponse(res)` other sites can call, mirroring `throttle()`/`backoff()` | ~30 |
| `lib/widgets/anilist_status_banner.dart` *(new)* | a small banner — "AniList is unavailable. Showing saved data from {time}." / "…nothing saved yet." — reading the static above | ~40 |
| `lib/features/discovery/discovery_screen.dart` | `noteResponse(res)` at `:637`; banner above the seasonal hub when serving the stale branch | ~8 |
| `lib/features/anime_detail/anime_detail_screen.dart` | `noteResponse` at `:184` and `:227`; banner in the detail header | ~7 |
| **total** | | **~85** |

Search is covered for free: it routes through `AnilistService` (#1), so the status is set by
the service itself and the banner reads it.

### Second cut — the rest

Home airing + trending (~15), Pulse (~10), Calendar (~12), Import (~5, already has an error
path to reuse), avatar picker (~8), login screen backdrop (~10). **~60 lines.**

Cadre (#10) needs **nothing** — it already reports the status verbatim.

### Constraints

- **No new dependencies, no `pubspec.yaml` change.** Nothing above needs one.
- **Android must not regress.** Every change is additive: a static field, a banner widget,
  and one call per site. No existing branch is removed, and the stale-fallback behaviour at
  `offline_cache_service.dart:148` and `discovery_screen.dart:644` is preserved exactly.
- **Web must not regress.** The banner is a plain widget with no platform code.
- **Verifiable against a real 403 while the outage lasts — yes, but only on a device**, and
  only while the window is open. `flutter build web` plus a browser would verify the web
  half at any time.

### One thing I would not do

Do not make `AnilistService` throw on non-200. Eight call sites currently rely on getting
`[]` or `null` back, and three of them (`offline_cache_service.dart:148`,
`discovery_screen.dart:644`, `:659`) use exactly that empty return to trigger their stale
fallback. Throwing would bypass the fallbacks and make the outage **more** visible by making
the app **less** useful.

---

## Part E — headers, scoped separately

> **Verdict `[SRC]`: ~22 lines to route all ten through one constant. None of it caused
> anything — a browser UA gets the identical 403 `[LIVE]`.**

| `file:line` | User-Agent sent |
|---|---|
| [anilist_service.dart:52-54](lib/services/anilist_service.dart#L52-L54) | `Hanj/1.0` |
| [pulse_service.dart:27-29](lib/services/pulse_service.dart#L27-L29) | `Hanj/1.0` |
| [edit_profile_screen.dart:74](lib/features/profile/edit_profile_screen.dart#L74) | **`Aruku/1.0`** — the old project name |
| [anime_detail_screen.dart:181](lib/features/anime_detail/anime_detail_screen.dart#L181) | none |
| [anime_detail_screen.dart:224](lib/features/anime_detail/anime_detail_screen.dart#L224) | none |
| [anime_calendar_screen.dart:115-118](lib/features/calendar/anime_calendar_screen.dart#L115-L118) | none |
| [discovery_screen.dart:634](lib/features/discovery/discovery_screen.dart#L634) | none |
| [home_screen.dart:1957](lib/features/home/home_screen.dart#L1957) | none |
| [anilist_import_screen.dart:114](lib/features/import/anilist_import_screen.dart#L114) | none |
| [cadre_roster_service.dart:199-202](lib/cadre/services/cadre_roster_service.dart#L199-L202) | none |

**Cost:** one `static const Map<String, String> anilistHeaders` on `AnilistService`
(~4 lines), then replacing the header literal at nine sites (~2 lines each, ~18). **~22
lines, 9 files**, no behaviour change. `Aruku/1.0` is the same string as the phantom `aruku`
Functions codebase in `firebase.json` — worth correcting for consistency, not urgency.

---

## F. What needs the phone back on USB

Nothing in this report was observed on a device. These are the findings that need it, and
**the outage window has to still be open for the first four**:

1. **What each surface actually renders during the outage** — Discovery, Pulse, title
   detail, Calendar, Home. Part A predicts eight silent empties; unverified.
2. **Whether Home trending serves stale data with no indication** (Part C). This is the
   headline prediction and the one that most changes the fix.
3. **`AniList HTTP 403` in logcat**, from `anilist_service.dart:174`. One `adb logcat | grep`
   during a cold start settles whether the service path is even reached.
4. **Whether Cadre and Import really do show their messages** — the two sites that should be
   legible. Cadre should read "AniList returned 403. Try again."
5. **Whether the app's own requests get the same 403 as the host.** Same LAN and NAT, so it
   should, but device-specific headers were never tested from the device — `curl`, `wget`,
   `nc` and `python` are all absent from the device shell, so this needs the app itself or
   another method.

After the outage ends, 1-4 become unreproducible until the next one. If the phone comes back
while AniList is still 403, that capture is worth taking before anything else.
