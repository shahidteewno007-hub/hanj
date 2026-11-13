// Emulator tests for the arcs redesign's rules (watch-alongs, 2026-11-14).
//
// Run from firestore-tests/:  npm test
//
// Rules are loaded from ../firestore.rules directly, so these test the file
// and say NOTHING about the ruleset deployed in production.
//
// What the redesign's rules add (firestore.rules, "Arcs (watch-alongs)"):
//   - an arc is created with a show and a schedule, at server time, with
//     text limits;
//   - every counter (postCount, replyCount) moves by exactly 1 in the same
//     batch as the post or reply it counts, which it names (countedPost,
//     countedReply), and each side checks the other (AUDIT R7);
//   - posts and replies are for members, at server time, within limits;
//   - an arc can be deleted only while it has no posts (AUDIT R8);
//   - reports are create-only.
// The ALLOWS tests are what the app's ArcsService sends; they prove the
// DENIES tests aren't passing on broken fixtures.

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
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  collection,
  writeBatch,
  increment,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const MAKER = 'maker';
const MEMBER = 'member';
const STRANGER = 'stranger';

let testEnv;
let n = 0;
const fresh = (p) => `${p}_${++n}`;

const arcRef = (db, a) => doc(db, 'arcs', a);
const postRef = (db, a, p) => doc(db, 'arcs', a, 'posts', p);
const replyRef = (db, a, p, r) => doc(db, 'arcs', a, 'posts', p, 'replies', r);
const as = (uid) => testEnv.authenticatedContext(uid).firestore();

function today() {
  const t = new Date();
  return Timestamp.fromDate(new Date(t.getFullYear(), t.getMonth(), t.getDate()));
}

// What ArcsService.create sends.
function newArc(uid, over = {}) {
  return {
    v: 2,
    name: 'Frieren, episodes 1–28',
    description: '',
    anime: { id: '154587', title: 'Frieren', cover: 'https://example.invalid/c.jpg', episodes: 28 },
    from: 1,
    to: 28,
    pace: 4,
    startsOn: today(),
    createdBy: uid,
    creatorName: 'Maker',
    members: [uid],
    memberCount: 1,
    postCount: 0,
    createdAt: serverTimestamp(),
    ...over,
  };
}

// What ArcsService.addPost sends, minus the batch.
function newPost(uid, over = {}) {
  return {
    title: '',
    body: 'That ending.',
    ep: 4,
    authorId: uid,
    authorName: 'Someone',
    likes: [],
    likeCount: 0,
    replyCount: 0,
    createdAt: serverTimestamp(),
    ...over,
  };
}

function newReply(uid, over = {}) {
  return {
    body: 'Agreed.',
    authorId: uid,
    authorName: 'Someone',
    likes: [],
    likeCount: 0,
    createdAt: serverTimestamp(),
    ...over,
  };
}

// An arc made by MAKER with MEMBER in it, and optionally posts/replies.
async function seed({ posts = [], replies = {} } = {}) {
  const a = fresh('arc');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(arcRef(db, a), {
      ...newArc(MAKER),
      createdAt: Timestamp.now(),
      members: [MAKER, MEMBER],
      memberCount: 2,
      postCount: posts.length,
    });
    for (const p of posts) {
      const rs = replies[p.id] ?? [];
      await setDoc(postRef(db, a, p.id), {
        ...newPost(p.author),
        createdAt: Timestamp.now(),
        replyCount: rs.length,
      });
      for (const r of rs) {
        await setDoc(replyRef(db, a, p.id, r.id), {
          ...newReply(r.author),
          createdAt: Timestamp.now(),
        });
      }
    }
  });
  return a;
}

async function postBatch(uid, a, p, post = newPost(uid), step = 1) {
  const db = as(uid);
  const b = writeBatch(db);
  b.set(postRef(db, a, p), post);
  b.update(arcRef(db, a), { postCount: increment(step), countedPost: p });
  return b.commit();
}

