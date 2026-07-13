#!/usr/bin/env bash
#
# demo-fx.sh — shared "narrate it, type it, run it" helpers for the demo scripts.
# Sourced by scripts/demo-vm.sh and scripts/demo-openshift.sh — not meant to be run directly.
#
# Env vars you can set to control pacing:
#   DEMO_TYPE_DELAY=0.02   seconds per typed character (default shown)
#   DEMO_AUTOPLAY=1        don't wait for Enter between steps — just a short pause (for a
#                           timed rehearsal / recording; default is to wait for Enter so you
#                           can talk between beats live)

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; CYAN=""; RESET=""
fi

TYPE_DELAY="${DEMO_TYPE_DELAY:-0.02}"
AUTOPLAY="${DEMO_AUTOPLAY:-0}"

# narrate "One short line of what we're about to show" — printed instantly, not typed.
narrate() {
  echo ""
  echo "${BOLD}${CYAN}▸ $1${RESET}"
}

# type_cmd "literal command text" — simulates typing it, character by character. Does NOT run it.
type_cmd() {
  local text="$1" i
  printf '%s' "${DIM}\$ ${RESET}"
  for (( i=0; i<${#text}; i++ )); do
    printf '%s' "${text:$i:1}"
    sleep "${TYPE_DELAY}"
  done
  printf '\n'
}

# run "narration" "command to actually execute"
# Narrates, types the command out for effect, then really executes it via eval.
run() {
  local note="$1" cmd="$2"
  narrate "$note"
  type_cmd "$cmd"
  eval "$cmd"
}

# step_pause — hold here so the presenter can talk, unless DEMO_AUTOPLAY=1.
step_pause() {
  if [[ "${AUTOPLAY}" == "1" ]]; then
    sleep 1.5
  else
    read -rsp "$(printf '%s' "${DIM}  … press Enter to continue …${RESET}")" _ 2>/dev/null
    echo ""
  fi
}

# wait_for_http URL [timeout_seconds] — polls until it responds, with a visible countdown dots.
wait_for_http() {
  local url="$1" timeout="${2:-60}" waited=0
  printf '%s' "${DIM}  waiting for ${url} to respond${RESET}"
  until curl -sf -o /dev/null "${url}" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    printf '.'
    if (( waited >= timeout )); then
      echo ""
      echo "${RED}  timed out after ${timeout}s waiting for ${url}${RESET}"
      return 1
    fi
  done
  echo " ${GREEN}up${RESET}"
}

# wait_for_version URL EXPECTED_VERSION [timeout_seconds]
#
# A "/api/health" 200 is NOT proof a redeploy finished — WildFly's deployment scanner can
# keep the OLD app answering healthily for a moment while it swaps in the new one in the
# background. Polling log4jRunningNow directly waits for the fact that actually matters,
# closing the race condition that let a stale "still vulnerable" result show on screen after
# a real, successful redeploy.
wait_for_version() {
  local url="$1" expected="$2" timeout="${3:-30}" waited=0 got=""
  printf '%s' "${DIM}  waiting for ${url} to report log4jRunningNow=${expected}${RESET}"
  while true; do
    got="$(curl -sf "${url}" 2>/dev/null | jq -r '.log4jRunningNow // empty' 2>/dev/null)"
    if [[ "${got}" == "${expected}" ]]; then
      echo " ${GREEN}confirmed${RESET}"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
    printf '.'
    if (( waited >= timeout )); then
      echo ""
      echo "${RED}  timed out after ${timeout}s — still reporting '${got:-no response}', expected '${expected}'.${RESET}"
      echo "${RED}  The redeploy may still be in progress; check manually: curl -s ${url} | jq .${RESET}"
      return 1
    fi
  done
}

# stop_port PORT — kill whatever is actually bound to a port, by PID, not by shell job number.
# (This is the fix for the "Address already in use" failure mode from an earlier run.)
# Tries lsof first (standard on macOS), falls back to fuser (common on Linux), and tells you
# plainly if neither tool is available rather than silently doing nothing.
stop_port() {
  local port="$1" pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -ti:"${port}" 2>/dev/null || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser "${port}"/tcp 2>/dev/null || true)"
  else
    echo "${RED}  Neither lsof nor fuser is available — can't check port ${port} automatically.${RESET}"
    echo "  If the next step fails with 'Address already in use', find and stop the process"
    echo "  bound to port ${port} manually, then re-run this script."
    return 0
  fi
  if [[ -n "${pids}" ]]; then
    echo "${DIM}  stopping process(es) on port ${port}: ${pids}${RESET}"
    # shellcheck disable=SC2086
    kill -9 ${pids} 2>/dev/null || true
    sleep 1
  fi
}
