# Hanj — batch five: rules, and the deploy path

Operating rules from `AUDIT-BRIEF.md` still apply. One branch per batch, one commit per
logical fix, gates clean before a batch is done.

One change to the standing rules, narrowly scoped: **you may run the Firestore
emulator** (`firebase.cmd emulators:start --only firestore`) to verify rules locally.
You still may not deploy anything. Deploys are mine.

Read `AUDIT.md` §6b before starting — that's your own report and it has the detail.

---

## Why rules get verified locally before they ship

A bad rules deploy takes effect immediately and can lock every user out of their own
data, including me. There is no gradual rollout and no partial failure. So nothing in
this batch goes out on the assumption that it's correct.

For each rule you change, write a test against the emulator that proves both halves: the
access that should be allowed still is, and the access that should be denied now is. If
writing emulator tests turns out to be a large piece of work in its own right, stop and
tell me rather than skipping the verification — I would rather spend a batch on test
infrastructure than deploy rules on inspection alone.

---

## 5a. The users collection read rule — first, and on its own branch

`allow read: if true` on user documents holding `email` and `fcmToken`. Unauthenticated
read access to personal data.

The naive fix is `if request.auth != null`, and that closes the unauthenticated hole. But
think one step further before you write it, because there is a known future requirement:
`public_profile_screen` is one of the four screens lost in the recovery and it will come
back. When it does, some subset of user data has to be readable by other users — and if
the rule is "any signed-in user can read any user document", you are back to exposing
`email` and `fcmToken`, just to a slightly smaller audience.

So propose the shape, don't just patch the line. The direction I would expect is
separating what is public about a user from what is private — a public profile document
or subcollection carrying display name, avatar, founder badge and stats, with `email`,
`fcmToken` and anything else sensitive readable only by the owner. Tell me what that
costs in client changes before you write any of it. If it's large, we do the
`request.auth != null` fix now to close the hole and schedule the split separately, and
that's a perfectly good outcome — say so rather than quietly doing the bigger thing.

Whichever way it goes, `fcmToken` should never be readable by another user under any
rule. A push token in someone else's hands is a channel straight to that person's phone.

---

## 5b. `companion_chat` has no rule

Default deny, so the client read fails and Loki's history never loads, while the function
keeps writing it via the Admin SDK. Add the rule: owner-only read, and no client write at
all, since only the function should ever write there.

Verify against the emulator that the owner can read their own history and that a second
account cannot.

---

## 5c. Founder status — needs my decision before you write anything

Do not implement this yet. I want the options first.

The situation: the rule freezes `founderNumber` once it exists, so the first write is
unconstrained. A tampered client writes the badge to its own document without touching
the counter. And separately, any signed-in user can run the counter to 50 for fifty
writes and deny founder status to everyone else.

My understanding is that client-side claiming cannot be made safe in rules alone — the
client is the attacker in this threat model, and rules can constrain the shape of a write
but not the honesty of the client making it. The claim has to move server-side, into a
callable function using the Admin SDK that checks eligibility, increments the counter and
writes the badge in a transaction, with rules then denying client writes to
`founderNumber` outright.

Write that up as a proposal in `AUDIT.md`: what the function does, what changes in the
client, what changes in the rules, and what happens to the founders who already hold
badges. If you see a genuinely safe rules-only approach I've missed, argue for it — but
be honest if there isn't one.

**Do fix the comment now**, in this batch, whatever we decide about the mechanism. Lines
51–54 assert that the counter constraints make client-side claiming safe, above a rule
that doesn't do that. Replace it with an accurate description of what the rule actually
enforces, and a note that the claim path is not yet secured. A confidently wrong comment
is worse than none, because it stops the next reader from checking.

---

## 5d. The remaining rules findings

- **`followers`/`following` grant any user write access to anyone's follower graph.**
  Latent because the client doesn't use them, which makes this the cheapest possible time
  to fix it. Restrict writes so a user can only modify their own edges.
- **`reviews` and `episodeDiscussions` accept a create carrying someone else's uid.**
  Require the uid on the document to match `request.auth.uid`.
- **Vote counts bounded by key but not by value.** Constrain the values so a vote can
  move a count by one, in one direction, rather than to an arbitrary number.

Emulator tests for each, same standard as above.

---

## 5e. `firebase.json` — the deploy blocker

I'll have run the dry run by the time you read this; the output is in the chat or I'll
paste it in. Assuming it confirms the phantom `aruku` codebase:

Fix `firebase.json` so config validation passes. Nothing else — do not reorganise the
functions config, do not add an `indexes` key, do not change the codebase name of the
functions that work.

Then tell me plainly what the first successful deploy will actually push, because it will
be more than the thing I'm trying to ship. Ten functions that have never run in
production, plus — now that the `firestore` block exists — the rules, which were
previously skipped silently. I want that list in front of me before I run anything.

---

## Deploy order, when we get there

For my reference, not yours to execute:

1. Rules alone, verified on the emulator first. Smallest blast radius, fixes the leak.
2. Confirm the live app still works for a signed-in user.
3. `firebase.json` fix and functions after that, as a separate deliberate step.

---

## Also outstanding

- **The 4a device verification** never completed — the phone dropped mid-run. Close it in
  one run when I reconnect. Include an explicit `_ContinueCard` repro: two shows on the
  same episode number, bump one, then bump the other, and read both Firestore documents
  afterwards to confirm no episode is skipped. That path writes to the database, so
  inspection isn't enough.
- **4b, 4c, 4d** from `BATCH-FOUR.md` are untouched and still queued.
- **The arcs fix** — reclassified from data corruption to an unhandled `permission-denied`
  surfacing in Crashlytics as fatal. Still worth its ~15 lines, still not urgent.

Start with 5a. Stop at 5c and wait for me.
