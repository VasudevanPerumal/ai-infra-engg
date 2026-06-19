#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="/var/log/connectivity-check.log"
PING_COUNT="3"
PING_TIMEOUT_SECONDS="5"
OP_TIMEOUT_SECONDS="5"
NC_TIMEOUT_SECONDS="5"

DRY_RUN="false"
CRITICAL_ONLY="false"

TOTAL_PASSED="0"
TOTAL_FAILED="0"
TOTAL_SKIPPED="0"
CRITICAL_FAILURES="0"

usage() {
  cat <<'EOF'
Usage:
  connectivity-check.sh [--dry-run] [--critical-only] [--help]

Options:
  --dry-run        Print checks without executing them
  --critical-only  Run only critical checks
  --help           Show this help message
EOF
}

timestamp() {
  date '+%Y-%m-%d %H:%M:%S%z'
}

ensure_log_file() {
  local log_dir
  log_dir="$(dirname "${LOG_FILE}")"

  if ! sudo mkdir -p "${log_dir}"; then
    echo "Failed to create log directory: ${log_dir}" >&2
    return 1
  fi

  if ! sudo touch "${LOG_FILE}"; then
    echo "Failed to create log file: ${LOG_FILE}" >&2
    return 1
  fi

  if ! sudo chown "$(id -u):$(id -g)" "${LOG_FILE}"; then
    echo "Failed to set ownership on log file: ${LOG_FILE}" >&2
    return 1
  fi

  if ! sudo chmod 0644 "${LOG_FILE}"; then
    echo "Failed to set permissions on log file: ${LOG_FILE}" >&2
    return 1
  fi

  return 0
}

log_line() {
  local line
  line="$1"
  printf '%s %s\n' "$(timestamp)" "${line}" | tee -a "${LOG_FILE}" >/dev/null
}

mark_pass() {
  local name
  local message
  name="$1"
  message="$2"

  TOTAL_PASSED="$((TOTAL_PASSED + 1))"
  log_line "[PASS] ${name} - ${message}"
}

mark_fail() {
  local name
  local message
  local critical
  name="$1"
  message="$2"
  critical="$3"

  TOTAL_FAILED="$((TOTAL_FAILED + 1))"
  if [ "${critical}" = "true" ]; then
    CRITICAL_FAILURES="$((CRITICAL_FAILURES + 1))"
  fi
  log_line "[FAIL] ${name} - ${message}"
}

mark_skip() {
  local name
  local message
  name="$1"
  message="$2"

  TOTAL_SKIPPED="$((TOTAL_SKIPPED + 1))"
  log_line "[SKIP] ${name} - ${message}"
}

should_skip_non_critical() {
  local critical
  critical="$1"

  if [ "${CRITICAL_ONLY}" = "true" ] && [ "${critical}" = "false" ]; then
    return 0
  fi

  return 1
}

run_ping_check() {
  local name
  local host
  local critical
  local output
  local status
  name="$1"
  host="$2"
  critical="$3"

  if should_skip_non_critical "${critical}"; then
    mark_skip "${name}" "Skipped by --critical-only"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    mark_skip "${name}" "[DRY-RUN] Would run: timeout ${OP_TIMEOUT_SECONDS} ping -c${PING_COUNT} -W ${PING_TIMEOUT_SECONDS} ${host}"
    return 0
  fi

  output="$(timeout "${OP_TIMEOUT_SECONDS}" ping -c"${PING_COUNT}" -W "${PING_TIMEOUT_SECONDS}" "${host}" 2>&1)"
  status="$?"

  if [ "${status}" -eq 0 ]; then
    mark_pass "${name}" "Ping to ${host} succeeded"
  else
    mark_fail "${name}" "Ping to ${host} failed (exit ${status}): ${output}" "${critical}"
  fi
}

run_nc_check() {
  local name
  local host
  local port
  local critical
  local output
  local status
  name="$1"
  host="$2"
  port="$3"
  critical="$4"

  if should_skip_non_critical "${critical}"; then
    mark_skip "${name}" "Skipped by --critical-only"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    mark_skip "${name}" "[DRY-RUN] Would run: timeout ${OP_TIMEOUT_SECONDS} nc -zv -w ${NC_TIMEOUT_SECONDS} ${host} ${port}"
    return 0
  fi

  output="$(timeout "${OP_TIMEOUT_SECONDS}" nc -zv -w "${NC_TIMEOUT_SECONDS}" "${host}" "${port}" 2>&1)"
  status="$?"

  if [ "${status}" -eq 0 ]; then
    mark_pass "${name}" "Port ${port} on ${host} is reachable"
  else
    mark_fail "${name}" "Port ${port} on ${host} is unreachable (exit ${status}): ${output}" "${critical}"
  fi
}

