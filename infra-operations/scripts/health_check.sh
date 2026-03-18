#!/bin/bash
set -euo pipefail

# =============================================================================
# Infrastructure Health Check Script
#
# Performs 6 categories of health checks with structured PASS/WARN/FAIL output.
# Works on both macOS and Linux.
#
# Usage: ./health_check.sh [domain]
#   domain  — optional FQDN for SSL certificate expiry check
#
# Exit codes:
#   0 — all checks passed (may include warnings)
#   1 — one or more checks failed
# =============================================================================

# ---------------------------------------------------------------------------
# Globals — counters for the summary
# ---------------------------------------------------------------------------
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Color support — disabled when stdout is not a terminal
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  COLOR_GREEN="\033[0;32m"
  COLOR_YELLOW="\033[0;33m"
  COLOR_RED="\033[0;31m"
  COLOR_CYAN="\033[0;36m"
  COLOR_BOLD="\033[1m"
  COLOR_RESET="\033[0m"
else
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_CYAN=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

# ---------------------------------------------------------------------------
# Detect operating system once
# ---------------------------------------------------------------------------
OS_TYPE="unknown"
case "$(uname -s)" in
  Darwin) OS_TYPE="macos" ;;
  Linux)  OS_TYPE="linux" ;;
esac

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
print_pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  ${COLOR_GREEN}[PASS]${COLOR_RESET} %s\n" "$1"
}

print_warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "  ${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$1"
}

print_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${COLOR_RED}[FAIL]${COLOR_RESET} %s\n" "$1"
}

print_info() {
  printf "  ${COLOR_CYAN}[INFO]${COLOR_RESET} %s\n" "$1"
}

print_section() {
  printf "\n${COLOR_BOLD}=== %s ===${COLOR_RESET}\n" "$1"
}

# =============================================================================
# Report header
# =============================================================================
print_header() {
  local hostname_val
  hostname_val="$(hostname 2>/dev/null || echo "unknown")"

  local date_val
  date_val="$(date '+%Y-%m-%d %H:%M:%S %Z')"

  local os_info
  if [ "$OS_TYPE" = "macos" ]; then
    os_info="macOS $(sw_vers -productVersion 2>/dev/null || echo "unknown") ($(uname -m))"
  else
    # Prefer /etc/os-release, fall back to uname
    if [ -f /etc/os-release ]; then
      os_info="$(. /etc/os-release && echo "${PRETTY_NAME:-Linux}") ($(uname -m))"
    else
      os_info="$(uname -sr) ($(uname -m))"
    fi
  fi

  printf "${COLOR_BOLD}╔══════════════════════════════════════════════════╗${COLOR_RESET}\n"
  printf "${COLOR_BOLD}║         Infrastructure Health Check              ║${COLOR_RESET}\n"
  printf "${COLOR_BOLD}╚══════════════════════════════════════════════════╝${COLOR_RESET}\n"
  printf "  Hostname : %s\n" "$hostname_val"
  printf "  Date     : %s\n" "$date_val"
  printf "  OS       : %s\n" "$os_info"
}

