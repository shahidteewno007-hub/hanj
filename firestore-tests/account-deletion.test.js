// Emulator tests for what account deletion can do to episodeDiscussions.
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
//
// Rules are loaded from ../firestore.rules directly rather than via
// firebase.json, so these test the file itself and say NOTHING about the
// ruleset deployed in production.
//
// delete_account_screen.dart `_wipeUserData` deletes the user's comments and
// replies before the Auth account goes: one query on `userId`, from the
// server, then deletes in batches of 400. `clientWipeComments` below is that
// step, step for step. No rule changed for it. These tests pin the two rules
// it depends on (signed-in read, author-only delete) and record what it
// cannot reach: other users' replies to the deleted comments, and vote
// records, which have no field to find them by. AUDIT.md §6g.

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
  getDocsFromServer,
  setDoc,
  deleteDoc,
  writeBatch,
  query,
  where,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const DANA = 'acct_dana';   // deletes her account
const ERIN = 'acct_erin';   // replies to and votes on Dana's comment
// An anime id no other test file uses.
const ANIME = 990015;

const SEEDED_AT = Timestamp.fromMillis(Date.UTC(2026, 9, 1));

const comment = (db, id) => doc(db, 'episodeDiscussions', id);
const voteOf = (db, id, uid) => doc(db, 'episodeDiscussions', id, 'votes', uid);

let testEnv;

// The client's comment step in `_wipeUserData`, step for step.
async function clientWipeComments(db, uid) {
  const snap = await getDocsFromServer(
    query(collection(db, 'episodeDiscussions'), where('userId', '==', uid)),
  );
  for (let i = 0; i < snap.docs.length; i += 400) {
    const batch = writeBatch(db);
    for (const d of snap.docs.slice(i, i + 400)) batch.delete(d.ref);
    await batch.commit();
  }
  return snap.size;
}

// What is stored, read with rules disabled.
async function exists(ref) {
  let found;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    found = (await getDoc(ref(ctx.firestore()))).exists();
  });
  return found;
}

async function upvotes(id) {
  let n;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    n = (await getDoc(comment(ctx.firestore(), id))).data().upvotes;
  });
  return n;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-test',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });

  // Seed with rules disabled, as production data would be. Dana's top-level
  // comment predates the D13 fix, so it still carries her email. Erin replied
  // to it and upvoted it; Dana upvoted it too (the screen lets you vote on
  // your own comment), replied to Erin's comment, and upvoted that.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const base = {
      animeId: ANIME,
      animeTitle: 'Rules Test',
      episodeNumber: 0,
      commentText: 'seed',
      containsSpoilers: false,
      upvotes: 0,
      downvotes: 0,
      parentId: null,
      createdAt: SEEDED_AT,
    };
    await setDoc(comment(db, 'acct_dana_top'), {
      ...base, userId: DANA, userName: 'dana', userEmail: 'dana@example.com',
      upvotes: 2,
    });
    await setDoc(voteOf(db, 'acct_dana_top', ERIN), { dir: 1, votedAt: SEEDED_AT });
    await setDoc(voteOf(db, 'acct_dana_top', DANA), { dir: 1, votedAt: SEEDED_AT });
    await setDoc(comment(db, 'acct_erin_reply'), {
      ...base, userId: ERIN, userName: 'Erin', parentId: 'acct_dana_top',
    });
    await setDoc(comment(db, 'acct_erin_top'), {
      ...base, userId: ERIN, userName: 'Erin', upvotes: 1,
    });
    await setDoc(voteOf(db, 'acct_erin_top', DANA), { dir: 1, votedAt: SEEDED_AT });
    await setDoc(comment(db, 'acct_dana_reply'), {
      ...base, userId: DANA, userName: 'Dana', parentId: 'acct_erin_top',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── Before the wipe: only the author can delete ────────────────────────────

test('DENIES Erin deleting Dana\'s comment', async () => {
  const db = testEnv.authenticatedContext(ERIN).firestore();
  await assertFails(deleteDoc(comment(db, 'acct_dana_top')));
});

test('DENIES Dana deleting Erin\'s reply to her comment, so the wipe leaves it', async () => {
  const db = testEnv.authenticatedContext(DANA).firestore();
  await assertFails(deleteDoc(comment(db, 'acct_erin_reply')));
});

// ── The wipe ───────────────────────────────────────────────────────────────

test('ALLOWS the client\'s wipe: Dana\'s comment and reply go, the pre-D13 one included', async () => {
  const db = testEnv.authenticatedContext(DANA).firestore();
  const deleted = await assertSucceeds(clientWipeComments(db, DANA));
  assert.equal(deleted, 2);
  assert.equal(await exists((d) => comment(d, 'acct_dana_top')), false);
  assert.equal(await exists((d) => comment(d, 'acct_dana_reply')), false);
  // Erin's own comment is untouched.
  assert.equal(await exists((d) => comment(d, 'acct_erin_top')), true);
});

// ── After the wipe: what it leaves behind ──────────────────────────────────

test('Erin\'s reply to the deleted comment stays stored, parent gone', async () => {
  // The screen renders a reply only under a top-level comment it has, so this
  // drops out of view without being deleted.
  assert.equal(await exists((d) => comment(d, 'acct_erin_reply')), true);
});

test('Dana\'s vote on Erin\'s comment stays, and so does the count it made', async () => {
  assert.equal(await exists((d) => voteOf(d, 'acct_erin_top', DANA)), true);
  assert.equal(await upvotes('acct_erin_top'), 1);
});

test('Vote records under the deleted comment stay, Dana\'s own included', async () => {
  assert.equal(await exists((d) => voteOf(d, 'acct_dana_top', ERIN)), true);
  assert.equal(await exists((d) => voteOf(d, 'acct_dana_top', DANA)), true);
});

test('DENIES Erin deleting her own vote under the deleted comment: R5 has no counter to move', async () => {
  // An un-vote has to move the comment's counters in the same write, and the
  // comment is gone, so a bare delete is all that is left. That errors:
  // countersFollow() reads the missing parent with getAfter(). With the
  // parent present a bare delete is denied too, because nothing moves, so
  // this test alone cannot tell the two apart; a probe of the denial message
  // did (AUDIT.md §6g). Like R8's stranded arc posts, these can only be
  // removed with the Admin SDK.
  const db = testEnv.authenticatedContext(ERIN).firestore();
  await assertFails(deleteDoc(voteOf(db, 'acct_dana_top', ERIN)));
});
