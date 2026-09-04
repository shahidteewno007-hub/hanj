# Hanj — web app

New workstream. The security batches (5d, 5e) and the queued performance items
(4b, 4c, 4d, the `_ContinueCard` repro, the arcs fix) are unaffected and still queued —
this does not replace them.

Standing rules from `AUDIT-BRIEF.md` apply. One additional rule specific to this work,
and it is the most important line in this file:

**The Android app must not regress.** Every responsive change touches layout code that
the phone app also runs. A change that improves desktop and quietly breaks a phone screen
is a net loss — Android is the shipped product and web is the addition. Verify on the
CPH2573 before any batch is called done, with the `lastUpdateTime` install check from
`CLAUDE.md`.

---

## What I want

Two surfaces from the one Flutter codebase:

- **Desktop web, deliberately designed for a large screen.** Not the phone layout
  stretched to 2560 px. A real desktop layout that uses the width.
- **Mobile web that matches the phone app.** This half should be close to free, since the
  app is already phone-shaped. The job here is making sure it behaves like an app in a
  browser rather than a website that happens to be narrow.

The driving reason is iPhone. There is no iOS build and web is how those users get in.

---

## Phase 1: audit — report only, change nothing

Write `WEB.md`. Same standard as `PERF.md`: measure, don't guess, and mark clearly what
you measured versus what you suspect.

### What breaks with width

Run the web build and step through widths: 390, 768, 1024, 1440, 1920. For each screen,
record what breaks. I expect three failure modes and want them separated:

- **Stretch** — a phone layout spanning the full width, line lengths becoming unreadable,
  a two-column grid becoming two enormous columns.
- **Hardcoded dimensions** — fixed pixel widths and heights that assume a phone. Find every
  one. Note which are genuinely fixed by design (icon sizes, card aspect ratios) and which
  are phone assumptions in disguise.
- **Broken** — overflow errors, clipped content, unreachable controls.

### Web-specific behaviour

The double-`SafeArea` bug survived for months because it was invisible on web. The reverse
class exists too — things that only break in a browser. Check specifically:

- **Browser back button and history.** Does back navigate the app or leave it? This is the
  single most common way a Flutter web app feels broken.
- **Deep links and URLs.** Does any screen have an addressable URL? Can a user share a link
  to an anime? If the whole app lives at one path, say so — it's a real limitation for a
  shareable-card app.
- **Auth.** Does Google sign-in work on web? Firebase auth uses popup or redirect flows on
  web rather than the native path, and popups get blocked. Test it signed out, in a fresh
  profile, on both Chrome and Safari.
- **Scroll.** Mouse wheel, trackpad momentum, and scrollbars — Flutter web often gets scroll
  physics subtly wrong.
- **Hover.** Nothing in a phone-built app has hover states. Note where they're needed, don't
  build them yet.
- **Text selection and find-in-page**, and right-click.
- **iOS Safari specifically.** It's the whole point of this work and it's the most likely
  browser to have problems. If you can't test it directly, say so plainly rather than
  assuming it matches Chrome.

### Measure the load

Bundle size, time to first paint, time to interactive. Desktop and throttled mobile, cold
cache and warm. This is the weakest part of Flutter web and I want the real numbers before
deciding how much to care.

Font loading is already known to be part of this — the `google_fonts` runtime fetch and the
family count from 4b both land here.

### PWA readiness

What exists in `web/` today: manifest, icons, service worker, theme colour, splash. Report
what's there, what's default Flutter boilerplate, and what's missing for a real
add-to-home-screen experience on iOS.

Note explicitly: web push on iOS only works for home-screen-installed PWAs. Since episode
reminders are a core feature, work out what that means for an iPhone user and write it
down.

### Screen inventory

List every screen, and rank by how much responsive work each needs against how important it
is. I want to fix the five screens that matter before the twenty that don't.

---

## Phase 2: propose the desktop design — report, don't build

Write it into `WEB.md`. I'll review before anything is implemented.

The app's identity does not change. Same palette (`#0D0B09`, coral `#E8624A`, ivory
`#F3EEE7`), same typefaces, same card rarity treatments. This is a layout system, not a
redesign.

Cover:

- **Breakpoints.** As few as possible. Justify each one from the audit rather than copying
  a framework's defaults.
- **Navigation.** Bottom nav works on a phone and is wrong on a desktop. Propose the
  desktop pattern — rail, sidebar, top bar — and say how it maps to the existing structure
  so the two don't diverge into different information architectures.
- **Content width.** Nothing should span 2560 px of text. Say what's constrained and to what.
- **Grids.** The card collection is two columns on a phone. Say what it becomes at each
  breakpoint, keeping the card aspect ratio intact.
- **What desktop can do that the phone can't.** Detail alongside list, persistent sidebar,
  more visible at once. Propose the ones that are genuinely better, not everything possible.
- **How this is implemented.** A shared responsive layer both platforms use, or per-screen
  branching? Say which, and what it costs in review surface. I'd rather have one boring
  mechanism used everywhere than clever per-screen decisions.

---

## Phase 3: implement — on my approval, in priority order

One branch per screen or small group. Each one verified at all breakpoints **and on the
phone** before it's called done.

Take the highest-value screens first, and stop after the first two so I can look before the
pattern gets applied everywhere.

---

## PWA and hosting

Separable from the responsive work and can land earlier if it's quick — a proper manifest,
real icons at all required sizes, theme colour, offline shell.

Firebase Hosting is already in the project. Rules deploys are unaffected by the `aruku`
block, and hosting should be too, but confirm with a dry run before assuming — and as
always, **you do not deploy, I do**. Tell me the command and what it will publish.

One thing to check before anything ships publicly: the web build has to be pointed at a
Firebase config, and its rules are the ones we've just hardened. A public web build is a
much easier target to inspect than an APK. Confirm there is nothing in the web bundle that
isn't already in the Android build.

---

## Not in scope

- No redesign of the visual identity.
- No new features. This is the existing app on a second surface.
- No touching the four unrecovered screens — they're rebuilds and they're separate.
- No SEO or server-side rendering work. Flutter web can't do it meaningfully and I don't
  want effort spent pretending otherwise.

Start phase one. Write `WEB.md`, change nothing, and stop.
