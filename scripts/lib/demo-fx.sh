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

# =========================================================================================
# compatibility_gate <old> <new> — real japicmp run against the two real Log4j JARs.
# =========================================================================================
# classify_stream OLD NEW — Red Hat's z-stream (patch) / y-stream (minor) / x-stream (major),
# same distinction as semver's patch/minor/major, which is what renovate.json's packageRules
# already key off of.
classify_stream() {
  local old="$1" new="$2"
  local old_major old_minor new_major new_minor
  old_major="$(echo "${old}" | cut -d. -f1)"; old_minor="$(echo "${old}" | cut -d. -f2)"
  new_major="$(echo "${new}" | cut -d. -f1)"; new_minor="$(echo "${new}" | cut -d. -f2)"
  if [[ "${old_major}" != "${new_major}" ]]; then
    echo "x-stream (major)"
  elif [[ "${old_minor}" != "${new_minor}" ]]; then
    echo "y-stream (minor)"
  else
    echo "z-stream (patch)"
  fi
}

compatibility_gate() {
  local old="${1:-2.14.1}" new="${2:-2.17.1}"
  local japicmp_version="0.26.1"
  local workdir; workdir="$(mktemp -d)"
  trap "rm -rf '${workdir}'" RETURN

  narrate "Real compatibility gate: japicmp ${old} -> ${new} (this is japicmp, not a mockup)"
  local cache="${HOME}/.cache/japicmp"
  mkdir -p "${cache}"
  if [[ ! -f "${cache}/japicmp-${japicmp_version}.jar" ]]; then
    local jc="curl -fSL https://repo1.maven.org/maven2/com/github/siom79/japicmp/japicmp/${japicmp_version}/japicmp-${japicmp_version}-jar-with-dependencies.jar -o japicmp.jar"
    type_cmd "${jc}"
    curl -fSL "https://repo1.maven.org/maven2/com/github/siom79/japicmp/japicmp/${japicmp_version}/japicmp-${japicmp_version}-jar-with-dependencies.jar" \
         -o "${cache}/japicmp-${japicmp_version}.jar"
  fi
  cp "${cache}/japicmp-${japicmp_version}.jar" "${workdir}/japicmp.jar"

  # Filenames here match exactly what's typed below — no silent old.jar/new.jar swap.
  local oldjar="log4j-core-${old}.jar" newjar="log4j-core-${new}.jar"
  local base="${MAVEN_BASE:-https://repo1.maven.org/maven2/org/apache/logging/log4j}"
  local oc="curl -fSL ${base}/log4j-core/${old}/${oldjar} -o ${oldjar}"
  local nc="curl -fSL ${base}/log4j-core/${new}/${newjar} -o ${newjar}"
  type_cmd "${oc}"; curl -fSL "${base}/log4j-core/${old}/${oldjar}" -o "${workdir}/${oldjar}"
  type_cmd "${nc}"; curl -fSL "${base}/log4j-core/${new}/${newjar}" -o "${workdir}/${newjar}"

  # --ignore-missing-classes: log4j-core references classes (e.g. from log4j-api) not present
  # when comparing the two log4j-core JARs in isolation. Without this flag japicmp aborts with
  # "Could not load ... Class not found" instead of completing the comparison.
  local japicmp_out="${workdir}/japicmp-output.txt"
  type_cmd "java -jar japicmp.jar -o ${oldjar} -n ${newjar} --only-incompatible --ignore-missing-classes"
  java -jar "${workdir}/japicmp.jar" -o "${workdir}/${oldjar}" -n "${workdir}/${newjar}" \
       --only-incompatible --ignore-missing-classes > "${japicmp_out}" 2>&1 || true
  cat "${japicmp_out}"

  # --- The verdict: z-stream default fast lane, y/x-stream default full regression, japicmp
  # findings escalate a z-stream patch OUT of the fast lane regardless of the default. ---
  local stream; stream="$(classify_stream "${old}" "${new}")"
  local found=0
  grep -qE '(\*\*\*|---)' "${japicmp_out}" && found=1

  echo ""
  echo "${BOLD}Verdict (default routing: z-stream -> fast lane, y/x-stream -> full regression;${RESET}"
  echo "${BOLD}japicmp findings escalate a z-stream patch out of the fast lane):${RESET}"
  if [[ "${stream}" == "z-stream (patch)" && "${found}" -eq 0 ]]; then
    echo "${GREEN}  ${old} -> ${new} is ${stream}, japicmp found no incompatibilities.${RESET}"
    echo "${GREEN}  -> FAST LANE: rebuild, smoke test, canary, done.${RESET}"
  elif [[ "${stream}" == "z-stream (patch)" && "${found}" -eq 1 ]]; then
    echo "${RED}  ${old} -> ${new} is ${stream}, but japicmp found real structural changes.${RESET}"
    echo "${RED}  -> ESCALATED to full regression, despite being a nominal patch release.${RESET}"
  else
    echo "${RED}  ${old} -> ${new} is ${stream} -> FULL REGRESSION by default, regardless of${RESET}"
    echo "${RED}  what japicmp shows (minor/major bumps are assumed to carry new functionality).${RESET}"
  fi
  echo ""
  echo "   Reminder: this verdict only sees STRUCTURAL changes — and the y/x-stream default is"
  echo "   doing real work here. Log4j's actual JNDI-lookup change landed at a minor-version"
  echo "   boundary, so this exact pair already routes to full regression regardless of japicmp."
  echo "   The gap this rule can't close is narrower: a PATCH-level (z-stream) release that"
  echo "   changes behavior with zero structural fingerprint would still slip through as fast"
  echo "   lane. That's why canary + rollback exist even for the patches this rule fast-lanes,"
  echo "   not just as a backstop for the ones it correctly flags."
}

# check_drift [URL] [POM_PATH] — configuration drift check: does the actual running server
# agree with what git says should be running? Drift, servers silently diverging from what
# source control claims is deployed, is one of the least glamorous, most common real
# production problems. This makes it a measured, visible fact in the demo instead of an
# assumption nobody checks. Uses only what's already running (no new downloads, no new deps).
check_drift() {
  local url="${1:-http://localhost:8080}" pom="${2:-app/pom.xml}"
  local running expected
  running="$(curl -sf "${url}/api/version" 2>/dev/null | jq -r '.log4jRunningNow // empty')"
  expected="$(sed -n 's#.*<log4j\.version>\([0-9.]*\)</log4j\.version>.*#\1#p' "${pom}" 2>/dev/null | head -1)"

  narrate "Configuration drift check: what's actually running vs. what git says should be"
  echo "   Server (live, ${url}):  log4jRunningNow = ${running:-no response}"
  echo "   Git (${pom}):           log4j.version   = ${expected:-not found}"

  if [[ -z "${running}" || -z "${expected}" ]]; then
    echo "${DIM}   Couldn't compare — server or pom.xml value missing.${RESET}"
  elif [[ "${running}" == "${expected}" ]]; then
    echo "${GREEN}   MATCH — no drift. What's running is exactly what git says should be.${RESET}"
  else
    echo "${RED}   DRIFT — server and git disagree.${RESET}"
    echo "   Right now that's expected: the fix already shipped live; git hasn't caught up"
    echo "   yet. That's exactly what the PR step closes. The dangerous version of this same"
    echo "   gap is the one nobody measures — a fleet where some server quietly never got"
    echo "   patched, and nothing notices. Measuring drift on purpose is what makes it safe"
    echo "   to allow it on purpose."
  fi
}
