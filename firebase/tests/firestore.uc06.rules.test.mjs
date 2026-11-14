// Kiểm thử Security Rules cho UC06 – Cộng tác nhóm.
// Mỗi ca ghi đúng dạng dữ liệu mà app (FirestoreCollaborationRepository,
// FirestoreCardRepository.setAssignee) gửi lên, để chắc chắn Rules chấp
// nhận/từ chối đúng.
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
  arrayRemove,
  arrayUnion,
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  increment,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const rules = await readFile(path.join(root, 'firestore.rules'), 'utf8');
const emulator = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
const BOARD = 'uc06-board';
const BOARD_NAME = 'Board UC06';
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

function userDb(uid, email = `${uid}@example.com`) {
  return env.authenticatedContext(uid, { email }).firestore();
}

const boardRef = db => doc(db, `boards/${BOARD}`);
const memberRef = (db, uid) => doc(db, `boards/${BOARD}/members/${uid}`);
const invitationRef = (db, email) => doc(db, `boards/${BOARD}/invitations/${email}`);
const cardRef = (db, id = 'c0') => doc(db, `boards/${BOARD}/cards/${id}`);
const commentRef = (db, cardId, id) => doc(db, `boards/${BOARD}/cards/${cardId}/comments/${id}`);

// Board có Owner + Member; tùy chọn: lời mời, card giao cho member, bình luận.
async function seedBoard({ invitations = [], assignedCards = 0, extraCards = [], comments = [] } = {}) {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(boardRef(db), {
      name: BOARD_NAME, description: '', ownerId: 'owner',
      memberIds: ['owner', 'member'], archivedAt: null,
      createdAt: created, updatedAt: created,
    });
    for (const uid of ['owner', 'member']) {
      await setDoc(memberRef(db, uid), {
        role: uid === 'owner' ? 'owner' : 'member',
        displayName: uid, email: `${uid}@example.com`, joinedAt: created,
      });
    }
    for (const invitation of invitations) {
      await setDoc(invitationRef(db, invitation.normalizedEmail), storedInvitation(invitation));
    }
    const batchSize = 400;
    for (let start = 0; start < assignedCards; start += batchSize) {
      const batch = writeBatch(db);
      for (let i = start; i < Math.min(assignedCards, start + batchSize); i++) {
        batch.set(cardRef(db, `assigned${i}`), storedCard({
          position: (i + 1) * 1024,
          assigneeIds: ['member', 'owner'],
          // Card đã lưu trữ cũng phải được gỡ người được giao (luật I3).
          archivedAt: i % 5 === 4 ? created : null,
        }));
      }
      await batch.commit();
    }
    for (const card of extraCards) {
      await setDoc(cardRef(db, card.id), storedCard(card));
    }
    for (const comment of comments) {
      await setDoc(commentRef(db, comment.cardId, comment.id), {
        authorId: comment.authorId, authorName: comment.authorId,
        body: comment.body ?? 'Bình luận mẫu', createdAt: created, updatedAt: created,
      });
    }
  });
}

function storedCard(overrides = {}) {
  const { id, ...rest } = overrides;
  return {
    boardId: BOARD, listId: 'todo', title: 'Card mẫu', description: '',
    position: 1024, isCompleted: false, assigneeIds: [], labelIds: [],
    dueAt: null, archivedAt: null, commentCount: 0, checklistTotal: 0,
    checklistDone: 0, createdBy: 'owner', createdAt: created, updatedAt: created,
    ...rest,
  };
}

function storedInvitation({ normalizedEmail, status = 'pending' }) {
  return {
    email: normalizedEmail, normalizedEmail, invitedBy: 'owner',
    inviterName: 'owner', boardName: BOARD_NAME, status,
    createdAt: created, updatedAt: created,
  };
}

