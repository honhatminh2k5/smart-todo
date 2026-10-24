# Phân quyền và Security Rules – Smart Todo

> File luật: [`firestore.rules`](../firestore.rules) · Bộ smoke test tự động: [`firebase/tests/firestore.rules.test.mjs`](../firebase/tests/firestore.rules.test.mjs)
> Cấu trúc dữ liệu: [`firestore-schema.md`](firestore-schema.md) · Truy vấn: [`firestore-access-patterns.md`](firestore-access-patterns.md)

---

## 1. Security Rules là gì?

Hãy coi Firestore là **kho hồ sơ**, còn Security Rules là **người bảo vệ đứng ở cửa kho**. Mỗi lần app muốn đọc hoặc ghi một tờ hồ sơ, bảo vệ kiểm tra: *ai đang hỏi? họ có quyền không? dữ liệu họ muốn ghi có đúng quy định không?*

Vì sao không chỉ ẩn nút trên giao diện? Vì app chạy trên điện thoại của người dùng, và người có kiến thức có thể gửi yêu cầu thẳng tới Firestore mà không đi qua giao diện. Security Rules chạy **trên máy chủ của Google**, nên không ai qua mặt được. Mọi quy tắc phân quyền trong đặc tả (ví dụ "Member không được sửa board", UC03 3f) đều phải có mặt ở đây.

---

## 2. Ma trận phân quyền

Bốn nhóm người dùng, mọi người đều đã đăng nhập (chưa đăng nhập thì không làm được gì ngoài đăng ký/đăng nhập qua Firebase Authentication):

- **Người ngoài:** không phải thành viên của board đang xét.
- **Người được mời:** có lời mời `pending` gửi tới đúng email của họ, chưa phải thành viên.
- **Member:** thành viên, không phải chủ board.
- **Owner:** chủ board.

| Dữ liệu / thao tác | Người ngoài | Người được mời | Member | Owner |
|---|:-:|:-:|:-:|:-:|
| Đọc / sửa hồ sơ **của chính mình** (`users/{uid}`) | ✅ | ✅ | ✅ | ✅ |
| Đọc hồ sơ người khác | ❌ | ❌ | ❌ | ❌ |
| Tạo board mới (mình là Owner) | ✅ | ✅ | ✅ | ✅ |
| Đọc board, danh sách thành viên, nhãn | ❌ | ❌ | ✅ | ✅ |
| Sửa tên/mô tả board, lưu trữ, khôi phục | ❌ | ❌ | ❌ | ✅ |
| Xóa board | ❌ | ❌ | ❌ | ❌ (chỉ lưu trữ) |
| Mời thành viên, hủy lời mời, đọc lời mời của board | ❌ | ❌ | ❌ | ✅ |
| Đọc lời mời **gửi cho mình**, chấp nhận hoặc từ chối | ❌ | ✅ | ✅ (nếu email trùng) | ✅ (nếu email trùng) |
| Xóa một Member khỏi board | ❌ | ❌ | ❌ | ✅ |
| Rời board | ❌ | ❌ | ✅ | ❌ (Owner không rời được) |
| Thêm / sửa / lưu trữ / kéo thả list | ❌ | ❌ | ✅ | ✅ |
| Xóa list | ❌ | ❌ | ❌ | ❌ (chỉ lưu trữ) |
| Đọc / thêm / sửa / lưu trữ / xóa card | ❌ | ❌ | ✅ | ✅ |
| Đọc card **được giao cho mình** (truy vấn xuyên board) | ❌ | ❌ | ✅ | ✅ |
| Thêm / sửa / xóa mục checklist | ❌ | ❌ | ✅ | ✅ |
| Thêm / sửa / xóa nhãn (*giả định, xem câu hỏi Q1*) | ❌ | ❌ | ✅ | ✅ |
| Gửi bình luận | ❌ | ❌ | ✅ | ✅ |
| Sửa bình luận | ❌ | ❌ | chỉ của mình | chỉ của mình |
| Xóa bình luận | ❌ | ❌ | chỉ của mình | của mình **hoặc của người khác** |

> Một người có thể vừa là Owner của board này, vừa là Member của board khác. Vai trò tính **theo từng board**.

---

## 3. Những điểm đáng chú ý trong cách Rules vận hành

