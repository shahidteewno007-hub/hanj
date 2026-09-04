# Hanj — performance and typography brief

Same operating rules as `AUDIT-BRIEF.md`. Read that file first if you have not already:
never delete files, never restructure, never refactor working code, no new dependencies,
no `firebase deploy`. This brief adds a second area of work, it does not replace those
constraints.

---

## The rule for this brief

**Measure before you change anything.**

"Make it faster" without measurement produces a large diff full of plausible-looking
optimisations that fix nothing, and it is unreviewable. Every change you propose must
trace back to something you actually observed being slow. If you cannot point at a
measurement, it does not go in the batch.

Phase one is a report. Phase two is fixes I have picked. Do not begin phase two on your
own initiative.

---

## Phase one: profile and report

Write `PERF.md`. Change no application code. You may add temporary instrumentation to
take a measurement, but remove it before you finish and do not commit it.

### Where to measure

Run in **profile mode**, not debug — debug-mode timings are meaningless because
assertions and unoptimised code dominate everything.

```
flutter run --profile -d chrome
```

Critically: **web timings are not the answer here.** The audit already established that
this codebase hides device-only bugs behind the Chrome dev loop — `padding.top` is 0 in
a desktop browser, which is exactly why the double-`SafeArea` inset survived for months.
Performance has the same shape. A screen that scrolls smoothly on a desktop browser can
be dropping frames badly on a mid-range Android phone.

The target device is an Oppo CPH2573. I have to run device builds myself, so structure
`PERF.md` so I can carry out the device measurements and hand you back the numbers:
write the exact commands, say what to tap, and say what number to read off. Do the web
profiling yourself, mark clearly which findings are web-measured and which are waiting
on device data, and never present a web timing as if it were a device timing.

### What to look for

**Frame timing.** Which screens drop frames, and is it the UI thread or the raster
thread? They have completely different causes and the distinction changes the fix
entirely. Name specific screens, not "the app".

**Startup.** Time from launch to first usable frame. Break it into phases: Flutter
engine start, Firebase init, auth restore, first data fetch, first paint. Say which
phase dominates. Look specifically for work in `main()` that blocks first paint and
could be deferred or run in parallel.

**Rebuilds.** Widgets rebuilding when their inputs did not change — `setState` too high
in the tree, a provider that notifies on every write, a `Timer.periodic` rebuilding
whole subtrees. The live episode countdown on the anime detail screen uses
`Timer.periodic` and is the obvious first place to check: if that rebuilds more than the
countdown text itself, that is a finding.

**Network.** This is where I expect the real problems to be, so spend proper time here.

- Any Firestore or AniList call made inside `build()`.
- AniList requests that miss the in-memory cache when they should hit it. There is an
  adaptive throttle at 350ms with a 2s backoff — count actual requests per screen and
  say whether the caching is working or just present.
- `offline_cache_service.dart` has an in-memory layer with stale fallbacks. Verify it is
  genuinely serving reads rather than being bypassed.
- Firestore listeners that stay attached after their screen is disposed.
- Queries fetching whole documents or collections where a narrower query would do.

**Images.** `cached_network_image` is in use. Look for full-resolution AniList cover art
being decoded into small grid thumbnails — no `cacheWidth`/`cacheHeight`, no
`ResizeImage`. On a 2-column grid this is often the single biggest raster-thread cost
and it is usually a few lines to fix.

**Lists.** Any `ListView`/`GridView` building all children eagerly instead of lazily,
and any expensive work happening per-item during scroll.

**Card rendering.** The collection screen is a 2-column grid across six rarity tiers,
and `card_unlock_overlay.dart` runs a 3D flip with a particle painter and a radial glow.
Custom painters and repeated shader work are common raster-thread costs. Check whether
the particle painter repaints when nothing has changed, and whether `RepaintBoundary` is
used where it should be.

### How to report

Rank findings by **measured impact**, not by how easy they are to fix. For each one:
what you measured, the number, which files, the proposed fix, and rough effort.

Separate them into:
- **Measured** — you have a number.
- **Suspected** — it looks wrong but you could not measure it, usually because it needs
  the device. Say what measurement would confirm it.

Be honest about the split. A short report of things you actually measured is worth far
more to me than a long list of things that might in principle be slow.

---

## Typography

The font families are **not** up for discussion. Playfair Display for headings, DM Sans
for body, Space Grotesk for numerals and mono. These are the app's identity — they are
on the store listing and in the shareable cards people post. Do not propose replacing
them, do not propose adding a fourth family, and do not substitute anything "cleaner" or
"more modern". A request to improve typography here means improving how these three are
used.

What to actually audit:

**Consistency.** Find every place a text style is defined inline rather than pulled from
the theme. Report where the same semantic role (screen title, card title, body, caption,
numeral) is rendered at different sizes or weights in different places. Propose a
consolidated scale that covers what is actually in use — do not invent roles that
nothing needs.

**Readability on a phone.** Playfair Display is a display serif and it does not survive
being set small. Flag every place it is used below roughly 18px, or with line-height too
tight for its size, or in a long run of body text where DM Sans belongs. Flag any body
text under 14px, and any line length that runs too long to read comfortably.

**Hierarchy.** Places where two adjacent elements are too close in size or weight for
their difference in importance to read.

### The one change worth making

`google_fonts` fetches font files over the network at runtime by default and caches them
after first use. On a cold start with poor connectivity, text paints in a fallback font
and then reflows when the real font arrives — visible, ugly, and a genuine load-time
cost.

Fix it by bundling the font files as assets and declaring them in `pubspec.yaml`, so
they are available at first frame with no network dependency. Include only the weights
actually used — measure which those are first, since bundling nine weights of three
families would add megabytes to the APK for nothing.

Report the expected APK size change alongside the fix. If it comes out larger than
roughly 1.5MB, say so and let me decide rather than assuming I want it.

---

## Phase two

Only on my say-so, and under `AUDIT-BRIEF.md` phase-two rules: one branch per batch,
one commit per fix, `flutter analyze` and `flutter build web` clean before you call a
batch done, and anything over ~200 lines gets written up instead of done.

Two additions specific to performance work:

- **Re-measure after each fix** and record the before/after in `PERF.md`. An
  optimisation with no measured improvement gets reverted, not kept because it seems
  theoretically better.
- **Never trade correctness for speed.** Do not weaken the AniList throttle, shorten a
  backoff, drop a `mounted` check, or remove error handling to save a frame. Blank
  screens from rate limiting were a real bug in this app once and I am not having them
  back.

Start phase one. Write `PERF.md`, change nothing else, and stop when it's done.
