// Emulator tests for the Arcs safety kit (code batch 2, audit 7a item 7,
// Q179, LR-006): reports of an arc or a person as well as a post or reply,
// and the rules date and block list on the reader's own user document.
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
  collection,
  addDoc,
  setDoc,
  getDoc,
  arrayUnion,
  arrayRemove,
  serverTimestamp,
} from 'firebase/firestore';

const here = dirname(fileURLToPath(import.meta.url));

const ROSA = 'sk_rosa'; // reports and blocks
const TROLL = 'sk_troll';

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
    await setDoc(doc(db, 'users', ROSA), { displayName: 'Rosa' });
    await setDoc(doc(db, 'users', TROLL), { displayName: 'Troll', blocked: [] });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

const as = (uid) => testEnv.authenticatedContext(uid).firestore();
const report = (uid, fields) =>
  addDoc(collection(as(uid), 'reports'), {
    reporter: uid,
    createdAt: serverTimestamp(),
    ...fields,
  });

// ── Reports: what the kit adds ────────────────────────────────────────────

test('ALLOWS reporting an arc', async () => {
  await assertSucceeds(report(ROSA, { path: 'arcs/a1', reason: 'spam' }));
});

test('ALLOWS reporting a person for their name, from their post', async () => {
  await assertSucceeds(
    report(ROSA, { path: `users/${TROLL}`, reason: 'name', from: 'arcs/a1/posts/p1' }),
  );
});

test('ALLOWS reporting a person for abuse, from their reply', async () => {
  await assertSucceeds(
    report(ROSA, {
      path: `users/${TROLL}`,
      reason: 'abuse',
      from: 'arcs/a1/posts/p1/replies/r1',
    }),
  );
});

test('ALLOWS reporting a person with no "from"', async () => {
  await assertSucceeds(report(ROSA, { path: `users/${TROLL}`, reason: 'spam' }));
});

// ── Reports: what stays as it was ─────────────────────────────────────────

test('ALLOWS reporting a post, as before', async () => {
  await assertSucceeds(report(ROSA, { path: 'arcs/a1/posts/p1', reason: 'spoiler' }));
});

test('ALLOWS reporting a reply, as before', async () => {
  await assertSucceeds(report(ROSA, { path: 'arcs/a1/posts/p1/replies/r1', reason: 'abuse' }));
});

// ── Reports: what stays refused ───────────────────────────────────────────

test('DENIES reporting yourself', async () => {
  await assertFails(report(ROSA, { path: `users/${ROSA}`, reason: 'abuse' }));
});

test('DENIES "name" as the reason for a post', async () => {
  await assertFails(report(ROSA, { path: 'arcs/a1/posts/p1', reason: 'name' }));
});

test('DENIES a reason the app never sends', async () => {
  await assertFails(report(ROSA, { path: `users/${TROLL}`, reason: 'dislike' }));
});

test('DENIES a person path that reaches into their documents', async () => {
  await assertFails(report(ROSA, { path: `users/${TROLL}/animeList/1`, reason: 'abuse' }));
});

test('DENIES a "from" outside Arcs', async () => {
  await assertFails(
    report(ROSA, { path: `users/${TROLL}`, reason: 'abuse', from: 'episodeDiscussions/c1' }),
  );
});

test('DENIES a "from" on a report about words', async () => {
  await assertFails(
    report(ROSA, { path: 'arcs/a1/posts/p1', reason: 'spam', from: 'arcs/a1' }),
  );
});

test('DENIES a report filed as someone else', async () => {
  await assertFails(
    addDoc(collection(as(ROSA), 'reports'), {
      reporter: TROLL,
      path: 'arcs/a1',
      reason: 'spam',
      createdAt: serverTimestamp(),
    }),
  );
});

test('DENIES a report with extra fields', async () => {
  await assertFails(report(ROSA, { path: 'arcs/a1', reason: 'spam', note: 'free text' }));
});

test('DENIES reading a report back', async () => {
  const ref = doc(as(ROSA), 'reports', 'sk_read');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'reports', 'sk_read'), { reporter: ROSA });
  });
  await assertFails(getDoc(ref));
});

// ── Block list and rules date: your own record only ───────────────────────

test('ALLOWS Rosa blocking and unblocking on her own record', async () => {
  const ref = doc(as(ROSA), 'users', ROSA);
  await assertSucceeds(setDoc(ref, { blocked: arrayUnion(TROLL) }, { merge: true }));
  await assertSucceeds(setDoc(ref, { blocked: arrayRemove(TROLL) }, { merge: true }));
});

test('ALLOWS Rosa storing the day she agreed to the rules', async () => {
  await assertSucceeds(
    setDoc(doc(as(ROSA), 'users', ROSA), { arcsRulesAt: serverTimestamp() }, { merge: true }),
  );
});

test('DENIES Troll reading Rosa\'s record, and so her block list', async () => {
  await assertFails(getDoc(doc(as(TROLL), 'users', ROSA)));
});

test('DENIES Troll emptying Rosa\'s block list', async () => {
  await assertFails(
    setDoc(doc(as(TROLL), 'users', ROSA), { blocked: [] }, { merge: true }),
  );
});
