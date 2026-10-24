import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const source = JSON.parse(await readFile(path.join(here, 'seed-data.json'), 'utf8'));
const docs = source.documents;
const byPath = new Map();
const issues = [];
const report = (condition, message) => { if (!condition) issues.push(message); };

for (const item of docs) {
  report(typeof item.path === 'string' && item.path.length > 0, 'Có bản ghi thiếu path.');
  report(item.data && typeof item.data === 'object' && !Array.isArray(item.data), `Dữ liệu không hợp lệ: ${item.path}`);
  report(!byPath.has(item.path), `Trùng document path: ${item.path}`);
  byPath.set(item.path, item.data);
}
const values = [...byPath.entries()];
const getChildren = (prefix) => values.filter(([p]) => p.startsWith(prefix + '/') && p.slice(prefix.length + 1).split('/').length === 1);
const starts = (prefix) => values.filter(([p]) => p.startsWith(prefix + '/'));
const isText = (v, min, max) => typeof v === 'string' && v.trim().length >= min && v.length <= max;
const isTimestamp = (v) => v === null || (typeof v === 'string' && !Number.isNaN(Date.parse(v)));

// Kiểm tra trường bắt buộc theo từ điển dữ liệu.
const required = [
  [/^users\/[^/]+$/, ['displayName','email','createdAt','updatedAt']],
  [/^boards\/[^/]+$/, ['name','description','ownerId','memberIds','archivedAt','createdAt','updatedAt']],
  [/^boards\/[^/]+\/members\/[^/]+$/, ['role','displayName','email','joinedAt']],
  [/^boards\/[^/]+\/invitations\/[^/]+$/, ['email','normalizedEmail','invitedBy','inviterName','boardName','status','createdAt','updatedAt']],
  [/^boards\/[^/]+\/labels\/[^/]+$/, ['name','color','createdAt']],
  [/^boards\/[^/]+\/lists\/[^/]+$/, ['name','position','archivedAt','createdAt','updatedAt']],
  [/^boards\/[^/]+\/cards\/[^/]+$/, ['boardId','listId','title','description','position','isCompleted','assigneeIds','labelIds','dueAt','archivedAt','commentCount','checklistTotal','checklistDone','createdBy','createdAt','updatedAt']],
  [/^boards\/[^/]+\/cards\/[^/]+\/checklist\/[^/]+$/, ['title','isCompleted','position','createdAt','updatedAt']],
  [/^boards\/[^/]+\/cards\/[^/]+\/comments\/[^/]+$/, ['authorId','authorName','body','createdAt','updatedAt']],
];
for (const [docPath, data] of values) {
  const rule = required.find(([re]) => re.test(docPath));
  report(Boolean(rule), `Đường dẫn document không theo schema: ${docPath}`);
  if (rule) {
    const keys = rule[1];
    report(keys.every(k => Object.hasOwn(data, k)), `Thiếu trường bắt buộc ở ${docPath}`);
    report(Object.keys(data).length === keys.length && Object.keys(data).every(k => keys.includes(k)), `Có trường lạ hoặc thiếu trường ở ${docPath}`);
  }
  for (const [k,v] of Object.entries(data)) {
    if (['createdAt','updatedAt','joinedAt','dueAt','archivedAt'].includes(k)) report(isTimestamp(v), `${docPath}.${k} phải là ISO timestamp hoặc null`);
  }
}

