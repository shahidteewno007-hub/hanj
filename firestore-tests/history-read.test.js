// Emulator tests for the /users/{userId}/animeList and /activity read rules.
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Both collections previously carried `allow read: if true`, so any watch
// history was readable by anyone on the internet with the project id and a
// document path — no account required. These assert the closed state and the
// access that has to survive it.

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
import { doc, collection, getDoc, getDocs, setDoc, deleteDoc } from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const OWNER = 'user_owner';
const OTHER = 'user_other';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  // Seed with rules disabled so the fixtures exist regardless of what the
  // rules currently permit.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'users', OWNER, 'animeList', '21'), {
      animeId: '21',
      title: 'One Piece',
      status: 'WATCHING',
      currentEpisode: 1148,
      userRating: 10.0,
    });
    await setDoc(doc(db, 'users', OWNER, 'activity', 'act1'), {
      type: 'WATCHING',
      animeId: '21',
      animeTitle: 'One Piece',
    });

    // A second user's list, so the cross-user cases are real rather than
    // owner-reads-own dressed up.
    await setDoc(doc(db, 'users', OTHER, 'animeList', '5114'), {
      animeId: '5114',
      title: 'Fullmetal Alchemist: Brotherhood',
      status: 'COMPLETED',
    });
    await setDoc(doc(db, 'users', OTHER, 'activity', 'act1'), {
      type: 'COMPLETED',
      animeId: '5114',
      animeTitle: 'Fullmetal Alchemist: Brotherhood',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── The fix: nothing logged out gets to read watch history ─────────────────

test('DENIES an unauthenticated read of a single animeList entry', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', OWNER, 'animeList', '21')));
});

test('DENIES an unauthenticated listing of a whole animeList', async () => {
  // The listing case matters more than the single-document one: this is the
  // shape that would let someone enumerate an entire watch history.
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(db, 'users', OWNER, 'animeList')));
});

test('DENIES an unauthenticated read of an activity entry', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', OWNER, 'activity', 'act1')));
});

test('DENIES an unauthenticated listing of a whole activity feed', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(db, 'users', OWNER, 'activity')));
});

// ── The access that must keep working ──────────────────────────────────────

test('ALLOWS the owner to read their own animeList', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const snap = await assertSucceeds(getDocs(collection(db, 'users', OWNER, 'animeList')));
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].data().title, 'One Piece');
});

test('ALLOWS a signed-in user to read another user animeList (soulmatch)', async () => {
  // soulmatch_screen reads the friend's animeList directly to compare the two.
  // If this ever flips to a denial, soulmatch breaks.
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const snap = await assertSucceeds(getDocs(collection(db, 'users', OTHER, 'animeList')));
  assert.equal(snap.size, 1);
  assert.equal(snap.docs[0].data().status, 'COMPLETED');
});

test('ALLOWS the owner to read their own activity', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertSucceeds(getDocs(collection(db, 'users', OWNER, 'activity')));
});

test('ALLOWS a signed-in user to read another user activity (social feed)', async () => {
  // FirestoreService.getUserActivity(uid) takes an arbitrary uid.
  const db = testEnv.authenticatedContext(OTHER).firestore();
  const snap = await assertSucceeds(getDocs(collection(db, 'users', OWNER, 'activity')));
  assert.equal(snap.docs[0].data().animeTitle, 'One Piece');
});

// ── Writes: unchanged here, asserted so the read fix cannot loosen them ────

test('ALLOWS the owner to write their own animeList entry', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertSucceeds(
    setDoc(doc(db, 'users', OWNER, 'animeList', '21'), { currentEpisode: 1149 }, { merge: true }),
  );
});

test('DENIES one user writing to another user animeList', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER, 'animeList', '21'), { userRating: 1.0 }, { merge: true }),
  );
});

test('DENIES one user deleting another user animeList entry', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(deleteDoc(doc(db, 'users', OWNER, 'animeList', '21')));
});

test('DENIES one user writing to another user activity feed', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER, 'activity', 'forged'), { type: 'COMPLETED' }),
  );
});
