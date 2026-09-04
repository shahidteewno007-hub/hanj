# Hanj — phase two, batch plan

Operating rules from `AUDIT-BRIEF.md` still apply in full: never delete files, never
restructure, no refactoring of working code, no new dependencies, no `firebase deploy`,
no changes to `pubspec.yaml` versions. One branch per batch, one commit per logical fix,
`flutter analyze` and `flutter build web` clean before a batch is done, anything over
~200 lines gets written up instead of done.

Work the batches in order. Stop after batch 3 and wait for me.

---

## 0. Housekeeping first

- Commit `PERF.md`. It's staged; it should be in history.
- `PERF-BRIEF.md` vanished from the project directory mid-session. The copy in
  `Downloads/` is intact — restore it to the project root and commit it. If it
  disappears again, say so rather than restoring it silently; this machine runs Avast
  alongside Defender and one of them may be taking it.
- Run `/init` to generate `CLAUDE.md`, then extend what it writes with the things it
  can't infer: the palette (`#0D0B09`, coral `#E8624A`, ivory `#F3EEE7`), the intended
  type roles, the rule that all AniList calls go through the adaptive throttle, the six
  card rarity tiers, and the constraint that Loki is meant to be owner-gated. This file
  loads automatically in every future session, so it's worth getting right once.

---

## Batch 1 — profile screen

Two things I want fixed, both on the profile screen. This batch is mine, not the
performance report's, and it goes first.

### 1a. Card corners

The card on the profile screen doesn't read as a true square — all four corners look
clipped. I want genuinely square corners.

Find where that radius comes from before you change anything. If it's a shared constant
or theme token, **do not change the token** — that would round off every surface in the
app. Scope the change to this card only, and tell me in the commit message whether the
value was shared or local. If it turns out the corners are already square and something
else is producing the cut-off impression — an overflow clip, a gradient, a border
painted inside the bounds — say that instead of forcing a radius change that doesn't
address the real cause.

### 1b. Founding member card appears late

On opening the profile screen, the founding member card doesn't render immediately —
it appears a couple of seconds in.

Diagnose the actual cause first. My expectation is a Firestore read that resolves after
first paint, but confirm rather than assume.

If that's what it is, the fix has two halves and I want both:

- **Make it fast.** Founder status is immutable by design — it's enforced in the
  security rules and it cannot change once granted. That means it never needs re-reading
  after the first successful fetch. Persist it locally and read from there on subsequent
  loads, refreshing in the background if you like, but never blocking the card on a
  network round trip again.
- **Make it not jump.** Even on a cold first load, the card should not pop into
  existence and shove the layout around. Reserve its space and show a placeholder in the
  same footprint, so the only thing that changes is the content filling in.

---

## Batch 2 — the measured performance wins

Four items from `PERF.md`, all device-measured, all small. Take them in this order —
it's descending by measured impact.

**The countdown rebuild.** 15 janky frames in 15 idle seconds, median build ~17 ms
against an 11.1 ms budget, purely UI-thread. `_timeUntilAiring` feeds exactly one widget
but `setState` rebuilds a 2,190-line screen once a second. Scope the rebuild to the
countdown text — `ValueListenableBuilder` or equivalent. Re-measure the same repro (One
Piece, ON AIR, 15 seconds idle) and record before/after.

**`NotificationService.init()` at startup.** ~1.0 s of a 1,964 ms time-to-first-frame,
on the already-granted fast path. Move it off the pre-`runApp` path so it doesn't block
first paint. Be careful that nothing downstream assumes it has completed — FCM token
saving happens in `auth_service.dart`, so check the ordering there specifically. Measure
time-to-first-frame before and after.

**The duplicate `getSeasonal` call.** Two widgets on the same screen call it with
identical arguments, so one of the three requests on every Home mount is pure waste.
Deduplicate it. Separately, the static caches seed display state without suppressing the
fetch — if making them actually short-circuit the request is small and safe, do it; if
it turns out to be a structural change to the caching layer, write it up instead and
leave it for a batch of its own.

**`RepaintBoundary` on the card glow painters.** Collection scroll is raster-bound: 26
of 183 frames over budget, worst raster 20.4 ms, zero build frames over. `MaskFilter.blur`
with no paint isolation. You estimated ~5 lines — try it, measure the same scroll, and
if the numbers don't move, revert it rather than keeping it on theory.

For all four: an optimisation with no measured improvement gets reverted. And nothing
here is allowed to weaken the AniList throttle, shorten a backoff, drop a `mounted`
check, or remove error handling.

---

## Batch 3 — the font decision, which you do not land on your own

`AppTheme.sans()` resolves to Inter across 224 call sites while DM Sans is used directly
at 84. The app's actual body typeface is Inter and I did not know that.

I want to decide this with the app in my hand, not from a description. So:

1. On a branch, repoint `AppTheme.sans` to DM Sans.
2. Build and install on the CPH2573.
3. Capture the same five screens both ways — home, profile, anime detail, card
   collection, and one dense text screen. Before and after, same content, same scroll
   position.
4. Write up what changed beyond the obvious: DM Sans and Inter have different metrics,
   so look for line-wrap changes, clipped text, buttons whose labels no longer fit, and
   anywhere the vertical rhythm shifts.
5. **Stop there.** Leave it on the branch, unmerged, and tell me it's ready. I'll look at
   the screenshots and decide.

Do not take the alternative route of repointing DM Sans call sites to Inter to make the
codebase consistent with what ships. That's consistency in the wrong direction.

---

## Explicitly not now

Report on these if you learn something, but don't act:

- **Consolidating the type scale.** 61 distinct sizes across three roles is real debt,
  but fixing it touches most files in the app and can't be reviewed as one diff. It
  needs its own plan.
- **The 20 Playfair sites under 18 px.** Related to the above, same reason. List them in
  `PERF.md` with sizes so I can see the shape of it.
- **Font bundling.** It fails the 1.5 MB test at six families and 20 files, and Noto
  Serif JP is megabytes on its own for four call sites. The right first move is dropping
  families the app doesn't need, and that's downstream of the Inter/DM Sans decision.
- **Image cache sizing.** Your pushback was correct: at DPR 4.0 the grid cells are larger
  than AniList's `large` asset, so `memCacheWidth` there would soften the art for no
  gain. Leave it. If you want to pursue the small-thumbnail case, measure it first.
- **The Loki owner gate.** Deferred deliberately — the only tester can't reach the
  current build. It needs a deploy and a policy decision from me about whether it's
  owner-only or beta-tester-wide.

---

## Device notes

Driving the CPH2573 over adb: swipes that end low trigger gesture navigation and throw
the app to the launcher. The repro section in `PERF.md` has the nav-bar coordinates —
use them.

The phone currently has a debuggable profile build on it (versionName 1.0.1). That's
fine for measurement work, but don't treat its timings as release timings, and remind me
to reinstall the release build when this session's measuring is done.

Start with housekeeping, then batch 1.
