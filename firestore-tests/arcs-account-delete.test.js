// Emulator tests for what account deletion does in Arcs (arcs-account-delete,
// 2026-11-14).
//
// Run from firestore-tests/:  npm test
//
// Rules are loaded from ../firestore.rules directly, so these test the file
// and say NOTHING about the ruleset deployed in production. This file uses
// its own project id, so its collection-group queries see only its own data.
//
// ArcsService.wipeUser (lib/services/arcs_service.dart) runs before the Auth
// account goes. `clientWipe` below is that method, step for step:
//   1. the user's replies (collection group, authorId == uid), each deleted
//      with its post's replyCount -1 in the same transaction, or alone when
//      the post is gone;
//   2. the user's posts (collection group, authorId == uid), each deleted
//      with its arc's postCount -1, or alone when the arc is gone;
//   3. the user's likes (collection group, likes array-contains uid), each
//      removed with likeCount -1;
//   4. the arcs they're in or made: an arc they made with no posts and no
//      one else in it is deleted; otherwise they leave it, and if they made
//      it, its maker becomes "Deleted account" and its about is cleared.
//
// What the rules add for it (firestore.rules):
//   - collection-group LIST of posts/replies, only for your own
//     (authorId == you) or the posts you like (likes array-contains you);
//   - an author may delete their post under a missing arc, or their reply
//     under a missing post (no count is left to move);
//   - the maker may set creatorName to exactly 'Deleted account' and clear
//     the about, and nothing else, in that write.

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
  deleteDoc,
  collection,
  collectionGroup,
  query,
  where,
  limit,
  getDocs,
  getDocsFromServer,
  writeBatch,
  runTransaction,
  increment,
  Timestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const DANA = 'del_dana';   // deletes her account
const ERIN = 'del_erin';
const FINN = 'del_finn';

let testEnv;
let n = 0;
const fresh = (p) => `${p}_${++n}`;
const as = (uid) => testEnv.authenticatedContext(uid).firestore();

const arcRef = (db, a) => doc(db, 'arcs', a);
const postRef = (db, a, p) => doc(db, 'arcs', a, 'posts', p);
const replyRef = (db, a, p, r) => doc(db, 'arcs', a, 'posts', p, 'replies', r);

const AT = Timestamp.fromMillis(Date.UTC(2026, 10, 1));

function arcV2(maker, over = {}) {
  return {
    v: 2,
    name: 'Frieren, episodes 1–28',
    description: 'Watching slowly.',
    anime: { id: '154587', title: 'Frieren', cover: null, episodes: 28 },
    from: 1, to: 28, pace: 4, startsOn: AT,
    createdBy: maker, creatorName: 'Maker',
    members: [maker], memberCount: 1, postCount: 0, createdAt: AT,
    ...over,
  };
}

// The shape of Shahid's 2 Jun "One Piece Lore": a free-form arc from
// before the redesign. Its posts carry no `ep`, its replies no `likes`.
function arcOld(maker, over = {}) {
  return {
    name: 'One Piece Lore', description: 'Theories.', emoji: '🏴‍☠️',
    color: '#E8624A', tags: ['lore'], createdBy: maker, creatorName: 'Maker',
    members: [maker], memberCount: 1, postCount: 0, createdAt: AT,
    ...over,
  };
}

function post(author, over = {}) {
  return {
    title: '', body: 'That ending.', ep: 4, authorId: author,
    authorName: author, likes: [], likeCount: 0, replyCount: 0,
    createdAt: AT, ...over,
  };
}

function reply(author, over = {}) {
  return {
    body: 'Agreed.', authorId: author, authorName: author,
    likes: [], likeCount: 0, createdAt: AT, ...over,
  };
}

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

async function read(ref) {
  let out;
  await seed(async (db) => {
    const s = await getDoc(ref(db));
    out = s.exists() ? s.data() : null;
  });
  return out;
}

// ArcsService.wipeUser, step for step.
const POST_PATH = /^arcs\/[^/]+\/posts\/[^/]+$/;
const REPLY_PATH = /^arcs\/[^/]+\/posts\/[^/]+\/replies\/[^/]+$/;
const ARC_PATH = /^arcs\/[^/]+$/;

