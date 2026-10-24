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
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  deleteDoc,
  where,
  writeBatch,
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

function userDb(uid, email = `${uid}@example.com`) {
  return env.authenticatedContext(uid, { email }).firestore();
}
function anonDb() { return env.unauthenticatedContext().firestore(); }
async function seedBoard({ boardId = 'b1', owner = 'owner', members = ['owner', 'member'], name = 'Board thử' } = {}) {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, `boards/${boardId}`), {
      name, description: '', ownerId: owner, memberIds: members,
      archivedAt: null, createdAt: new Date('2026-10-01T00:00:00Z'),
      updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
    for (const uid of members) {
      await setDoc(doc(db, `boards/${boardId}/members/${uid}`), {
        role: uid === owner ? 'owner' : 'member',
        displayName: uid,
        email: `${uid}@example.com`,
        joinedAt: new Date('2026-10-01T00:00:00Z'),
      });
    }
    await setDoc(doc(db, `boards/${boardId}/lists/l1`), {
      name: 'Cần làm', position: 1024, archivedAt: null,
      createdAt: new Date('2026-10-01T00:00:00Z'), updatedAt: new Date('2026-10-01T00:00:00Z'),
    });
  });
}
function validCard({ boardId = 'b1', listId = 'l1', createdBy = 'member', assigneeIds = [] } = {}) {
  return {
    boardId, listId, title: 'Card hợp lệ', description: '', position: 1024,
    isCompleted: false, assigneeIds, labelIds: [], dueAt: null, archivedAt: null,
    commentCount: 0, checklistTotal: 0, checklistDone: 0, createdBy,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  };
}

test('T-U: người dùng chỉ đọc được hồ sơ của chính mình', async () => {
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(), 'users/member'), {
      displayName: 'Member', email: 'member@example.com', createdAt: new Date(), updatedAt: new Date(),
    });
  });
  const db = userDb('member');
  await assertSucceeds(getDoc(doc(db, 'users/member')));
  await assertFails(getDoc(doc(db, 'users/other')));
  await assertFails(getDoc(doc(anonDb(), 'users/member')));
});