const boards = values.filter(([p]) => /^boards\/[^/]+$/.test(p));
for (const [boardPath, b] of boards) {
  const [, boardId] = boardPath.split('/');
  report(isText(b.name, 1, 100), `${boardPath}: tên board phải 1–100 ký tự`);
  report(isText(b.description, 0, 500), `${boardPath}: mô tả board tối đa 500 ký tự`);
  report(Array.isArray(b.memberIds) && b.memberIds.includes(b.ownerId), `${boardPath}: I1 ownerId phải có trong memberIds`);
  const memberDocs = getChildren(`${boardPath}/members`);
  const memberIds = memberDocs.map(([p]) => p.split('/').at(-1));
  report(memberIds.length === (b.memberIds || []).length && memberIds.every(id => b.memberIds.includes(id)) && b.memberIds.every(id => memberIds.includes(id)), `${boardPath}: I2 memberIds phải khớp các document members`);
  for (const [mp, m] of memberDocs) {
    const uid = mp.split('/').at(-1);
    report(m.role === (uid === b.ownerId ? 'owner' : 'member'), `${mp}: role không khớp Owner/Member`);
  }
  const lists = getChildren(`${boardPath}/lists`);
  const labels = getChildren(`${boardPath}/labels`);
  const listIds = new Set(lists.map(([p]) => p.split('/').at(-1)));
  const labelIds = new Set(labels.map(([p]) => p.split('/').at(-1)));
  const listPositions = new Set();
  for (const [lp, l] of lists) {
    report(isText(l.name, 1, 100), `${lp}: tên list phải 1–100 ký tự`);
    const posKey = String(l.position);
    report(!listPositions.has(posKey), `${boardPath}: I9 trùng position ở list ${posKey}`);
    listPositions.add(posKey);
  }
  const boardCards = getChildren(`${boardPath}/cards`);
  const cardsByListPos = new Set();
  for (const [cp, c] of boardCards) {
    const cardId = cp.split('/').at(-1);
    report(c.boardId === boardId, `${cp}: I4 boardId không khớp board cha`);
    report(listIds.has(c.listId), `${cp}: I4 listId không trỏ tới list trong cùng board`);
    report(isText(c.title, 1, 200), `${cp}: tiêu đề card phải 1–200 ký tự`);
    report(isText(c.description, 0, 5000), `${cp}: mô tả card tối đa 5000 ký tự`);
    report(Array.isArray(c.assigneeIds) && c.assigneeIds.every(id => b.memberIds.includes(id)), `${cp}: I3 assigneeIds chứa người ngoài board`);
    report(Array.isArray(c.labelIds) && c.labelIds.every(id => labelIds.has(id)), `${cp}: I5 labelIds có nhãn không tồn tại trong board`);
    report(isTimestamp(c.dueAt) && isTimestamp(c.archivedAt), `${cp}: dueAt/archivedAt không hợp lệ`);
    report(Number.isInteger(c.commentCount) && c.commentCount >= 0, `${cp}: commentCount không hợp lệ`);
    report(Number.isInteger(c.checklistTotal) && c.checklistTotal >= 0, `${cp}: checklistTotal không hợp lệ`);
    report(Number.isInteger(c.checklistDone) && c.checklistDone >= 0 && c.checklistDone <= c.checklistTotal, `${cp}: checklistDone không hợp lệ`);
    const posKey = `${c.listId}:${c.position}`;
    report(!cardsByListPos.has(posKey), `${boardPath}: I9 trùng position card ${posKey}`);
    cardsByListPos.add(posKey);
    const childPrefix = `${cp}/`;
    const checklist = values.filter(([p]) => p.startsWith(`${childPrefix}checklist/`) && p.split('/').length === 6);
    const comments = values.filter(([p]) => p.startsWith(`${childPrefix}comments/`) && p.split('/').length === 6);
    report(c.checklistTotal === checklist.length, `${cp}: I6 checklistTotal không khớp số mục con`);
    report(c.checklistDone === checklist.filter(([,item]) => item.isCompleted === true).length, `${cp}: I6 checklistDone không khớp mục hoàn thành`);
    report(c.commentCount === comments.length, `${cp}: I6 commentCount không khớp số bình luận`);
    if (lists.find(([p]) => p === `${boardPath}/lists/${c.listId}`)?.[1].archivedAt) {
      report(c.archivedAt !== null, `${cp}: I7 card thuộc list đã lưu trữ cũng phải được lưu trữ`);
    }
  }
  for (const [ip, inv] of getChildren(`${boardPath}/invitations`)) {
    const invitationId = ip.split('/').at(-1);
    report(inv.normalizedEmail === invitationId && inv.email.toLowerCase() === invitationId, `${ip}: I8 ID phải bằng normalizedEmail`);
    report(['pending','accepted','declined'].includes(inv.status), `${ip}: status không hợp lệ`);
    report(!((b.memberIds || []).some(uid => byPath.get(`users/${uid}`)?.email?.toLowerCase() === invitationId) && inv.status === 'pending'), `${ip}: I10 thành viên không được có lời mời pending cùng board`);
  }
}

const count = (re) => values.filter(([p]) => re.test(p)).length;
report(count(/^users\/[^/]+$/) === 4, 'Fixture cần đúng 4 hồ sơ user mẫu');
report(count(/^boards\/[^/]+$/) === 3, 'Fixture cần đúng 3 board mẫu');
report(count(/^boards\/[^/]+\/cards\/[^/]+$/) === 16, 'Fixture cần đúng 16 card mẫu');

if (issues.length) {
  console.error(`❌ Kiểm tra thất bại: ${issues.length} lỗi`);
  for (const issue of issues) console.error(`- ${issue}`);
  process.exitCode = 1;
} else {
  console.log('✅ Dữ liệu mẫu đúng cấu trúc trường và các luật toàn vẹn I1–I10 (các kiểm tra tương ứng với I1–I10 được chạy trên fixture).');
  console.log(`✅ ${docs.length} documents hợp lệ: ${count(/^users\/[^/]+$/)} users, ${count(/^boards\/[^/]+$/)} boards, ${count(/^boards\/[^/]+\/cards\/[^/]+$/)} cards.`);
}
