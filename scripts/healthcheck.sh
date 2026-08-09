#!/usr/bin/env bash
# Linux Server & Network Monitoring Lab
# Point-in-time health check for Linux resources, basic networking, DNS and Nginx.
# Reports deliberately omit hostname, IP/MAC addresses, gateways and service names in failure lists.

set -uo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$PROJECT_DIR/reports"

# Tunable thresholds (can be overridden using environment variables).
CPU_WARN="${CPU_WARN:-80}"
CPU_CRIT="${CPU_CRIT:-95}"
MEM_WARN="${MEM_WARN:-80}"
MEM_CRIT="${MEM_CRIT:-90}"
DISK_WARN="${DISK_WARN:-80}"
DISK_CRIT="${DISK_CRIT:-90}"
LOAD_WARN_PER_CORE="${LOAD_WARN_PER_CORE:-1.0}"
LOAD_CRIT_PER_CORE="${LOAD_CRIT_PER_CORE:-2.0}"
CPU_SAMPLE_SECONDS="${CPU_SAMPLE_SECONDS:-1}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-4}"
HTTP_URL="${HTTP_URL:-http://127.0.0.1/}"
DNS_TEST_DOMAIN="${DNS_TEST_DOMAIN:-google.com}"

is_number() { [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]; }
is_integer() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }

validate_pair() {
    local label="$1" warn="$2" crit="$3" max="${4:-}"
    if ! is_number "$warn" || ! is_number "$crit"; then
        printf 'ERROR: %s thresholds must be numeric.\n' "$label" >&2
        exit 2
    fi
    if ! awk -v w="$warn" -v c="$crit" 'BEGIN { exit !(w < c) }'; then
        printf 'ERROR: %s warning threshold must be lower than critical threshold.\n' "$label" >&2
        exit 2
    fi
    if [[ -n "$max" ]] && ! awk -v w="$warn" -v c="$crit" -v m="$max" 'BEGIN { exit !(w >= 0 && c <= m) }'; then
        printf 'ERROR: %s thresholds must be between 0 and %s.\n' "$label" "$max" >&2
        exit 2
    fi
}

validate_pair CPU "$CPU_WARN" "$CPU_CRIT" 100
validate_pair memory "$MEM_WARN" "$MEM_CRIT" 100
validate_pair disk "$DISK_WARN" "$DISK_CRIT" 100
validate_pair load-per-core "$LOAD_WARN_PER_CORE" "$LOAD_CRIT_PER_CORE"
if ! is_integer "$CPU_SAMPLE_SECONDS" || (( CPU_SAMPLE_SECONDS < 1 || CPU_SAMPLE_SECONDS > 5 )); then
    printf 'ERROR: CPU_SAMPLE_SECONDS must be an integer from 1 to 5.\n' >&2
    exit 2
fi
if ! is_integer "$HTTP_TIMEOUT" || (( HTTP_TIMEOUT < 1 || HTTP_TIMEOUT > 20 )); then
    printf 'ERROR: HTTP_TIMEOUT must be an integer from 1 to 20.\n' >&2
    exit 2
fi

if ! mkdir -p "$REPORT_DIR"; then
    printf 'ERROR: Cannot create reports directory.\n' >&2
    exit 2
fi
REPORT_FILE="$(mktemp "$REPORT_DIR/healthcheck-$(date +%Y%m%d-%H%M%S)-XXXXXX.txt")" || {
    printf 'ERROR: Cannot create a report file.\n' >&2
    exit 2
}

OK_COUNT=0
WARNING_COUNT=0
CRITICAL_COUNT=0

log() {
    printf '%s\n' "$*" | tee -a "$REPORT_FILE"
}

section() {
    log ""
    log "===== $1 ====="
}

record() {
    local level="$1" check="$2" detail="$3"
    case "$level" in
        OK)       ((OK_COUNT += 1)) ;;
        WARNING)  ((WARNING_COUNT += 1)) ;;
        CRITICAL) ((CRITICAL_COUNT += 1)) ;;
    esac
    log "[$level] $check: $detail"
}

number_ge() {
    awk -v value="$1" -v threshold="$2" 'BEGIN { exit !(value >= threshold) }'
}

classify_threshold() {
    local value="$1" warn="$2" crit="$3"
    if number_ge "$value" "$crit"; then
        printf 'CRITICAL'
    elif number_ge "$value" "$warn"; then
        printf 'WARNING'
    else
        printf 'OK'
    fi
}