run_dns_check() {
  local name
  local critical
  local output
  local status
  name="DNS resolution"
  critical="true"

  if [ "${DRY_RUN}" = "true" ]; then
    mark_skip "${name}" "[DRY-RUN] Would run: timeout ${OP_TIMEOUT_SECONDS} nslookup google.com"
    return 0
  fi

  output="$(timeout "${OP_TIMEOUT_SECONDS}" nslookup google.com 2>&1)"
  status="$?"

  if [ "${status}" -eq 0 ]; then
    mark_pass "${name}" "nslookup google.com succeeded"
  else
    mark_fail "${name}" "nslookup google.com failed (exit ${status}): ${output}" "${critical}"
  fi
}

run_default_route_check() {
  local name
  local critical
  local route_output
  local route_status
  local grep_status
  name="Default route"
  critical="true"

  if [ "${DRY_RUN}" = "true" ]; then
    mark_skip "${name}" "[DRY-RUN] Would run: ip route show | grep default"
    return 0
  fi

  route_output="$(ip route show 2>&1)"
  route_status="$?"

  if [ "${route_status}" -ne 0 ]; then
    mark_fail "${name}" "ip route show failed (exit ${route_status}): ${route_output}" "${critical}"
    return 0
  fi

  printf '%s\n' "${route_output}" | grep -q '^default'
  grep_status="$?"

  if [ "${grep_status}" -eq 0 ]; then
    mark_pass "${name}" "Default route is present"
  else
    mark_fail "${name}" "No default route found" "${critical}"
  fi
}

run_tc_qdisc_check() {
  local name
  local critical
  local output
  local status
  local grep_status
  name="tc qdisc eth0 latency"
  critical="false"

  if should_skip_non_critical "${critical}"; then
    mark_skip "${name}" "Skipped by --critical-only"
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    mark_skip "${name}" "[DRY-RUN] Would run: tc qdisc show dev eth0"
    return 0
  fi

  output="$(tc qdisc show dev eth0 2>&1)"
  status="$?"

  if [ "${status}" -ne 0 ]; then
    mark_fail "${name}" "tc qdisc show failed (exit ${status}): ${output}" "${critical}"
    return 0
  fi

  printf '%s\n' "${output}" | grep -Eq 'netem| delay '
  grep_status="$?"

  if [ "${grep_status}" -eq 0 ]; then
    mark_fail "${name}" "Artificial latency indicators found on eth0: ${output}" "${critical}"
  else
    mark_pass "${name}" "No artificial latency indicators detected on eth0"
  fi
}

print_summary() {
  local summary_line
  summary_line="Summary: passed=${TOTAL_PASSED} failed=${TOTAL_FAILED} skipped=${TOTAL_SKIPPED}"
  log_line "${summary_line}"

  if [ "${CRITICAL_FAILURES}" -gt 0 ]; then
    log_line "Critical failures detected: ${CRITICAL_FAILURES}"
    return 1
  fi

  return 0
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN="true"
        ;;
      --critical-only)
        CRITICAL_ONLY="true"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  if ! ensure_log_file; then
    exit 1
  fi

  log_line "Starting connectivity checks (dry_run=${DRY_RUN}, critical_only=${CRITICAL_ONLY})"

  run_ping_check "Gateway ping" "10.0.0.1" "true"
  run_ping_check "Self ping" "10.0.0.4" "true"
  run_ping_check "Internet ping" "8.8.8.8" "true"

  run_ping_check "App server ping" "10.0.1.10" "false"
  run_ping_check "DB server ping" "10.0.2.10" "false"

  run_nc_check "PostgreSQL port check" "10.0.2.10" "5432" "false"
  run_nc_check "App health port check" "10.0.1.10" "8080" "false"

  run_dns_check
  run_default_route_check
  run_tc_qdisc_check

  if print_summary; then
    exit 0
  fi

  exit 1
}

main "$@"