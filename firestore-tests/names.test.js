// Emulator tests for display-name limits (code batch 2, LR-014): at most 24
// characters, and no word kept for Hanj, on the user document and on the
// names a new arc, post or reply carries. lib/core/display_name.dart runs
// the same test in the app.
//
// Run from firestore-tests/:  npm test
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and not the host config.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import test, { before, after } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  setDoc,
  updateDoc,
  writeBatch,
  serverTimestamp,
  increment,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const NEW = 'nm_new';       // no user document yet
const OLD = 'nm_old';       // a name from before the limits
const POSTER = 'nm_poster'; // a member of the arc below
const ARC = 'nm_arc';

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
    await setDoc(doc(db, 'users', OLD), {
      displayName: 'A name from before the limits, far too long',
      avatarColorIndex: 1,
    });
    await setDoc(doc(db, 'users', POSTER), { displayName: 'Poster' });
    await setDoc(doc(db, 'arcs', ARC), {
      v: 2,
      name: 'Names',
      description: '',
      anime: { id: '1', title: 'Show' },
      from: 1,
      to: 12,
      pace: 2,
      startsOn: Timestamp.now(),
      createdBy: POSTER,
      creatorName: 'Poster',
      members: [POSTER],
      memberCount: 1,
      postCount: 0,
      createdAt: Timestamp.now(),
    });
    await setDoc(doc(db, 'arcs', ARC, 'posts', 'p0'), {
      title: '', body: 'seed', ep: 1, authorId: POSTER, authorName: 'Poster',
      likes: [], likeCount: 0, replyCount: 0, createdAt: Timestamp.now(),
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const setName = (uid, displayName) =>
  setDoc(doc(as(uid), 'users', uid), { displayName }, { merge: true });

// ── The user document ─────────────────────────────────────────────────────

test('ALLOWS a 24-character name at sign-up', async () => {
  await assertSucceeds(setName(NEW, 'abcdefghijklmnopqrstuvwx'));
});

test('DENIES a 25-character name', async () => {
  await assertFails(setName(NEW, 'abcdefghijklmnopqrstuvwxy'));
});

test('ALLOWS 24 accented letters: the rules count characters, not bytes', async () => {
  await assertSucceeds(setName(NEW, 'é'.repeat(24)));
});

for (const name of ['Hanj', 'hanj team', 'The Hanj Team', 'Admin', 'admin_01',
  'Moderator', 'mod', 'Hanj Support', 'OFFICIAL', 'staff']) {
  test(`DENIES the kept name "${name}"`, async () => {
    await assertFails(setName(NEW, name));
  });
}

for (const name of ['Hanjiro', 'Badminton fan', 'modern_otaku', 'Supporter', 'naruto_fan99']) {
  test(`ALLOWS "${name}", where the word is only part of another`, async () => {
    await assertSucceeds(setName(NEW, name));
  });
}

test('ALLOWS a name from before the limits to stay while other fields change', async () => {
  await assertSucceeds(
    updateDoc(doc(as(OLD), 'users', OLD), { avatarColorIndex: 3 }),
  );
});

test('ALLOWS Edit Profile saving the old name unchanged with the rest', async () => {
  await assertSucceeds(
    setDoc(
      doc(as(OLD), 'users', OLD),
      { displayName: 'A name from before the limits, far too long', avatarColorIndex: 4 },
      { merge: true },
    ),
  );
});

test('DENIES changing a name to one over 24 characters', async () => {
  await assertFails(setName(OLD, 'Another name that is far too long'));
});

// ── Names in Arcs ─────────────────────────────────────────────────────────

const arcDoc = (uid, creatorName) => ({
  v: 2,
  name: 'A new arc',
  description: '',
  anime: { id: '2', title: 'Another show' },
  from: 1,
  to: 12,
  pace: 2,
  startsOn: Timestamp.now(),
  createdBy: uid,
  creatorName,
  members: [uid],
  memberCount: 1,
  postCount: 0,
  createdAt: serverTimestamp(),
});

test('ALLOWS starting an arc under a 24-character name', async () => {
  await assertSucceeds(setDoc(doc(as(POSTER), 'arcs', 'nm_a1'), arcDoc(POSTER, 'x'.repeat(24))));
});

test('DENIES starting an arc as "Hanj Team"', async () => {
  await assertFails(setDoc(doc(as(POSTER), 'arcs', 'nm_a2'), arcDoc(POSTER, 'Hanj Team')));
});

test('DENIES starting an arc under a 25-character name', async () => {
  await assertFails(setDoc(doc(as(POSTER), 'arcs', 'nm_a3'), arcDoc(POSTER, 'x'.repeat(25))));
});

function post(db, id, authorName) {
  const b = writeBatch(db);
  b.set(doc(db, 'arcs', ARC, 'posts', id), {
    title: '', body: 'words', ep: 2, authorId: POSTER, authorName,
    likes: [], likeCount: 0, replyCount: 0, createdAt: serverTimestamp(),
  });
  b.update(doc(db, 'arcs', ARC), { postCount: increment(1), countedPost: id });
  return b.commit();
}

function reply(db, id, authorName) {
  const b = writeBatch(db);
  b.set(doc(db, 'arcs', ARC, 'posts', 'p0', 'replies', id), {
    body: 'words', authorId: POSTER, authorName,
    likes: [], likeCount: 0, createdAt: serverTimestamp(),
  });
  b.update(doc(db, 'arcs', ARC, 'posts', 'p0'), { replyCount: increment(1), countedReply: id });
  return b.commit();
}

test('ALLOWS a post signed "Anonymous"', async () => {
  await assertSucceeds(post(as(POSTER), 'nm_p1', 'Anonymous'));
});

test('DENIES a post signed "Moderator"', async () => {
  await assertFails(post(as(POSTER), 'nm_p2', 'Moderator'));
});

test('DENIES a post signed with 25 characters', async () => {
  await assertFails(post(as(POSTER), 'nm_p3', 'y'.repeat(25)));
});

test('ALLOWS a reply signed "Poster"', async () => {
  await assertSucceeds(reply(as(POSTER), 'nm_r1', 'Poster'));
});

test('DENIES a reply signed "Hanj"', async () => {
  await assertFails(reply(as(POSTER), 'nm_r2', 'Hanj'));
});