### 3.1. Quyền được suy ra từ **một** tờ hồ sơ: tờ board
Mọi kiểm tra "có phải thành viên?" / "có phải Owner?" chỉ cần đọc `boards/{boardId}` (các trường `memberIds`, `ownerId`). Không cần duyệt collection `members`. Đây là quyết định D2 trong schema. Hệ quả: `memberIds` là **nguồn sự thật**, nên không bao giờ được để nó lệch với `members` (luật I2).

### 3.2. Board chỉ có đúng bốn kiểu cập nhật hợp lệ, không trộn lẫn
| Kiểu | Ai | Được đổi trường | Điều kiện kèm theo |
|---|---|---|---|
| Sửa thông tin | Owner | `name`, `description`, `archivedAt`, `updatedAt` | Tên 1–100, mô tả ≤ 500 |
| Xóa thành viên | Owner | `memberIds` | Chỉ **bớt** người, Owner luôn còn |
| Rời board | Member | `memberIds` | Chỉ bớt **chính mình** |
| Tham gia board | Người được mời | `memberIds` | Chỉ thêm **chính mình**, và phải có lời mời `pending` đúng email của mình |

Nhờ vậy không ai tự nâng quyền: đổi `ownerId` bị chặn với mọi người (T-B14); Owner không thể "thêm thẳng" người vào board mà bỏ qua lời mời (T-M6).

### 3.3. Luồng chấp nhận lời mời an toàn thế nào?
Người được mời **chưa là thành viên** nên chưa đọc được board. Khi bấm "Chấp nhận", app ghi 3 thứ trong **một batch** (W28): đổi trạng thái lời mời, tạo tờ `members/{uid}`, và thêm uid vào `memberIds`. Rules cho phép cả ba **chỉ khi** lời mời `pending` có ID đúng bằng email của người đang đăng nhập (ID lời mời = email chuẩn hóa, quyết định D3). Vì vậy:
- Không có lời mời, hoặc lời mời đã bị Owner hủy → batch bị từ chối (UC06 9a; T-M5, T-I11).
- Đã từ chối, hoặc đã chấp nhận trước đó → không dùng lại được (T-I10).
- Tự đặt mình làm `owner` → bị từ chối (T-I8).

### 3.4. Truy vấn xuyên board ("Công việc của tôi", "Lời mời của tôi")
Rules **không phải bộ lọc**: Firestore từ chối cả truy vấn nếu có thể trả về tờ hồ sơ mà bạn không được đọc. Với truy vấn xuyên mọi board, Rules không tra được board cha, nên điều kiện phải kiểm tra được **ngay trên tờ hồ sơ**:
- Card: chỉ cho đọc nếu uid của mình nằm trong `assigneeIds`. Truy vấn *bắt buộc* có `where('assigneeIds', arrayContains: uid)`.
- Lời mời: chỉ cho đọc nếu `normalizedEmail` bằng email của mình. Truy vấn *bắt buộc* có `where('normalizedEmail', isEqualTo: email)`.

Thiếu điều kiện đó, hoặc hỏi về người khác, đều bị từ chối (T-C15, T-C16, T-C17, T-I5, T-I6).

### 3.5. Xóa card kèm bình luận của người khác
Bình thường chỉ tác giả hoặc Owner xóa được bình luận. Nhưng xóa card (UC05 3f) phải xóa luôn mọi bình luận bên trong, kể cả của người khác. Rules phân biệt hai trường hợp bằng cách kiểm tra "sau batch này, card cha còn tồn tại không?": nếu card cũng bị xóa trong cùng batch thì cho phép, nếu không thì vẫn chặn (T-K8 so với T-K11).

### 3.6. Kiểm tra dữ liệu ghi vào
Ngoài phân quyền, Rules còn ép đúng từ điển dữ liệu:
- **Đủ trường, không thừa trường**, đúng kiểu (nhờ vậy lỗi "quên ghi `archivedAt`" bị chặn ngay, quy ước Q5).
- **Độ dài:** tên board/list 1–100, tiêu đề card 1–200, bình luận 1–2000...
- **Giờ máy chủ:** `createdAt`/`updatedAt`/`joinedAt` phải bằng giờ máy chủ, không tin giờ điện thoại.
- **Trường bất biến:** không đổi `ownerId`, `boardId`, `createdBy`, `createdAt`, `authorId`...
- **Giao việc:** chỉ giao cho người đang là thành viên (luật I3).
- **Bộ đếm** của card phải là số nguyên không âm, và `checklistDone ≤ checklistTotal`.

---

## 4. Những gì Rules KHÔNG kiểm tra được