async function clientWipe(db, uid) {
  const out = {
    posts: 0, postsRemoved: 0, replies: 0, repliesRemoved: 0,
    likes: 0, likesRemoved: 0, arcs: 0, arcsDone: 0, unknown: [],
  };
  async function look(what, q, path) {
    try {
      const s = await getDocsFromServer(q);
      return s.docs.filter((d) => path.test(d.ref.path));
    } catch (e) {
      out.unknown.push(what);
      return [];
    }
  }

  // 1. Replies.
  const replies = await look('replies',
    query(collectionGroup(db, 'replies'), where('authorId', '==', uid)), REPLY_PATH);
  out.replies = replies.length;
  for (const d of replies) {
    const p = d.ref.parent.parent;
    try {
      await runTransaction(db, async (tx) => {
        const snap = await tx.get(p);
        tx.delete(d.ref);
        if (snap.exists()) {
          tx.update(p, { replyCount: increment(-1), countedReply: d.id });
        }
      });
      out.repliesRemoved++;
    } catch (_) {}
  }

  // 2. Posts.
  const posts = await look('posts',
    query(collectionGroup(db, 'posts'), where('authorId', '==', uid)), POST_PATH);
  out.posts = posts.length;
  for (const d of posts) {
    const a = d.ref.parent.parent;
    try {
      await runTransaction(db, async (tx) => {
        const snap = await tx.get(a);
        tx.delete(d.ref);
        if (snap.exists()) {
          tx.update(a, { postCount: increment(-1), countedPost: d.id });
        }
      });
      out.postsRemoved++;
    } catch (_) {}
  }

  // 3. Likes.
  const liked = await look('likes',
    query(collectionGroup(db, 'posts'), where('likes', 'array-contains', uid)), POST_PATH);
  out.likes = liked.length;
  for (const d of liked) {
    try {
      await runTransaction(db, async (tx) => {
        const snap = await tx.get(d.ref);
        const likes = [...(snap.data()?.likes ?? [])];
        if (!likes.includes(uid)) return;
        const count = snap.data()?.likeCount ?? 0;
        tx.update(d.ref, {
          likes: likes.filter((e) => e !== uid),
          likeCount: count - 1,
        });
      });
      out.likesRemoved++;
    } catch (_) {}
  }

  // 4. Arcs they're in or made.
  const arcs = new Map();
  for (const q of [
    query(collection(db, 'arcs'), where('members', 'array-contains', uid)),
    query(collection(db, 'arcs'), where('createdBy', '==', uid)),
  ]) {
    for (const d of await look('memberships', q, ARC_PATH)) arcs.set(d.id, d);
  }
  out.arcs = arcs.size;
  for (const d of arcs.values()) {
    try {
      const data = d.data();
      const made = data.createdBy === uid;
      if (made) {
        const alone = (data.members ?? []).every((m) => m === uid);
        const count = data.postCount ?? 0;
        const empty = (await getDocsFromServer(
          query(collection(d.ref, 'posts'), limit(1)))).empty;
        if (empty && alone && count === 0) {
          await deleteDoc(d.ref);
          out.arcsDone++;
          continue;
        }
      }
      // ArcsService.setMember(join: false): a transaction on the server copy.
      await runTransaction(db, async (tx) => {
        const snap = await tx.get(d.ref);
        if (!snap.exists()) return;
        const members = [...(snap.data().members ?? [])];
        if (!members.includes(uid)) return;
        tx.update(d.ref, {
          members: members.filter((e) => e !== uid),
          memberCount: (snap.data().memberCount ?? members.length) - 1,
        });
      });
      if (made) {
        await updateDoc(d.ref, { creatorName: 'Deleted account', description: '' });
      }
      out.arcsDone++;
    } catch (_) {}
  }
  return out;
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hanj-rules-arcsdel',
    firestore: {
      rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── The whole sweep ──────────────────────────────────────────

test('ALLOWS: the sweep removes Dana\'s posts, replies, likes and memberships, with every count moved', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    // Erin's arc, all three in it.
    await setDoc(arcRef(db, 'arcE'), arcV2(ERIN, {
      members: [ERIN, DANA, FINN], memberCount: 3, postCount: 2 }));
    await setDoc(postRef(db, 'arcE', 'postE1'), post(ERIN, {
      likes: [DANA, FINN], likeCount: 2, replyCount: 2 }));
    await setDoc(replyRef(db, 'arcE', 'postE1', 'rD1'), reply(DANA));
    await setDoc(replyRef(db, 'arcE', 'postE1', 'rF1'), reply(FINN));
    await setDoc(postRef(db, 'arcE', 'postD1'), post(DANA, {
      likes: [ERIN], likeCount: 1, replyCount: 2 }));
    await setDoc(replyRef(db, 'arcE', 'postD1', 'rE2'), reply(ERIN));
    await setDoc(replyRef(db, 'arcE', 'postD1', 'rD2'), reply(DANA));
    // Dana's reply under a post Erin already deleted.
    await setDoc(replyRef(db, 'arcE', 'postGone', 'rG'), reply(DANA));

    // Dana's arc, nobody else: goes.
    await setDoc(arcRef(db, 'arcD1'), arcV2(DANA));
    // Dana's arc, Finn joined, no posts: stays for Finn.
    await setDoc(arcRef(db, 'arcD2'), arcV2(DANA, {
      members: [DANA, FINN], memberCount: 2 }));
    // Dana's arc, which she left, with Erin's post: stays for Erin.
    await setDoc(arcRef(db, 'arcD3'), arcV2(DANA, {
      members: [ERIN], memberCount: 1, postCount: 1, description: 'My notes' }));
    await setDoc(postRef(db, 'arcD3', 'postE3'), post(ERIN));
    // An old free-form arc Dana made, her post with Erin's reply.
    await setDoc(arcRef(db, 'arcOld'), arcOld(DANA, {
      members: [DANA, ERIN], memberCount: 2, postCount: 1 }));
    const { ep, ...noEp } = post(DANA, { title: 'Imu', replyCount: 1 });
    await setDoc(postRef(db, 'arcOld', 'postOld'), noEp);
    const { likes, likeCount, ...oldReply } = reply(ERIN);
    await setDoc(replyRef(db, 'arcOld', 'postOld', 'rOld'), oldReply);
    // Dana's post under an arc that no longer exists.
    await setDoc(postRef(db, 'arcGone', 'postG'), post(DANA));
  });

  const out = await clientWipe(as(DANA), DANA);
  assert.deepEqual(out, {
    posts: 3, postsRemoved: 3, replies: 3, repliesRemoved: 3,
    likes: 1, likesRemoved: 1, arcs: 5, arcsDone: 5, unknown: [],
  });

  // Nothing of Dana's is left (read with rules off).
  await seed(async (db) => {
    for (const g of ['posts', 'replies']) {
      const s = await getDocs(query(collectionGroup(db, g), where('authorId', '==', DANA)));
      assert.equal(s.size, 0, `${g} by Dana`);
    }
    const l = await getDocs(query(collectionGroup(db, 'posts'), where('likes', 'array-contains', DANA)));
    assert.equal(l.size, 0, 'likes by Dana');
    const m = await getDocs(query(collection(db, 'arcs'), where('members', 'array-contains', DANA)));
    assert.equal(m.size, 0, 'arcs with Dana in them');
  });

  // Counts match what's there.
  const arcE = await read((db) => arcRef(db, 'arcE'));
  assert.deepEqual([arcE.members, arcE.memberCount, arcE.postCount],
    [[ERIN, FINN], 2, 1]);
  const postE1 = await read((db) => postRef(db, 'arcE', 'postE1'));
  assert.deepEqual([postE1.replyCount, postE1.likes, postE1.likeCount],
    [1, [FINN], 1]);
  assert.equal(await read((db) => arcRef(db, 'arcD1')), null);
  const d2 = await read((db) => arcRef(db, 'arcD2'));
  assert.deepEqual([d2.creatorName, d2.description, d2.members, d2.memberCount, d2.createdBy],
    ['Deleted account', '', [FINN], 1, DANA]);
  const d3 = await read((db) => arcRef(db, 'arcD3'));
  assert.deepEqual([d3.creatorName, d3.description, d3.members, d3.postCount],
    ['Deleted account', '', [ERIN], 1]);
  const old = await read((db) => arcRef(db, 'arcOld'));
  assert.deepEqual([old.creatorName, old.description, old.members, old.memberCount, old.postCount, old.emoji],
    ['Deleted account', '', [ERIN], 1, 0, '🏴‍☠️']);

  // Left, as recorded: other people's replies under Dana's deleted posts.
  assert.ok(await read((db) => replyRef(db, 'arcE', 'postD1', 'rE2')));
  assert.ok(await read((db) => replyRef(db, 'arcOld', 'postOld', 'rOld')));

  // A second run finds nothing but the three arcs Dana made that stayed
  // (createdBy keeps her uid), and changes nothing in them.
  const again = await clientWipe(as(DANA), DANA);
  assert.deepEqual(again, {
    posts: 0, postsRemoved: 0, replies: 0, repliesRemoved: 0,
    likes: 0, likesRemoved: 0, arcs: 3, arcsDone: 3, unknown: [],
  });
  assert.deepEqual(await read((db) => arcRef(db, 'arcD2')), d2);
});

