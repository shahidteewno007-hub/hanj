// Emulator tests for the episodeDiscussions vote and update rules (R5).
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and say NOTHING about the
// ruleset deployed in production.
//
// The client votes in one transaction (episode_discussion_screen.dart `_vote`,
// unchanged since the root commit): read its own record at votes/{uid}, then
//
//   same direction again  -> delete the record, counter -1
//   new vote              -> set {dir, votedAt}, counter +1
//   switch direction      -> set {dir, votedAt}, new counter +1, old counter -1
//
// `clientVote` below is that transaction, step for step. The rules now check
// each half of it against the other: the comment's counters may move only by
// what the caller's own record moves by, in the same write, and the record may
// change only together with that counter move. Before, any signed-in user
// could set either counter to any value on any comment, and write or delete
// anyone's vote record.
//
// As in arcs.test.js, the ALLOWS tests are load-bearing: every DENIES test
// would also pass if the fixtures were broken and nothing could be written.

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
  setDoc,
  addDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  runTransaction,
  increment,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const ALICE = 'r5_alice';   // writes the comments
const BOB = 'r5_bob';       // votes on them
const CAROL = 'r5_carol';   // a third party with a vote of her own
// An anime id no other test file uses.
const ANIME = 990014;

const SEEDED_AT = Timestamp.fromMillis(Date.UTC(2026, 9, 1));

const comment = (db, id) => doc(db, 'episodeDiscussions', id);
const voteOf = (db, id, uid) => doc(db, 'episodeDiscussions', id, 'votes', uid);

let testEnv;

// A comment by `by` with the given counters, plus any existing vote records
// ({uid: dir}). Written with rules disabled, as production data would be.
async function seed(id, { by = ALICE, up = 0, down = 0, votes = {} } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(comment(db, id), {
      animeId: ANIME,
      animeTitle: 'Rules Test',
      episodeNumber: 0,
      userId: by,
      userName: by,
      commentText: 'seed',
      containsSpoilers: false,
      upvotes: up,
      downvotes: down,
      parentId: null,
      createdAt: SEEDED_AT,
    });
    for (const [uid, dir] of Object.entries(votes)) {
      await setDoc(voteOf(db, id, uid), { dir, votedAt: SEEDED_AT });
    }
  });
}

// Reads back with rules disabled, so the assertion sees what was stored.
async function stored(id, uid) {
  let result;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const c = (await getDoc(comment(db, id))).data();
    const v = uid ? await getDoc(voteOf(db, id, uid)) : null;
    result = {
      up: c.upvotes,
      down: c.downvotes,
      vote: v && v.exists() ? v.data().dir : 0,
    };
  });
  return result;
}

