# Báo cáo sự cố: Nginx ngừng hoạt động

- **Mã sự cố:** `INC-001`
- **Môi trường:** Kali GNU/Linux Rolling trong máy ảo VMware
- **Dịch vụ:** Nginx HTTP Server
- **Phạm vi:** Trang web thử nghiệm truy cập từ loopback trên máy lab
- **Mức độ:** Thấp - sự cố mô phỏng có chủ đích
- **Trạng thái:** **Đã khôi phục và xác minh (Resolved)**

## 1. Tóm tắt

Sự cố được mô phỏng bằng lệnh `sudo systemctl stop nginx`. Trước khi dừng service, cấu hình Nginx hợp lệ, service `active`, request HTTP trả `200` và cổng 80 đang lắng nghe.

Trong lúc mô phỏng, Nginx chuyển sang `inactive (dead)`. Kết nối tới `127.0.0.1:80` thất bại; `curl` trả HTTP `000` cùng mã thoát `7`; không còn listener ở cổng 80. Script `healthcheck.sh` nhận diện Nginx và HTTP endpoint ở mức `CRITICAL`.

Sau đó, cấu hình được kiểm tra lại, Nginx được khởi động và xác minh bằng trạng thái service, socket và request HTTP. Sau khôi phục, HTTP trả `200` và healthcheck không còn mục `CRITICAL`. Trạng thái tổng thể vẫn là `WARNING` do filesystem gốc sử dụng khoảng 82%.

## 2. Dòng thời gian

| Thời điểm (UTC+07:00) | Hoạt động | Kết quả |
|---|---|---|
| 14:38:42 | Chạy healthcheck trước sự cố | Nginx/HTTP `OK`; tổng thể `WARNING` do filesystem 82% |
| Trước 14:39:08 | Kiểm tra trạng thái và cấu hình | `nginx -t` thành công; service `active`; HTTP `200`; cổng 80 lắng nghe |
| 14:39:08 | Dừng Nginx có chủ đích | Service dừng thành công |
| Sau 14:39:08 | Kiểm tra service, HTTP và socket | `inactive (dead)`; HTTP thất bại; cổng 80 không có listener |
| 14:39:54 | Chạy healthcheck trong lúc service dừng | `CRITICAL`; 6 OK, 3 WARNING, 2 CRITICAL |
| Khoảng 14:42 | Kiểm tra cấu hình và khởi động lại | `nginx -t` thành công; service `active` |
| 14:42:37 | Chạy healthcheck sau khôi phục | Nginx/port 80/HTTP `OK`; 10 OK, 1 WARNING, 0 CRITICAL |

## 3. Bằng chứng và triệu chứng

### 3.1. Trạng thái trước sự cố

Các lệnh đã được chạy:

```bash
sudo nginx -t
systemctl is-active nginx
curl --connect-timeout 2 --max-time 5 \
  -sS -o /dev/null \
  -w 'HTTP status: %{http_code}\n' \
  http://127.0.0.1/
sudo ss -ltnp 'sport = :80'
```

Kết quả: cấu hình hợp lệ; service `active`; HTTP `200`; Nginx lắng nghe cổng 80 qua IPv4 và IPv6.

### 3.2. Trong lúc sự cố

```bash
sudo systemctl stop nginx
systemctl is-active nginx
curl --connect-timeout 2 --max-time 5 \
  -sS -o /dev/null \
  -w 'HTTP status: %{http_code}\n' \
  http://127.0.0.1/
sudo ss -ltnp 'sport = :80'
sudo systemctl status nginx --no-pager -l
sudo journalctl -u nginx --since '10 minutes ago' --no-pager -n 30
```

Kết quả quan sát được:

- Service `inactive (dead)`.
- `curl` không kết nối được tới `127.0.0.1:80`, mã thoát `7`, HTTP status `000`.
- `ss` không hiển thị socket lắng nghe cổng 80.
- `systemctl status` cho biết service đã dừng thành công.
- Journal ghi nhận `Stopping`, `Deactivated successfully` và `Stopped`.
- Healthcheck báo `CRITICAL` cho Nginx service và HTTP endpoint.