// Đúng 8 trường mà FirestoreCollaborationRepository.inviteMember ghi (W26).
function newInvitation(email) {
  return {
    email,
    normalizedEmail: email.trim().toLowerCase(),
    invitedBy: 'owner',
    inviterName: 'owner',
    boardName: BOARD_NAME,
    status: 'pending',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

// --- W28: acceptInvitation (transaction 3 thao tác ghi) ----------------------
function acceptInvitation(db, uid, email) {
  return runTransaction(db, async tx => {
    const invitation = await tx.get(invitationRef(db, email));
    if (invitation.data()?.status !== 'pending') throw new Error('Lời mời không còn hiệu lực');
    tx.update(invitationRef(db, email), { status: 'accepted', updatedAt: serverTimestamp() });
    tx.set(memberRef(db, uid), {
      role: 'member', displayName: uid, email, joinedAt: serverTimestamp(),
    });
    tx.update(boardRef(db), { memberIds: arrayUnion(uid) });
  });
}

// --- W29: declineInvitation ----------------------------------------------------
function declineInvitation(db, email) {
  return runTransaction(db, async tx => {
    const invitation = await tx.get(invitationRef(db, email));
    if (invitation.data()?.status !== 'pending') throw new Error('Lời mời không còn hiệu lực');
    tx.update(invitationRef(db, email), { status: 'declined', updatedAt: serverTimestamp() });
  });
}

// --- W30/W31: _detachMember (card trước, tư cách thành viên ở batch cuối) -----
async function detachMember(db, uid, { chunk = 100 } = {}) {
  const assigned = await getDocs(query(
    collection(db, `boards/${BOARD}/cards`),
    where('assigneeIds', 'array-contains', uid),
  ));
  const cards = assigned.docs.map(d => d.ref);
  const unassign = { assigneeIds: arrayRemove(uid), updatedAt: serverTimestamp() };
  let start = 0;
  while (cards.length - start > chunk) {
    const batch = writeBatch(db);
    cards.slice(start, start + chunk).forEach(ref => batch.update(ref, unassign));
    await batch.commit();
    start += chunk;
  }
  const batch = writeBatch(db);
  cards.slice(start).forEach(ref => batch.update(ref, unassign));
  batch.delete(memberRef(db, uid));
  batch.update(boardRef(db), { memberIds: arrayRemove(uid) });
  await batch.commit();
  return cards.length;
}

// --- W23 / W25 ----------------------------------------------------------------
function addComment(db, uid, cardId, id, body) {
  const batch = writeBatch(db);
  batch.set(commentRef(db, cardId, id), {
    authorId: uid, authorName: uid, body,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  });
  batch.update(cardRef(db, cardId), { commentCount: increment(1), updatedAt: serverTimestamp() });
  return batch.commit();
}

function deleteComment(db, cardId, id) {
  return runTransaction(db, async tx => {
    const comment = await tx.get(commentRef(db, cardId, id));
    if (!comment.exists()) throw new Error('Bình luận không còn tồn tại');
    const card = await tx.get(cardRef(db, cardId));
    const count = card.data()?.commentCount ?? 0;
    tx.delete(commentRef(db, cardId, id));
    if (card.exists()) {
      tx.update(cardRef(db, cardId), { commentCount: Math.max(0, count - 1), updatedAt: serverTimestamp() });
    }
  });
}

// =============================================================================
// Mời thành viên (bước 2–5, 2a, 4a)
// =============================================================================

test('UC06 b3–5: Owner tạo lời mời đủ 8 trường; Owner đọc được lời mời đang chờ, Member thì không', async () => {
  await seedBoard();
  const ownerDb = userDb('owner');
  await assertSucceeds(setDoc(invitationRef(ownerDb, 'ban@example.com'), newInvitation('Ban@Example.com')));

  const pending = query(collection(ownerDb, `boards/${BOARD}/invitations`), where('status', '==', 'pending'));
  const snapshot = await assertSucceeds(getDocs(pending));
  assert.equal(snapshot.size, 1);
  assert.equal(snapshot.docs[0].data().email, 'Ban@Example.com');

  // App đọc members để kiểm tra "đã là thành viên" (4a).
  await assertSucceeds(getDocs(collection(ownerDb, `boards/${BOARD}/members`)));
  await assertFails(getDocs(query(collection(userDb('member'), `boards/${BOARD}/invitations`), where('status', '==', 'pending'))));
});

test('UC06 4a: lời mời sai định dạng, sai tên board hoặc ID khác email chuẩn hóa bị từ chối', async () => {
  await seedBoard();
  const ownerDb = userDb('owner');
  await assertFails(setDoc(invitationRef(ownerDb, 'khong-hop-le'), newInvitation('khong-hop-le')));
  await assertFails(setDoc(invitationRef(ownerDb, 'ban@example.com'), { ...newInvitation('ban@example.com'), boardName: 'Tên khác' }));
  await assertFails(setDoc(invitationRef(ownerDb, 'khac@example.com'), newInvitation('ban@example.com')));
});

test('UC06 Q12: Owner mời lại người đã từ chối bằng cách ghi đè về pending', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com', status: 'declined' }] });
  const ownerDb = userDb('owner');
  await assertSucceeds(setDoc(invitationRef(ownerDb, 'ban@example.com'), newInvitation('ban@example.com')));
  const saved = await getDoc(invitationRef(ownerDb, 'ban@example.com'));
  assert.equal(saved.data().status, 'pending');
});

test('UC06 2a: Owner hủy lời mời; người nhận không còn thấy lời mời', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com' }] });
  const ownerDb = userDb('owner');
  await assertSucceeds(runTransaction(ownerDb, async tx => {
    const invitation = await tx.get(invitationRef(ownerDb, 'ban@example.com'));
    assert.equal(invitation.data().status, 'pending');
    tx.delete(invitationRef(ownerDb, 'ban@example.com'));
  }));
  const banDb = userDb('ban', 'ban@example.com');
  const mine = await getDocs(query(collectionGroup(banDb, 'invitations'),
    where('normalizedEmail', '==', 'ban@example.com'), where('status', '==', 'pending')));
  assert.equal(mine.size, 0);
});