test('ALLOWS: Erin can still delete her reply left under Dana\'s deleted post', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(replyRef(db, 'arcE', 'postD1', 'rE2'), reply(ERIN));
  });
  await assertSucceeds(deleteDoc(replyRef(as(ERIN), 'arcE', 'postD1', 'rE2')));
});

// ── Finding your own: collection-group lists ─────────────────

async function seedLists() {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(arcRef(db, 'arcL'), arcV2(ERIN, { members: [ERIN, DANA], memberCount: 2, postCount: 2 }));
    await setDoc(postRef(db, 'arcL', 'pE'), post(ERIN, { likes: [DANA], likeCount: 1, replyCount: 1 }));
    await setDoc(postRef(db, 'arcL', 'pD'), post(DANA, { likes: [ERIN], likeCount: 1 }));
    await setDoc(replyRef(db, 'arcL', 'pE', 'rD'), reply(DANA));
  });
}

test('ALLOWS: listing your own posts, replies and liked posts across arcs', async () => {
  await seedLists();
  const db = as(DANA);
  await assertSucceeds(getDocsFromServer(query(collectionGroup(db, 'posts'), where('authorId', '==', DANA))));
  await assertSucceeds(getDocsFromServer(query(collectionGroup(db, 'replies'), where('authorId', '==', DANA))));
  await assertSucceeds(getDocsFromServer(query(collectionGroup(db, 'posts'), where('likes', 'array-contains', DANA))));
});

