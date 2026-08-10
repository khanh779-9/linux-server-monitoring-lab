# Checklist ảnh minh chứng và dữ liệu trước khi công khai

Tài liệu này ghi rõ ảnh nào đã có trong repository và ảnh nào nên chụp bổ sung. **Không tạo ảnh giả**: chỉ thêm ảnh chụp từ chính máy lab, có kết quả thực tế.

## 1. Ảnh đang có trong `images/`

| File | Nội dung | Được tham chiếu ở |
|---|---|---|
| `ram_and_disk_check.png` | RAM, filesystem và thiết bị lưu trữ | `README.md`, `architecture.md` |
| `host_check.png` | Hệ điều hành/kernel và thông tin môi trường | `architecture.md` |
| `env_check.png` | Tổng hợp kiểm tra môi trường ban đầu | `architecture.md` |
| `dns_resole_check.png` | Kết quả kiểm tra DNS cơ bản | `README.md`, `network-troubleshooting.md` |
| `service_monitor.png` | Nginx, listener và access log khi dịch vụ hoạt động | `README.md`, `nginx-deployment.md`, báo cáo sự cố |
| `services_err_and_ports_check.png` | Kết quả kiểm tra unit lỗi và socket | `README.md`, `architecture.md`, `nginx-deployment.md` |
| `grafana_dashboard.png` | Dashboard Grafana: Node Exporter Status, CPU, RAM, Disk | `prometheus-monitoring.md`, `README.md` |
| `prometheus_node_check_cpu.png` | Backup `prometheus.yml`, promtool check, restart, hai service `active`, readiness, truy vấn `up` và RAM qua API | `prometheus-monitoring.md`, `README.md` |

Tám ảnh trên là bản gốc, được giữ nguyên như khi chụp. Một số ảnh có hostname/dấu nhắc terminal, địa chỉ mạng, gateway, MAC hoặc mã định danh máy ảo. Cần chỉnh sửa/che thông tin trên bản dùng để public; không cần sửa bản gốc nếu muốn giữ nó trong thư mục làm việc riêng.

## 2. Ảnh chụp bổ sung

| Tên file đề xuất | Nội dung cần thể hiện | Tài liệu nên nhúng |
|---|---|---|
| `healthcheck-summary.png` | Phần `SUMMARY` của `healthcheck.sh`, gồm tổng trạng thái và số lượng OK/WARNING/CRITICAL | `healthcheck-script.md`, `README.md` |
| `systemd-timer-status.png` | `systemctl --user status linux-healthcheck.timer` và thời điểm trigger kế tiếp | `systemd-timer.md` |
| `nginx-incident-down.png` | Service inactive, HTTP thất bại và không có listener trong lúc mô phỏng | `incident-reports/nginx-service-down.md` |
| `nginx-incident-recovered.png` | Service active, cổng 80 lắng nghe và HTTP 200 sau khôi phục | `incident-reports/nginx-service-down.md` |
| `backup-restore-sha256.png` | `sha256sum -c` trả `index.html: OK` và kiểm tra HTTP sau restore | `backup-restore.md` |
| `network-baseline.png` | Interface/route, ping summary, DNS và HTTP status sau khi che địa chỉ | `network-troubleshooting.md` |
| `prometheus-targets.png` | Trang Prometheus Targets cho thấy job `node` ở trạng thái UP | `prometheus-monitoring.md` |

Nếu chụp terminal, cắt hoặc che hostname, IP/MAC, gateway, tên user, mã định danh VM và các thông tin nội bộ không cần thiết. Không dùng địa chỉ IP hiện tại làm ví dụ cố định trong tài liệu.