test('UC06 2a: Member không hủy được lời mời', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com' }] });
  const memberDb = userDb('member');
  await assertFails(runTransaction(memberDb, async tx => {
    tx.delete(invitationRef(memberDb, 'ban@example.com'));
  }));
});

// =============================================================================
// Chấp nhận / từ chối (bước 6–10, 8a, 9a)
// =============================================================================

test('UC06 b6–10: người được mời thấy lời mời, chấp nhận và thấy board trong danh sách của mình', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com' }] });
  const banDb = userDb('ban', 'ban@example.com');

  const mine = await assertSucceeds(getDocs(query(collectionGroup(banDb, 'invitations'),
    where('normalizedEmail', '==', 'ban@example.com'), where('status', '==', 'pending'))));
  assert.equal(mine.size, 1);
  assert.equal(mine.docs[0].data().boardName, BOARD_NAME);
  assert.equal(mine.docs[0].ref.parent.parent.id, BOARD);

  // Chưa là thành viên thì chưa đọc được board.
  await assertFails(getDoc(boardRef(banDb)));
  await assertSucceeds(acceptInvitation(banDb, 'ban', 'ban@example.com'));

  const boards = await assertSucceeds(getDocs(query(collection(banDb, 'boards'), where('memberIds', 'array-contains', 'ban'))));
  assert.deepEqual(boards.docs.map(d => d.id), [BOARD]);
  const member = await getDoc(memberRef(banDb, 'ban'));
  assert.equal(member.data().role, 'member');
  const invitation = await getDoc(invitationRef(userDb('owner'), 'ban@example.com'));
  assert.equal(invitation.data().status, 'accepted');
});

