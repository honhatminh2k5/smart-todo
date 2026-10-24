# Ma trận use case ↔ dữ liệu – Smart Todo

> Tài liệu này trả lời: **mỗi use case đọc và ghi những dữ liệu nào, ai được làm?** Nó là bằng chứng rằng cấu trúc dữ liệu trong [`firestore-schema.md`](firestore-schema.md) bao phủ đủ đặc tả UC01–UC08, và là chỗ để kiểm tra khi đặc tả thay đổi.
> Mã `W..` là công thức ghi trong [`firestore-access-patterns.md`](firestore-access-patterns.md#3-công-thức-ghi-dữ-liệu); mã `A..G` là truy vấn ở [mục 1](firestore-access-patterns.md#1-màn-hình--truy-vấn) của tài liệu đó.

---

## 1. Bảng CRUD: loại dữ liệu × use case

`C` = tạo · `R` = đọc · `U` = sửa · `D` = xóa. Ô trống = use case không đụng tới dữ liệu đó.

| Dữ liệu | UC01 Đăng ký | UC02 Đăng nhập | UC03 Board | UC04 List | UC05 Card | UC06 Cộng tác | UC07 Thời hạn | UC08 Tìm/lọc |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `users` | **C** | | | | | | | |
| `boards` | | | **C R U** | R | R | **U** (thêm/bớt `memberIds`) | R | R |
| `members` | | | **C** (Owner) | R | | **C R D** | | R |
| `invitations` | | | | | | **C R U D** | | |
| `labels` | | | | | R | | | R |
| `lists` | | | | **C R U** | R | | | R |
| `cards` | | | | R | **C R U D** | **U** (người được giao) | **R U** (hạn chót, hoàn thành) | R |
| `checklist` | | | | | R (tiến độ) | | | |
| `comments` | | | | | R (số lượng) | **C R U D** | | |

**Hai khoảng trống trong đặc tả** (xem [câu hỏi cần chốt](database-open-questions.md)):
- **Nhãn** (`labels`) chỉ được nhắc ở dạng *hiển thị* (UC05 bước 2, UC08), nhưng việc tạo/sửa/xóa nhãn thuộc "Chi tiết card", chức năng chưa có use case riêng.
- **Checklist** tương tự: chỉ có phần hiển thị tiến độ (UC05 bước 2); phần thêm/sửa/xóa mục thuộc "Chi tiết card".

Thiết kế đã dự phòng cả hai (có đủ dữ liệu, bộ đếm và Rules), nhưng giới hạn cụ thể (độ dài tên nhãn, bảng màu, số mục tối đa) đang là **giả định**.

---

## 2. Bảng chi tiết từng bước

### UC01: Đăng ký (Người dùng)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 4–5 | Kiểm tra dữ liệu, gọi Firebase Authentication | – | – | Chỉ Authentication; mật khẩu **không** vào Firestore |
| 7 | Tạo hồ sơ người dùng | – | `users/{uid}` | **W1**. Code hiện tại đã đúng |
| 6a–6b | Email đã tồn tại | – | – | Authentication báo lỗi |
| 6c | Mất mạng | – | – | Giữ nguyên dữ liệu nhập |

### UC02: Đăng nhập (Người dùng)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 5–7 | Xác thực, lưu phiên, chuyển tới Danh sách board | – | – | Chỉ Authentication. Sau đó chạy truy vấn **A** |
| – | Quên mật khẩu | – | – | Authentication gửi email đặt lại; không đụng Firestore |

### UC03: Quản lý board (Owner, Member)

| Bước | Hành động | Đọc | Ghi | Ai | Ghi chú |
|---|---|---|---|---|---|
| 2 | Hiện board chưa lưu trữ, mới nhất lên đầu | `boards` (**A**) | – | Thành viên | Lọc/sắp xếp trên máy |
| 2a | Chưa có board nào | `boards` (**A**) | – | – | Trạng thái trống ở giao diện |
| 6–7 | Kiểm tra tên 1–100 ký tự, tạo board, gán Owner | – | `boards/{id}` + `members/{uid}` | Người tạo | **W2**, một batch |
| 3a–3b | Sửa tên/mô tả, đồng bộ mọi thiết bị | – | `boards/{id}` | Owner | **W3**. Đồng bộ nhờ lắng nghe thời gian thực |
| 3c–3d | Lưu trữ board | – | `boards/{id}.archivedAt` | Owner | **W4** |
| 3e | Khôi phục board đã lưu trữ | `boards` (**A**) | `boards/{id}.archivedAt = null` | Owner | **W4** |
| 3f | Member cố sửa/lưu trữ | – | – | Member | **Bị Rules từ chối** (T-B10, T-B12) |
| 6a | Tên rỗng hoặc > 100 ký tự | – | – | – | App báo lỗi; Rules cũng chặn (T-B7, T-B8) |

### UC04: Quản lý List (Owner, Member)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 2 | Hiện các list theo đúng thứ tự | `lists` (**B**) | – | Sắp theo `position` |
| 5–8 | Thêm list, thứ tự đứng sau list cuối | `lists` | `lists/{id}` | **W5**; `position` = cuối + 1024 |
| 3a | Đổi tên list | – | `lists/{id}.name` | **W6** |
| 3b–3c | Lưu trữ list: list và card bên trong bị ẩn | `cards` của list | `lists/{id}.archivedAt` + `cards/*.archivedAt` | **W8**, cùng một thời điểm (D7) |
| 3d–3e | Kéo thả đổi vị trí | – | `lists/{id}.position` | **W7**; chỉ ghi **một** tờ |
| 5a | Tên rỗng hoặc > 100 ký tự | – | – | T-C3 |

### UC05: Quản lý card (Owner, Member)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 2 | Hiện card tóm tắt: tiêu đề, nhãn, hạn chót, tiến độ checklist, số bình luận, avatar người được giao | `cards`, `labels`, `members` (**B**) | – | Nhờ bộ đếm trong card nên **không** đọc `checklist`/`comments` (D4) |
| 5–8 | Thêm card ở cuối list, ghi người tạo và thời gian tạo | `cards` | `cards/{id}` | **W9** |
| 3a–3b | Sửa tiêu đề, tự động lưu, đồng bộ | – | `cards/{id}` | **W10** |
| 3c–3d | Đánh dấu / bỏ hoàn thành | – | `cards/{id}.isCompleted` | **W11** |
| 3e | Lưu trữ card | – | `cards/{id}.archivedAt` | **W13** |
| 3f | Xóa vĩnh viễn (xác nhận hai bước) | `checklist`, `comments` của card | Xóa `checklist/*`, `comments/*`, `cards/{id}` | **W14**, một batch |
| 3g | Card đang mở đã bị người khác xóa | `cards/{id}` (**C**) | – | Lắng nghe tờ card; thấy "không tồn tại" |
| 5a | Tiêu đề rỗng hoặc > 200 ký tự | – | – | T-C6, T-C7 |

### UC06: Cộng tác nhóm (Owner, Member, Người được mời)

| Bước | Hành động | Đọc | Ghi | Ai | Ghi chú |
|---|---|---|---|---|---|
| 1–2 | Màn Thành viên: thành viên kèm vai trò và lời mời đang chờ | `members`, `invitations` (**D**) | – | Owner | |
| 4 | Kiểm tra email hợp lệ, chưa là thành viên, chưa có lời mời chờ | `members`, `invitations/{email}` | – | Owner | **App phải tự kiểm tra** (Rules không làm được) |
| 5 | Tạo lời mời `pending` | – | `invitations/{emailChuanHoa}` | Owner | **W26**. ID = email chuẩn hóa chặn trùng |
| 6–7 | Người được mời xem lời mời: tên board, người mời | `invitations` (**E**) | – | Người được mời | Truy vấn xuyên board theo email |
| 8–10 | Chấp nhận: vào board với vai trò Member | – | `invitations.status`, `members/{uid}`, `boards.memberIds` | Người được mời | **W28**, một batch |
| 8a | Từ chối | – | `invitations.status = "declined"` | Người được mời | **W29** |
| 9a | Lời mời đã bị Owner hủy trước đó | – | – | – | Batch bị Rules từ chối (T-I11) ⇒ báo "không còn hiệu lực" |
| 2a | Hủy lời mời đang chờ | – | Xóa `invitations/{email}` | Owner | **W27** |
| 2b–2c | Xóa Member; gỡ khỏi board và khỏi mọi card | `cards` có người đó | `members/{uid}` (xóa), `boards.memberIds`, `cards.assigneeIds` | Owner | **W30**, một batch hoặc chia nhỏ (R1) |
| 2d | Member rời board (Owner không được rời) | `cards` có người đó | như 2b–2c | Member | **W31** |
| 1a–1b | Giao việc: chỉ chọn thành viên của board | `members` | `cards.assigneeIds` | Thành viên | **W16** |
| 1c–1d | Gửi bình luận (1–2000 ký tự), kèm tên và thời gian | `comments` (**C**) | `comments/{id}` + `cards.commentCount` | Thành viên | **W23** |
| 1d | Tác giả sửa bình luận của mình | – | `comments.body` | Tác giả | **W24** |
| 1d | Tác giả hoặc Owner xóa bình luận | – | Xóa `comments/{id}`, `cards.commentCount` | Tác giả / Owner | **W25** |

### UC07: Quản lý thời hạn (Owner, Member)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 3–5 | Đặt hạn chót (ngày giờ, nằm trong tương lai) | – | `cards.dueAt` | **W15** |
| 6 | Hiện nhãn hạn chót theo trạng thái: bình thường, sắp đến hạn 24 giờ, quá hạn, đã hoàn thành | – | – | **Tính ra, không lưu** (xem [mục 6](firestore-access-patterns.md#6-trạng-thái-hạn-chót-và-nhóm-công-việc-của-tôi)) |
| 7 | Đặt thông báo nhắc trước 24 giờ | – | – | **Thông báo cục bộ trên máy**, không lưu Firestore (D8) |
| 1a–1b | "Công việc của tôi": card được giao ở mọi board, theo nhóm Quá hạn / Hôm nay / Sắp tới / Không có hạn | `cards` xuyên board (**F**) | – | Cần `boardId` trong card (D5) và chỉ mục |
| 3a–3b | Sửa hạn chót, đặt lại nhắc | – | `cards.dueAt` | **W15** |
| 3c–3d | Xóa hạn chót, hủy nhắc | – | `cards.dueAt = null` | **W15** |
| 3e–3f | Đánh dấu hoàn thành thì hủy nhắc | – | `cards.isCompleted` | **W11** |
| 4a | Chọn thời điểm đã qua: cảnh báo, xác nhận vẫn lưu | – | `cards.dueAt` | App xử lý; **Rules không chặn** quá khứ |
| 7a | Chưa cấp quyền thông báo | – | – | Chỉ liên quan thiết bị |

### UC08: Tìm kiếm và lọc công việc (Owner, Member)

| Bước | Hành động | Đọc | Ghi | Ghi chú |
|---|---|---|---|---|
| 3–5 | Lọc card theo tiêu đề, không phân biệt hoa thường và dấu | Card đã tải ở **B** | – | **Trên máy**, [mục 7](firestore-access-patterns.md#7-tìm-kiếm-và-lọc-uc08) |
| 3a–3b | Lọc theo nhãn, người được giao, tình trạng hạn, hoàn thành | Card + `labels` + `members` đã tải | – | Khác loại: AND. Cùng loại: OR |
| 3c–3d | Xóa bộ lọc | – | – | |
| 5b | Không đồng bộ được: tìm tiếp trên dữ liệu đã tải | Bộ nhớ đệm | – | Khớp thiết kế lọc trên máy |

---

## 3. Kiểm tra độ bao phủ

| Câu hỏi | Kết quả |
|---|---|
| Mọi trường hiển thị trên thẻ card (UC05 bước 2) có chỗ lưu? | ✅ tiêu đề, nhãn (`labelIds`), hạn chót (`dueAt`), tiến độ checklist (`checklistTotal/Done`), số bình luận (`commentCount`), avatar người được giao (`assigneeIds` + `members.displayName`) |
| Mọi giới hạn độ dài trong đặc tả có trong Rules và từ điển? | ✅ tên board 1–100, tên list 1–100, tiêu đề card 1–200, bình luận 1–2000 |
| Mọi bước "đồng bộ thời gian thực" khả thi? | ✅ dùng `snapshots()` của Firestore |
| Mọi quyền Owner/Member trong đặc tả có trong Rules? | ✅ xem [ma trận phân quyền](firestore-security.md#2-ma-trận-phân-quyền) |
| Có use case nào cần dữ liệu **chưa có** chỗ lưu? | ❌ không. Hai chỗ chưa rõ là giới hạn của nhãn và checklist (xem mục 1) |