read_cpu_counters() {
    awk '$1 == "cpu" { idle = $5 + $6; total = 0; for (i = 2; i <= NF; i++) total += $i; printf "%.0f %.0f\n", idle, total; exit }' /proc/stat 2>/dev/null
}

{
    log '=============================================='
    log ' LINUX SERVER & NETWORK MONITORING LAB'
    log ' HEALTHCHECK REPORT'
    log '=============================================='
    log "Collected at: $(date '+%Y-%m-%d %H:%M:%S %z')"
    log 'Privacy: hostname, addresses, MACs, gateways and raw failed-unit names are omitted.'
    log "Thresholds: CPU ${CPU_WARN}/${CPU_CRIT}%, memory ${MEM_WARN}/${MEM_CRIT}%, disk ${DISK_WARN}/${DISK_CRIT}%, load/core ${LOAD_WARN_PER_CORE}/${LOAD_CRIT_PER_CORE}."

    section 'OPERATING SYSTEM'
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        log "Distribution: ${PRETTY_NAME:-Unknown}"
    else
        record WARNING 'Distribution' '/etc/os-release unavailable'
    fi
    log "Kernel: $(uname -r 2>/dev/null || printf 'Unknown')"
    log "Architecture: $(uname -m 2>/dev/null || printf 'Unknown')"
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virt="$(systemd-detect-virt 2>/dev/null || true)"
        log "Virtualization: ${virt:-none/unknown}"
    else
        log 'Virtualization: systemd-detect-virt unavailable'
    fi
    if command -v uptime >/dev/null 2>&1; then
        log "Uptime: $(uptime -p 2>/dev/null || printf 'unavailable')"
    else
        log 'Uptime: uptime command unavailable'
    fi

    section 'CPU AND LOAD'
    CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf '1')"
    if ! is_integer "$CPU_CORES" || (( CPU_CORES < 1 )); then CPU_CORES=1; fi
    log "Online CPU cores: $CPU_CORES"
    cpu_before="$(read_cpu_counters)"
    if [[ -n "$cpu_before" ]]; then
        sleep "$CPU_SAMPLE_SECONDS"
        cpu_after="$(read_cpu_counters)"
        if [[ -n "$cpu_after" ]]; then
            read -r idle_before total_before <<< "$cpu_before"
            read -r idle_after total_after <<< "$cpu_after"
            cpu_percent="$(awk -v i1="$idle_before" -v t1="$total_before" -v i2="$idle_after" -v t2="$total_after" 'BEGIN { dt=t2-t1; di=i2-i1; if (dt > 0) { p=(dt-di)*100/dt; if (p<0) p=0; if (p>100) p=100; printf "%.1f", p } else print "" }')"
            if [[ -n "$cpu_percent" ]]; then
                level="$(classify_threshold "$cpu_percent" "$CPU_WARN" "$CPU_CRIT")"
                record "$level" 'CPU utilization' "${cpu_percent}% (sampled over ${CPU_SAMPLE_SECONDS}s; thresholds ${CPU_WARN}/${CPU_CRIT}%)"
            else
                record WARNING 'CPU utilization' 'Unable to calculate CPU usage from /proc/stat'
            fi
        else
            record WARNING 'CPU utilization' 'Unable to read second /proc/stat sample'
        fi
    else
        record WARNING 'CPU utilization' '/proc/stat unavailable'
    fi
    if [[ -r /proc/loadavg ]]; then
        read -r load1 load5 load15 _ < /proc/loadavg
        load_level="$(awk -v load_value="$load1" -v cores="$CPU_CORES" -v warn="$LOAD_WARN_PER_CORE" -v crit="$LOAD_CRIT_PER_CORE" 'BEGIN { ratio=load_value/cores; if (ratio >= crit) print "CRITICAL"; else if (ratio >= warn) print "WARNING"; else print "OK" }')"
        load_ratio="$(awk -v load_value="$load1" -v cores="$CPU_CORES" 'BEGIN { printf "%.2f", load_value/cores }')"
        record "$load_level" 'Load average' "1m=${load1}, 5m=${load5}, 15m=${load15}; 1m load/core=${load_ratio} (not the same as CPU utilization)"
    else
        record WARNING 'Load average' '/proc/loadavg unavailable'
    fi

    section 'MEMORY'
    if [[ -r /proc/meminfo ]]; then
        mem_stats="$(awk '
            /^MemTotal:/ { total=$2 }
            /^MemAvailable:/ { available=$2; has_available=1 }
            /^MemFree:/ { free_mem=$2 }
            /^Buffers:/ { buffers=$2 }
            /^Cached:/ { cached=$2 }
            END {
                if (!has_available) available=free_mem+buffers+cached
                if (total > 0) {
                    used=total-available
                    printf "%.2f %.2f %.2f %.1f\n", total/1048576, used/1048576, available/1048576, used*100/total
                }
            }
        ' /proc/meminfo)"
        if [[ -n "$mem_stats" ]]; then
            read -r mem_total mem_used mem_available mem_pct <<< "$mem_stats"
            mem_level="$(classify_threshold "$mem_pct" "$MEM_WARN" "$MEM_CRIT")"
            record "$mem_level" 'Memory utilization' "${mem_pct}% used; total=${mem_total} GiB, used≈${mem_used} GiB, available≈${mem_available} GiB (thresholds ${MEM_WARN}/${MEM_CRIT}%)"
        else
            record WARNING 'Memory utilization' 'Unable to parse /proc/meminfo'
        fi
    else
        record WARNING 'Memory utilization' '/proc/meminfo unavailable'
    fi

    section 'ROOT FILESYSTEM'
    if command -v df >/dev/null 2>&1; then
        disk_stats="$(df -Pk / 2>/dev/null | awk 'NR==2 { gsub(/%/, "", $5); printf "%.2f %.2f %.2f %s\n", $2/1048576, $3/1048576, $4/1048576, $5 }')"
        if [[ -n "$disk_stats" ]]; then
            read -r disk_total disk_used disk_available disk_pct <<< "$disk_stats"
            disk_level="$(classify_threshold "$disk_pct" "$DISK_WARN" "$DISK_CRIT")"
            record "$disk_level" 'Root filesystem usage' "${disk_pct}% used; total=${disk_total} GiB, used=${disk_used} GiB, available=${disk_available} GiB (thresholds ${DISK_WARN}/${DISK_CRIT}%)"
        else
            record WARNING 'Root filesystem usage' 'Unable to parse df output'
        fi
    else
        record WARNING 'Root filesystem usage' 'df command unavailable'
    fi

    section 'NETWORK AND DNS'
    if command -v ip >/dev/null 2>&1; then
        interface_count="$(ip -o link show up 2>/dev/null | awk -F': ' '$2 !~ /^lo(@|$)/ {count++} END {print count+0}')"
        if (( interface_count > 0 )); then
            record OK 'Network interfaces' "${interface_count} non-loopback interface(s) are UP; names and addresses omitted"
        else
            record WARNING 'Network interfaces' 'No non-loopback interface reported UP'
        fi
        if ip route show default 2>/dev/null | grep -q .; then
            record OK 'Default route' 'Present; gateway omitted'
        else
            record WARNING 'Default route' 'No default route detected'
        fi
    else
        record WARNING 'Network interfaces and route' 'ip command unavailable'
    fi
    if command -v getent >/dev/null 2>&1; then
        if getent ahosts "$DNS_TEST_DOMAIN" >/dev/null 2>&1; then
            record OK 'DNS resolution' "Lookup for configured test domain succeeded; resolved addresses omitted"
        else
            record WARNING 'DNS resolution' 'Lookup failed or returned no addresses; check connectivity and resolver configuration'
        fi
    else
        record WARNING 'DNS resolution' 'getent command unavailable'
    fi

    section 'SYSTEMD SERVICES'
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        failed_units="$(systemctl --failed --no-legend --no-pager 2>/dev/null)"
        systemctl_rc=$?
        if (( systemctl_rc != 0 )); then
            record WARNING 'Failed systemd units' 'Unable to query systemd at this time'
        else
            failed_count="$(printf '%s\n' "$failed_units" | awk 'NF {n++} END {print n+0}')"
            if (( failed_count == 0 )); then
                record OK 'Failed systemd units' 'No failed units listed'
            else
                record CRITICAL 'Failed systemd units' "${failed_count} failed unit(s); unit names omitted from this report"
            fi
        fi
    else
        record WARNING 'Failed systemd units' 'systemd is not available in this runtime; check manually on the target host'
    fi

    section 'NGINX AND HTTP'
    nginx_installed=false
    nginx_active=false
    if command -v nginx >/dev/null 2>&1 || [[ -x /usr/sbin/nginx ]] || [[ -x /usr/local/sbin/nginx ]]; then
        nginx_installed=true
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]] && systemctl is-active --quiet nginx 2>/dev/null; then
            nginx_active=true
        elif command -v pgrep >/dev/null 2>&1 && pgrep -x nginx >/dev/null 2>&1; then
            nginx_active=true
        fi
        if [[ "$nginx_active" == true ]]; then
            record OK 'Nginx service' 'Process/service appears active'
        else
            record CRITICAL 'Nginx service' 'Nginx is installed but does not appear active; inspect systemctl status and journalctl'
        fi
    else
        record WARNING 'Nginx service' 'Nginx is not installed; service check is optional until this lab deploys Nginx'
    fi

    if command -v ss >/dev/null 2>&1; then
        port80_listening="$(ss -H -ltn 2>/dev/null | awk '$4 ~ /:80$/ {found=1} END {print found+0}')"
        if [[ "$port80_listening" == 1 ]]; then
            record OK 'TCP port 80' 'A listening socket was detected; local address omitted'
        else
            record WARNING 'TCP port 80' 'No listener detected on port 80; this is expected if the web service is not configured for HTTP/80'
        fi
        listener_count="$(ss -H -lntu 2>/dev/null | awk 'NF {n++} END {print n+0}')"
        if (( listener_count > 0 )); then
            record OK 'Listening sockets' "${listener_count} TCP/UDP listening socket(s); endpoints omitted"
        else
            record WARNING 'Listening sockets' 'No listening TCP/UDP sockets detected'
        fi
    else
        record WARNING 'Listening sockets' 'ss command unavailable'
    fi

    if command -v curl >/dev/null 2>&1; then
        http_code="$(curl --silent --show-error --output /dev/null --connect-timeout 2 --max-time "$HTTP_TIMEOUT" --write-out '%{http_code}' "$HTTP_URL" 2>/dev/null)"
        curl_rc=$?
        if (( curl_rc == 0 )) && [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
            if (( 10#$http_code >= 200 && 10#$http_code < 400 )); then
                record OK 'HTTP endpoint' "HTTP ${http_code}; endpoint URL omitted from report"
            elif (( 10#$http_code >= 500 )); then
                record CRITICAL 'HTTP endpoint' "Server returned HTTP ${http_code}; endpoint URL omitted from report"
            else
                record WARNING 'HTTP endpoint' "HTTP ${http_code}; check the expected page and server configuration"
            fi
        else
            if [[ "$nginx_installed" == true ]]; then
                record CRITICAL 'HTTP endpoint' "No successful HTTP response; inspect Nginx status, logs and URL configuration"
            else
                record WARNING 'HTTP endpoint' 'No HTTP response; install/start a web server or configure HTTP_URL for the endpoint to test'
            fi
        fi
    else
        record WARNING 'HTTP endpoint' 'curl command unavailable; HTTP check skipped'
    fi

    section 'SUMMARY'
    if (( CRITICAL_COUNT > 0 )); then
        OVERALL='CRITICAL'
        EXIT_CODE=2
    elif (( WARNING_COUNT > 0 )); then
        OVERALL='WARNING'
        EXIT_CODE=1
    else
        OVERALL='OK'
        EXIT_CODE=0
    fi
    log "Overall status: $OVERALL"
    log "Check counts: OK=$OK_COUNT WARNING=$WARNING_COUNT CRITICAL=$CRITICAL_COUNT"
    log 'Suggested next steps:'
    log '- For CRITICAL checks, investigate first; inspect the relevant service journal/logs and rerun the healthcheck after recovery.'
    log '- For WARNING checks, decide whether the condition is expected for this lab before changing configuration.'
    log '- Compare reports over time; this script samples the current state and is not continuous monitoring.'
    log '- Review the generated report before sharing it publicly.'
} 2>&1

printf '\nReport saved to: %s\n' "$REPORT_FILE"
printf 'Overall status: %s (exit code %s)\n' "$OVERALL" "$EXIT_CODE"
exit "$EXIT_CODE"