test('DENIES: listing every post across arcs', async () => {
  await seedLists();
  await assertFails(getDocsFromServer(query(collectionGroup(as(DANA), 'posts'))));
});

test('DENIES: listing someone else\'s posts across arcs', async () => {
  await seedLists();
  await assertFails(getDocsFromServer(query(collectionGroup(as(DANA), 'posts'), where('authorId', '==', ERIN))));
});

test('DENIES: listing the posts someone else likes', async () => {
  await seedLists();
  await assertFails(getDocsFromServer(query(collectionGroup(as(DANA), 'posts'), where('likes', 'array-contains', ERIN))));
});

test('DENIES: listing every reply, or someone else\'s, across arcs', async () => {
  await seedLists();
  await assertFails(getDocsFromServer(query(collectionGroup(as(DANA), 'replies'))));
  await assertFails(getDocsFromServer(query(collectionGroup(as(DANA), 'replies'), where('authorId', '==', ERIN))));
});

test('DENIES: listing across arcs signed out', async () => {
  await seedLists();
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocsFromServer(query(collectionGroup(db, 'posts'), where('authorId', '==', DANA))));
});

// ── Orphans: no count left to move ───────────────────────────

test('ALLOWS: the author deletes their reply under a missing post, and their post under a missing arc', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(replyRef(db, 'arcX', 'gone', 'r'), reply(DANA));
    await setDoc(postRef(db, 'goneArc', 'p'), post(DANA));
  });
  await assertSucceeds(deleteDoc(replyRef(as(DANA), 'arcX', 'gone', 'r')));
  await assertSucceeds(deleteDoc(postRef(as(DANA), 'goneArc', 'p')));
});

test('DENIES: someone else deletes a reply under a missing post', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(replyRef(db, 'arcX', 'gone', 'r'), reply(DANA));
  });
  await assertFails(deleteDoc(replyRef(as(FINN), 'arcX', 'gone', 'r')));
});

