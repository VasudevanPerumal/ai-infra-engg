#!/usr/bin/env bash
set -euo pipefail

HEALTH_URL="http://localhost:80"
CHECK_INTERVAL_SECONDS="30"
APACHE_SERVICE="apache2"
LOG_FILE="/var/log/payment-monitor.log"
THREAD_DUMP_DIR="/var/log/apache-thread-dumps"
PID_FILE="/tmp/payment-monitor.pid"
STATE_FILE="/tmp/payment-monitor.state"
LOCK_FILE="/tmp/payment-monitor.lock"
CURL_TIMEOUT_SECONDS="10"

RUN_MODE="daemon"
DRY_RUN="false"
ROLLBACK_ONLY="false"

usage() {
  cat <<'EOF'
Usage:
  payment-monitor.sh [--daemon] [--dry-run]
  payment-monitor.sh --once [--dry-run]
  payment-monitor.sh --rollback [--dry-run]

Options:
  --daemon     Run monitor loop continuously (default)
  --once       Run one health check cycle and exit
  --rollback   Stop monitor loop (if running) and restore original apache state
  --dry-run    Print what would happen without restarting/stopping/starting apache
  --help       Show this help message
EOF
}

log() {
  local message="$1"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S%z')"
  echo "${timestamp} ${message}" | sudo tee -a "${LOG_FILE}" >/dev/null
}

ensure_log_targets() {
  sudo touch "${LOG_FILE}"
  sudo chmod 0644 "${LOG_FILE}"
  sudo mkdir -p "${THREAD_DUMP_DIR}"
  sudo chmod 0755 "${THREAD_DUMP_DIR}"
}

is_apache_active() {
  if systemctl is-active --quiet "${APACHE_SERVICE}"; then
    return 0
  fi
  return 1
}

write_state_file() {
  local mode="$1"
  local original_state="$2"

  cat <<EOF | sudo tee "${STATE_FILE}" >/dev/null
mode=${mode}
original_apache_state=${original_state}
EOF
}

read_state_value() {
  local key="$1"
  local value=""

  if [ -f "${STATE_FILE}" ]; then
    value="$(grep -E "^${key}=" "${STATE_FILE}" | head -n 1 | cut -d'=' -f2- || true)"
  fi

  echo "${value}"
}

capture_original_apache_state() {
  local original_state

  if is_apache_active; then
    original_state="active"
  else
    original_state="inactive"
  fi

  write_state_file "${RUN_MODE}" "${original_state}"
  log "Captured original apache state: ${original_state}"
}

remove_state_file() {
  if [ -f "${STATE_FILE}" ]; then
    sudo rm -f "${STATE_FILE}"
  fi
}

remove_pid_file() {
  if [ -f "${PID_FILE}" ]; then
    rm -f "${PID_FILE}"
  fi
}

read_pid_file() {
  local pid=""

  if [ -f "${PID_FILE}" ]; then
    pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  fi

  echo "${pid}"
}

is_pid_running() {
  local pid="$1"

  if [ -z "${pid}" ]; then
    return 1
  fi

  if kill -0 "${pid}" 2>/dev/null; then
    return 0
  fi

  return 1
}

acquire_monitor_lock() {
  exec 9>"${LOCK_FILE}"

  if ! flock -n 9; then
    local running_pid
    running_pid="$(read_pid_file)"

    if ! is_pid_running "${running_pid}"; then
      running_pid="unknown"
    fi

    log "Monitor already running with PID ${running_pid}. Exiting for idempotency."
    exit 0
  fi

  echo "$$" > "${PID_FILE}"
}

capture_apache_thread_dump() {
  local timestamp
  local dump_file
  local main_pid

  timestamp="$(date '+%Y%m%d-%H%M%S')"
  dump_file="${THREAD_DUMP_DIR}/apache-thread-dump-${timestamp}.log"
  main_pid="$(systemctl show -p MainPID --value "${APACHE_SERVICE}" || true)"

  if [ -z "${main_pid}" ] || [ "${main_pid}" = "0" ]; then
    log "No apache main PID found; skipping thread dump."
    return 0
  fi

  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would capture apache thread dump for PID ${main_pid} into ${dump_file}."
    return 0
  fi

  if command -v gstack >/dev/null 2>&1; then
    sudo gstack "${main_pid}" | sudo tee "${dump_file}" >/dev/null
    log "Captured apache thread dump with gstack: ${dump_file}"
    return 0
  fi

  if command -v pstack >/dev/null 2>&1; then
    sudo pstack "${main_pid}" | sudo tee "${dump_file}" >/dev/null
    log "Captured apache thread dump with pstack: ${dump_file}"
    return 0
  fi

  {
    echo "gstack/pstack unavailable; fallback thread/process snapshot"
    sudo ps -Lp "${main_pid}" -o pid,tid,pcpu,pmem,stat,comm
  } | sudo tee "${dump_file}" >/dev/null
  log "Captured apache fallback thread snapshot: ${dump_file}"
}

