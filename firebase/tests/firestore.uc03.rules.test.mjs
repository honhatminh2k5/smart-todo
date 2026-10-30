import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  serverTimestamp,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const rules = await readFile(path.join(root, 'firestore.rules'), 'utf8');
const emulator = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-smart-todo',
    firestore: {
      host: emulator[0],
      port: Number(emulator[1] || 8080),
      rules,
    },
  });
});

after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

function userDb(uid) {
  return env.authenticatedContext(uid, { email: `${uid}@example.com` }).firestore();
}

async function seedBoard({ archivedAt = null } = {}) {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'boards/uc03-board'), {
      name: 'Board UC03',
      description: 'Board dùng để kiểm thử',
      ownerId: 'owner',
      memberIds: ['owner', 'member'],
      archivedAt,
      createdAt: new Date('2026-10-01T00:00:00Z'),
      updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
    for (const uid of ['owner', 'member']) {
      await setDoc(doc(db, `boards/uc03-board/members/${uid}`), {
        role: uid === 'owner' ? 'owner' : 'member',
        displayName: uid,
        email: `${uid}@example.com`,
        joinedAt: new Date('2026-10-01T00:00:00Z'),
      });
    }
  });
}

test('UC03: Owner được sửa tên và mô tả board', async () => {
  await seedBoard();
  const db = userDb('owner');
  await assertSucceeds(updateDoc(doc(db, 'boards/uc03-board'), {
    name: 'Tên board mới',
    description: 'Mô tả mới',
    updatedAt: serverTimestamp(),
  }));
  const saved = await assertSucceeds(getDoc(doc(db, 'boards/uc03-board')));
  assert.equal(saved.data().name, 'Tên board mới');
  assert.equal(saved.data().description, 'Mô tả mới');
});

test('UC03: Owner được lưu trữ rồi khôi phục board', async () => {
  await seedBoard();
  const boardRef = doc(userDb('owner'), 'boards/uc03-board');

  await assertSucceeds(updateDoc(boardRef, {
    archivedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
  const archived = await assertSucceeds(getDoc(boardRef));
  assert.ok(archived.data().archivedAt);

  await assertSucceeds(updateDoc(boardRef, {
    archivedAt: null,
    updatedAt: serverTimestamp(),
  }));
  const restored = await assertSucceeds(getDoc(boardRef));
  assert.equal(restored.data().archivedAt, null);
});

test('UC03: Member không được sửa thông tin hoặc lưu trữ board', async () => {
  await seedBoard();
  const boardRef = doc(userDb('member'), 'boards/uc03-board');

  await assertFails(updateDoc(boardRef, {
    name: 'Member tự đổi tên',
    updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(boardRef, {
    archivedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('UC03: Member không được khôi phục board đã lưu trữ', async () => {
  await seedBoard({ archivedAt: new Date('2026-10-02T00:00:00Z') });
  const boardRef = doc(userDb('member'), 'boards/uc03-board');

  await assertFails(updateDoc(boardRef, {
    archivedAt: null,
    updatedAt: serverTimestamp(),
  }));
});

test('UC03: không thể sửa thông tin board đồng thời chiếm quyền Owner', async () => {
  await seedBoard();
  const boardRef = doc(userDb('owner'), 'boards/uc03-board');
  await assertFails(updateDoc(boardRef, {
    name: 'Tên mới',
    ownerId: 'member',
    updatedAt: serverTimestamp(),
  }));
});
