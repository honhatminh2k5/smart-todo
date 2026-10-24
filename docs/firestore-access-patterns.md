# Truy vấn, chỉ mục và thao tác ghi – Smart Todo

> Tài liệu này dành cho **người viết code kết nối Firestore**. Nó trả lời hai câu hỏi cho từng chức năng: *app hỏi Firestore thế nào?* và *app ghi vào Firestore những gì?*
> Cấu trúc dữ liệu xem [`firestore-schema.md`](firestore-schema.md). Phân quyền xem [`firestore-security.md`](firestore-security.md).

Các đoạn mã bên dưới dùng cú pháp của gói `cloud_firestore` (Flutter). `db` là `FirebaseFirestore.instance`, `uid` là `FirebaseAuth.instance.currentUser!.uid`.

---

## 1. Màn hình ↔ truy vấn

| # | Màn hình / chức năng | Câu hỏi app hỏi Firestore | Nguồn |
|---|---|---|---|
| A | Danh sách board | Các board có mình là thành viên | UC03 bước 2 |
| B | Chi tiết board | List, card, thành viên, nhãn của board này | UC04, UC05 |
| C | Chi tiết card | Checklist và bình luận của card | UC05, UC06 |
| D | Màn hình Thành viên (Owner) | Thành viên và lời mời đang chờ | UC06 bước 2 |
| E | Lời mời của tôi | Lời mời `pending` gửi tới email của mình | UC06 bước 6–7 |
| F | **Công việc của tôi** | Card được giao cho mình ở **mọi** board | UC07 1b |
| G | Tìm kiếm và lọc | *Không truy vấn mới*, lọc trên card đã tải của màn B | UC08 |

### A. Danh sách board

```dart
db.collection('boards')
  .where('memberIds', arrayContains: uid)
  .snapshots();
```

Số board của một người rất ít, nên **tách "chưa lưu trữ" / "đã lưu trữ" và sắp xếp theo `updatedAt` giảm dần ngay trên máy**: `archivedAt == null` là board đang dùng, ngược lại là board đã lưu trữ (mục "Board đã lưu trữ", UC03 3e). Một truy vấn phục vụ cả hai danh sách và không cần chỉ mục đặc biệt.

### B. Chi tiết board

```dart
final board = db.doc('boards/$boardId');

board.collection('lists')
  .where('archivedAt', isNull: true)
  .orderBy('position')
  .snapshots();                       // cần chỉ mục, xem mục 2

board.collection('cards')
  .where('archivedAt', isNull: true)
  .snapshots();                       // một kênh nghe cho TẤT CẢ card, rồi nhóm theo listId trên máy

board.collection('members').snapshots();
board.collection('labels').snapshots();
```

Dùng **một** kênh nghe cho toàn bộ card của board (thay vì mỗi list một kênh) để tiết kiệm; sau đó nhóm theo `listId` và sắp xếp theo `position` trong từng list ngay trên máy. Bộ đếm `commentCount`, `checklistTotal`, `checklistDone` nằm sẵn trong card nên **không cần** đọc dữ liệu con để vẽ thẻ tóm tắt.

### C. Chi tiết card

```dart
final card = db.doc('boards/$boardId/cards/$cardId');
card.snapshots();                                         // lắng nghe cả việc card bị xóa (UC05 3g)
card.collection('checklist').orderBy('position').snapshots();
card.collection('comments').orderBy('createdAt').snapshots();
```

Khi `card.snapshots()` trả về tờ hồ sơ **không tồn tại** nghĩa là thành viên khác đã xóa card: báo "card không còn tồn tại" và quay về board (UC05 3g).

### D. Màn hình Thành viên (chỉ Owner)

```dart
board.collection('members').snapshots();
board.collection('invitations')
  .where('status', isEqualTo: 'pending')
  .snapshots();
```

### E. Lời mời của tôi

```dart
final myEmail = FirebaseAuth.instance.currentUser!.email!.trim().toLowerCase();

db.collectionGroup('invitations')
  .where('normalizedEmail', isEqualTo: myEmail)
  .where('status', isEqualTo: 'pending')
  .snapshots();
```

Mỗi kết quả có đường dẫn `boards/{boardId}/invitations/{email}`. Lấy `boardId` từ `doc.reference.parent.parent!.id`. Tên board và tên người mời đã nằm sẵn trong lời mời (`boardName`, `inviterName`), vì người được mời **chưa là thành viên nên chưa đọc được board**.

