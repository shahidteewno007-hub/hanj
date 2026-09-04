# Hanj — audit and fix brief

This is an existing, feature-complete Flutter + Firebase app with a signed release
build already produced. It is **not** a greenfield project and must not be treated as
one. Your job is to find what is actually wrong and fix it surgically, not to improve
the codebase in general.

Read this whole file before starting.

---

## 0. Context you need

Hanj is an anime tracker: Flutter (web + Android), Firebase (Auth, Firestore, Cloud
Functions v2), AniList GraphQL API. Package `com.anitrack.anime_tracker`, Firebase
project `anime-tracker-275cc`.

**This codebase was recovered from a data-loss incident.** The `lib/` tree was
reassembled file by file from a Recycle Bin export, matched against screenshots of a
working APK. It runs and matches the last known-good build, but that history explains
things you will notice: a few screens are missing entirely, some code looks like it was
written by someone who could not see the rest of the file, and there may be orphans.

Two consequences, both non-negotiable:

- **Never delete a file.** If something looks dead, list it in the report as a deletion
  candidate and leave it alone. A file that looks orphaned may be the only surviving
  copy of a screen.
- **Never restructure.** No renaming files, no moving code between files, no
  reorganising folders, no "cleaning up" the architecture. The current shape of this
  tree is the output of a careful reconstruction and I need it to stay recognisable.

---

## 1. Phase one: audit only — change no code

In this phase you write exactly one file, `AUDIT.md`, and modify nothing else. Do not
fix anything yet, however trivial and however tempting. I want to read the whole
picture before any of it changes.

Cover:

**Architecture map.** What is in `lib/`, how the screens relate, where state lives, how
Firestore and AniList are reached. Written for someone who knows the app but has not
looked at the code in two months.

**`flutter analyze`.** Run it, then categorise every result: real bug, latent bug,
style noise. Do not just paste the output — the raw list is not useful, the triage is.

**Correctness sweep.** Read the code looking for: unawaited futures, missing `mounted`
checks after async gaps, `setState` after dispose, unhandled exceptions on network
paths, `null!` assertions that can actually be null, and any place a Firestore listener
or `Timer` is started and never cancelled. The live episode countdown uses
`Timer.periodic`, so check that one specifically.

**AniList integration.** There is an adaptive rate-limit throttle (350ms, 2s backoff)
with in-memory caches. Verify every AniList call actually goes through it — a call that
bypasses the throttle causes blank screens under load, which was a real bug here once.

**Known parked issues.** These are already known broken and are the highest-value
targets. Investigate each and propose a fix in the report:
- Shareable cards: vertical centring on the 9:16 canvas is wrong.
- Pulse and Discover screens: SafeArea gap on device.
- Missing screens never recovered: `wrapped_screen`, `reviews_screen`,
  `public_profile_screen`, `splash_screen`.
- `arcs_screen` needs redoing.
- Cloud Function `episodeReminderPrecise` is written but never deployed.

**Security.** Read `firestore.rules` and check every collection is actually protected —
particularly founder immutability, reply likes, and anything owner-gated. Loki (the AI
companion) is meant to be restricted to a single owner UID and capped at 40 messages a
day; verify that gate is real and enforced server-side, not just hidden in the UI.

**Dependencies.** `flutter pub outdated`. Flag anything unmaintained or with a breaking
major available, but propose nothing beyond flagging.

**TODO/FIXME sweep.** Collect them all with file and line.

End the report with a **ranked table**: severity, what it is, which files, rough effort.
Sorted by what I should fix first. Then commit `AUDIT.md` and stop.

---

## 2. Phase two: fixes, in batches

Only after I have read the report and told you which items to take.

- One branch per batch: `fix/<short-name>`. Never commit to `main` or `master`.
- One commit per logical fix, with a message saying what broke and why the fix works.
- After every batch: `flutter analyze` and `flutter build web`, both clean, before you
  say the batch is done.
- If a fix turns out to need more than about 200 changed lines, stop and write up why
  in `AUDIT.md` instead of doing it. Large changes need a conversation first.

**Do not**, at any point, without me asking for it specifically:

- refactor working code
- reformat files you are not otherwise changing
- upgrade dependencies or edit `pubspec.yaml` versions
- add a new dependency
- change the design system — the palette (`#0D0B09`, coral `#E8624A`, ivory `#F3EEE7`),
  the fonts (Playfair Display, DM Sans, Space Grotesk) and the card rarity tiers are all
  deliberate and settled
- touch `firebase_options.dart`, the keystore, or anything credential-shaped
- deploy Cloud Functions or run `firebase deploy`

---

## 3. Environment

- Windows 11, project at `C:\Users\ABC\anime_tracker`.
- Dev loop is `flutter run -d chrome`. Android device testing is manual and mine to do.
- JDK 17 portable at `C:\Users\ABC\Dev\jdk17`; Android SDK at `C:\Users\ABC\Dev\android-sdk`.
- `GRADLE_USER_HOME` is `C:\g` for Windows path-length reasons. Do not change it.
- Firebase CLI is `firebase.cmd`, and you are not to run deploys with it regardless.

Start phase one now. Write `AUDIT.md`, change nothing else, and stop when it's done.