test('T-U: chỉ được tạo hồ sơ với UID và email của tài khoản đang đăng nhập', async () => {
  const db = userDb('new-user', 'new@example.com');
  await assertSucceeds(setDoc(doc(db, 'users/new-user'), {
    displayName: 'Người mới', email: 'new@example.com',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db, 'users/someone-else'), {
    displayName: 'Người khác', email: 'new@example.com',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
});

test('T-B: tạo board và hồ sơ Owner trong cùng batch', async () => {
  const db = userDb('owner', 'owner@example.com');
  const batch = writeBatch(db);
  batch.set(doc(db, 'boards/new-board'), {
    name: 'Board mới', description: '', ownerId: 'owner', memberIds: ['owner'],
    archivedAt: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'boards/new-board/members/owner'), {
    role: 'owner', displayName: 'owner', email: 'owner@example.com', joinedAt: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
});

test('T-B: thành viên đọc board; người ngoài và người chưa đăng nhập bị chặn', async () => {
  await seedBoard();
  await assertSucceeds(getDoc(doc(userDb('member'), 'boards/b1')));
  await assertFails(getDoc(doc(userDb('outside'), 'boards/b1')));
  await assertFails(getDoc(doc(anonDb(), 'boards/b1')));
});

test('T-B: truy vấn danh sách board phải có điều kiện memberIds', async () => {
  await seedBoard();
  const db = userDb('member');
  await assertSucceeds(getDocs(query(collection(db, 'boards'), where('memberIds', 'array-contains', 'member'))));
  await assertFails(getDocs(collection(db, 'boards')));
});

test('T-B: Owner được sửa thông tin board nhưng Member không được', async () => {
  await seedBoard();
  await assertSucceeds(updateDoc(doc(userDb('owner'), 'boards/b1'), {
    name: 'Tên mới', updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(userDb('member'), 'boards/b1'), {
    name: 'Tự đổi tên', updatedAt: serverTimestamp(),
  }));
});

test('T-B: board chỉ được lưu trữ, không được xóa vĩnh viễn qua client', async () => {
  await seedBoard();
  await assertFails(deleteDoc(doc(userDb('owner'), 'boards/b1')));
});

test('T-L: thành viên tạo list được, người ngoài không tạo được, list không bị xóa', async () => {
  await seedBoard();
  const data = { name: 'Đang làm', position: 2048, archivedAt: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(userDb('member'), 'boards/b1/lists/l2'), data));
  await assertFails(setDoc(doc(userDb('outside'), 'boards/b1/lists/l3'), data));
  await assertFails(deleteDoc(doc(userDb('member'), 'boards/b1/lists/l1')));
});

test('T-C: thành viên tạo card hợp lệ; dữ liệu giao việc cho người ngoài bị chặn', async () => {
  await seedBoard();
  const db = userDb('member');
  await assertSucceeds(setDoc(doc(db, 'boards/b1/cards/c1'), validCard({ assigneeIds: ['owner'] })));
  await assertFails(setDoc(doc(db, 'boards/b1/cards/c2'), validCard({ assigneeIds: ['outside'] })));
  await assertFails(setDoc(doc(userDb('outside'), 'boards/b1/cards/c3'), validCard({ createdBy: 'outside' })));
});

test('T-C: truy vấn xuyên board chỉ cho phép card được giao cho chính người dùng', async () => {
  await seedBoard();
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(), 'boards/b1/cards/assigned'), {
      boardId: 'b1', listId: 'l1', title: 'Được giao', description: '', position: 1024,
      isCompleted: false, assigneeIds: ['recipient'], labelIds: [], dueAt: null, archivedAt: null,
      commentCount: 0, checklistTotal: 0, checklistDone: 0, createdBy: 'owner',
      createdAt: new Date(), updatedAt: new Date(),
    });
  });
  const recipientDb = userDb('recipient', 'recipient@example.com');
  await assertSucceeds(getDocs(query(collectionGroup(recipientDb, 'cards'), where('assigneeIds', 'array-contains', 'recipient'))));
  await assertFails(getDocs(query(collectionGroup(recipientDb, 'cards'), where('assigneeIds', 'array-contains', 'somebody-else'))));
});

test('T-I: Owner tạo lời mời; người được mời chỉ đọc được lời mời gửi đúng email', async () => {
  await seedBoard();
  const ownerDb = userDb('owner', 'owner@example.com');
  await assertSucceeds(setDoc(doc(ownerDb, 'boards/b1/invitations/invitee@example.com'), {
    email: 'invitee@example.com', normalizedEmail: 'invitee@example.com', invitedBy: 'owner',
    inviterName: 'owner', boardName: 'Board thử', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  const inviteeDb = userDb('invitee', 'invitee@example.com');
  await assertSucceeds(getDocs(query(collectionGroup(inviteeDb, 'invitations'), where('normalizedEmail', '==', 'invitee@example.com'), where('status', '==', 'pending'))));
  await assertFails(getDocs(query(collectionGroup(userDb('another', 'another@example.com'), 'invitations'), where('normalizedEmail', '==', 'invitee@example.com'))));
});

test('T-I: Member không được tạo lời mời', async () => {
  await seedBoard();
  await assertFails(setDoc(doc(userDb('member'), 'boards/b1/invitations/new@example.com'), {
    email: 'new@example.com', normalizedEmail: 'new@example.com', invitedBy: 'member',
    inviterName: 'member', boardName: 'Board thử', status: 'pending',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
});

test('T-K: tác giả tạo và sửa bình luận của mình; người khác không được sửa', async () => {
  await seedBoard();
  const memberDb = userDb('member');
  await assertSucceeds(setDoc(doc(memberDb, 'boards/b1/cards/c1'), validCard({ createdBy: 'member' })));
  await assertSucceeds(setDoc(doc(memberDb, 'boards/b1/cards/c1/comments/cm1'), {
    authorId: 'member', authorName: 'member', body: 'Bình luận thử',
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(memberDb, 'boards/b1/cards/c1/comments/cm1'), {
    body: 'Bình luận đã sửa', updatedAt: serverTimestamp(),
  }));
  await env.withSecurityRulesDisabled(async c => {
    await setDoc(doc(c.firestore(), 'boards/b1/cards/c1/comments/cm2'), {
      authorId: 'owner', authorName: 'owner', body: 'Bình luận của Owner',
      createdAt: new Date(), updatedAt: new Date(),
    });
  });
  await assertFails(updateDoc(doc(memberDb, 'boards/b1/cards/c1/comments/cm2'), {
    body: 'Sửa trái phép', updatedAt: serverTimestamp(),
  }));
});
