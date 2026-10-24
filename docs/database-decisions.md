# Quyết định thiết kế database – Smart Todo

> Trạng thái: đã chọn phương án mặc định cho bản đồ án đầu tiên (23/10/2026). Đây là quyết định kỹ thuật để tiếp tục triển khai, không thay thế phê duyệt của giảng viên nếu đề bài có yêu cầu khác.

## Các quyết định đã chốt

| Mục | Quyết định | Lý do / tác động |
|---|---|---|
| **Q1 – Nhãn** | Mọi thành viên của board được tạo/sửa/xóa nhãn. Tên nhãn 1–50 ký tự; màu do người dùng chọn theo dạng #RRGGBB. | Phù hợp chức năng cộng tác và không cần bảng màu riêng. |
| **Q2 – Checklist và mô tả card** | Tiêu đề mỗi mục checklist tối đa 200 ký tự; mô tả card tối đa 5.000 ký tự; chưa đặt giới hạn số mục checklist ở phiên bản này. | Giữ theo cấu trúc và Rules của bản thiết kế. Khi triển khai nên giữ số mục ở mức hợp lý. |
| **Q3 – Họ tên và mô tả board** | Tên hiển thị tối đa 100 ký tự; mô tả board tối đa 500 ký tự. | Giới hạn rõ ràng và dễ kiểm tra ở giao diện lẫn Rules. |
| **Q4 – Mời email chưa đăng ký** | CHO PHÉP gửi lời mời. Lời mời ở trạng thái pending; người nhận sẽ thấy lời mời sau khi đăng ký bằng đúng email đó. | Không cần tra cứu hồ sơ/email riêng tư của người khác hoặc dùng Cloud Functions. |
| **Q5 – Khôi phục list/card** | Chưa hỗ trợ khôi phục list/card riêng lẻ. Lưu trữ không xóa dữ liệu; chỉ board được khôi phục trong phạm vi phiên bản hiện tại. | Khớp use case hiện có, giảm số chức năng phải viết. |
| **Q6 – Công việc đã hoàn thành** | Không hiển thị card đã hoàn thành trong mục “Công việc của tôi”. | Khớp bốn nhóm deadline trong UC07. |
| **Q7 – Nhắc hạn** | Dùng thông báo cục bộ trên thiết bị hiện tại; ứng dụng đặt lại lịch nhắc khi người dùng mở mục “Công việc của tôi”. Không triển khai nhắc đa thiết bị trong bản đầu. | Tránh backend bổ sung và không cần Cloud Functions. |
| **Q8 – Xác minh email** | Chưa bắt buộc xác minh email trong phiên bản đồ án đầu tiên; giữ đúng phạm vi use case. Có thể bổ sung sau nếu nhóm/giảng viên yêu cầu. | Đơn giản hóa luồng đăng ký; ghi nhận đây là lựa chọn bảo mật cần xem xét lại trước khi triển khai công khai. |
| **Q9 – Kích thước board** | Thiết kế cho board có dưới khoảng 500 card chưa lưu trữ. Nếu vượt quy mô này, phải bổ sung phân trang/truy vấn tìm kiếm phía máy chủ. | Màn hình hiện tải card về rồi tìm kiếm/lọc trên thiết bị. |
| **Q10 – Sắp xếp board mới nhất** | Sắp xếp theo thời điểm cập nhật thông tin/lưu trữ của chính board (boards.updatedAt), không theo mọi thao tác card/comment. | Tránh mỗi thao tác nhỏ đều ghi lại document board. |
| **Q11 – Ai được xóa card** | Mọi thành viên của board đều được xóa card, kể cả card do người khác tạo; giao diện phải hỏi xác nhận. Xóa card phải xử lý checklist và comments con. | Đi theo mặc định trong tài liệu hiện có; cần kiểm thử thao tác xóa theo lô. |
| **Q12 – Mời lại** | Owner được mời lại người từng từ chối hoặc bị xóa khỏi board; cập nhật lời mời cũ về pending. | Tránh giữ nhiều lời mời cho cùng một email trong một board. |
| **Q13 – Ngoài phạm vi** | Chưa làm đổi tên hồ sơ, luồng đổi mật khẩu trực tiếp, xóa tài khoản, chuyển quyền Owner và xóa hẳn board. UC02 vẫn có chức năng “Quên mật khẩu/đặt lại bằng email”. Owner không thể rời board; board được lưu trữ thay vì xóa hẳn. | Giữ đồ án trong phạm vi UC01–UC08. |
| **Q14 – Gói Firebase** | Chọn Spark (miễn phí) cho đồ án; không dùng Cloud Functions, không bật billing/Blaze chỉ để hoàn thành bản đầu. Dùng Emulator để thử nghiệm trước. | Ít rủi ro phát sinh chi phí. Khi cần tính năng trả phí, nhóm phải thống nhất và chủ project duyệt trước. |

## Điều kiện phải xem xét lại trước khi mở rộng

- Nếu cần nhắc hạn trên mọi thiết bị, phải thiết kế backend đáng tin cậy và rà soát chi phí trước khi chuyển gói Firebase.
- Nếu một board có hàng nghìn card, cần đổi cách tải dữ liệu, phân trang và tìm kiếm; giới hạn hiện tại không phù hợp cho quy mô lớn.
- Trước khi cho người dùng bên ngoài sử dụng thật, nhóm nên xem xét bật xác minh email và hoàn thiện thêm kiểm thử Rules.
- Bản test có 13 smoke tests ban đầu; tài liệu bảo mật mô tả ma trận rộng hơn gồm 71 ca. Không coi 13 ca là đã kiểm chứng hết mọi tình huống.
- Gói Spark có hạn mức miễn phí và điều kiện sử dụng cụ thể; kiểm tra trang giá chính thức trước khi thay đổi cấu hình hoặc dùng dịch vụ trả phí.
