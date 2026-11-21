// Emulator tests for the /users/{userId} read rule (batch 5a).
//
// Run from firestore-tests/:  npm test
// (starts the Firestore emulator, runs these, shuts it down)
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
import { doc, getDoc, setDoc, deleteDoc } from 'firebase/firestore';

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

  // Seed both user documents with rules disabled, so the fixtures exist
  // regardless of what the rules currently permit.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', OWNER), {
      displayName: 'Owner',
      email: 'owner@example.com',
      fcmToken: 'owner-device-token',
      isFounder: true,
      founderNumber: 1,
    });
    await setDoc(doc(db, 'users', OTHER), {
      displayName: 'Other',
      email: 'other@example.com',
      fcmToken: 'other-device-token',
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

// ── The fix ────────────────────────────────────────────────────────────────

test('DENIES an unauthenticated read of a user document', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', OWNER)));
});

test('DENIES an unauthenticated read even of a document with no sensitive fields set', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'users', OTHER)));
});

// ── The access that must keep working ──────────────────────────────────────

test('ALLOWS the owner to read their own document', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const snap = await assertSucceeds(getDoc(doc(db, 'users', OWNER)));
  assert.equal(snap.data().displayName, 'Owner');
});

test('DENIES a signed-in user reading another user document (code batch 2)', async () => {
  // Was the KNOWN RESIDUAL (AUDIT.md 6d): soulmatch_screen scanned every
  // user document, so any signed-in user could read anyone's email and
  // push token. Soulmatch is hidden (code batch 1) and the document is
  // owner-only since code batch 2 (Q178, LR-008); owner-only.test.js holds
  // the rest.
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(getDoc(doc(db, 'users', OWNER)));
});

// ── Writes: unchanged by 5a, asserted so the fix cannot loosen them ────────

test('ALLOWS the owner to update their own document', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertSucceeds(
    setDoc(doc(db, 'users', OWNER), { displayName: 'Owner renamed' }, { merge: true }),
  );
});

test('DENIES one user writing to another user document', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER), { displayName: 'hijacked' }, { merge: true }),
  );
});

test('DENIES one user deleting another user document', async () => {
  const db = testEnv.authenticatedContext(OTHER).firestore();
  await assertFails(deleteDoc(doc(db, 'users', OWNER)));
});

test('DENIES changing founderNumber once it is set', async () => {
  const db = testEnv.authenticatedContext(OWNER).firestore();
  await assertFails(
    setDoc(doc(db, 'users', OWNER), { founderNumber: 2 }, { merge: true }),
  );
});
