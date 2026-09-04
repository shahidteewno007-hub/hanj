# Hanj — batch four

Operating rules from `AUDIT-BRIEF.md` still apply: never delete files, never restructure,
no refactoring of working code, no new dependencies, no `firebase deploy`. One branch per
batch, one commit per logical fix, `flutter analyze` and `flutter build web` clean before
a batch is done, anything over ~200 lines gets written up instead of done.

Housekeeping first: commit `AUDIT-BRIEF.md` and `PHASE-TWO.md` if they're still
untracked, and this file with them.

---

## 4a. The sliver key sweep

This is the important one, and it is a correctness batch, not a performance batch.

You found that the recommendation slivers on Home are unkeyed `SliverToBoxAdapter`s, so
`canUpdate()` matches on `runtimeType` alone and `UpcomingAnimeRow`'s element gets handed
a recommendation row — mounting it twice per load. The duplicate network request is how
you noticed it, but it is the mildest possible symptom. The same defect also produces a
widget briefly showing another widget's data, controllers surviving into the wrong tile,
animation and scroll state bleeding between rows, and images appearing under the wrong
title. Those read as "the app is a bit glitchy sometimes" and never get reported as
bugs.

In a tree that was reassembled file by file from a recovery, one instance of a mistake
like this is a poor bet. Sweep for it.

**Find every dynamic sliver or child list in the app** where children are built from a
collection, conditionally inserted, or reordered — `SliverToBoxAdapter`s built in a list,
`SliverList` delegates, `Column`/`Stack` children assembled conditionally, anything where
the set of children can differ between builds. For each one, say whether the children
carry keys, whether the set can actually change at runtime, and what would go wrong if
elements were mismatched.

Fix the ones where mismatch is possible, with `ValueKey`s derived from stable identity —
an AniList media id, a document id, a section name. **Not the list index.** An index key
reintroduces exactly the bug when the list reorders.

Report the ones where the child set is genuinely fixed and keys would be noise. I would
rather see "checked, not needed, here's why" than have you key everything defensively.

Verify the Home fix the way you verified the original: instrument `initState`, confirm
`UpcomingAnimeRow` mounts once per Home load rather than twice, then remove the
instrumentation.

---

## 4b. The six Inter stragglers

The DM Sans change is merged. Six Inter call sites remain outside the theme in
`login_screen.dart` and `onboarding_screen.dart`, which means the app still fetches Inter
on the login path — the first screen anyone sees — and the family count stays at six.

Repoint them to the theme. Then report the actual family count and which families remain,
because that number is the input to the bundling decision and I want it measured rather
than assumed.

While you're in there: if any of the six were using Inter at a size or weight the theme
doesn't offer, say so rather than forcing the nearest match silently.

---

## 4c. Pre-render the card glow

Your own diagnosis of why the `RepaintBoundary` failed was right, so take the fix you
proposed instead: the glow is expensive because `MaskFilter.blur` runs per card per
scroll, and there are only six rarity tiers. Render each tier's glow once, cache it, and
draw the cached result.

Measure the same collection scroll you used before — 183 frames, 18 over budget, worst
raster 20.4 ms is the baseline to beat. Same rule as last time: if the numbers don't
move, revert it and write up why rather than keeping it on theory.

Do not change how any rarity actually looks. If the pre-rendered glow differs visibly
from the live one at any tier, that's a failed fix, not an acceptable trade.

---

## 4d. The deploy blocker — investigate only

Phase one hypothesised that `firebase.json` declares a second codebase `aruku` pointing
at a directory that doesn't exist, and that config validation fails before the CLI ever
reads `functions/index.js` — blocking all ten functions, which would explain why
`episodeReminderPrecise` is complete, correct, and has never run in production.

Confirm it:

```
firebase.cmd deploy --only functions --dry-run
```

A dry run is permitted. **An actual deploy is not**, under any circumstances, whatever
the dry run says.

Report what it prints. If the hypothesis holds, propose the exact `firebase.json` change
and stop — do not apply it. I want to make that edit knowing what it unblocks, because
the first real deploy after this fix ships ten functions at once, several of which have
never run against production data.

---

## Still deferred

Unchanged, listed so nothing gets picked up on impulse:

- **The Loki owner gate.** Needs a policy decision from me — owner-only or beta-tester-wide
  — and it needs a deploy, so it's downstream of 4d.
- **`arcs_screen`.** A genuine rewrite, over the line limit. But pull out the ~15-line fix
  now if 4a doesn't already cover it: the like toggle reads stale snapshot state and pairs
  an idempotent `arrayUnion` with a non-idempotent `increment`, so a double-tap
  permanently inflates `likeCount`. That's data corruption, not a UI bug, and it's cheap.
- **The four unrecovered screens** — `wrapped_screen`, `reviews_screen`,
  `public_profile_screen`, `splash_screen`. These are rebuilds, not fixes.
- **Type scale consolidation** — 61 sizes across three roles, and 20 Playfair sites under
  18 px.
- **Font bundling** — downstream of 4b's family count.

Start with housekeeping, then 4a.
