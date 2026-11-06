// Kiểm thử Security Rules cho UC05 – Quản lý card.
// Mỗi ca ghi đúng dạng dữ liệu mà app (FirestoreCardRepository,
// FirestoreListRepository) gửi lên, để chắc chắn Rules chấp nhận/từ chối đúng.
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
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  serverTimestamp,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const rules = await readFile(path.join(root, 'firestore.rules'), 'utf8');
const emulator = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const BOARD = 'uc05-board';
const created = new Date('2026-10-01T00:00:00Z');
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

// Board có Owner + Member, hai list và card do Owner tạo sẵn.
async function seedBoard({ cardsInTodo = 1 } = {}) {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, `boards/${BOARD}`), {
      name: 'Board UC05', description: '', ownerId: 'owner',
      memberIds: ['owner', 'member'], archivedAt: null,
      createdAt: created, updatedAt: created,
    });
    for (const [id, position] of [['todo', 1024], ['doing', 2048]]) {
      await setDoc(doc(db, `boards/${BOARD}/lists/${id}`), {
        name: id, position, archivedAt: null, createdAt: created, updatedAt: created,
      });
    }
    for (let i = 0; i < cardsInTodo; i++) {
      await setDoc(doc(db, `boards/${BOARD}/cards/c${i}`), storedCard({ position: (i + 1) * 1024 }));
    }
  });
}

// Card đã lưu trên máy chủ (giờ cố định thay cho serverTimestamp).
function storedCard(overrides = {}) {
  return {
    boardId: BOARD, listId: 'todo', title: 'Card mẫu', description: '',
    position: 1024, isCompleted: false, assigneeIds: [], labelIds: [],
    dueAt: null, archivedAt: null, commentCount: 0, checklistTotal: 0,
    checklistDone: 0, createdBy: 'owner', createdAt: created, updatedAt: created,
    ...overrides,
  };
}

// Đúng 16 trường mà FirestoreCardRepository.createCard ghi (W9).
function newCard(uid, overrides = {}) {
  return {
    ...storedCard({ createdBy: uid, title: 'Thẻ mới', position: 2048 }),
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

const cardRef = (db, id = 'c0') => doc(db, `boards/${BOARD}/cards/${id}`);

test('UC05: thành viên tạo card đủ 16 trường, ghi nhận người tạo', async () => {
  await seedBoard();
  const db = userDb('member');
  await assertSucceeds(setDoc(cardRef(db, 'new'), newCard('member')));
  const saved = await getDoc(cardRef(db, 'new'));
  assert.equal(saved.data().createdBy, 'member');
  assert.ok(saved.data().createdAt);
});

test('UC05 5a: tiêu đề rỗng hoặc dài hơn 200 ký tự bị từ chối', async () => {
  await seedBoard();
  const db = userDb('member');
  await assertFails(setDoc(cardRef(db, 'empty'), newCard('member', { title: '' })));
  await assertFails(setDoc(cardRef(db, 'long'), newCard('member', { title: 'a'.repeat(201) })));
  await assertSucceeds(setDoc(cardRef(db, 'max'), newCard('member', { title: 'a'.repeat(200) })));
});

test('UC05: không được tạo card thay người khác, thiếu trường, hoặc khi không là thành viên', async () => {
  await seedBoard();
  await assertFails(setDoc(cardRef(userDb('member'), 'x1'), newCard('owner')));
  const { description, ...missingField } = newCard('member');
  assert.equal(description, '');
  await assertFails(setDoc(cardRef(userDb('member'), 'x2'), missingField));
  await assertFails(setDoc(cardRef(userDb('outsider'), 'x3'), newCard('outsider')));
});

test('UC05 3a–3d: sửa tiêu đề, đánh dấu hoàn thành và kéo thả card', async () => {
  await seedBoard();
  const ref = cardRef(userDb('member'));
  await assertSucceeds(updateDoc(ref, { title: 'Tiêu đề mới', updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { isCompleted: true, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { listId: 'doing', position: 512, updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { title: 'a'.repeat(201), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { createdBy: 'member', updatedAt: serverTimestamp() }));
});

test('UC05: đánh số lại vị trí nhiều card trong một batch', async () => {
  await seedBoard({ cardsInTodo: 3 });
  const db = userDb('member');
  const batch = writeBatch(db);
  ['c2', 'c0', 'c1'].forEach((id, i) => batch.update(cardRef(db, id), {
    listId: 'todo', position: (i + 1) * 1024, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(batch.commit());
});

test('UC05 3e: lưu trữ card dùng giờ máy chủ; giờ tự đặt bị từ chối', async () => {
  await seedBoard();
  const ref = cardRef(userDb('member'));
  await assertFails(updateDoc(ref, { archivedAt: new Date('2020-01-01'), updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { archivedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
});

test('UC05 3f: xóa card cùng checklist và bình luận của người khác trong một batch', async () => {
  await seedBoard();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, `boards/${BOARD}/cards/c0/checklist/i1`), {
      title: 'Mục 1', isCompleted: false, position: 1024, createdAt: created, updatedAt: created,
    });
    await setDoc(doc(db, `boards/${BOARD}/cards/c0/comments/m1`), {
      authorId: 'owner', authorName: 'owner', body: 'Bình luận', createdAt: created, updatedAt: created,
    });
  });

  const db = userDb('member');
  // Xóa riêng bình luận của người khác thì bị chặn.
  await assertFails(deleteDoc(doc(db, `boards/${BOARD}/cards/c0/comments/m1`)));

  const card = cardRef(db);
  const batch = writeBatch(db);
  for (const sub of ['checklist', 'comments']) {
    const children = await getDocs(collection(card, sub));
    children.forEach(child => batch.delete(child.ref));
  }
  batch.delete(card);
  await assertSucceeds(batch.commit());
  assert.equal((await getDoc(card)).exists(), false);
});

test('UC05: người ngoài board không xóa được card', async () => {
  await seedBoard();
  await assertFails(deleteDoc(cardRef(userDb('outsider'))));
});

test('D7: lưu trữ list kéo theo 30 card trong một batch, rồi khôi phục lại', async () => {
  await seedBoard({ cardsInTodo: 30 });
  const db = userDb('member');
  const listRef = doc(db, `boards/${BOARD}/lists/todo`);
  const cardsOfList = query(
    collection(db, `boards/${BOARD}/cards`),
    where('listId', '==', 'todo'),
    where('archivedAt', '==', null),
  );

  const active = await getDocs(cardsOfList);
  assert.equal(active.size, 30);
  const archive = writeBatch(db);
  const archived = { archivedAt: serverTimestamp(), updatedAt: serverTimestamp() };
  archive.update(listRef, archived);
  active.forEach(card => archive.update(card.ref, archived));
  await assertSucceeds(archive.commit());

  const listArchivedAt = (await getDoc(listRef)).data().archivedAt;
  const sameTime = await getDocs(query(
    collection(db, `boards/${BOARD}/cards`),
    where('listId', '==', 'todo'),
    where('archivedAt', '==', listArchivedAt),
  ));
  assert.equal(sameTime.size, 30, 'card phải mang đúng archivedAt của list');

  const restore = writeBatch(db);
  const restored = { archivedAt: null, updatedAt: serverTimestamp() };
  restore.update(listRef, restored);
  sameTime.forEach(card => restore.update(card.ref, restored));
  await assertSucceeds(restore.commit());
  assert.equal((await getDocs(cardsOfList)).size, 30);
});
