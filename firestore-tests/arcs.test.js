// Emulator tests for the arcs post like-toggle rule (ARCS-FIX-0907).
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and say NOTHING about the
// ruleset deployed in production.
//
// The rule under test, firestore.rules:239-250 (isLikeToggle), requires an
// update to, all measured against the document as the server holds it:
//
//   1. touch only `likes` and `likeCount`
//   2. move the caller across the array, absent->present or present->absent
//   3. move `likeCount` by exactly the matching +1 / -1
//   4. find both fields already present — it dereferences both
//
// The headline case is "re-liking an already-liked post is denied". That is the
// production failure: the client used to decide direction from a widget
// snapshot, so a stale one sent arrayUnion for a uid already present. That is a
// no-op, `likes` does not change, and neither branch of the rule holds.
//
// The two ALLOWS tests are load-bearing, not decoration. Every DENIES assertion
// would also pass if the fixtures were broken and nothing could be written at
// all; the ALLOWS tests are what prove the suite can tell the two apart.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  arrayUnion,
  arrayRemove,
  increment,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const U1 = 'user_one';
const U2 = 'user_two';
const ARC = 'arc_one';

const post = (db, id) => doc(db, 'arcs', ARC, 'posts', id);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  // One post document per test, so nothing depends on execution order.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'arcs', ARC), {
      name: 'Arc One',
      createdBy: U1,
      members: [U1],
      memberCount: 1,
      postCount: 5,
    });

    const base = { title: 't', body: 'b', authorId: U1, replyCount: 0 };

    // Nobody has liked these.
    await setDoc(post(db, 'p_like_ok'), { ...base, likes: [], likeCount: 0 });
    await setDoc(post(db, 'p_extra_field'), { ...base, likes: [], likeCount: 0 });
    await setDoc(post(db, 'p_wrong_count'), { ...base, likes: [], likeCount: 0 });
    await setDoc(post(db, 'p_unlike_absent'), { ...base, likes: [], likeCount: 0 });

    // U1 has already liked these.
    await setDoc(post(db, 'p_unlike_ok'), { ...base, likes: [U1], likeCount: 1 });
    await setDoc(post(db, 'p_relike'), { ...base, likes: [U1], likeCount: 1 });

    // Written before likes/likeCount existed.
    await setDoc(post(db, 'p_legacy'), base);
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── The access that must keep working ──────────────────────────────────────
// These also prove the DENIES assertions below are not passing because the
// fixtures are broken.

test('ALLOWS a correct like: caller enters the array, count +1', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  await assertSucceeds(
    updateDoc(post(db, 'p_like_ok'), { likes: [U1], likeCount: 1 }),
  );

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(post(ctx.firestore(), 'p_like_ok'));
    assert.deepEqual(snap.data().likes, [U1]);
    assert.equal(snap.data().likeCount, 1);
  });
});

test('ALLOWS a correct unlike: caller leaves the array, count -1', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  await assertSucceeds(
    updateDoc(post(db, 'p_unlike_ok'), { likes: [], likeCount: 0 }),
  );
});

// ── The production failure ─────────────────────────────────────────────────

test('DENIES re-liking a post the caller has already liked — the reported bug', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  // Exactly what the old client sent from a stale snapshot: arrayUnion of a uid
  // already in the array. The union is a no-op, so `likes` is unchanged while
  // likeCount moves, and neither branch of isLikeToggle holds.
  await assertFails(
    updateDoc(post(db, 'p_relike'), {
      likes: arrayUnion(U1),
      likeCount: increment(1),
    }),
  );
});

test('DENIES un-liking a post the caller never liked', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  // The mirror image, and what a fast double-tap produces on the unlike side.
  await assertFails(
    updateDoc(post(db, 'p_unlike_absent'), {
      likes: arrayRemove(U1),
      likeCount: increment(-1),
    }),
  );
});

// ── The rest of the rule ───────────────────────────────────────────────────

test('DENIES a like that also touches a third field (hasOnly)', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  await assertFails(
    updateDoc(post(db, 'p_extra_field'), {
      likes: [U1],
      likeCount: 1,
      title: 'edited while liking',
    }),
  );
});

test('DENIES a like whose count moves by the wrong amount', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  await assertFails(
    updateDoc(post(db, 'p_wrong_count'), { likes: [U1], likeCount: 7 }),
  );
});

test('DENIES liking a post that has no likes/likeCount fields — legacy documents', async () => {
  const db = testEnv.authenticatedContext(U1).firestore();
  // Recorded, not fixed: isLikeToggle dereferences resource.data.likes and
  // resource.data.likeCount, so a post written before those fields existed can
  // never be liked by any client. Clearing it needs a rules change or a
  // backfill, neither of which is in this batch.
  await assertFails(
    updateDoc(post(db, 'p_legacy'), { likes: [U1], likeCount: 1 }),
  );
});

test('DENIES a like from a user who is not signed in', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(
    updateDoc(post(db, 'p_like_ok'), { likes: [U2], likeCount: 2 }),
  );
});
