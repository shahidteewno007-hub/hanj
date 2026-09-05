// Emulator tests for /users/{userId}/companion_chat (batch 5b).
//
// Run from firestore-tests/:  npm test
//
// This collection had no rule at all, so it fell through to default-deny:
// chatWithTomo kept writing the conversation via the Admin SDK (which bypasses
// rules) while the client could never read it back. These assert the owner can
// now read their own history, that nobody else can, and that the client still
// cannot write — the function is the only writer.

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
  doc, collection, getDoc, getDocs, setDoc, addDoc, deleteDoc,
} from 'firebase/firestore';

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

  // Seeded with rules disabled — this is what the Admin SDK write from
  // chatWithTomo looks like, since that path bypasses rules too.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', OWNER, 'companion_chat', 'm1'), {
      role: 'user',
      text: 'what should I watch tonight',
      ts: 1000,
    });
    await setDoc(doc(db, 'users', OWNER, 'companion_chat', 'm2'), {
      role: 'assistant',
      text: 'Something short. You have three unfinished shows.',
      ts: 1001,
    });
    await setDoc(doc(db, 'users', OWNER, 'companion_meta', 'usage'), {
      date: '2026-09-04',
      count: 3,
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── The fix: the owner can read their own history again ────────────────────

test('ALLOWS the owner to read their own companion_chat history', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const snap = await assertSucceeds(
    getDocs(collection(db, 'users', OWNER, 'companion_chat')),
  );
  assert.equal(snap.size, 2);
});

test('ALLOWS the owner to read a single companion_chat message', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const snap = await assertSucceeds(
    getDoc(doc(db, 'users', OWNER, 'companion_chat', 'm1')),
  );
  assert.equal(snap.data().role, 'user');
});

// ── Nobody else gets to read it ────────────────────────────────────────────

test('DENIES a second account reading the owner companion_chat', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(getDocs(collection(db, 'users', OWNER, 'companion_chat')));
});

test('DENIES an unauthenticated read of companion_chat', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(db, 'users', OWNER, 'companion_chat')));
});

// ── The client is never a writer, not even the owner ───────────────────────

test('DENIES the owner creating a companion_chat message', async () => {
  // Only chatWithTomo writes here. A client write could only be forged
  // history — e.g. fabricating assistant turns to steer later context.
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(
    addDoc(collection(db, 'users', OWNER, 'companion_chat'), {
      role: 'assistant',
      text: 'forged',
      ts: 2000,
    }),
  );
});

test('DENIES the owner editing an existing companion_chat message', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER, 'companion_chat', 'm2'), { text: 'edited' }, { merge: true }),
  );
});

test('DENIES the owner deleting a companion_chat message', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(deleteDoc(doc(db, 'users', OWNER, 'companion_chat', 'm1')));
});

test('DENIES a second account writing to the owner companion_chat', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(
    addDoc(collection(db, 'users', OWNER, 'companion_chat'), { role: 'user', text: 'x', ts: 3000 }),
  );
});

// ── companion_meta stays default-denied ────────────────────────────────────

test('DENIES the owner reading companion_meta (the daily usage counter)', async () => {
  // Deliberately unruled. The client has no reason to see it, and a client
  // that could write it could reset its own 40/day cap.
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(getDoc(doc(db, 'users', OWNER, 'companion_meta', 'usage')));
});

test('DENIES the owner writing companion_meta to reset their own daily cap', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER, 'companion_meta', 'usage'), { count: 0 }, { merge: true }),
  );
});