async function replyBatch(uid, a, p, r, reply = newReply(uid)) {
  const db = as(uid);
  const b = writeBatch(db);
  b.set(replyRef(db, a, p, r), reply);
  b.update(postRef(db, a, p), { replyCount: increment(1), countedReply: r });
  return b.commit();
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

// ── Arcs ───────────────────────────────────────────────────────────────────

test('ALLOWS starting an arc as the app does', async () => {
  const db = as(MAKER);
  await assertSucceeds(setDoc(arcRef(db, fresh('arc')), newArc(MAKER)));
});

test('DENIES an arc without a show (the old free-form shape)', async () => {
  const db = as(MAKER);
  const { anime, from, to, pace, startsOn, v, ...old } = newArc(MAKER);
  await assertFails(setDoc(arcRef(db, fresh('arc')), { ...old, emoji: '🎌', color: 'E8624A', tags: [] }));
});

test('DENIES an arc with a name over 60 characters', async () => {
  await assertFails(setDoc(arcRef(as(MAKER), fresh('arc')), newArc(MAKER, { name: 'x'.repeat(61) })));
});

test('DENIES an arc dated by the client instead of the server', async () => {
  await assertFails(setDoc(arcRef(as(MAKER), fresh('arc')),
    newArc(MAKER, { createdAt: Timestamp.fromDate(new Date(Date.now() + 864e5)) })));
});

test('DENIES an arc starting months away', async () => {
  await assertFails(setDoc(arcRef(as(MAKER), fresh('arc')),
    newArc(MAKER, { startsOn: Timestamp.fromDate(new Date(Date.now() + 90 * 864e5)) })));
});

test('DENIES an arc with honest-looking but inflated counters', async () => {
  await assertFails(setDoc(arcRef(as(MAKER), fresh('arc')), newArc(MAKER, { postCount: 40 })));
});

test('DENIES an arc made in someone else\'s name', async () => {
  await assertFails(setDoc(arcRef(as(STRANGER), fresh('arc')), newArc(MAKER)));
});

test('ALLOWS joining and leaving (yourself, count ±1)', async () => {
  const a = await seed();
  const db = as(STRANGER);
  await assertSucceeds(updateDoc(arcRef(db, a), { members: [MAKER, MEMBER, STRANGER], memberCount: 3 }));
  await assertSucceeds(updateDoc(arcRef(db, a), { members: [MAKER, MEMBER], memberCount: 2 }));
});

test('DENIES the maker setting postCount by hand (R7)', async () => {
  const a = await seed();
  await assertFails(updateDoc(arcRef(as(MAKER), a), { postCount: 99 }));
});

test('ALLOWS the maker renaming the arc', async () => {
  const a = await seed();
  await assertSucceeds(updateDoc(arcRef(as(MAKER), a), { name: 'Frieren, all of it' }));
});

test('ALLOWS deleting an arc with no posts', async () => {
  const a = await seed();
  await assertSucceeds(deleteDoc(arcRef(as(MAKER), a)));
});

test('DENIES deleting an arc that has posts (R8: they would be stranded)', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MEMBER }] });
  await assertFails(deleteDoc(arcRef(as(MAKER), a)));
});

// ── Posts and postCount ────────────────────────────────────────────────────

test('ALLOWS a member posting, counted in the same batch', async () => {
  const a = await seed();
  await assertSucceeds(postBatch(MEMBER, a, 'p1'));
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const snap = await getDoc(arcRef(ctx.firestore(), a));
    if (snap.data().postCount !== 1) throw new Error('postCount ' + snap.data().postCount);
  });
});

test('DENIES a post without the arc\'s count moving', async () => {
  const a = await seed();
  await assertFails(setDoc(postRef(as(MEMBER), a, 'p1'), newPost(MEMBER)));
});

test('DENIES bumping postCount with no post (R7)', async () => {
  const a = await seed();
  await assertFails(updateDoc(arcRef(as(MEMBER), a), { postCount: increment(1), countedPost: 'nothing' }));
});

test('DENIES bumping postCount by naming a post that already exists (R7)', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MEMBER }] });
  await assertFails(updateDoc(arcRef(as(MEMBER), a), { postCount: increment(1), countedPost: 'p1' }));
});

test('DENIES a post from someone who hasn\'t joined', async () => {
  const a = await seed();
  await assertFails(postBatch(STRANGER, a, 'p1', newPost(STRANGER)));
});

test('DENIES a post tagged with an episode outside the arc', async () => {
  const a = await seed();
  await assertFails(postBatch(MEMBER, a, 'p1', newPost(MEMBER, { ep: 29 })));
});

test('DENIES a post over 2,000 characters', async () => {
  const a = await seed();
  await assertFails(postBatch(MEMBER, a, 'p1', newPost(MEMBER, { body: 'x'.repeat(2001) })));
});

test('DENIES a post dated by the client', async () => {
  const a = await seed();
  await assertFails(postBatch(MEMBER, a, 'p1',
    newPost(MEMBER, { createdAt: Timestamp.fromDate(new Date(Date.now() + 864e5)) })));
});

test('DENIES a post counted twice in one batch', async () => {
  const a = await seed();
  await assertFails(postBatch(MEMBER, a, 'p1', newPost(MEMBER), 2));
});

test('ALLOWS deleting your own post, uncounted in the same batch', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MEMBER }] });
  const db = as(MEMBER);
  const b = writeBatch(db);
  b.delete(postRef(db, a, 'p1'));
  b.update(arcRef(db, a), { postCount: increment(-1), countedPost: 'p1' });
  await assertSucceeds(b.commit());
});