### 3.3. Sau khôi phục

```bash
sudo nginx -t
sudo systemctl start nginx
systemctl is-active nginx
curl --connect-timeout 2 --max-time 5 \
  -sS -o /dev/null \
  -w 'HTTP status: %{http_code}\n' \
  http://127.0.0.1/
sudo ss -ltnp 'sport = :80'
./scripts/healthcheck.sh
```

Kết quả quan sát được: cấu hình hợp lệ, service `active`, HTTP `200`, cổng 80 có listener; healthcheck có `0 CRITICAL` và `1 WARNING` về filesystem.

### 3.4. Ảnh hiện có

![Nginx đang hoạt động và ghi access log](../../images/service_monitor.png)

Ảnh này chứng minh trạng thái Nginx đang hoạt động và access log tại thời điểm chụp. Repository chưa có ảnh chụp trực tiếp trong lúc service bị dừng hoặc màn hình phục hồi; bảng thời gian và kết quả ở trên dựa trên log terminal của buổi thực hành. Hãy bổ sung ảnh đã che thông tin nếu muốn có bộ bằng chứng trực quan đầy đủ.

## 4. Nguyên nhân và phạm vi ảnh hưởng

**Nguyên nhân trực tiếp đã xác nhận:** lệnh `sudo systemctl stop nginx` được chủ động chạy để mô phỏng service outage.

**Ảnh hưởng:** Nginx không phục vụ HTTP qua endpoint thử nghiệm trong khoảng thời gian service bị dừng.

**Không có bằng chứng về crash tự phát:** journal cho thấy service được dừng thành công theo lệnh. Không nên mô tả bài lab này như một sự cố production hoặc Nginx tự crash.

## 5. Phân tích cảnh báo healthcheck

Khi Nginx dừng, healthcheck phát hiện:

- `CRITICAL`: Nginx không hoạt động.
- `CRITICAL`: HTTP endpoint không phản hồi trong khi Nginx đã cài.
- `WARNING`: không thấy listener cổng 80 và không thấy listening socket trong thời điểm kiểm tra.
- `WARNING`: filesystem gốc sử dụng khoảng 82%.

Cảnh báo filesystem độc lập với nguyên nhân của sự cố Nginx. Sau khôi phục, filesystem vẫn vượt ngưỡng `WARNING` 80%, nhưng thấp hơn ngưỡng `CRITICAL` 90% mặc định.

Trong các log cũ, phần load average của script từng lỗi do đặt tên biến AWK trùng với tên dựng sẵn `load`. Script cập nhật sử dụng tên `load_value`; cần xác minh bằng cách chạy bản mới trên VM và kiểm tra dòng load average không còn lỗi.

## 6. Khôi phục và tiêu chí xác minh

Các bước đã hoàn tất:

1. Chạy `sudo nginx -t`, nhận kết quả cấu hình hợp lệ.
2. Chạy `sudo systemctl start nginx`.
3. Xác nhận `systemctl is-active nginx` trả `active`.
4. Xác nhận HTTP endpoint trả `200`.
5. Xác nhận cổng 80 lắng nghe trở lại.
6. Chạy healthcheck và xác nhận không còn `CRITICAL`.

Sự cố được đánh dấu **Resolved** vì các tiêu chí khôi phục đã có kết quả thực tế.

## 7. Bài học

- Kiểm tra riêng trạng thái service, listener TCP và phản hồi HTTP.
- Đọc journal để phân biệt service bị dừng theo yêu cầu với service tự crash.
- Luôn xác minh lại sau khi khởi động dịch vụ.
- Không coi tổng trạng thái `WARNING` là thất bại khôi phục nếu cảnh báo còn lại thuộc hạng mục độc lập; cần đọc từng check.
- Giữ log và ảnh sau khi che dữ liệu nhận diện máy trước khi công khai.

## 8. Kết luận

Bài lab mô phỏng thành công Nginx ngừng hoạt động và xác nhận khôi phục thành công thông qua `systemctl`, `journalctl`, `ss`, `curl` và `healthcheck.sh`. Sự cố là có chủ đích trong VM và không phải sự cố ngoài dự kiến trong môi trường production.
