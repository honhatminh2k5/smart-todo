# Công cụ kiểm tra Firebase — Smart Todo

Trước khi bắt đầu, đọc `docs/database-decisions.md` ở thư mục gốc repository để biết các lựa chọn đã chốt.

## 0. Yêu cầu

- Node.js **22 trở lên**.
- Java/JDK tương thích với Firestore Emulator.
- Kết nối Internet để cài npm package và tải Firebase Emulator lần đầu.
- Đặt thư mục `firebase/` nằm tại gốc repository cùng `firebase.json`, `firestore.rules` và `firestore.indexes.json`.

## 1. Cài dependency

Chạy từ thư mục gốc repository:

```bash
npm --prefix firebase install
```

## 2. Kiểm tra dữ liệu mẫu (không cần Firebase/network)

```bash
node firebase/seed/validate-seed.mjs
```

Kết quả mong đợi: thông báo `Dữ liệu mẫu đúng...` và 57 documents gồm 4 users, 3 boards, 16 cards. Validator kiểm tra cấu trúc trường và các quan hệ I1–I10 trên fixture, chứ không kiểm tra dữ liệu production hiện có.

## 3. Chạy smoke tests Security Rules trên Emulator

Tại gốc repository:

```bash
npx firebase-tools emulators:exec --only firestore --project demo-smart-todo "npm --prefix firebase run test:rules"
```

Bộ script hiện có **13 smoke tests** tập trung vào quyền đọc hồ sơ, tạo board, phân quyền Owner/Member, list/card, lời mời và bình luận. Nó chưa bao phủ toàn bộ ma trận 71 tình huống được liệt kê trong `docs/firestore-security.md`; hãy bổ sung và chạy các ca còn lại trước khi dùng Rules trong production.

## 4. Nạp dữ liệu mẫu vào Emulator

Mở Emulator trong cửa sổ 1:

```bash
npx firebase-tools emulators:start --project demo-smart-todo
```

Ở cửa sổ 2, từ gốc repository, đặt biến môi trường trỏ tới Emulator rồi nạp fixture. PowerShell trên Windows:

```powershell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
npm --prefix firebase run seed
```

CMD trên Windows:

```bat
set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 && npm --prefix firebase run seed
```

macOS/Linux:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm --prefix firebase run seed
```

Mở `http://127.0.0.1:4000` để xem dữ liệu.

**An toàn:** `seed.mjs` tự từ chối chạy nếu `FIRESTORE_EMULATOR_HOST` không được thiết lập. Nó chỉ được thiết kế để nạp dữ liệu giả vào Emulator, không dùng với Firebase thật.

## 5. Triển khai Rules và index lên Firebase thật

Chỉ tiếp tục sau khi nhóm review schema, toàn bộ kiểm thử đạt trên Emulator, đã sao lưu Rules hiện tại và có quyền Editor/Owner vào Firebase project. Các lệnh bên dưới thay thế nội dung Rules/index được cấu hình ở project đích.

```bash
npx firebase-tools login
npx firebase-tools use <ID-cua-project-Firebase>
npx firebase-tools deploy --only firestore:rules,firestore:indexes
```

Theo dõi composite index trong Firebase Console → Firestore → Indexes tới khi trạng thái `Enabled`. Không đưa `firebase_config.json`, service-account key hoặc bí mật vào Git.