# =============================================================================
# 1. Disk Usage
#    Warn >80%%, Fail >90%%
# =============================================================================
check_disk() {
  print_section "Disk Usage"

  local df_output

  if [ "$OS_TYPE" = "macos" ]; then
    # -P for POSIX output (one line per filesystem), skip devfs and map* entries
    df_output="$(df -P -h 2>/dev/null | tail -n +2 | grep -v -E '^(devfs|map\s)' || true)"
  else
    # Exclude virtual/pseudo filesystems on Linux
    df_output="$(df -P -h --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=squashfs 2>/dev/null | tail -n +2 || true)"
  fi

  if [ -z "$df_output" ]; then
    print_warn "Could not retrieve disk usage information"
    return
  fi

  while IFS= read -r line; do
    # POSIX df columns: Filesystem Size Used Avail Capacity Mounted-on
    local fs mount_point usage_pct usage_num
    fs="$(echo "$line" | awk '{print $1}')"
    mount_point="$(echo "$line" | awk '{print $6}')"
    usage_pct="$(echo "$line" | awk '{print $5}')"
    # Strip the trailing % sign to get a numeric value
    usage_num="${usage_pct%%%}"

    # Guard against non-numeric values (e.g. header remnants)
    if ! [[ "$usage_num" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if [ "$usage_num" -gt 90 ]; then
      print_fail "Disk ${mount_point} (${fs}) at ${usage_pct} used — exceeds 90%"
    elif [ "$usage_num" -gt 80 ]; then
      print_warn "Disk ${mount_point} (${fs}) at ${usage_pct} used — exceeds 80%"
    else
      print_pass "Disk ${mount_point} (${fs}) at ${usage_pct} used"
    fi
  done <<< "$df_output"
}

# =============================================================================
# 2. Memory
#    Warn >85%% usage. Also report swap.
# =============================================================================
check_memory() {
  print_section "Memory"

  if [ "$OS_TYPE" = "macos" ]; then
    # Total physical memory in bytes via sysctl
    local total_bytes
    total_bytes="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    local total_mb=$((total_bytes / 1024 / 1024))

    # Parse vm_stat — page size and page counts
    local page_size
    page_size="$(vm_stat 2>/dev/null | head -1 | grep -oE '[0-9]+' || echo 4096)"

    # vm_stat fields vary ("Pages free:" has value in $3, "Pages wired down:" in $4).
    # Use $NF (last field) which always holds the numeric value with a trailing period.
    local pages_free pages_active pages_wired
    pages_free="$(vm_stat 2>/dev/null      | awk '/Pages free/{gsub(/\./,"",$NF); print $NF}' || echo 0)"
    pages_active="$(vm_stat 2>/dev/null    | awk '/Pages active/{gsub(/\./,"",$NF); print $NF}' || echo 0)"
    pages_wired="$(vm_stat 2>/dev/null     | awk '/Pages wired down/{gsub(/\./,"",$NF); print $NF}' || echo 0)"

    # "Used" = active + wired (inactive/speculative are reclaimable)
    local used_pages=$((pages_active + pages_wired))
    local used_bytes=$((used_pages * page_size))
    local used_mb=$((used_bytes / 1024 / 1024))

    local usage_pct=0
    if [ "$total_mb" -gt 0 ]; then
      usage_pct=$((used_mb * 100 / total_mb))
    fi

    if [ "$usage_pct" -gt 85 ]; then
      print_warn "Memory usage: ${used_mb}MB / ${total_mb}MB (${usage_pct}%) — exceeds 85%"
    else
      print_pass "Memory usage: ${used_mb}MB / ${total_mb}MB (${usage_pct}%)"
    fi

    # Swap on macOS via sysctl vm.swapusage
    local swap_info
    swap_info="$(sysctl -n vm.swapusage 2>/dev/null || echo "")"
    if [ -n "$swap_info" ]; then
      local swap_total swap_used
      swap_total="$(echo "$swap_info" | grep -oE 'total = [0-9]+\.[0-9]+M' | grep -oE '[0-9]+\.[0-9]+' || echo "0")"
      swap_used="$(echo "$swap_info" | grep -oE 'used = [0-9]+\.[0-9]+M' | grep -oE '[0-9]+\.[0-9]+' || echo "0")"
      print_info "Swap usage: ${swap_used}MB / ${swap_total}MB"
    fi

  else
    # Linux — use free -m
    local mem_line
    mem_line="$(free -m 2>/dev/null | awk '/^Mem:/' || echo "")"
    if [ -z "$mem_line" ]; then
      print_warn "Could not retrieve memory information"
      return
    fi

    local total_mb used_mb available_mb usage_pct
    total_mb="$(echo "$mem_line" | awk '{print $2}')"
    # "used" from free includes buffers/cache; "available" is more useful
    available_mb="$(echo "$mem_line" | awk '{print $7}')"
    used_mb=$((total_mb - available_mb))

    usage_pct=0
    if [ "$total_mb" -gt 0 ]; then
      usage_pct=$((used_mb * 100 / total_mb))
    fi

    if [ "$usage_pct" -gt 85 ]; then
      print_warn "Memory usage: ${used_mb}MB / ${total_mb}MB (${usage_pct}%) — exceeds 85%"
    else
      print_pass "Memory usage: ${used_mb}MB / ${total_mb}MB (${usage_pct}%)"
    fi

    # Swap on Linux
    local swap_line
    swap_line="$(free -m 2>/dev/null | awk '/^Swap:/' || echo "")"
    if [ -n "$swap_line" ]; then
      local swap_total swap_used swap_pct
      swap_total="$(echo "$swap_line" | awk '{print $2}')"
      swap_used="$(echo "$swap_line" | awk '{print $3}')"
      swap_pct=0
      if [ "$swap_total" -gt 0 ]; then
        swap_pct=$((swap_used * 100 / swap_total))
      fi

      if [ "$swap_total" -eq 0 ]; then
        print_info "No swap configured"
      elif [ "$swap_pct" -gt 10 ]; then
        print_warn "Swap usage: ${swap_used}MB / ${swap_total}MB (${swap_pct}%) — exceeds 10%"
      else
        print_pass "Swap usage: ${swap_used}MB / ${swap_total}MB (${swap_pct}%)"
      fi
    fi
  fi
}

# =============================================================================
# 3. CPU / Load Average
#    Warn if 1-min load average exceeds the number of CPU cores.
# =============================================================================
check_cpu() {
  print_section "CPU Load"

  # Determine number of CPU cores
  local cores=1
  if [ "$OS_TYPE" = "macos" ]; then
    cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
  else
    cores="$(nproc 2>/dev/null || echo 1)"
  fi

  # Extract 1-minute load average from uptime
  # uptime output varies, but the load averages are always the last 3 numbers
  local load_1min
  load_1min="$(uptime | awk -F'load average[s]?: ' '{print $2}' | awk -F'[, ]+' '{print $1}')"

  # Fallback: try alternate parsing if the above produced nothing
  if [ -z "$load_1min" ]; then
    load_1min="$(uptime | grep -oE 'load average[s]?: [0-9.]+' | grep -oE '[0-9.]+$' || echo "0")"
  fi

  # Compare using integer math (multiply by 100 to preserve 2 decimal places)
  local load_x100 cores_x100
  load_x100="$(printf '%s' "$load_1min" | awk '{printf "%d", $1 * 100}')"
  cores_x100=$((cores * 100))

  if [ "$load_x100" -gt "$cores_x100" ]; then
    print_warn "1-min load average ${load_1min} exceeds core count (${cores} cores)"
  else
    print_pass "1-min load average ${load_1min} within capacity (${cores} cores)"
  fi
}

# =============================================================================
# 4. Service Ports
#    Check common service ports. Report as INFO if not listening (not a failure).
# =============================================================================
check_ports() {
  print_section "Service Ports"

  # Associative-style list: port:label
  local ports="80:HTTP 443:HTTPS 5432:PostgreSQL 6379:Redis 3000:Dev_Server 8080:Alt_HTTP"

  for entry in $ports; do
    local port="${entry%%:*}"
    local label="${entry##*:}"
    local listening=false

    if [ "$OS_TYPE" = "macos" ]; then
      # lsof — look for LISTEN state on the given port
      if lsof -iTCP:"$port" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
        listening=true
      fi
    else
      # ss — look for LISTEN on the given port
      if ss -tlnp 2>/dev/null | grep -qE ":${port}\b"; then
        listening=true
      fi
    fi

    if [ "$listening" = true ]; then
      print_pass "Port ${port} (${label}) is listening"
    else
      print_info "Port ${port} (${label}) is not listening"
    fi
  done
}

# =============================================================================
# 5. SSL Certificate Expiry
#    Only runs when a domain argument is provided.
#    Warn if certificate expires in fewer than 30 days.
# =============================================================================
check_ssl() {
  local domain="${1:-}"

  print_section "SSL Certificates"

  if [ -z "$domain" ]; then
    print_info "No domain provided — skipping SSL check"
    return
  fi

  # Verify openssl is available
  if ! command -v openssl >/dev/null 2>&1; then
    print_warn "openssl not found — cannot check SSL certificate"
    return
  fi

  # Connect and extract the certificate expiry date
  local expiry_raw
  expiry_raw="$(echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//' || echo "")"

  if [ -z "$expiry_raw" ]; then
    print_fail "Could not retrieve SSL certificate for ${domain}"
    return
  fi

  # Convert expiry date to epoch seconds (handles macOS vs Linux date)
  local expiry_epoch
  if [ "$OS_TYPE" = "macos" ]; then
    # macOS date: -jf to parse, output as epoch
    expiry_epoch="$(date -jf '%b %d %H:%M:%S %Y %Z' "$expiry_raw" '+%s' 2>/dev/null || echo "")"
    # Fallback: try alternate format without timezone name
    if [ -z "$expiry_epoch" ]; then
      expiry_epoch="$(date -jf '%b  %d %H:%M:%S %Y %Z' "$expiry_raw" '+%s' 2>/dev/null || echo "")"
    fi
  else
    # GNU date: --date can parse the openssl format directly
    expiry_epoch="$(date --date="$expiry_raw" '+%s' 2>/dev/null || echo "")"
  fi

  if [ -z "$expiry_epoch" ]; then
    print_warn "Could not parse certificate expiry date: ${expiry_raw}"
    return
  fi

  local now_epoch
  now_epoch="$(date '+%s')"
  local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

  if [ "$days_left" -lt 0 ]; then
    print_fail "SSL certificate for ${domain} EXPIRED ${days_left#-} days ago"
  elif [ "$days_left" -lt 30 ]; then
    print_warn "SSL certificate for ${domain} expires in ${days_left} days (${expiry_raw})"
  else
    print_pass "SSL certificate for ${domain} valid for ${days_left} days (${expiry_raw})"
  fi
}

# =============================================================================
# 6. Docker
#    Skip entirely if Docker is not installed or daemon is not running.
# =============================================================================
check_docker() {
  print_section "Docker"

  # Check if docker CLI is installed
  if ! command -v docker >/dev/null 2>&1; then
    print_info "Docker is not installed — skipping"
    return
  fi

  # Check if the daemon is responding
  if ! docker info >/dev/null 2>&1; then
    print_info "Docker daemon is not running — skipping"
    return
  fi

  # Count running and stopped containers
  local running stopped
  running="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
  stopped="$(docker ps -q --filter 'status=exited' 2>/dev/null | wc -l | tr -d ' ')"
  print_pass "Containers: ${running} running, ${stopped} stopped"

  # Check for unhealthy containers
  local unhealthy
  unhealthy="$(docker ps --filter 'health=unhealthy' --format '{{.Names}}' 2>/dev/null || echo "")"
  if [ -n "$unhealthy" ]; then
    while IFS= read -r name; do
      print_fail "Container '${name}' is unhealthy"
    done <<< "$unhealthy"
  else
    print_pass "No unhealthy containers"
  fi

  # Check for restarting containers
  local restarting
  restarting="$(docker ps --filter 'status=restarting' --format '{{.Names}}' 2>/dev/null || echo "")"
  if [ -n "$restarting" ]; then
    while IFS= read -r name; do
      print_warn "Container '${name}' is restarting"
    done <<< "$restarting"
  else
    print_pass "No restarting containers"
  fi

  # Docker disk usage summary
  local disk_usage
  disk_usage="$(docker system df 2>/dev/null | tail -n +2 || echo "")"
  if [ -n "$disk_usage" ]; then
    print_info "Docker disk usage:"
    while IFS= read -r line; do
      printf "         %s\n" "$line"
    done <<< "$disk_usage"
  fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  printf "\n${COLOR_BOLD}══════════════════════════════════════════════════${COLOR_RESET}\n"
  printf "${COLOR_BOLD}  Summary${COLOR_RESET}\n"
  printf "${COLOR_BOLD}══════════════════════════════════════════════════${COLOR_RESET}\n"
  printf "  ${COLOR_GREEN}PASS : %d${COLOR_RESET}\n" "$PASS_COUNT"
  printf "  ${COLOR_YELLOW}WARN : %d${COLOR_RESET}\n" "$WARN_COUNT"
  printf "  ${COLOR_RED}FAIL : %d${COLOR_RESET}\n" "$FAIL_COUNT"
  printf "${COLOR_BOLD}══════════════════════════════════════════════════${COLOR_RESET}\n"

  if [ "$FAIL_COUNT" -gt 0 ]; then
    printf "  ${COLOR_RED}Result: FAILED — %d check(s) require attention${COLOR_RESET}\n\n" "$FAIL_COUNT"
  elif [ "$WARN_COUNT" -gt 0 ]; then
    printf "  ${COLOR_YELLOW}Result: PASSED with %d warning(s)${COLOR_RESET}\n\n" "$WARN_COUNT"
  else
    printf "  ${COLOR_GREEN}Result: ALL CHECKS PASSED${COLOR_RESET}\n\n"
  fi
}

# =============================================================================
# Main
# =============================================================================
main() {
  local domain="${1:-}"

  print_header

  check_disk
  check_memory
  check_cpu
  check_ports
  check_ssl "$domain"
  check_docker

  print_summary

  # Exit with failure if any check FAILed
  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
}

main "$@"