// The client's `_vote`, step for step.
async function clientVote(db, id, uid, dir) {
  const commentRef = comment(db, id);
  const voteRef = voteOf(db, id, uid);
  await runTransaction(db, async (txn) => {
    const voteSnap = await txn.get(voteRef);
    const prev = voteSnap.data()?.dir ?? 0;
    if (prev === dir) {
      txn.delete(voteRef);
      txn.update(commentRef, { [dir > 0 ? 'upvotes' : 'downvotes']: increment(-1) });
    } else {
      txn.set(voteRef, { dir, votedAt: serverTimestamp() });
      const updates = { [dir > 0 ? 'upvotes' : 'downvotes']: increment(1) };
      if (prev !== 0) updates[prev > 0 ? 'upvotes' : 'downvotes'] = increment(-1);
      txn.update(commentRef, updates);
    }
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── Half one: what the client does, which must keep working ────────────────

test('ALLOWS a new upvote — the client transaction', async () => {
  await seed('r5_new');
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(clientVote(db, 'r5_new', BOB, 1));
  assert.deepEqual(await stored('r5_new', BOB), { up: 1, down: 0, vote: 1 });
});

test('ALLOWS a new downvote — the client transaction', async () => {
  await seed('r5_new_down');
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(clientVote(db, 'r5_new_down', BOB, -1));
  assert.deepEqual(await stored('r5_new_down', BOB), { up: 0, down: 1, vote: -1 });
});

test('ALLOWS un-voting — the same arrow again', async () => {
  await seed('r5_off', { up: 1, votes: { [BOB]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(clientVote(db, 'r5_off', BOB, 1));
  assert.deepEqual(await stored('r5_off', BOB), { up: 0, down: 0, vote: 0 });
});

test('ALLOWS switching a downvote to an upvote', async () => {
  await seed('r5_switch', { up: 3, down: 1, votes: { [BOB]: -1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(clientVote(db, 'r5_switch', BOB, 1));
  assert.deepEqual(await stored('r5_switch', BOB), { up: 4, down: 0, vote: 1 });
});

test('ALLOWS a full round trip: up, switch down, un-vote', async () => {
  await seed('r5_trip', { up: 2, down: 2, votes: { [CAROL]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(clientVote(db, 'r5_trip', BOB, 1));
  await assertSucceeds(clientVote(db, 'r5_trip', BOB, -1));
  await assertSucceeds(clientVote(db, 'r5_trip', BOB, -1));
  // Back where it started; Carol's vote untouched throughout.
  assert.deepEqual(await stored('r5_trip', BOB), { up: 2, down: 2, vote: 0 });
  assert.equal((await stored('r5_trip', CAROL)).vote, 1);
});

test('ALLOWS the author voting on her own comment', async () => {
  await seed('r5_own');
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(clientVote(db, 'r5_own', ALICE, 1));
  assert.deepEqual(await stored('r5_own', ALICE), { up: 1, down: 0, vote: 1 });
});

test('ALLOWS a voter to read their own record — _loadMyVote', async () => {
  await seed('r5_read', { up: 1, votes: { [BOB]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  const snap = await assertSucceeds(getDoc(voteOf(db, 'r5_read', BOB)));
  assert.equal(snap.data().dir, 1);
});

test('ALLOWS the author editing her own comment text', async () => {
  // No edit UI exists; this is the old rule's intent, kept.
  await seed('r5_edit');
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertSucceeds(
    updateDoc(comment(db, 'r5_edit'), { commentText: 'edited', containsSpoilers: true }),
  );
});

// ── Half two: what R5 closes ───────────────────────────────────────────────

test('DENIES setting a counter to an arbitrary value', async () => {
  await seed('r5_set');
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(updateDoc(comment(db, 'r5_set'), { upvotes: 999 }));
});

test('DENIES a +1 with no vote record behind it', async () => {
  await seed('r5_bare');
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(updateDoc(comment(db, 'r5_bare'), { upvotes: increment(1) }));
});

test('DENIES voting twice in the same direction', async () => {
  // Record already says +1; re-asserting it alongside another +1.
  await seed('r5_twice', { up: 1, votes: { [BOB]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  const batch = writeBatch(db);
  batch.set(voteOf(db, 'r5_twice', BOB), { dir: 1, votedAt: serverTimestamp() });
  batch.update(comment(db, 'r5_twice'), { upvotes: increment(1) });
  await assertFails(batch.commit());
});

test('DENIES writing a vote record without the counter moving', async () => {
  // The set-up for draining a counter: plant a record, then "un-vote" it.
  await seed('r5_plant', { up: 5 });
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(setDoc(voteOf(db, 'r5_plant', BOB), { dir: 1, votedAt: serverTimestamp() }));
});

test('DENIES deleting a vote record without the counter moving', async () => {
  // Would leave the +1 standing and let the same person vote again.
  await seed('r5_unrecord', { up: 1, votes: { [BOB]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(deleteDoc(voteOf(db, 'r5_unrecord', BOB)));
});

test('DENIES Bob casting a vote as Carol, counter and all', async () => {
  await seed('r5_as_carol');
  const db = testEnv.authenticatedContext(BOB).firestore();
  const batch = writeBatch(db);
  batch.set(voteOf(db, 'r5_as_carol', CAROL), { dir: 1, votedAt: serverTimestamp() });
  batch.update(comment(db, 'r5_as_carol'), { upvotes: increment(1) });
  await assertFails(batch.commit());
});

test('DENIES Bob removing Carol\'s vote, counter and all', async () => {
  await seed('r5_unvote_carol', { up: 1, votes: { [CAROL]: 1 } });
  const db = testEnv.authenticatedContext(BOB).firestore();
  const batch = writeBatch(db);
  batch.delete(voteOf(db, 'r5_unvote_carol', CAROL));
  batch.update(comment(db, 'r5_unvote_carol'), { upvotes: increment(-1) });
  await assertFails(batch.commit());
});

test('DENIES reading someone else\'s vote record', async () => {
  await seed('r5_peek', { up: 1, votes: { [BOB]: 1 } });
  const db = testEnv.authenticatedContext(CAROL).firestore();
  await assertFails(getDoc(voteOf(db, 'r5_peek', BOB)));
});

test('DENIES a vote worth more than one', async () => {
  await seed('r5_big');
  const db = testEnv.authenticatedContext(BOB).firestore();
  const batch = writeBatch(db);
  batch.set(voteOf(db, 'r5_big', BOB), { dir: 5, votedAt: serverTimestamp() });
  batch.update(comment(db, 'r5_big'), { upvotes: increment(5) });
  await assertFails(batch.commit());
});

test('DENIES a vote that also rewrites the comment', async () => {
  await seed('r5_piggyback');
  const db = testEnv.authenticatedContext(BOB).firestore();
  const batch = writeBatch(db);
  batch.set(voteOf(db, 'r5_piggyback', BOB), { dir: 1, votedAt: serverTimestamp() });
  batch.update(comment(db, 'r5_piggyback'), {
    upvotes: increment(1),
    commentText: 'not what Alice wrote',
  });
  await assertFails(batch.commit());
});

test('DENIES the author setting her own counters', async () => {
  // The old rule let the author update any field of her own comment.
  await seed('r5_author_count');
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertFails(updateDoc(comment(db, 'r5_author_count'), { upvotes: 50 }));
});

test('DENIES the author handing her comment to someone else', async () => {
  await seed('r5_author_uid');
  const db = testEnv.authenticatedContext(ALICE).firestore();
  await assertFails(updateDoc(comment(db, 'r5_author_uid'), { userId: BOB }));
});

test('DENIES Bob editing Alice\'s text', async () => {
  await seed('r5_other_edit');
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(updateDoc(comment(db, 'r5_other_edit'), { commentText: 'edited by Bob' }));
});

// ── Create: counters and timestamp ─────────────────────────────────────────

const fresh = (uid, extra = {}) => ({
  animeId: ANIME,
  animeTitle: 'Rules Test',
  episodeNumber: 0,
  userId: uid,
  userName: 'Bob',
  commentText: 'new',
  containsSpoilers: false,
  upvotes: 0,
  downvotes: 0,
  parentId: null,
  createdAt: serverTimestamp(),
  ...extra,
});

test('ALLOWS a new comment with zero counters and the server\'s timestamp', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertSucceeds(addDoc(collection(db, 'episodeDiscussions'), fresh(BOB)));
});

test('DENIES a new comment that starts with votes', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(addDoc(collection(db, 'episodeDiscussions'), fresh(BOB, { upvotes: 100 })));
});

test('DENIES a new comment dated in the future — pinned to the top', async () => {
  const db = testEnv.authenticatedContext(BOB).firestore();
  await assertFails(
    addDoc(
      collection(db, 'episodeDiscussions'),
      fresh(BOB, { createdAt: Timestamp.fromMillis(Date.UTC(2100, 0, 1)) }),
    ),
  );
});
