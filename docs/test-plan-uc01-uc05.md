# Bộ kiểm thử 5 Use Case đầu tiên – Smart Todo

## 1. Phạm vi đã đối chiếu

Đối chiếu file `Đặc tả use case` với mã nguồn trên nhánh `main` của repository:

`https://github.com/honhatminh2k5/smart-todo`

Tài liệu đặc tả có 8 use case, từ UC01 đến UC08. Trong repository hiện có mã triển khai cho UC01, UC02, UC03, UC04, UC05 và UC08. UC06 mới có một số thành phần giao diện; nút cộng tác viên trong `board_detail_screen.dart` hiện chưa có xử lý (`onPressed: () {}`). UC07 có trường `dueAt` và logic tính trạng thái hạn chót trong module card, nhưng chưa thấy luồng quản lý hạn chót hoàn chỉnh theo đặc tả.

Tài liệu này lập bộ test cho **5 use case UC01–UC05**, theo đúng thứ tự trong tài liệu đặc tả.

## 2. Bảng đối chiếu và vị trí file test

| Use case | Chức năng trong đặc tả | File test trong repository | Nội dung được kiểm tra |
|---|---|---|---|
| UC01 | Đăng ký | `test/features/auth/auth_screens_test.dart` (file mới); `firebase/tests/auth.uc01-02.test.mjs` (file mới) | Validation biểu mẫu; tạo tài khoản Auth Emulator; tạo hồ sơ `users/{uid}`; từ chối email trùng và email sai định dạng. |
| UC02 | Đăng nhập | `test/features/auth/auth_screens_test.dart`; `firebase/tests/auth.uc01-02.test.mjs` | Validation biểu mẫu; đăng nhập đúng; từ chối mật khẩu sai; gửi yêu cầu đặt lại mật khẩu qua Auth Emulator. |
| UC03 | Quản lý board | `firebase/tests/firestore.uc03.rules.test.mjs` | Owner sửa tên/mô tả, lưu trữ/khôi phục; Member không được sửa/lưu trữ/khôi phục; không được chiếm quyền Owner. `firestore.rules.test.mjs` còn kiểm tra tạo board theo batch và quyền đọc. |
| UC04 | Quản lý List | `test/features/lists/data/list_repository_test.dart`; `test/features/lists/presentation/providers/list_providers_test.dart`; `test/features/lists/presentation/widgets/board_lists_section_test.dart`; `test/features/lists/presentation/widgets/archived_lists_sheet_test.dart` | Tạo, đổi tên, lưu trữ, khôi phục, sắp xếp; hiển thị danh sách và trạng thái trống; thao tác giao diện; quyền Firestore cơ bản được kiểm tra ở `firestore.rules.test.mjs` (nhóm T-L). |
| UC05 | Quản lý card | `test/features/cards/domain/card_rules_test.dart`; `test/features/cards/presentation/providers/card_providers_test.dart`; `test/features/cards/presentation/widgets/card_management_test.dart`; `firebase/tests/firestore.uc05.rules.test.mjs` | Kiểm tra tiêu đề 1–200 ký tự, tạo/sửa/hoàn thành/di chuyển/lưu trữ/xóa card, xử lý lỗi mạng, quyền và dữ liệu Firestore. |

Lưu ý: các file UC03–UC05 kể trên **đã tồn tại trên GitHub** tại thời điểm rà soát; không cần tạo bản sao với tên khác. Gói bổ sung tạo hai file test mới (`test/features/auth/auth_screens_test.dart`, `firebase/tests/auth.uc01-02.test.mjs`) và cập nhật script `test:auth` trong `firebase/package.json`.

## 3. Cách thêm file mới

Giải nén gói test vào thư mục gốc dự án `D:\smart todo`. Giữ nguyên cấu trúc thư mục. Sau khi giải nén, file mới phải nằm tại:

`D:\smart todo\test\features\auth\auth_screens_test.dart`

Tài liệu hướng dẫn này nằm tại:

`D:\smart todo\docs\test-plan-uc01-uc05.md`

## 4. Cách chạy kiểm thử

Mở PowerShell tại thư mục dự án:

```powershell
cd "D:\smart todo"
flutter pub get
```

### 4.1. Chạy test giao diện đăng ký/đăng nhập (UC01, UC02)

```powershell
flutter test test/features/auth/auth_screens_test.dart
```

Kết quả mong đợi: 6 test thành công. Các test này kiểm tra validation giao diện; chúng không tạo tài khoản Firebase thật.

### 4.2. Chạy test tích hợp Firebase Authentication (UC01, UC02)

Lệnh sau tự khởi động Auth Emulator và Firestore Emulator, chạy 6 ca kiểm thử, rồi tự tắt emulator:

