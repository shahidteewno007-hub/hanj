// Emulator tests for the episodeDiscussions read and create rules (D13).
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and say NOTHING about the
// ruleset deployed in production.
//
// D13: every comment used to store its author's email in `userEmail`, in a
// collection readable without signing in. The client fix stops writing it;
// these rules (a) stop serving the collection to logged-out callers and (b)
// refuse the field on create, so an install older than the fix cannot keep
// publishing it. The create rule also binds `userId` to the caller (R5).
//
// The comment shapes below are the exact maps the client writes in
// episode_discussion_screen.dart `_submitComment`, before and after the fix.
// `reviews` is covered for its read rule only; nothing in the app writes it.

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
  collection,
  getDoc,
  getDocs,
  setDoc,
  addDoc,
  query,
  where,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const ALICE = 'd13_alice';
const BOB = 'd13_bob';
// An anime id no other test file uses, so the thread query sees only these.
const ANIME = 990013;

// What the fixed client writes.
const clientComment = (uid, extra = {}) => ({
  animeId: ANIME,
  animeTitle: 'Rules Test',
  episodeNumber: 0,
  userId: uid,
  userName: 'Alice',
  commentText: 'hello',
  containsSpoilers: false,
  upvotes: 0,
  downvotes: 0,
  parentId: null,
  createdAt: serverTimestamp(),
  ...extra,
});

// What every build before the fix wrote: the same map plus the address, and a
// name taken from the address when Auth had no displayName.
const preFixComment = (uid) =>
  clientComment(uid, { userName: 'alice', userEmail: 'alice@example.com' });

const thread = (db) =>
  query(
    collection(db, 'episodeDiscussions'),
    where('animeId', '==', ANIME),
    where('episodeNumber', '==', 0),
  );

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  // Seed with rules disabled. The legacy comment is what is already in
  // production: written before the fix, email included.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'episodeDiscussions', 'd13_legacy'), {
      ...preFixComment(ALICE),
      createdAt: Timestamp.fromMillis(Date.UTC(2026, 8, 1)),
    });
    await setDoc(doc(db, 'reviews', 'd13_review'), {
      userId: ALICE,
      text: 'seed',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── Half one: what D13 closes ──────────────────────────────────────────────

test('DENIES an unauthenticated read of a comment', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'episodeDiscussions', 'd13_legacy')));
});

test('DENIES an unauthenticated load of a thread — the screen\'s own query', async () => {
  // This is the D13 exposure itself: list a thread, collect every userEmail.
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocs(thread(db)));
});

test('DENIES a comment carrying userEmail — the pre-fix client\'s exact write', async () => {
  // Every install older than the fix sends this. Rejecting it is the point:
  // the alternative is the address going on being published.
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertFails(addDoc(collection(db, 'episodeDiscussions'), preFixComment(ALICE)));
});

test('DENIES a comment carrying userEmail even when it is null', async () => {
  // A pre-fix client whose Auth user has no email still sends the key.
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertFails(
    addDoc(collection(db, 'episodeDiscussions'), clientComment(ALICE, { userEmail: null })),
  );
});

test('DENIES Bob posting a comment under Alice\'s uid (R5)', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(addDoc(collection(db, 'episodeDiscussions'), clientComment(ALICE)));
});

test('DENIES an unauthenticated comment', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(addDoc(collection(db, 'episodeDiscussions'), clientComment(ALICE)));
});

test('DENIES an unauthenticated read of a review', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'reviews', 'd13_review')));
});

// ── Half two: the access that must keep working ────────────────────────────

test('ALLOWS a signed-in user to load a thread — the screen\'s own query', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  const snap = await assertSucceeds(getDocs(thread(db)));
  assert.ok(snap.docs.some((d) => d.id === 'd13_legacy'));
});

test('ALLOWS the fixed client\'s comment', async () => {
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(addDoc(collection(db, 'episodeDiscussions'), clientComment(ALICE)));
});

test('ALLOWS the fixed client\'s comment with no displayName (\'Anonymous\')', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(
    addDoc(
      collection(db, 'episodeDiscussions'),
      clientComment(BOB, { userName: 'Anonymous' }),
    ),
  );
});

test('ALLOWS a reply — a comment with a parentId', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(
    addDoc(
      collection(db, 'episodeDiscussions'),
      clientComment(BOB, { userName: 'Bob', parentId: 'd13_legacy' }),
    ),
  );
});

test('ALLOWS a signed-in user to read a review', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(getDoc(doc(db, 'reviews', 'd13_review')));
});
