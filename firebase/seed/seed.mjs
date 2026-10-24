import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('Từ chối nạp dữ liệu: FIRESTORE_EMULATOR_HOST chưa được đặt. Script này chỉ được phép ghi vào Firestore Emulator.');
  process.exit(1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = JSON.parse(await readFile(path.join(here, 'seed-data.json'), 'utf8'));
const projectId = process.env.GCLOUD_PROJECT || 'demo-smart-todo';
initializeApp({ projectId });
const db = getFirestore();

function convert(value, key = '') {
  if (Array.isArray(value)) return value.map(v => convert(v));
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, convert(v, k)]));
  }
  if (typeof value === 'string' && ['createdAt','updatedAt','joinedAt','dueAt','archivedAt'].includes(key)) {
    return Timestamp.fromDate(new Date(value));
  }
  return value;
}

for (let i = 0; i < fixture.documents.length; i += 400) {
  const batch = db.batch();
  for (const item of fixture.documents.slice(i, i + 400)) {
    batch.set(db.doc(item.path), convert(item.data));
  }
  await batch.commit();
}
console.log(`Đã nạp ${fixture.documents.length} documents vào Emulator project ${projectId} (${process.env.FIRESTORE_EMULATOR_HOST}).`);
console.log('Không sử dụng script này với Firebase production. Dữ liệu mẫu có thể được xóa hoặc nạp lại trong Emulator.');
process.exit(0);