restart_apache() {
  if [ "${DRY_RUN}" = "true" ]; then
    log "[DRY-RUN] Would restart ${APACHE_SERVICE} via systemctl."
    return 0
  fi

  sudo systemctl restart "${APACHE_SERVICE}"
  log "Restarted ${APACHE_SERVICE} via systemctl."
}

check_health_once() {
  local http_code

  http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time "${CURL_TIMEOUT_SECONDS}" "${HEALTH_URL}" || true)"
  if [ -z "${http_code}" ]; then
    http_code="000"
  fi

  log "Health check ${HEALTH_URL} returned HTTP ${http_code}."

  if [ "${http_code}" != "200" ]; then
    log "Non-200 detected (HTTP ${http_code}). Preparing thread dump and apache restart."
    capture_apache_thread_dump
    restart_apache
  fi
}

rollback() {
  local state_mode
  local original_state

  state_mode="$(read_state_value "mode")"
  original_state="$(read_state_value "original_apache_state")"

  if [ -z "${state_mode}" ]; then
    state_mode="${RUN_MODE}"
  fi

  if [ -z "${original_state}" ]; then
    if is_apache_active; then
      original_state="active"
    else
      original_state="inactive"
    fi
  fi

  log "Rollback started. mode=${state_mode}, target_apache_state=${original_state}."

  if [ "${state_mode}" = "daemon" ] && [ -f "${PID_FILE}" ]; then
    local running_pid
    running_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"

    if [ -n "${running_pid}" ] && kill -0 "${running_pid}" 2>/dev/null && [ "${running_pid}" != "$$" ]; then
      if [ "${DRY_RUN}" = "true" ]; then
        log "[DRY-RUN] Would stop monitor loop PID ${running_pid}."
      else
        kill "${running_pid}" >/dev/null 2>&1 || true
        log "Stopped monitor loop PID ${running_pid}."
      fi
    fi
  fi

  if [ "${original_state}" = "inactive" ]; then
    if is_apache_active; then
      if [ "${DRY_RUN}" = "true" ]; then
        log "[DRY-RUN] Would stop ${APACHE_SERVICE} to restore original inactive state."
      else
        sudo systemctl stop "${APACHE_SERVICE}"
        log "Stopped ${APACHE_SERVICE} to restore original inactive state."
      fi
    else
      log "Apache already inactive; no restore action needed."
    fi
  else
    if is_apache_active; then
      log "Apache already active; no restore action needed."
    else
      if [ "${DRY_RUN}" = "true" ]; then
        log "[DRY-RUN] Would start ${APACHE_SERVICE} to restore original active state."
      else
        sudo systemctl start "${APACHE_SERVICE}"
        log "Started ${APACHE_SERVICE} to restore original active state."
      fi
    fi
  fi

  if [ "${DRY_RUN}" = "false" ]; then
    remove_pid_file
    remove_state_file
  fi

  log "Rollback complete."
}

run_once() {
  RUN_MODE="once"
  ensure_log_targets
  acquire_monitor_lock
  trap 'remove_pid_file' EXIT
  capture_original_apache_state
  check_health_once
}

run_daemon() {
  RUN_MODE="daemon"
  ensure_log_targets
  acquire_monitor_lock
  capture_original_apache_state

  trap 'log "Received termination signal in daemon mode."; rollback; exit 0' INT TERM
  trap 'remove_pid_file' EXIT

  log "Starting payment monitor daemon loop with interval ${CHECK_INTERVAL_SECONDS}s."

  while true; do
    check_health_once
    sleep "${CHECK_INTERVAL_SECONDS}"
  done
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --daemon)
        RUN_MODE="daemon"
        ;;
      --once)
        RUN_MODE="once"
        ;;
      --dry-run)
        DRY_RUN="true"
        ;;
      --rollback)
        ROLLBACK_ONLY="true"
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

  ensure_log_targets

  if [ "${ROLLBACK_ONLY}" = "true" ]; then
    rollback
    exit 0
  fi

  if [ "${RUN_MODE}" = "once" ]; then
    run_once
  else
    run_daemon
  fi
}

main "$@"