test('DENIES: someone else deletes a post under a missing arc', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(postRef(db, 'goneArc', 'p'), post(DANA));
  });
  await assertFails(deleteDoc(postRef(as(ERIN), 'goneArc', 'p')));
});

test('DENIES: an author deletes their reply without the count while the post exists', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(arcRef(db, 'a'), arcV2(ERIN, { members: [ERIN, DANA], memberCount: 2, postCount: 1 }));
    await setDoc(postRef(db, 'a', 'p'), post(ERIN, { replyCount: 1 }));
    await setDoc(replyRef(db, 'a', 'p', 'r'), reply(DANA));
  });
  await assertFails(deleteDoc(replyRef(as(DANA), 'a', 'p', 'r')));
});

test('DENIES: an author deletes their post without the count while the arc exists', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(arcRef(db, 'a'), arcV2(ERIN, { members: [ERIN, DANA], memberCount: 2, postCount: 1 }));
    await setDoc(postRef(db, 'a', 'p'), post(DANA));
  });
  await assertFails(deleteDoc(postRef(as(DANA), 'a', 'p')));
});

test('DENIES: deleting the post in the same batch doesn\'t free its reply from the count', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(arcRef(db, 'a'), arcV2(ERIN, { members: [ERIN, DANA], memberCount: 2, postCount: 1 }));
    await setDoc(postRef(db, 'a', 'p'), post(DANA, { replyCount: 1 }));
    await setDoc(replyRef(db, 'a', 'p', 'r'), reply(DANA));
  });
  const db = as(DANA);
  // The post's own delete is counted and allowed; the reply rides along
  // uncounted, which must not pass.
  const b = writeBatch(db);
  b.delete(postRef(db, 'a', 'p'));
  b.update(arcRef(db, 'a'), { postCount: increment(-1), countedPost: 'p' });
  b.delete(replyRef(db, 'a', 'p', 'r'));
  await assertFails(b.commit());
});

test('DENIES: deleting the arc in the same batch doesn\'t free its post from the count', async () => {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    // A count that drifted to 0 (an old two-write client) with a post left.
    await setDoc(arcRef(db, 'a'), arcV2(DANA, { postCount: 0 }));
    await setDoc(postRef(db, 'a', 'p'), post(DANA));
  });
  const db = as(DANA);
  const b = writeBatch(db);
  b.delete(arcRef(db, 'a'));
  b.delete(postRef(db, 'a', 'p'));
  await assertFails(b.commit());
});

// ── The maker's name ─────────────────────────────────────────

async function seedMade() {
  await testEnv.clearFirestore();
  await seed(async (db) => {
    await setDoc(arcRef(db, 'm'), arcV2(DANA, {
      members: [DANA, ERIN], memberCount: 2, postCount: 0, creatorName: 'Dana' }));
  });
}

test('ALLOWS: the maker becomes "Deleted account" and clears the about', async () => {
  await seedMade();
  await assertSucceeds(updateDoc(arcRef(as(DANA), 'm'), {
    creatorName: 'Deleted account', description: '' }));
});

test('DENIES: the maker sets any other name', async () => {
  await seedMade();
  await assertFails(updateDoc(arcRef(as(DANA), 'm'), { creatorName: 'Erin', description: '' }));
});

test('DENIES: "Deleted account" with the about kept or rewritten', async () => {
  await seedMade();
  await assertFails(updateDoc(arcRef(as(DANA), 'm'), {
    creatorName: 'Deleted account', description: 'Still mine' }));
});

test('DENIES: "Deleted account" together with any other field', async () => {
  await seedMade();
  const db = as(DANA);
  await assertFails(updateDoc(arcRef(db, 'm'), {
    creatorName: 'Deleted account', description: '', name: 'Renamed' }));
  await assertFails(updateDoc(arcRef(db, 'm'), {
    creatorName: 'Deleted account', description: '', createdBy: ERIN }));
  await assertFails(updateDoc(arcRef(db, 'm'), {
    creatorName: 'Deleted account', description: '', members: [ERIN], memberCount: 1 }));
});

test('DENIES: anyone but the maker marks the maker deleted', async () => {
  await seedMade();
  await assertFails(updateDoc(arcRef(as(ERIN), 'm'), {
    creatorName: 'Deleted account', description: '' }));
});
