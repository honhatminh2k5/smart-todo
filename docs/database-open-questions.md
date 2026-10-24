# Câu hỏi cần chốt cho thiết kế cơ sở dữ liệu

> Những chỗ đặc tả chưa quy định hoặc còn mơ hồ. **Bản thiết kế đã chốt theo các mặc định được chọn ngày 23/10/2026** để tiếp tục triển khai. Các quyết định được liệt kê ở `database-decisions.md`; chỉ thay đổi khi nhóm/giảng viên yêu cầu khác.
> Cách dùng: gửi file này cho nhóm, điền cột **Quyết định**, rồi báo lại để cập nhật tài liệu, Rules và dữ liệu mẫu.

Mức ưu tiên: 🔴 ảnh hưởng cấu trúc hoặc phải làm lại nếu sai · 🟡 ảnh hưởng quy tắc/giới hạn · 🟢 chi tiết nhỏ.

| # | Mức | Vấn đề | Giả định mặc định (đang dùng) | Nếu đổi thì sao? | Quyết định |
|---|:-:|---|---|---|---|
| **Q1** | 🟡 | **Nhãn:** UC05 chỉ nói nhãn hiển thị trên thẻ; việc tạo/sửa/xóa thuộc "Chi tiết card" (chưa có use case). Tên nhãn dài tối đa bao nhiêu? Bảng màu cố định hay tự chọn? Ai được tạo/sửa/xóa nhãn? | Tên 1–50 ký tự; màu dạng `#RRGGBB`; **mọi thành viên** được tạo/sửa/xóa | Chỉ Owner: sửa 3 dòng trong `firestore.rules`. Bảng màu cố định: thêm kiểm tra danh sách màu | Đã chốt theo mặc định |
| **Q2** | 🟡 | **Checklist và mô tả card:** độ dài tối đa của một mục checklist, số mục tối đa, độ dài mô tả card? | Mục ≤ 200 ký tự, không giới hạn số mục; mô tả ≤ 5000 ký tự | Đổi số trong Rules và từ điển | Đã chốt theo mặc định |
| **Q3** | 🟢 | **Giới hạn ở UC01/UC03 chưa nêu:** họ tên tối đa mấy ký tự? Mô tả board tối đa mấy ký tự? | Họ tên ≤ 100; mô tả board ≤ 500 | Đổi số trong Rules. **Lưu ý:** màn đăng ký cần cùng giới hạn, nếu không người dùng nhập 150 ký tự sẽ bị Rules từ chối khi ghi hồ sơ (và code hiện tại sẽ xóa tài khoản vừa tạo) | Đã chốt theo mặc định |
| **Q4** | 🔴 | **Mời email chưa có tài khoản:** tiền điều kiện UC06 nói người được mời đã có tài khoản, nhưng không có luồng xử lý khi email chưa đăng ký. | **Cho phép**: lời mời nằm chờ, khi người đó đăng ký bằng đúng email sẽ tự thấy lời mời (nhờ thiết kế D3) | Nếu muốn **cấm**: app phải tra email có tồn tại không, mà Rules hiện không cho tra hồ sơ người khác ⇒ cần thêm collection tra cứu email hoặc Cloud Functions | Đã chốt theo mặc định |
| **Q5** | 🟡 | **Khôi phục list và card đã lưu trữ:** đặc tả chỉ cho khôi phục **board** (UC03 3e). List và card lưu trữ có khôi phục được không? | **Chưa có** chức năng khôi phục; dữ liệu vẫn được giữ (không bị xóa) | Nếu có: cần màn hình "đã lưu trữ" trong board. Dữ liệu đã đủ: khôi phục list thì khôi phục các card có `archivedAt` đúng bằng của list (quyết định D7) | Đã chốt theo mặc định |
| **Q6** | 🟡 | **"Công việc của tôi" có hiện card đã hoàn thành không?** UC07 1b chỉ liệt kê 4 nhóm: Quá hạn, Hôm nay, Sắp tới, Không có hạn. | **Không** hiện card đã hoàn thành | Nếu có: thêm nhóm "Đã hoàn thành" ở giao diện, không đổi cấu trúc dữ liệu | Đã chốt theo mặc định |
| **Q7** | 🔴 | **Nhắc hạn chót (UC07 bước 7):** chỉ nhắc trên thiết bị đang đặt hạn, hay trên **mọi thiết bị** của người được giao? | **Chỉ thiết bị hiện tại** bằng thông báo cục bộ; app đặt lại nhắc khi mở "Công việc của tôi" | Nhắc trên mọi thiết bị cần **Cloud Functions + gói Blaze** (trả phí theo mức dùng) và lưu thêm token thiết bị | Đã chốt theo mặc định |
| **Q8** | 🟡 | **Xác minh email:** đặc tả không bắt xác minh email khi đăng ký. | **Không xác minh** | Hệ quả bảo mật nhỏ ở D3 / rủi ro R3. Nếu muốn bắt xác minh: thêm điều kiện `email_verified` vào Rules lời mời | Đã chốt theo mặc định |
| **Q9** | 🔴 | **Quy mô một board:** tối đa khoảng bao nhiêu card? | Dưới **500 card/board**, vì mở board tải mọi card chưa lưu trữ (D9 tìm kiếm trên máy) | Nếu hàng nghìn card: cần phân trang và tìm kiếm phía máy chủ, thay đổi lớn | Đã chốt theo mặc định |
| **Q10** | 🟡 | **Sắp xếp "mới cập nhật nhất" của board (UC03 bước 2):** tính theo lần sửa **thông tin board**, hay theo **hoạt động bất kỳ** trong board (thêm card, bình luận...)? | Chỉ theo sửa thông tin/lưu trữ board (`updatedAt` của board) | Nếu theo hoạt động: mỗi thao tác phải ghi thêm `updatedAt` của board, tăng số lần ghi và có thể "nghẽn" khi nhiều người cùng ghi vào một tờ | Đã chốt theo mặc định |
| **Q11** | 🟢 | **Ai được xóa card:** UC05 3f nói "Thành viên" được xóa vĩnh viễn, kể cả card của người khác? | **Mọi thành viên** xóa được mọi card | Chỉ người tạo hoặc Owner: sửa luật `delete` của card | Đã chốt theo mặc định |
| **Q12** | 🟢 | **Mời lại** người đã từ chối hoặc đã bị xóa khỏi board. | **Cho phép**: Owner ghi đè lời mời cũ về `pending` | Nếu muốn cấm: sửa Rules lời mời | Đã chốt theo mặc định |
| **Q13** | 🟢 | **Ngoài phạm vi đặc tả hiện tại:** đổi tên hiển thị, đổi mật khẩu, xóa tài khoản, chuyển quyền Owner, xóa hẳn board. | **Chưa có.** Board chỉ lưu trữ; Owner không thể rời hay chuyển quyền | Mỗi chức năng cần thêm quy tắc và có thể phải sửa các bản sao tên (D10) | Đã chốt theo mặc định |
| **Q14** | 🔴 | **Gói Firebase:** dùng gói miễn phí (Spark) hay trả phí (Blaze)? | **Spark** (50.000 lượt đọc, 20.000 ghi, 20.000 xóa mỗi ngày); **không** dùng Cloud Functions | Nếu cần Cloud Functions (Q7, hoặc dọn dẹp dữ liệu tự động): phải bật Blaze | Đã chốt theo mặc định |

---

## Cách mình đã chọn mặc định

Nguyên tắc: chọn phương án **đơn giản nhất, ít phụ thuộc nhất, và dễ nới lỏng/siết chặt về sau** (đổi giới hạn trong Rules là việc vài dòng; đổi cấu trúc dữ liệu là việc lớn). Vì vậy các câu 🔴 là những câu nên chốt **sớm nhất**, trước khi nhóm viết code kết nối Firestore: Q4, Q7, Q9, Q14.

## Trạng thái chốt

Các lựa chọn Q1–Q14 đã được ghi tại `database-decisions.md`. Những câu hỏi này không còn là việc chặn bước thử nghiệm. Không triển khai lên Firebase thật cho đến khi bộ kiểm thử Rules được chạy và nhóm review.