test('UC06 9a: lời mời đã bị Owner hủy thì không chấp nhận được', async () => {
  await seedBoard();
  const banDb = userDb('ban', 'ban@example.com');
  await assertFails(acceptInvitation(banDb, 'ban', 'ban@example.com'));

  // Kể cả khi bỏ qua bước đọc: Rules vẫn chặn việc tự thêm mình vào board.
  const batch = writeBatch(banDb);
  batch.set(memberRef(banDb, 'ban'), { role: 'member', displayName: 'ban', email: 'ban@example.com', joinedAt: serverTimestamp() });
  batch.update(boardRef(banDb), { memberIds: arrayUnion('ban') });
  await assertFails(batch.commit());
});

test('UC06: người khác email không chấp nhận được lời mời không gửi cho mình', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com' }] });
  const otherDb = userDb('other', 'other@example.com');
  await assertFails(acceptInvitation(otherDb, 'other', 'ban@example.com'));
  await assertFails(acceptInvitation(otherDb, 'other', 'other@example.com'));
});

test('UC06 8a: từ chối đổi trạng thái lời mời, không thêm vào board; không trả lời lại được', async () => {
  await seedBoard({ invitations: [{ normalizedEmail: 'ban@example.com' }] });
  const banDb = userDb('ban', 'ban@example.com');
  await assertSucceeds(declineInvitation(banDb, 'ban@example.com'));
  const invitation = await getDoc(invitationRef(userDb('owner'), 'ban@example.com'));
  assert.equal(invitation.data().status, 'declined');
  const board = await getDoc(boardRef(userDb('owner')));
  assert.deepEqual(board.data().memberIds, ['owner', 'member']);

  // App tự chặn trước khi ghi...
  await assert.rejects(acceptInvitation(banDb, 'ban', 'ban@example.com'), /không còn hiệu lực/);
  // ...và Rules cũng chặn nếu bỏ qua bước kiểm tra của app.
  const batch = writeBatch(banDb);
  batch.update(invitationRef(banDb, 'ban@example.com'), { status: 'accepted', updatedAt: serverTimestamp() });
  batch.set(memberRef(banDb, 'ban'), { role: 'member', displayName: 'ban', email: 'ban@example.com', joinedAt: serverTimestamp() });
  batch.update(boardRef(banDb), { memberIds: arrayUnion('ban') });
  await assertFails(batch.commit());
});

// =============================================================================
// Xóa thành viên / rời board (2b–2d)
// =============================================================================

test('UC06 2b–2c: Owner xóa Member, gỡ khỏi mọi card được giao; Member mất quyền truy cập', async () => {
  await seedBoard({ assignedCards: 6, extraCards: [{ id: 'other', assigneeIds: ['owner'] }] });
  const ownerDb = userDb('owner');
  const count = await assertSucceeds(detachMember(ownerDb, 'member'));
  assert.equal(count, 6);

  const board = await getDoc(boardRef(ownerDb));
  assert.deepEqual(board.data().memberIds, ['owner']);
  assert.equal((await getDoc(memberRef(ownerDb, 'member'))).exists(), false);
  for (let i = 0; i < 6; i++) {
    const card = await getDoc(cardRef(ownerDb, `assigned${i}`));
    assert.deepEqual(card.data().assigneeIds, ['owner']);
  }
  await assertFails(getDoc(boardRef(userDb('member'))));
  await assertFails(getDocs(collection(userDb('member'), `boards/${BOARD}/cards`)));
});

test('UC06 T-L3: Owner xóa Member đang được giao 25 card trong một batch', async () => {
  await seedBoard({ assignedCards: 25 });
  await assertSucceeds(detachMember(userDb('owner'), 'member', { chunk: 500 }));
});

test('UC06 T-L3+: gỡ 100 card trong một batch (kích thước batch app dùng)', async () => {
  await seedBoard({ assignedCards: 100 });
  await assertSucceeds(detachMember(userDb('owner'), 'member', { chunk: 100 }));
});

test('UC06 2c: chia nhiều batch khi Member được giao hơn 100 card', async () => {
  await seedBoard({ assignedCards: 230 });
  const ownerDb = userDb('owner');
  assert.equal(await assertSucceeds(detachMember(ownerDb, 'member')), 230);
  const left = await getDocs(query(collection(ownerDb, `boards/${BOARD}/cards`), where('assigneeIds', 'array-contains', 'member')));
  assert.equal(left.size, 0);
});