### F. Công việc của tôi

```dart
db.collectionGroup('cards')
  .where('assigneeIds', arrayContains: uid)
  .where('archivedAt', isNull: true)
  .snapshots();
```

Lọc thêm **trên máy**:
1. Bỏ các card có `boardId` **không** nằm trong danh sách board chưa lưu trữ của mình (kết quả truy vấn A), để card của board đã lưu trữ không xuất hiện.
2. Bỏ card đã hoàn thành (nếu nhóm chốt như vậy, xem file câu hỏi cần chốt).
3. Chia nhóm theo [mục 6](#6-trạng-thái-hạn-chót-và-nhóm-công-việc-của-tôi).

> Truy vấn này **bắt buộc** có đúng điều kiện `assigneeIds arrayContains uid`. Security Rules chỉ cho phép đọc xuyên board khi điều kiện đó có mặt; thiếu nó, Firestore từ chối toàn bộ truy vấn.

---

## 2. Chỉ mục (index)

Chỉ mục giống "mục lục" của cuốn sổ: giúp Firestore tìm nhanh. Truy vấn nào kết hợp nhiều điều kiện thì cần mục lục riêng. Các chỉ mục dưới đây khai báo sẵn trong [`firestore.indexes.json`](../firestore.indexes.json).

| Collection | Phạm vi | Trường (theo thứ tự) | Phục vụ |
|---|---|---|---|
| `lists` | Một board | `archivedAt` ↑, `position` ↑ | Truy vấn B (list) |
| `cards` | **Toàn bộ board** (collection group) | `assigneeIds` (chứa), `archivedAt` ↑ | Truy vấn F |
| `invitations` | **Toàn bộ board** (collection group) | `normalizedEmail` ↑, `status` ↑ | Truy vấn E |

Cách triển khai và kiểm tra trong Emulator: xem [`firebase/README.md`](../firebase/README.md). Nếu quên một chỉ mục, app báo lỗi `FAILED_PRECONDITION` kèm **đường link tạo chỉ mục**, bấm vào link là xong. Nhớ chép định nghĩa chỉ mục mới vào `firestore.indexes.json` cho cả nhóm.

---

## 3. Công thức ghi dữ liệu

**Quy tắc vàng:** thao tác nào đụng tới **nhiều tờ hồ sơ** thì dùng **`WriteBatch`** (hoặc transaction) để *hoặc thành công hết, hoặc không gì cả*. Ghi lẻ từng tờ sẽ để lại dữ liệu lệch nhau nếu mất mạng giữa chừng.

Quy ước: `now` = `FieldValue.serverTimestamp()`. Mọi tờ hồ sơ tạo mới phải ghi **đủ trường** theo [từ điển dữ liệu](firestore-schema.md#4-từ-điển-dữ-liệu).

### Tài khoản và board

| # | Thao tác | Ghi gì (trong 1 batch) | Ghi chú |
|---|---|---|---|
| W1 | Đăng ký (UC01 b7) | Tạo `users/{uid}` | Code hiện tại đã đúng |
| W2 | Tạo board (UC03) | Tạo `boards/{id}` với `ownerId = uid`, `memberIds = [uid]`, `archivedAt = null`; tạo `boards/{id}/members/{uid}` với `role = "owner"` | **Hai tờ cùng một batch** (luật I2) |
| W3 | Sửa board (UC03 3a) | Cập nhật `name`, `description`, `updatedAt = now` | Chỉ Owner |
| W4 | Lưu trữ / khôi phục board | Cập nhật `archivedAt = now` (hoặc `null`), `updatedAt = now` | Chỉ Owner |

### List

| # | Thao tác | Ghi gì | Ghi chú |
|---|---|---|---|
| W5 | Thêm list (UC04) | Tạo `lists/{id}` với `position` = vị trí list cuối + 1024 (hoặc 1024 nếu chưa có list) | [Mục 5](#5-sắp-xếp-bằng-position-kéo-thả) |
| W6 | Đổi tên list | Cập nhật `name`, `updatedAt` | |
| W7 | Kéo thả list | Cập nhật `position`, `updatedAt` | |
| W8 | Lưu trữ list (UC04 3b) | Cập nhật `lists/{id}.archivedAt = now` **và** `archivedAt = now` cho **mọi card chưa lưu trữ** của list | Cùng một batch ⇒ cùng một giá trị thời gian (quyết định D7). Cần đọc trước các card của list |

### Card

| # | Thao tác | Ghi gì | Ghi chú |
|---|---|---|---|
| W9 | Thêm card (UC05) | Tạo `cards/{id}`: `boardId`, `listId`, `title`, `description = ""`, `position` = cuối list + 1024, `isCompleted = false`, `assigneeIds = []`, `labelIds = []`, `dueAt = null`, `archivedAt = null`, ba bộ đếm = 0, `createdBy = uid`, `createdAt/updatedAt = now` | |
| W10 | Sửa tiêu đề, mô tả | Cập nhật trường + `updatedAt` | |
| W11 | Đánh dấu / bỏ hoàn thành | Cập nhật `isCompleted`, `updatedAt` | Đồng thời hủy nhắc hạn trên máy (UC07 3f) |
| W12 | Kéo thả card (đổi list hoặc vị trí) | Cập nhật `listId`, `position`, `updatedAt` | Chỉ chuyển sang list **cùng board** |
| W13 | Lưu trữ card (UC05 3e) | Cập nhật `archivedAt = now`, `updatedAt` | Hủy nhắc hạn trên máy |
| W14 | **Xóa card** (UC05 3f) | Xóa **mọi** tờ trong `checklist` và `comments` của card, rồi xóa card, **cùng một batch** | Firestore **không tự xóa** dữ liệu con. Xem mục 4 |
| W15 | Đặt / sửa / xóa hạn chót (UC07) | Cập nhật `dueAt` (Timestamp hoặc `null`), `updatedAt` | Đặt/hủy nhắc hạn trên máy |
| W16 | Giao việc / bỏ giao (UC06 1b) | `assigneeIds` dùng `arrayUnion(uid)` / `arrayRemove(uid)`, `updatedAt` | Chỉ cho chọn thành viên hiện tại (luật I3) |
| W17 | Gắn / bỏ nhãn | `labelIds` dùng `arrayUnion` / `arrayRemove`, `updatedAt` | Chỉ nhãn của cùng board (luật I5) |

### Nhãn, checklist, bình luận

| # | Thao tác | Ghi gì | Ghi chú |
|---|---|---|---|
| W18 | Tạo / sửa nhãn | Tạo/cập nhật `labels/{id}` | |
| W19 | **Xóa nhãn** | Xóa `labels/{id}` **và** `labelIds: arrayRemove(id)` trên **mọi card** có nhãn đó | Giữ luật I5. Cần đọc trước các card có nhãn |
| W20 | Thêm mục checklist | Tạo `checklist/{id}`; card: `checklistTotal += 1`, `updatedAt` | `FieldValue.increment(1)` |
| W21 | Đánh dấu / bỏ mục | Cập nhật `isCompleted` của mục; card: `checklistDone += 1` (hoặc `-1`), `updatedAt` | |
| W22 | Xóa mục checklist | Xóa mục; card: `checklistTotal -= 1`, và `checklistDone -= 1` nếu mục đó đã hoàn thành | |
| W23 | Gửi bình luận (UC06 1d) | Tạo `comments/{id}` (`authorId = uid`, `authorName`, `body`, `createdAt/updatedAt = now`); card: `commentCount += 1` | |
| W24 | Sửa bình luận | Cập nhật `body`, `updatedAt = now` | Chỉ tác giả |
| W25 | Xóa bình luận | Xóa bình luận; card: `commentCount -= 1` | Tác giả hoặc Owner |

### Cộng tác nhóm (UC06)

| # | Thao tác | Ghi gì | Ghi chú |
|---|---|---|---|
| W26 | **Mời thành viên** | Đọc `invitations/{emailChuanHoa}` rồi ghi (set) tờ lời mời: `status = "pending"`, `invitedBy = uid`, `inviterName`, `boardName`, `createdAt/updatedAt = now` | **App phải kiểm tra trước** (mục 8): email hợp lệ, chưa là thành viên, chưa có lời mời `pending`. Mời lại người đã từ chối: ghi đè tờ cũ về `pending` |
| W27 | Hủy lời mời (UC06 2a) | Xóa `invitations/{email}` | Chỉ Owner |
| W28 | **Chấp nhận lời mời** (UC06 8–9) | Một batch gồm 3 ghi: (1) `invitations/{email}.status = "accepted"`, `updatedAt`; (2) tạo `members/{uid}` với `role = "member"`, `displayName`, `email`, `joinedAt`; (3) `boards/{id}.memberIds = arrayUnion(uid)` | Nếu Owner đã hủy lời mời, batch bị **từ chối** ⇒ báo "lời mời không còn hiệu lực" (UC06 9a) |
| W29 | Từ chối lời mời (UC06 8a) | `invitations/{email}.status = "declined"`, `updatedAt` | |
| W30 | **Owner xóa Member** (UC06 2b–2c) | Đọc trước các card của board có `assigneeIds` chứa uid đó. Một batch: xóa `members/{uid}`; `boards/{id}.memberIds = arrayRemove(uid)`; mỗi card đó: `assigneeIds = arrayRemove(uid)`, `updatedAt` | Giữ luật I2, I3 |
| W31 | **Member rời board** (UC06 2d) | Giống W30 nhưng người rời tự thực hiện; **Owner không được rời** | |

### Ghi chú về kích thước batch

Mỗi batch (và mỗi lượt kiểm tra của Security Rules) có giới hạn số thao tác. Các thao tác ảnh hưởng nhiều tờ như W8, W14, W19, W30 nên **thử với dữ liệu lớn** (ví dụ list 30 card). Nếu vướng giới hạn thì chia thành nhiều batch nhỏ và ghi thao tác "đánh dấu" ở batch cuối cùng. Chi tiết ở [`firestore-security.md`](firestore-security.md#6-rủi-ro-và-điều-cần-kiểm-thử).

---

## 4. Xóa card đúng cách (W14)

Xóa tờ `cards/{id}` **không** xóa `checklist` và `comments` bên trong; chúng thành "dữ liệu mồ côi" vẫn chiếm chỗ và vẫn tính tiền lưu trữ. Quy trình:

```dart
Future<void> deleteCard(String boardId, String cardId) async {
  final cardRef = db.doc('boards/$boardId/cards/$cardId');
  final checklist = await cardRef.collection('checklist').get();
  final comments  = await cardRef.collection('comments').get();

  final batch = db.batch();
  for (final d in checklist.docs) { batch.delete(d.reference); }
  for (final d in comments.docs)  { batch.delete(d.reference); }
  batch.delete(cardRef);
  await batch.commit();
}
```

Security Rules cho phép xóa bình luận **của người khác** *chỉ khi* cùng batch đó xóa luôn card cha. Nếu không, thành viên bình thường không xóa được bình luận của người khác.

---

## 5. Sắp xếp bằng `position` (kéo thả)

Mỗi list (trong board) và mỗi card (trong list) có `position` là **số thực**. Sắp xếp tăng dần theo số này.

**Nguyên tắc:** chèn vào *giữa* hai phần tử thì lấy **trung bình** hai vị trí. Như vậy kéo thả chỉ phải ghi **một** tờ hồ sơ, không phải đánh số lại cả danh sách.

```dart
const kPositionStep = 1024.0;

/// before/after là position của phần tử liền trước/liền sau chỗ thả (null nếu không có).
double positionBetween(double? before, double? after) {
  if (before == null && after == null) return kPositionStep;     // danh sách đang trống
  if (before == null) return after! / 2;                          // thả lên đầu
  if (after == null) return before + kPositionStep;               // thả xuống cuối
  return (before + after) / 2;                                    // thả vào giữa
}
```

| Tình huống | Vị trí mới |
|---|---|
| Danh sách trống | 1024 |
| Thêm vào cuối, phần tử cuối đang là 3072 | 4096 |
| Thả giữa 1024 và 2048 | 1536 |
| Thả lên đầu, phần tử đầu đang là 1024 | 512 |

**Khi nào phải đánh số lại:** chèn mãi vào cùng một khe thì khoảng cách nhỏ dần. Nếu khoảng cách giữa hai phần tử liền kề **nhỏ hơn 0,000001**, đánh lại số cả danh sách thành 1024, 2048, 3072… trong **một batch** (hiếm khi xảy ra).

**Hai người kéo thả cùng lúc** có thể ra hai card trùng `position`. Chấp nhận được: khi sắp xếp, dùng `createdAt` làm tiêu chí phụ.

---

## 6. Trạng thái hạn chót và nhóm "Công việc của tôi"

Không lưu trạng thái, **tính mỗi lần hiển thị** từ `dueAt`, `isCompleted` và giờ hiện tại `now`. Giờ so sánh lấy từ đồng hồ máy; ranh giới "hôm nay" tính theo múi giờ của máy.

### Trạng thái trên thẻ (UC07 bước 6) và bộ lọc (UC08 3a)

Áp dụng theo thứ tự, trúng điều kiện đầu tiên thì dừng:

| Thứ tự | Điều kiện | Trạng thái |
|---|---|---|
| 1 | `isCompleted == true` | Đã hoàn thành |
| 2 | `dueAt == null` | Không có hạn |
| 3 | `dueAt < now` | Quá hạn |
| 4 | `dueAt ≤ now + 24 giờ` | Sắp đến hạn |
| 5 | còn lại | Bình thường |

### Nhóm trong "Công việc của tôi" (UC07 1b)

Chỉ áp dụng cho card **chưa hoàn thành**; các nhóm không chồng lên nhau:

| Nhóm | Điều kiện |
|---|---|
| Quá hạn | `dueAt < now` |
| Hôm nay | `now ≤ dueAt <` 00:00 ngày mai (giờ máy) |
| Sắp tới | `dueAt ≥` 00:00 ngày mai |
| Không có hạn | `dueAt == null` |

---

## 7. Tìm kiếm và lọc (UC08)

Làm **hoàn toàn trên máy**, trên danh sách card của board đã tải ở truy vấn B. Không phát sinh lượt đọc.

**Từ khóa, không phân biệt hoa/thường và dấu tiếng Việt:** chuẩn hóa cả tiêu đề và từ khóa rồi kiểm tra "chứa".

```dart
// Gói gợi ý: diacritic (removeDiacritics). KIỂM TRA kỹ chữ đ/Đ trước khi dùng.
String normalizeVi(String s) =>
    removeDiacritics(s).replaceAll('đ', 'd').replaceAll('Đ', 'D').toLowerCase().trim();

bool matchesKeyword(String title, String keyword) =>
    normalizeVi(title).contains(normalizeVi(keyword));
```

**Bộ lọc kết hợp** (UC08 3b):
- Các **loại** điều kiện khác nhau (nhãn, người được giao, tình trạng hạn, hoàn thành) phải thỏa **đồng thời** (AND).
- Trong **cùng một loại** chọn nhiều giá trị thì khớp **một trong các** giá trị đó (OR).
- Từ khóa kết hợp (AND) với các bộ lọc.
- Từ khóa trống ⇒ chỉ áp dụng bộ lọc (UC08 4a).

Tình trạng hạn dùng đúng bảng ở mục 6 (Quá hạn / Sắp đến hạn / Không có hạn).

---

## 8. Những điều Security Rules **không** kiểm tra được, app phải tự kiểm tra

| Việc | Vì sao Rules không làm được | App làm gì |
|---|---|---|
| Khi mời: email chưa là thành viên | Rules không duyệt được cả subcollection `members` | Đọc `members`, so `email` với email chuẩn hóa |
| Khi mời: chưa có lời mời `pending` | Đây là thao tác ghi đè lên cùng tờ | Đọc `invitations/{email}` trước, nếu `pending` thì báo lỗi (UC06 4a) |
| `listId` của card thuộc đúng board | Tránh tốn lượt kiểm tra thêm | Chỉ cho chọn list của board đang mở |
| `labelIds` là nhãn có thật | Rules không kiểm tra được từng phần tử mảng | Chỉ cho chọn nhãn của board |
| Hạn chót nằm ở tương lai (UC07 b4) | Có cho phép quá khứ sau khi xác nhận (UC07 4a) | Hiện cảnh báo, hỏi xác nhận |
| Bộ đếm (`commentCount`...) đúng | Rules chỉ kiểm tra kiểu và khoảng giá trị | Luôn ghi cùng batch với thao tác gốc |
| Độ dài tên/tiêu đề | Rules **có** chặn, nhưng chỉ báo "từ chối" chung chung | Kiểm tra trước để báo lỗi dễ hiểu (UC03 6a, UC04 5a, UC05 5a) |

---

## 9. Chất lượng khi mất mạng

Firestore trên Flutter có sẵn **bộ nhớ đệm ngoại tuyến**: đọc được dữ liệu đã tải khi mất mạng, và các thao tác ghi được xếp hàng, tự gửi khi có mạng lại. Điều đó khớp thông báo lỗi mất kết nối trong đặc tả (các mục "Tại bất kỳ thời điểm nào..."). Lưu ý với W28 (chấp nhận lời mời) và W26 (mời): kiểm tra điều kiện *trước khi* ghi cần có mạng, vì dữ liệu cũ trong bộ nhớ đệm có thể đã lỗi thời.
