// Integration tests for UC01 (Registration) and UC02 (Login).
// Requires BOTH Firebase Authentication and Firestore emulators.
import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  initializeAuth,
  inMemoryPersistence,
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  updateProfile,
  signInWithEmailAndPassword,
  signOut,
  sendPasswordResetEmail,
} from 'firebase/auth';
import {
  getFirestore,
  connectFirestoreEmulator,
  doc,
  getDoc,
  setDoc,
  serverTimestamp,
} from 'firebase/firestore';

const projectId = 'demo-smart-todo';
const authEmulator = (process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099').split(':');
const firestoreEmulator = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080').split(':');
let app;
let auth;
let db;
let accountNumber = 0;

before(() => {
  app = initializeApp(
    {
      apiKey: 'demo-api-key',
      authDomain: 'localhost',
      projectId,
      appId: '1:123456789:web:smart-todo-test',
    },
    `uc01-02-tests-${process.pid}`,
  );

  auth = initializeAuth(app, { persistence: inMemoryPersistence });
  connectAuthEmulator(
    auth,
    `http://${authEmulator[0]}:${Number(authEmulator[1] || 9099)}`,
    { disableWarnings: true },
  );

  db = getFirestore(app);
  connectFirestoreEmulator(
    db,
    firestoreEmulator[0],
    Number(firestoreEmulator[1] || 8080),
  );
});

after(async () => {
  if (auth) await signOut(auth).catch(() => {});
  if (app) await deleteApp(app);
});

function nextEmail(prefix) {
  accountNumber += 1;
  return `${prefix}-${process.pid}-${accountNumber}@example.com`;
}

async function createAccount(email, password = 'MatKhau123!') {
  return createUserWithEmailAndPassword(auth, email, password);
}

test('UC01: đăng ký tạo tài khoản và hồ sơ users/{uid} trên Firestore', async () => {
  const email = nextEmail('uc01');
  const displayName = 'Nguyen Van A';
  const credential = await createAccount(email);

  await updateProfile(credential.user, { displayName });
  await setDoc(doc(db, 'users', credential.user.uid), {
    displayName,
    email: credential.user.email,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });

  const profile = await getDoc(doc(db, 'users', credential.user.uid));
  assert.equal(credential.user.email, email);
  assert.equal(profile.exists(), true);
  assert.equal(profile.data().displayName, displayName);
  assert.equal(profile.data().email, email);
  assert.ok(profile.data().createdAt);
  assert.ok(profile.data().updatedAt);
});

test('UC01: không cho đăng ký lại email đã được sử dụng', async () => {
  const email = nextEmail('uc01-duplicate');
  await createAccount(email);
  await signOut(auth);

  await assert.rejects(
    () => createAccount(email),
    (error) => error.code === 'auth/email-already-in-use',
  );
});

test('UC01: Firebase từ chối email sai định dạng', async () => {
  await assert.rejects(
    () => createAccount('email-khong-hop-le'),
    (error) => error.code === 'auth/invalid-email',
  );
});

test('UC02: đăng nhập thành công bằng email và mật khẩu đúng', async () => {
  const email = nextEmail('uc02-login');
  const password = 'MatKhau123!';
  const created = await createAccount(email, password);
  const expectedUid = created.user.uid;
  await signOut(auth);

  const signedIn = await signInWithEmailAndPassword(auth, email, password);
  assert.equal(signedIn.user.uid, expectedUid);
  assert.equal(auth.currentUser?.email, email);
});

test('UC02: từ chối đăng nhập khi mật khẩu không đúng', async () => {
  const email = nextEmail('uc02-wrong-password');
  await createAccount(email, 'MatKhau123!');
  await signOut(auth);

  await assert.rejects(
    () => signInWithEmailAndPassword(auth, email, 'SaiMatKhau123!'),
    (error) => ['auth/invalid-credential', 'auth/wrong-password'].includes(error.code),
  );
});

test('UC02: gửi yêu cầu đặt lại mật khẩu cho email đã đăng ký', async () => {
  const email = nextEmail('uc02-reset');
  await createAccount(email);
  await signOut(auth);

  await assert.doesNotReject(() => sendPasswordResetEmail(auth, email));
});
