// Emulator tests for the follow graph rules (batch 5d).
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and not the host config.
//
// The shape under test: a follow is two mirrored edges written by the SAME
// person into TWO different people's subtrees.
//
//   A follows B  ->  users/B/followers/A   (written by A, lives under B)
//                    users/A/following/B   (written by A, lives under A)
//
// So the owner of the document path is not the owner of the write, which is
// why followers and following need different conditions.

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
import { doc, getDoc, setDoc, deleteDoc } from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const ALICE = 'user_alice';     // does the following
const BOB = 'user_bob';         // gets followed; the seeded edge is Alice->Bob
const CAROL = 'user_carol';     // a third party, follows nobody
const DAVE = 'user_dave';       // target for the create/delete round trip

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  // Seed with rules disabled so the fixtures exist regardless of what the
  // rules currently permit. The Alice -> Bob edge is the one the read and
  // unfollow tests use.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ALICE, BOB, CAROL, DAVE]) {
      await setDoc(doc(db, 'users', uid), { displayName: uid });
    }
    await setDoc(doc(db, 'users', BOB, 'followers', ALICE), { since: 'seed' });
    await setDoc(doc(db, 'users', ALICE, 'following', BOB), { since: 'seed' });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── Half one: what 5d closes ───────────────────────────────────────────────

test('DENIES an unauthenticated read of a followers edge', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', BOB, 'followers', ALICE)));
});

test('DENIES an unauthenticated read of a following edge', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', ALICE, 'following', BOB)));
});

test('DENIES an unauthenticated write to a followers edge', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(
    setDoc(doc(db, 'users', BOB, 'followers', CAROL), { since: 'anon' }),
  );
});

test('DENIES Carol putting Alice into Bob\'s followers', async () => {
  // The core of the old hole: `allow write: if request.auth != null` let any
  // signed-in account fabricate an edge between two other people.
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertFails(
    setDoc(doc(db, 'users', BOB, 'followers', ALICE), { since: 'forged' }),
  );
});

test('DENIES Carol writing into Alice\'s following list', async () => {
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertFails(
    setDoc(doc(db, 'users', ALICE, 'following', BOB), { since: 'forged' }),
  );
});

test('DENIES Carol deleting the Alice -> Bob follower edge', async () => {
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertFails(deleteDoc(doc(db, 'users', BOB, 'followers', ALICE)));
});

test('DENIES Carol deleting the Alice -> Bob following edge', async () => {
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertFails(deleteDoc(doc(db, 'users', ALICE, 'following', BOB)));
});

test('DENIES Bob fabricating a follower on his own profile', async () => {
  // Bob owns the path but not the edge. He cannot invent followers, which is
  // what makes a follower count worth anything.
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(
    setDoc(doc(db, 'users', BOB, 'followers', CAROL), { since: 'inflated' }),
  );
});

test('DENIES Bob removing an existing follower — NOT granted, by design', async () => {
  // Asserting the current accepted state, not a desirable one. There is no
  // remove-follower feature yet; when one lands this rule widens and this
  // expectation flips to assertSucceeds. See the comment in firestore.rules.
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(deleteDoc(doc(db, 'users', BOB, 'followers', ALICE)));
});

// ── Half two: the access that must keep working ────────────────────────────

test('ALLOWS a signed-in user to read another user\'s followers edge', async () => {
  const db = testEnv.authenticatedContext(CAROL).firestore();
  const snap = await assertSucceeds(
    getDoc(doc(db, 'users', BOB, 'followers', ALICE)),
  );
  assert.equal(snap.data().since, 'seed');
});

test('ALLOWS a signed-in user to read another user\'s following edge', async () => {
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertSucceeds(getDoc(doc(db, 'users', ALICE, 'following', BOB)));
});

test('ALLOWS Alice to read her own following edge', async () => {
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(getDoc(doc(db, 'users', ALICE, 'following', BOB)));
});

test('ALLOWS Alice to follow Dave — both halves of the edge', async () => {
  const db = testEnv.authenticatedContext(ALICE).firestore();
  // Alice adds herself to Dave's followers...
  await assertSucceeds(
    setDoc(doc(db, 'users', DAVE, 'followers', ALICE), { since: 'now' }),
  );
  // ...and Dave to her own following.
  await assertSucceeds(
    setDoc(doc(db, 'users', ALICE, 'following', DAVE), { since: 'now' }),
  );
});

test('ALLOWS Alice to unfollow Dave — both halves of the edge', async () => {
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(deleteDoc(doc(db, 'users', DAVE, 'followers', ALICE)));
  await assertSucceeds(deleteDoc(doc(db, 'users', ALICE, 'following', DAVE)));
});

test('ALLOWS Alice to update her own follower edge under Bob', async () => {
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(
    setDoc(
      doc(db, 'users', BOB, 'followers', ALICE),
      { since: 'updated' },
      { merge: true },
    ),
  );
});