Xem bảng ở [`firestore-access-patterns.md`, mục 8](firestore-access-patterns.md#8-những-điều-security-rules-không-kiểm-tra-được-app-phải-tự-kiểm-tra). Tóm tắt: email mời chưa là thành viên, `listId` đúng board, `labelIds` có thật, hạn chót ở tương lai, bộ đếm có đúng số bản ghi con không. Những việc này app phải tự bảo đảm.

---

## 5. Danh mục ca kiểm thử (test plan)

Bảng dưới là ma trận kiểm thử đề xuất cho Security Rules. Gói bàn giao hiện thực hóa **13 ca smoke test tự động** trong `firebase/tests/firestore.rules.test.mjs`; các mã `T-xxx` còn lại là các ca cần được bổ sung/chạy theo ma trận trước khi triển khai production. Không coi số ca trong bảng là bằng chứng rằng chúng đã chạy thành công.

**users**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-U1 | đọc hồ sơ của chính mình được | Cho phép |
| T-U2 | đọc hồ sơ người khác bị chặn | Bị chặn |
| T-U3 | chưa đăng nhập không đọc được | Bị chặn |
| T-U4 | tạo hồ sơ của mình đúng định dạng (như code đăng ký) | Cho phép |
| T-U5 | tạo hồ sơ cho uid khác bị chặn | Bị chặn |
| T-U6 | tạo hồ sơ với email khác email tài khoản bị chặn | Bị chặn |

**boards**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-B1 | thành viên đọc được board | Cho phép |
| T-B2 | người ngoài không đọc được board | Bị chặn |
| T-B3 | truy vấn "board của tôi" (memberIds array-contains) được phép | Cho phép |
| T-B4 | truy vấn toàn bộ board (không điều kiện) bị chặn | Bị chặn |
| T-B5 | tạo board + tờ thành viên Owner trong cùng batch (UC03 bước 7) | Cho phép |
| T-B6 | tạo board nhưng đặt người khác làm Owner bị chặn | Bị chặn |
| T-B7 | tên board 101 ký tự bị chặn (UC03 6a) | Bị chặn |
| T-B8 | tên board rỗng bị chặn | Bị chặn |
| T-B9 | Owner sửa tên board được (UC03 3a) | Cho phép |
| T-B10 | Member sửa tên board bị chặn (UC03 3f) | Bị chặn |
| T-B11 | Owner lưu trữ board được, rồi khôi phục được (UC03 3c, 3e) | Cho phép |
| T-B12 | Member lưu trữ board bị chặn | Bị chặn |
| T-B13 | không ai xóa được board (kể cả Owner) | Bị chặn |
| T-B14 | Member tự nâng mình làm Owner bị chặn | Bị chặn |

**members (UC06 xóa thành viên, rời board)**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-M1 | Owner xóa Member, gỡ khỏi card, trong 1 batch (UC06 2b–2c) | Cho phép |
| T-M2 | Member xóa Member khác bị chặn | Bị chặn |
| T-M3 | Owner không thể rời board (UC06 2d) | Bị chặn |
| T-M4 | Member tự rời board, gỡ khỏi card, trong 1 batch (UC06 2d) | Cho phép |
| T-M5 | người ngoài tự thêm mình vào board khi KHÔNG có lời mời bị chặn | Bị chặn |
| T-M6 | Owner thêm thẳng một người vào memberIds (bỏ qua lời mời) bị chặn | Bị chặn |

**invitations (UC06 cộng tác nhóm)**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-I1 | Owner tạo lời mời hợp lệ | Cho phép |
| T-I2 | Member tạo lời mời bị chặn | Bị chặn |
| T-I3 | ID lời mời khác email chuẩn hóa bị chặn | Bị chặn |
| T-I4 | email sai định dạng bị chặn (UC06 4a) | Bị chặn |
| T-I5 | người được mời thấy lời mời của mình (truy vấn nhóm) | Cho phép |
| T-I6 | người khác truy vấn lời mời của người được mời bị chặn | Bị chặn |
| T-I7 | người được mời CHẤP NHẬN: 3 thao tác trong 1 batch (UC06 bước 9) | Cho phép |
| T-I8 | người được mời CHẤP NHẬN nhưng tự đặt mình là owner bị chặn | Bị chặn |
| T-I9 | người được mời TỪ CHỐI (UC06 8a) | Cho phép |
| T-I10 | đã từ chối rồi thì không thể tự vào board | Bị chặn |
| T-I11 | lời mời đã bị Owner hủy thì chấp nhận thất bại (UC06 9a) | Bị chặn |
| T-I12 | Owner hủy lời mời (UC06 2a) | Cho phép |
| T-I13 | Member không hủy được lời mời | Bị chặn |
| T-I14 | người được mời tự ý đổi trạng thái lời mời của người khác bị chặn | Bị chặn |

**lists và cards (UC04, UC05)**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-C1 | Member thêm list được (UC04) | Cho phép |
| T-C2 | người ngoài thêm list bị chặn | Bị chặn |
| T-C3 | tên list 101 ký tự bị chặn (UC04 5a) | Bị chặn |
| T-C4 | không ai xóa được list (chỉ lưu trữ) | Bị chặn |
| T-C5 | Member thêm card hợp lệ được (UC05) | Cho phép |
| T-C6 | tiêu đề card 201 ký tự bị chặn (UC05 5a) | Bị chặn |
| T-C7 | tiêu đề card rỗng bị chặn | Bị chặn |
| T-C8 | card thiếu trường archivedAt (Q5) bị chặn | Bị chặn |
| T-C9 | giao card cho người KHÔNG phải thành viên bị chặn (UC06 1b) | Bị chặn |
| T-C10 | giao card cho thành viên được | Cho phép |
| T-C11 | Member đánh dấu hoàn thành được (UC05 3c) | Cho phép |
| T-C12 | đặt hạn chót được (UC07) | Cho phép |
| T-C13 | không đổi được boardId hoặc createdBy của card | Bị chặn |
| T-C14 | người ngoài không đọc được card | Bị chặn |
| T-C15 | "Công việc của tôi": truy vấn card được giao cho mình (xuyên board) được phép (UC07 1b) | Cho phép |
| T-C16 | truy vấn xuyên board nhưng hỏi card được giao cho NGƯỜI KHÁC bị chặn | Bị chặn |
| T-C17 | truy vấn xuyên board không có điều kiện bị chặn | Bị chặn |

**checklist và bình luận (UC05, UC06 1c–1d)**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-K1 | thêm mục checklist + tăng bộ đếm cùng batch | Cho phép |
| T-K2 | gửi bình luận + tăng bộ đếm cùng batch (UC06 1d) | Cho phép |
| T-K3 | bình luận giả mạo tác giả bị chặn | Bị chặn |
| T-K4 | bình luận 2001 ký tự bị chặn | Bị chặn |
| T-K5 | người ngoài không bình luận được | Bị chặn |
| T-K6 | tác giả sửa bình luận của mình được | Cho phép |
| T-K7 | sửa bình luận của người khác bị chặn | Bị chặn |
| T-K8 | Member xóa bình luận của người khác (đơn lẻ) bị chặn | Bị chặn |
| T-K9 | tác giả xóa bình luận của mình được | Cho phép |
| T-K10 | Owner xóa bình luận của người khác được (UC06 1d) | Cho phép |
| T-K11 | Member xóa card kèm bình luận của người khác, trong 1 batch (UC05 3f) | Cho phép |

**batch lớn (rủi ro giới hạn truy cập của Rules)**

| Mã | Tình huống | Kết quả mong đợi |
|---|---|---|
| T-L1 | lưu trữ 1 list kèm 25 card trong 1 batch (W8) | Cho phép |
| T-L2 | xóa 1 card kèm 25 bình luận của người khác trong 1 batch (W14) | Cho phép |
| T-L3 | Owner xóa 1 Member đang được giao 25 card trong 1 batch (W30) | Cho phép |

**Cách chạy smoke test và kiểm tra fixture:** xem [`firebase/README.md`](../firebase/README.md).

> ⚠️ **Tình trạng:** bộ kiểm thử đã được kiểm tra cú pháp và tải thư viện thành công, nhưng **chưa từng được chạy trên Firestore Emulator thật** (môi trường tạo ra nó không tải được Emulator). Hãy chạy trước khi triển khai Rules lên Firebase. Nếu có ca thất bại, đọc thông báo lỗi: có thể là Rules sai, cũng có thể là ca kiểm thử viết sai, cần xem xét cả hai.

---

## 6. Rủi ro và điều cần kiểm thử

| # | Rủi ro | Mức độ | Cách xử lý |
|---|---|---|---|
| R1 | **Giới hạn số lần Rules truy cập tài liệu trong một batch.** Firebase quy định tối đa **20** lần truy cập (`get`/`exists`/`getAfter`) cho mỗi batch ghi, và mỗi thao tác tối đa 10. Tài liệu Firebase nói *một số lần truy cập có thể được lưu đệm và không bị tính*, nhưng chưa rõ chắc chắn trong trường hợp này. Các batch lớn như lưu trữ list nhiều card (W8), xóa card nhiều bình luận (W14), xóa Member được giao nhiều card (W30) có thể chạm giới hạn | **Cao** cần kiểm thử | Chạy T-L1, T-L2, T-L3. Nếu thất bại: chia thành nhiều batch nhỏ (ví dụ 8 thao tác/batch) theo **thứ tự an toàn** bên dưới |
| R2 | Mỗi lần Rules gọi `get()` cũng **tốn một lượt đọc** có tính phí, kể cả khi yêu cầu bị từ chối (theo tài liệu Firebase) | Thấp | Chấp nhận; với quy mô đồ án rất nhỏ so với hạn mức 50.000 lượt đọc/ngày |
| R3 | Lời mời khớp theo email nhưng đặc tả **không bắt xác minh email**: ai đăng ký trước bằng email của người khác sẽ thấy lời mời gửi cho email đó (quyết định D3) | Thấp–Trung bình | Chấp nhận cho đồ án; muốn chặt hơn thì bắt xác minh email và thêm điều kiện `email_verified` vào Rules |
| R4 | `boardName`, `inviterName` trong lời mời là **bản sao**; đổi tên board sau khi mời thì lời mời cũ hiển thị tên cũ | Thấp | Chấp nhận (quyết định D10) |
| R5 | Rules chỉ kiểm tra bộ đếm là số hợp lệ, **không** kiểm tra nó khớp số bản ghi con | Trung bình | App luôn ghi cùng batch với thao tác gốc; có thể dùng `validate-seed.mjs` làm mẫu để viết script quét dữ liệu định kỳ |
| R6 | Rules lời mời dùng `request.auth.token.email`. Nếu sau này thêm đăng nhập bằng số điện thoại hoặc ẩn danh (không có email) thì phần này cần thiết kế lại | Thấp | Ghi nhận |
| R7 | Tên collection `cards` và `invitations` được dùng trong luật truy vấn xuyên board toàn cục. Nếu sau này tạo thêm một collection khác **cùng tên** ở chỗ khác thì luật này cũng áp dụng cho nó | Thấp | Đặt tên collection mới khác đi |
| R8 | File `firestore.rules` đã được kiểm tra cú pháp bằng script đơn giản (ngoặc, tên hàm, dấu `;`) nhưng **chưa qua trình biên dịch Rules thật** | Trung bình | Khi triển khai, Firebase báo lỗi kèm số dòng nếu có lỗi cú pháp |

### Thứ tự ghi an toàn khi phải chia nhỏ batch
Chia sao cho **dù dừng giữa chừng, luật toàn vẹn I1–I10 vẫn đúng**:

| Thao tác | Thứ tự | Vì sao an toàn |
|---|---|---|
| Lưu trữ list (W8) | Các batch lưu trữ card trước, batch cuối lưu trữ list | Không bao giờ có list đã lưu trữ mà card chưa (luật I7) |
| Xóa card (W14) | Xóa bình luận và checklist trước, xóa card sau cùng | Không bao giờ có dữ liệu mồ côi mất card cha; thử lại được |
| Xóa Member / Member rời (W30, W31) | Gỡ khỏi `assigneeIds` của các card trước, xóa `members` và `memberIds` sau cùng | Không bao giờ có card giao cho người đã rời (luật I3) |

> Lưu ý với cách chia nhỏ: khi chia batch cho W14, comment của người khác chỉ xóa được nếu **cùng batch xóa card cha**. Nếu phải chia nhỏ, hãy báo lại để chỉnh Rules (ví dụ cho phép xóa bình luận khi card đã đánh dấu "đang xóa").

---

## 7. Triển khai Rules lên Firebase

Chỉ làm sau khi **toàn bộ ma trận kiểm thử đã được hiện thực hóa và đạt** trên Emulator. Bộ smoke test đi kèm chưa thay thế cho toàn bộ ma trận. Lệnh cụ thể nằm ở [`firebase/README.md`](../firebase/README.md#5-triển-khai-rules-và-index-lên-firebase-thật).

⚠️ Triển khai sẽ **thay thế hoàn toàn** bộ Rules đang có trên project. Trước đó, mở Firebase Console → Firestore → Rules và lưu lại bản đang chạy (rất có thể là bản "chế độ thử nghiệm" tự hết hạn sau 30 ngày, khi đó app sẽ ngừng đọc/ghi được).
