# Hanj — Mark Render Sizes and Optical Cuts

**Date:** 2026-09-05
**Commit:** `5be7a6a` (merge of `chore/sharecard-mark`)
**Companion to:** `AUDIT.md`, `PERF.md`

**This is a record, not a proposal. Nothing here has been implemented, and the open
question in §5 should not be acted on without a decision.**

---

## 1. The two cuts

The mark is a three-stroke fan. It now exists in two optical cuts, the way a display
typeface has optical sizes. This is deliberate, not drift.

| Cut | Stroke widths | Vector master | Used by |
|---|---|---|---|
| **Display** | 9.0 / 6.5 / 4.5 | `assets/icon/hanj_wing.svg` | the icon set only |
| **Text** | 11.0 / 7.5 / 5.0 | `assets/icon/hanj_wing_text.svg` (+`_mono`) | the nine inline sites |

The text cut also opens the gaps between strokes and shortens the third stroke. Both are
reproducible from `tools/regenerate_brand.py` and `tools/regenerate_text_cut.py`.

The display cut feeds the adaptive foreground, monochrome, legacy, round, PWA icons and
the favicon. None of those changed when the text cut landed.

## 2. Where the mark renders, and at what size

All nine inline sites load the same file, `assets/images/hanj_wing_transparent.png`
(96/192/288 px for 1.0x/2.0x/3.0x), so **all nine are on the text cut**. There is no
per-site override.

| Size | Sites |
|---|---|
| **18** | `features/profile/ranking_cards.dart:222`, `:478`, `:746`; `widgets/share_card.dart:283` |
| **22** | `features/cards/hanj_card.dart:989` |
| **48** | `features/auth/login_screen.dart:489` |
| **56** | `features/cards/card_unlock_overlay.dart:284` |
| **72** | `features/onboarding/onboarding_screen.dart:301` |
| **78** | `features/profile/profile_screen.dart:539` |

Four sites at 18, one at 22, then a gap, then four sites spread across 48–78. The
distribution is bimodal, which is what makes a two-cut split coherent at all.

## 3. Measured separation

Method: downscale each asset to true device pixels on `#0A0414` (the share-card
background) with high-quality filtering, then walk the central 50% of columns. A stroke
band opens at 55% of peak ink and closes at 34% (hysteresis). **Gap depth** is
`1 − mean(valley floor) / mean(peak)`, averaged over those columns — 100% means the gaps
reach background, 0% means the strokes have merged.

| | 18px display → text | 48px display → text |
|---|---|---|
| dpr 1 | 86% → **89%** | 100% → 100% |
| dpr 2 | 96% → **99%** | 100% → 100% |
| dpr 3 | 99% → **100%** | 100% → 100% |

3/3 strokes resolved in every cell, both cuts. The text cut improves 18px at every dpr and
does not regress 48px.

Two limits on these numbers, both important:

- **The metric saturates.** At 48px both cuts are already at 100%, so gap depth cannot
  distinguish them there, and cannot say anything at all about 56–78. It measures
  separation, not weight, balance or elegance.
- **It stops one dpr short of the target device.** `PERF.md` records the CPH2573 at
  density 640, **DPR 4.0**. There is no 4.0x variant, so on that device Flutter takes the
  3.0x (288px) asset and scales it up — a path none of the figures above cover.

## 4. Observed, not measured

- The display cut's **third stroke is thin enough to disappear over light backgrounds.**
  Visible on the login screen, where the mark sits over a photographic backdrop: across
  pale regions the top stroke drops out and the fan reads as two strokes. The text cut's
  heavier third stroke holds.
- Above roughly 48, **the text cut reads bolder, with a stubbier third stroke.** Its fan is
  less evenly graduated than the display cut's — the bottom stroke is long, the top one
  short — so the silhouette is chunkier and grouped more loosely.

Both are visual judgments from side-by-side renders of the login screen at 48. Neither is
captured by the §3 figures.

## 5. Open: 56–78 is unvalidated

The text cut was **drawn against 18px and validated at 48px.** Nothing above 48 was
checked by either of us. That leaves four sites — 48, 56, 72, 78 — carrying a cut chosen
for the small end, and §4 says the character difference grows with size rather than
shrinking.

So there may be a case for a third split, or for returning the large sites to the display
cut. If that gets picked up:

- **Set the threshold from the sizes in §2**, which cluster 18/22 against 48/56/72/78. The
  natural boundary is somewhere in the 22–48 gap.
- **The 96px rule in the earlier briefs was wrong** and should not be used. No site renders
  the mark anywhere near 96 — the largest is 78. A 96px threshold would put every one of
  the nine sites on the small-size cut, which is not a split at all.
- Validate at 56, 72 and 78 before changing anything, and at DPR 4.0 on the CPH2573 rather
  than in Chrome, per §3.

A split costs a second asset at all three densities and a per-site decision at nine call
sites, against a difference that is currently a judgment call. It is not obviously worth
doing. Recorded so the question is not rediscovered from scratch.