```powershell
npx firebase-tools emulators:exec --only auth,firestore --project demo-smart-todo "npm --prefix firebase run test:auth"
```

### 4.3. Chạy test Flutter cho List và Card (UC04, UC05)

```powershell
flutter test test/features/lists
flutter test test/features/cards
```

Hoặc chạy toàn bộ test Flutter hiện có:

```powershell
flutter test
```

### 4.4. Chạy test Firestore Rules cho Board và dữ liệu (UC03–UC05)

Đảm bảo Node.js và Firebase CLI đã cài. Chạy tại thư mục dự án:

```powershell
npx firebase-tools emulators:exec --only firestore --project demo-smart-todo "npm --prefix firebase run test:rules"
```

Script `test:rules` hiện chạy lần lượt:

- `firebase/tests/firestore.rules.test.mjs`
- `firebase/tests/firestore.uc03.rules.test.mjs`
- `firebase/tests/firestore.uc05.rules.test.mjs`

Kết quả trước đây trên môi trường dự án đã ghi nhận 18/18 test Rules thành công; sau khi đồng bộ code hoặc thay đổi test, cần chạy lại trên máy của nhóm để xác nhận trạng thái hiện tại.

## 5. Giới hạn kiểm thử cần ghi trong báo cáo

1. Test UC01–UC02 gồm hai lớp: widget test kiểm tra validation biểu mẫu Flutter; Auth Emulator test kiểm tra tạo tài khoản, hồ sơ Firestore, đăng nhập, sai mật khẩu và đặt lại mật khẩu. Emulator test gọi Firebase JS SDK nên kiểm tra tích hợp Auth/Firestore, không trực tiếp gọi lớp Dart `AuthRepository`.
2. Test UC03 tập trung vào quyền Firestore và các thao tác dữ liệu; chưa có widget test độc lập cho toàn bộ màn hình Board.
3. UC04–UC05 đã có unit/widget test dùng repository giả và Rules test. Test dùng repository giả không thay thế hoàn toàn kiểm thử tích hợp với Firebase thật.
4. Không ghi kết quả “Pass” cho một lần chạy mới nếu chưa thực sự chạy lệnh tương ứng trên máy.

## 6. Danh sách test chính để đưa vào báo cáo

| Mã test | Use case | Dữ liệu/Thao tác | Kết quả mong đợi |
|---|---|---|---|
| AUTH-01 | UC01 | Bỏ trống họ tên | Hiện lỗi yêu cầu nhập họ tên; không gọi đăng ký. |
| AUTH-02 | UC01 | Email không đúng định dạng | Hiện lỗi email; không gọi đăng ký. |
| AUTH-03 | UC01 | Mật khẩu có 7 ký tự | Hiện lỗi mật khẩu tối thiểu 8 ký tự. |
| AUTH-04 | UC01 | Mật khẩu xác nhận khác mật khẩu | Hiện lỗi không khớp; không gọi đăng ký. |
| AUTH-05 | UC02 | Email hoặc mật khẩu để trống | Hiện lỗi tại trường tương ứng; không gọi đăng nhập. |
| AUTH-06 | UC02 | Email sai định dạng | Hiện lỗi định dạng email; không gọi đăng nhập. |
| BOARD-01 | UC03 | Owner sửa tên/mô tả | Firestore cho phép cập nhật. |
| BOARD-02 | UC03 | Owner lưu trữ rồi khôi phục | `archivedAt` được đặt thời điểm rồi trở về `null`. |
| BOARD-03 | UC03 | Member sửa/lưu trữ/khôi phục | Firestore từ chối. |
| LIST-01 | UC04 | Tạo list hợp lệ | List mới xuất hiện cuối danh sách. |
| LIST-02 | UC04 | Tên list rỗng | Không tạo; trạng thái lỗi được hiển thị. |
| LIST-03 | UC04 | Đổi tên/lưu trữ/khôi phục list | Danh sách hoạt động và lưu trữ được cập nhật đúng. |
| LIST-04 | UC04 | Kéo thả sắp xếp list | Thứ tự mới được lưu và hiển thị đúng. |
| CARD-01 | UC05 | Tạo card có tiêu đề hợp lệ | Card được thêm vào cuối list. |
| CARD-02 | UC05 | Tiêu đề rỗng hoặc trên 200 ký tự | Bị từ chối. |
| CARD-03 | UC05 | Đổi tiêu đề/đánh dấu hoàn thành | Nội dung và trạng thái được cập nhật. |
| CARD-04 | UC05 | Di chuyển card giữa các list | Card nằm trong list đích đúng vị trí. |
| CARD-05 | UC05 | Lưu trữ/xóa card | Lưu trữ thì vẫn còn dữ liệu; xóa thì card và dữ liệu con bị xóa theo batch. |