test('UC06 2d: Member tự rời board; Owner không rời được; Member không xóa được người khác', async () => {
  await seedBoard({ assignedCards: 3 });
  await assertFails(detachMember(userDb('owner'), 'owner'));
  await assertFails(detachMember(userDb('member'), 'owner'));
  await assertSucceeds(detachMember(userDb('member'), 'member'));
  const board = await getDoc(boardRef(userDb('owner')));
  assert.deepEqual(board.data().memberIds, ['owner']);
});

// =============================================================================
// Giao việc (1a–1b)
// =============================================================================

test('UC06 1b: giao/bỏ giao card cho thành viên; không giao được cho người ngoài', async () => {
  await seedBoard({ extraCards: [{ id: 'c0' }] });
  const db = userDb('member');
  await assertSucceeds(updateDoc(cardRef(db), { assigneeIds: arrayUnion('owner'), updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(cardRef(db), { assigneeIds: arrayUnion('member'), updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(cardRef(db), { assigneeIds: arrayRemove('owner'), updatedAt: serverTimestamp() }));
  assert.deepEqual((await getDoc(cardRef(db))).data().assigneeIds, ['member']);
  await assertFails(updateDoc(cardRef(db), { assigneeIds: arrayUnion('outsider'), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(cardRef(userDb('outsider')), { assigneeIds: arrayUnion('member'), updatedAt: serverTimestamp() }));
});

// =============================================================================
// Bình luận (1c–1d)
// =============================================================================

test('UC06 1d: gửi bình luận 1–2000 ký tự cùng batch tăng bộ đếm', async () => {
  await seedBoard({ extraCards: [{ id: 'c0' }] });
  const db = userDb('member');
  await assertSucceeds(addComment(db, 'member', 'c0', 'cm1', 'Xin chào'));
  await assertSucceeds(addComment(db, 'member', 'c0', 'cm2', 'a'.repeat(2000)));
  await assertFails(addComment(db, 'member', 'c0', 'cm3', ''));
  await assertFails(addComment(db, 'member', 'c0', 'cm4', 'a'.repeat(2001)));
  assert.equal((await getDoc(cardRef(db))).data().commentCount, 2);
  await assertFails(addComment(userDb('outsider'), 'outsider', 'c0', 'cm5', 'Người ngoài'));
});

test('UC06 1d: bình luận vào card đã bị xóa thất bại cả batch', async () => {
  await seedBoard();
  await assertFails(addComment(userDb('member'), 'member', 'gone', 'cm1', 'Xin chào'));
});

test('UC06 1d: tác giả sửa bình luận của mình; tác giả hoặc Owner xóa và giảm bộ đếm', async () => {
  await seedBoard({
    extraCards: [{ id: 'c0', commentCount: 3 }],
    comments: [
      { cardId: 'c0', id: 'byMember', authorId: 'member' },
      { cardId: 'c0', id: 'byOwner', authorId: 'owner' },
      { cardId: 'c0', id: 'byMember2', authorId: 'member' },
    ],
  });
  const memberDb = userDb('member');
  const ownerDb = userDb('owner');

  await assertSucceeds(updateDoc(commentRef(memberDb, 'c0', 'byMember'), { body: 'Đã sửa', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(commentRef(ownerDb, 'c0', 'byMember'), { body: 'Owner sửa', updatedAt: serverTimestamp() }));

  await assertFails(deleteComment(memberDb, 'c0', 'byOwner'));
  await assertSucceeds(deleteComment(memberDb, 'c0', 'byMember'));
  await assertSucceeds(deleteComment(ownerDb, 'c0', 'byMember2'));
  assert.equal((await getDoc(cardRef(ownerDb))).data().commentCount, 1);
  await assert.rejects(deleteComment(ownerDb, 'c0', 'byMember2'), /không còn tồn tại/);
});