test('ALLOWS the arc\'s maker removing someone\'s post', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MEMBER }] });
  const db = as(MAKER);
  const b = writeBatch(db);
  b.delete(postRef(db, a, 'p1'));
  b.update(arcRef(db, a), { postCount: increment(-1), countedPost: 'p1' });
  await assertSucceeds(b.commit());
});

test('DENIES deleting a post without uncounting it', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MEMBER }] });
  await assertFails(deleteDoc(postRef(as(MEMBER), a, 'p1')));
});

test('DENIES deleting someone else\'s post in an arc you didn\'t make', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  const db = as(MEMBER);
  const b = writeBatch(db);
  b.delete(postRef(db, a, 'p1'));
  b.update(arcRef(db, a), { postCount: increment(-1), countedPost: 'p1' });
  await assertFails(b.commit());
});

// ── Replies and replyCount ─────────────────────────────────────────────────

test('ALLOWS a member replying, counted in the same batch', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertSucceeds(replyBatch(MEMBER, a, 'p1', 'r1'));
});

test('DENIES the old client\'s reply (no likes / likeCount): why replies always failed', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  const { likes, likeCount, ...old } = newReply(MEMBER);
  await assertFails(addDoc(collection(as(MEMBER), 'arcs', a, 'posts', 'p1', 'replies'), old));
});

test('DENIES a reply without the post\'s count moving', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertFails(setDoc(replyRef(as(MEMBER), a, 'p1', 'r1'), newReply(MEMBER)));
});

test('DENIES anyone bumping replyCount with no reply (R7)', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertFails(updateDoc(postRef(as(STRANGER), a, 'p1'), { replyCount: increment(1), countedReply: 'x' }));
});

test('DENIES a reply from someone who hasn\'t joined', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertFails(replyBatch(STRANGER, a, 'p1', 'r1', newReply(STRANGER)));
});

test('DENIES a reply over 1,000 characters', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertFails(replyBatch(MEMBER, a, 'p1', 'r1', newReply(MEMBER, { body: 'x'.repeat(1001) })));
});

test('ALLOWS deleting your own reply, uncounted in the same batch', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }], replies: { p1: [{ id: 'r1', author: MEMBER }] } });
  const db = as(MEMBER);
  const b = writeBatch(db);
  b.delete(replyRef(db, a, 'p1', 'r1'));
  b.update(postRef(db, a, 'p1'), { replyCount: increment(-1), countedReply: 'r1' });
  await assertSucceeds(b.commit());
});

test('DENIES deleting a reply without uncounting it', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }], replies: { p1: [{ id: 'r1', author: MEMBER }] } });
  await assertFails(deleteDoc(replyRef(as(MEMBER), a, 'p1', 'r1')));
});

test('ALLOWS liking a post as the app does (unchanged rule)', async () => {
  const a = await seed({ posts: [{ id: 'p1', author: MAKER }] });
  await assertSucceeds(updateDoc(postRef(as(STRANGER), a, 'p1'), { likes: [STRANGER], likeCount: 1 }));
});

// ── Reports ────────────────────────────────────────────────────────────────

function report(uid, over = {}) {
  return { reporter: uid, path: 'arcs/a/posts/p', reason: 'spoiler', createdAt: serverTimestamp(), ...over };
}

test('ALLOWS reporting a post or a reply', async () => {
  const db = as(MEMBER);
  await assertSucceeds(addDoc(collection(db, 'reports'), report(MEMBER)));
  await assertSucceeds(addDoc(collection(db, 'reports'),
    report(MEMBER, { path: 'arcs/a/posts/p/replies/r', reason: 'abuse' })));
});

test('DENIES reading reports, even your own', async () => {
  const db = as(MEMBER);
  const ref = doc(db, 'reports', fresh('rep'));
  await assertSucceeds(setDoc(ref, report(MEMBER)));
  await assertFails(getDoc(ref));
});

test('DENIES a report in someone else\'s name, of another path, or with another reason', async () => {
  const db = as(MEMBER);
  await assertFails(addDoc(collection(db, 'reports'), report(STRANGER)));
  await assertFails(addDoc(collection(db, 'reports'), report(MEMBER, { path: 'users/x' })));
  await assertFails(addDoc(collection(db, 'reports'), report(MEMBER, { reason: 'dislike' })));
});

test('DENIES changing a report once made', async () => {
  const db = as(MEMBER);
  const ref = doc(db, 'reports', fresh('rep'));
  await assertSucceeds(setDoc(ref, report(MEMBER)));
  await assertFails(updateDoc(ref, { reason: 'spam' }));
});
