// Emulator tests for code batch 2's owner-only rules (Q178, LR-008, LR-005,
// LR-020): a user's document, list and activity are the owner's alone;
// episode discussions take no new comment or edit; reviews are closed.
//
// Run from firestore-tests/:  npm test
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and not the host config.

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
  updateDoc,
  deleteDoc,
  query,
  where,
  writeBatch,
  serverTimestamp,
  increment,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const ANA = 'oo_ana';
const BEN = 'oo_ben';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ANA, BEN]) {
      await setDoc(doc(db, 'users', uid), {
        displayName: uid === ANA ? 'Ana' : 'Ben',
        email: `${uid}@example.com`,
        fcmToken: `${uid}-token`,
      });
      await setDoc(doc(db, 'users', uid, 'animeList', '21'), {
        title: 'One Piece',
        status: 'WATCHING',
        currentEpisode: 12,
      });
      await setDoc(doc(db, 'users', uid, 'activity', 'a1'), {
        animeTitle: 'One Piece',
        type: 'status',
      });
    }
    await setDoc(doc(db, 'episodeDiscussions', 'oo_c1'), {
      animeId: 'oo_anime',
      animeTitle: 'Rules Test',
      episodeNumber: 0,
      userId: ANA,
      userName: 'Ana',
      commentText: 'old words',
      containsSpoilers: false,
      upvotes: 0,
      downvotes: 0,
      parentId: null,
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'episodeDiscussions', 'oo_c2'), {
      animeId: 'oo_anime',
      userId: ANA,
      userName: 'Ana',
      commentText: 'to delete',
      upvotes: 0,
      downvotes: 0,
      createdAt: new Date(),
    });
    await setDoc(doc(db, 'reviews', 'oo_r1'), { userId: BEN, text: 'old review' });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();

// ── The user document ─────────────────────────────────────────────────────

test('DENIES Ben reading Ana\'s user document (email, push token)', async () => {
  await assertFails(getDoc(doc(as(BEN), 'users', ANA)));
});

test('DENIES Soulmatch\'s scan: listing every user document', async () => {
  await assertFails(getDocs(collection(as(BEN), 'users')));
});

test('DENIES a query for one user by name', async () => {
  await assertFails(
    getDocs(query(collection(as(BEN), 'users'), where('displayName', '==', 'Ana'))),
  );
});

test('ALLOWS Ana reading her own document', async () => {
  const snap = await assertSucceeds(getDoc(doc(as(ANA), 'users', ANA)));
  assert.equal(snap.data().displayName, 'Ana');
});

test('ALLOWS Ana updating her own document (block list, rules date)', async () => {
  await assertSucceeds(
    setDoc(
      doc(as(ANA), 'users', ANA),
      { blocked: [BEN], arcsRulesAt: serverTimestamp() },
      { merge: true },
    ),
  );
});

// ── Lists and activity ────────────────────────────────────────────────────

test('DENIES Ben listing Ana\'s animeList (Soulmatch\'s compare)', async () => {
  await assertFails(getDocs(collection(as(BEN), 'users', ANA, 'animeList')));
});

test('DENIES Ben reading one entry on Ana\'s list', async () => {
  await assertFails(getDoc(doc(as(BEN), 'users', ANA, 'animeList', '21')));
});

test('DENIES Ben reading Ana\'s activity (the Friends tab)', async () => {
  await assertFails(getDocs(collection(as(BEN), 'users', ANA, 'activity')));
});

test('ALLOWS Ana reading her own list and activity', async () => {
  const list = await assertSucceeds(getDocs(collection(as(ANA), 'users', ANA, 'animeList')));
  assert.equal(list.size, 1);
  await assertSucceeds(getDocs(collection(as(ANA), 'users', ANA, 'activity')));
});

test('ALLOWS Arcs reading the reader\'s own progress (ArcsService.progress)', async () => {
  await assertSucceeds(getDoc(doc(as(BEN), 'users', BEN, 'animeList', '21')));
});

// ── Episode discussions: no new words ─────────────────────────────────────

const comment = (uid, extra = {}) => ({
  animeId: 'oo_anime',
  animeTitle: 'Rules Test',
  episodeNumber: 0,
  userId: uid,
  userName: 'Ben',
  commentText: 'new words',
  containsSpoilers: false,
  upvotes: 0,
  downvotes: 0,
  parentId: null,
  createdAt: serverTimestamp(),
  ...extra,
});

test('DENIES a new comment, even one the old rules took', async () => {
  await assertFails(addDoc(collection(as(BEN), 'episodeDiscussions'), comment(BEN)));
});

test('DENIES a new reply', async () => {
  await assertFails(
    addDoc(collection(as(BEN), 'episodeDiscussions'), comment(BEN, { parentId: 'oo_c1' })),
  );
});

test('DENIES the author rewriting her old comment', async () => {
  await assertFails(
    updateDoc(doc(as(ANA), 'episodeDiscussions', 'oo_c1'), { commentText: 'x'.repeat(5000) }),
  );
});

test('ALLOWS reading a thread (account deletion finds comments this way)', async () => {
  await assertSucceeds(
    getDocs(query(collection(as(ANA), 'episodeDiscussions'), where('userId', '==', ANA))),
  );
});

test('ALLOWS a vote on an old comment, counter and record together', async () => {
  const db = as(BEN);
  const b = writeBatch(db);
  b.set(doc(db, 'episodeDiscussions', 'oo_c1', 'votes', BEN), { dir: 1, votedAt: serverTimestamp() });
  b.update(doc(db, 'episodeDiscussions', 'oo_c1'), { upvotes: increment(1) });
  await assertSucceeds(b.commit());
});

test('ALLOWS the author deleting her own comment (account deletion)', async () => {
  await assertSucceeds(deleteDoc(doc(as(ANA), 'episodeDiscussions', 'oo_c2')));
});

// ── Reviews: closed ───────────────────────────────────────────────────────

test('DENIES reading a review', async () => {
  await assertFails(getDoc(doc(as(ANA), 'reviews', 'oo_r1')));
});

test('DENIES writing a review', async () => {
  await assertFails(addDoc(collection(as(ANA), 'reviews'), { userId: ANA, text: 'free storage' }));
});

test('DENIES the author deleting her own review', async () => {
  await assertFails(deleteDoc(doc(as(BEN), 'reviews', 'oo_r1')));
});

test('DENIES a vote under a review', async () => {
  await assertFails(setDoc(doc(as(ANA), 'reviews', 'oo_r1', 'votes', ANA), { dir: 1 }));
});
