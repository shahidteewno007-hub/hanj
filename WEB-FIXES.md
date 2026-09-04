# Hanj — web fixes

Follows `WEB-APP.md` phase one. Standing rules apply, including the one that matters most
here: **the Android app must not regress**, and every batch is verified on the CPH2573
with the `lastUpdateTime` install check before it's called done.

Phase two of `WEB-APP.md` stays paused. I'm capturing the width screenshots manually,
since headless Chrome couldn't get past `AuthWrapper`, and the desktop design shouldn't be
proposed on Suspected data. I'll tell you when they're ready.

---

## W1. Google sign-in on web — the blocker

Nothing else in this workstream matters if iPhone users can't sign in.

You established the shape: `google_sign_in_web-1.1.3` doesn't implement `authenticate()`
and `supportsAuthenticate()` returns false, so web needs the `renderButton` flow;
`initialize()` fails before that anyway because `serverClientId` is unsupported on web and
no `clientId` is provided; and in a release build the asserts compile out so it fails on a
null check with a worse message.

I'm supplying a Web application OAuth client ID from Google Cloud Console. Use it.

Requirements:

- Branch the auth path by platform. The Android flow works and ships — **do not change
  it**, do not unify the two behind a clever abstraction, and do not refactor
  `auth_service.dart` beyond what the web path needs. A regression in Android sign-in is
  far worse than no web sign-in.
- Web uses `renderButton`. Note that this means Google's own rendered button rather than
  the custom-styled one on Android — say how far it can be styled toward the app's
  identity, and if the answer is "barely", say that.
- Handle the release-build failure mode. Whatever happens, a user who can't sign in should
  see a real message, not a blank screen or a null-check crash.
- Verify signed out, in a fresh browser profile, on Chrome and on Firefox. Test the popup
  being blocked, since that's the normal case for a first-time visitor.
- Confirm email/password still works on both platforms afterwards.

The authorised origins in Google Cloud need to include wherever this gets hosted plus
`localhost` for development. Tell me exactly what to add rather than assuming I know.

---

## W2. The loading shell

4.05 MB before first paint, landing on a bare dark `Scaffold` with nothing on it. A
first-time visitor on a slow connection sees a blank screen for several seconds and
concludes the link is broken.

Put a real loading state in `web/index.html` — plain HTML and CSS that paints immediately,
before Flutter boots, and is removed when the app takes over. The Hanj wordmark or logo,
the app's own background (`#0D0B09`), and a coral (`#E8624A`) progress indicator. It
should look like the app is starting, not like a page is loading.

Two things to get right: the background colour must match what Flutter paints first, so
there's no flash at handover; and it must not depend on a webfont, since fetching one
defeats the purpose.

This doesn't make the bundle smaller. It makes the wait legible, which is most of the
perceived problem.

---

## W3. Fonts — 4b, now with a web reason

`BATCH-FOUR.md` 4b is still open: six Inter call sites in `login_screen.dart` and
`onboarding_screen.dart`. On Android that's tidying. On web the login screen downloads an
entire extra family to render itself, on the first screen anyone sees.

Do 4b. Then report the family count and the total font bytes fetched at runtime on the
login path specifically.

With that number, revisit bundling. It failed the 1.5 MB test at six families, but the web
case is different from the APK case — a runtime fetch on web is a blocking network request
before text renders, not just size on disk. Give me the numbers for both surfaces and your
recommendation. If Noto Serif JP for four call sites is what's blocking the decision, say
whether those four sites can use something already loaded.

---

## W4. Hosting

There's no `hosting` block in `firebase.json`, so there's nothing to deploy. Add one.

Then a dry run to confirm hosting deploys aren't caught by the `aruku` block, the way rules
weren't. Report the command and exactly what it would publish. **You do not deploy.**

Don't add this to a deploy that also touches functions or rules. Hosting goes out on its
own, first time.

---

## W5. Routing — proposal only

60 of 62 navigations are inline `MaterialPageRoute` and the whole app lives at one URL.
Converting all of them is an architecture change I'm not authorising on the strength of a
shared-link problem.

I don't think I need 62 addressable screens. I think I need about three: an anime detail
page, a public profile, and whatever a shared card should point at. Everything else can
stay inline.

Write up whether that hybrid is actually workable — a router handling a small set of
entry-point routes with the existing inline navigation continuing underneath — or whether
adopting a router is all-or-nothing in practice. If it's all-or-nothing, say so and give
me the real cost, including how the browser back button behaves in each case.

Include what a shared card's URL should contain, and what happens when someone opens it
signed out. That's the growth path, so it should work for a stranger.

**Proposal in `WEB.md`. Implement nothing.**

---

## Also

- **5d before any of this goes public.** `followers`/`following` still carry
  `allow read: if true` and any-signed-in-user write. Your point that a web bundle is
  easier to inspect than an APK is right, and it moves 5d ahead of the web launch rather
  than after it.
- **iOS reminders.** Don't build the install flow yet — I need to decide how this is
  presented. Write up what an honest iPhone experience looks like: what works, what
  doesn't, where the app should say so, and what an install prompt would need to do given
  that the permission request has to come from a user gesture rather than `main()`.

Order: W1, W2, W3, W4. Stop before W5 if the session is short — the proposal can wait, the
blocker can't.
