#!/usr/bin/env bash
#
# demo-vm.sh — THE ONE SCRIPT for the VM / WildFly window.
#
# Consolidated: build, setup, vulnerable, optional exploit proof, compatibility gate, patch,
# GitHub PR (real, with local-only fallback), and the Fat JAR contrast — all in one file, as
# named functions. Run with no arguments for the full narrated demo. Run with a function name
# as the first argument to run just that one step, for debugging (e.g. `demo-vm.sh patch_fat`).
#
# Flags (env vars):
#   DEMO_SKIP_CALLBACK=1   skip the optional, safe Log4Shell reachability proof
#   DEMO_SKIP_GATE=1       skip the real japicmp compatibility-gate run (needs internet)
#   DEMO_SKIP_FATJAR=1     skip the Fat JAR contrast section
#   DEMO_AUTOPLAY=1        don't wait for Enter — brief pause instead
#   DEMO_TYPE_DELAY=0.02   seconds per typed character
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck disable=SC1091
source scripts/lib/demo-fx.sh

WILDFLY_HOME="${WILDFLY_HOME:-$HOME/wildfly-demo}"
VULN=2.14.1
PATCHED=2.17.1
MAVEN_BASE="https://repo1.maven.org/maven2/org/apache/logging/log4j"
MODULE_DIR="${WILDFLY_HOME}/modules/com/redhat/demo/log4j/main"
DEPLOY_DIR="${WILDFLY_HOME}/standalone/deployments"

# =========================================================================================
# build_thin — build the thin WAR, prove it carries no Log4j.
# =========================================================================================
build_thin() {
  narrate "Build the thin WAR from source"
  type_cmd "( cd app && mvn clean package )"
  ( cd app && mvn -q clean package )
  echo "${DIM}   Built: app/target/decoupled-patching-demo.war${RESET}"

  narrate "Prove it's thin: no bundled Log4j JAR (only your compiled classes)"
  local cmd="unzip -l app/target/decoupled-patching-demo.war | grep -iE 'log4j-(api|core).*\\.jar'"
  type_cmd "${cmd}"
  if unzip -l app/target/decoupled-patching-demo.war | grep -iE 'log4j-(api|core).*\.jar'; then
    echo "   ⚠️  A Log4j JAR was FOUND inside the WAR — it is not thin. Check pom.xml scopes."
    return 1
  else
    echo "   ✅  No Log4j JAR inside the WAR. The library is supplied by the server module."
    echo "      (log4j2.xml — the app's own logging config — is expected; that's not a library.)"
  fi
}

# =========================================================================================
# build_fat — build the Fat JAR variant, confirm it bundles Log4j (for contrast).
# =========================================================================================
build_fat() {
  narrate "Also build the Fat JAR variant — same source code, different packaging — for contrast later"
  type_cmd "( cd app-fat && mvn clean package )"
  ( cd app-fat && mvn -q clean package )

  narrate "Confirm the two artifacts are genuinely different: thin carries no library, fat bundles it"
  type_cmd "unzip -l app-fat/target/decoupled-patching-demo-fat.war | grep -iE 'log4j-(api|core).*\\.jar'"
  unzip -l app-fat/target/decoupled-patching-demo-fat.war | grep -iE 'log4j-(api|core).*\.jar'
}

# =========================================================================================
# setup_wildfly — install WildFly, install the vulnerable Log4j module, deploy the thin WAR.
# Versioned filenames on purpose: at-a-glance traceability of the deployed version.
# =========================================================================================
setup_wildfly() {
  narrate "Install WildFly and deploy the thin WAR — it starts out vulnerable (Log4j ${VULN})"
  rm -f "${DEPLOY_DIR}"/decoupled-patching-demo-fat.war* 2>/dev/null

  if [[ ! -d "${WILDFLY_HOME}" ]]; then
    local wf="31.0.1.Final"
    local tmp; tmp="$(mktemp -d)"
    type_cmd "curl -fSL https://github.com/wildfly/wildfly/releases/download/${wf}/wildfly-${wf}.zip -o wildfly.zip"
    curl -fSL "https://github.com/wildfly/wildfly/releases/download/${wf}/wildfly-${wf}.zip" -o "${tmp}/wildfly.zip"
    type_cmd "unzip wildfly.zip -d $(dirname "${WILDFLY_HOME}")"
    unzip -q "${tmp}/wildfly.zip" -d "$(dirname "${WILDFLY_HOME}")"
    mv "$(dirname "${WILDFLY_HOME}")/wildfly-${wf}" "${WILDFLY_HOME}"
    rm -rf "${tmp}"
  else
    echo "${DIM}   WildFly already present at ${WILDFLY_HOME} — skipping download.${RESET}"
  fi

  mkdir -p "${MODULE_DIR}"
  type_cmd "cp vm/modules/com/redhat/demo/log4j/main/module.xml ${MODULE_DIR}/"
  cp vm/modules/com/redhat/demo/log4j/main/module.xml "${MODULE_DIR}/module.xml"
  local c1="curl -fSL ${MAVEN_BASE}/log4j-api/${VULN}/log4j-api-${VULN}.jar -o ${MODULE_DIR}/log4j-api-${VULN}.jar"
  local c2="curl -fSL ${MAVEN_BASE}/log4j-core/${VULN}/log4j-core-${VULN}.jar -o ${MODULE_DIR}/log4j-core-${VULN}.jar"
  type_cmd "${c1}"; eval "${c1}"
  type_cmd "${c2}"; eval "${c2}"

  type_cmd "cp app/target/decoupled-patching-demo.war ${DEPLOY_DIR}/"
  cp app/target/decoupled-patching-demo.war "${DEPLOY_DIR}/"
}

# =========================================================================================
# start_server <packaging> — (re)start WildFly, waiting for it to actually come up.
# =========================================================================================
start_server() {
  local packaging="${1:-thin}"
  stop_port 8080
  local cmd="DEMO_PACKAGING=${packaging} ${WILDFLY_HOME}/bin/standalone.sh -b 0.0.0.0"
  type_cmd "${cmd} &"
  DEMO_PACKAGING="${packaging}" "${WILDFLY_HOME}/bin/standalone.sh" -b 0.0.0.0 >/tmp/wildfly-demo.log 2>&1 &
  disown
  wait_for_http "http://localhost:8080/api/health" 60
}

# =========================================================================================
# compatibility_gate <old> <new> — real japicmp run against the two real Log4j JARs.
# =========================================================================================
compatibility_gate() {
  local old="${1:-${VULN}}" new="${2:-${PATCHED}}"
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
  local oc="curl -fSL ${MAVEN_BASE}/log4j-core/${old}/${oldjar} -o ${oldjar}"
  local nc="curl -fSL ${MAVEN_BASE}/log4j-core/${new}/${newjar} -o ${newjar}"
  type_cmd "${oc}"; curl -fSL "${MAVEN_BASE}/log4j-core/${old}/${oldjar}" -o "${workdir}/${oldjar}"
  type_cmd "${nc}"; curl -fSL "${MAVEN_BASE}/log4j-core/${new}/${newjar}" -o "${workdir}/${newjar}"

  # --ignore-missing-classes: log4j-core references classes (e.g. from log4j-api) not present
  # when comparing the two log4j-core JARs in isolation. Without this flag japicmp aborts with
  # "Could not load ... Class not found" instead of completing the comparison.
  type_cmd "java -jar japicmp.jar -o ${oldjar} -n ${newjar} --only-incompatible --ignore-missing-classes"
  java -jar "${workdir}/japicmp.jar" -o "${workdir}/${oldjar}" -n "${workdir}/${newjar}" \
       --only-incompatible --ignore-missing-classes || true

  echo ""
  echo "   Structurally clean is not the same claim as behaviorally identical. Log4j's own"
  echo "   Log4Shell-era fixes are a real example of a security fix changing a default"
  echo "   behavior (JNDI lookup evaluation) — verify the exact version before citing it."
  echo "   That gap is why canary + rollback exist downstream of this gate."
}

# =========================================================================================
# patch_vm — swap the Log4j module (versioned filenames, real diff), restart, prove the WAR
# never changed.
# =========================================================================================
patch_vm() {
  narrate "Patch it: swap the Log4j SERVER MODULE. Not the app. Watch the WAR checksum next."
  echo "   (In production this artifact comes backported from Lightwell's registry."
  echo "    Here we use the public ${PATCHED} as a stand-in.)"

  local war_file; war_file="$(ls "${DEPLOY_DIR}"/*.war | head -1)"
  local before; before="$(sha256sum "${war_file}" | awk '{print $1}')"
  echo "${DIM}   WAR before patch: $(basename "${war_file}")  sha256=${before:0:16}...${RESET}"

  narrate "Fetch the patched Log4j artifacts (this is the step Lightwell's registry replaces in production)"
  local c1="curl -fSL ${MAVEN_BASE}/log4j-api/${PATCHED}/log4j-api-${PATCHED}.jar -o ${MODULE_DIR}/log4j-api-${PATCHED}.jar"
  local c2="curl -fSL ${MAVEN_BASE}/log4j-core/${PATCHED}/log4j-core-${PATCHED}.jar -o ${MODULE_DIR}/log4j-core-${PATCHED}.jar"
  type_cmd "${c1}"; eval "${c1}"
  type_cmd "${c2}"; eval "${c2}"

  narrate "Update the module descriptor to reference the new filenames — here's the real diff"
  echo "   (Filenames carry the version on purpose, for at-a-glance traceability — this"
  echo "    two-line pointer update is the trade-off for that.)"
  local old_copy; old_copy="$(mktemp)"
  cp "${MODULE_DIR}/module.xml" "${old_copy}"
  cat > "${MODULE_DIR}/module.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- PATCHED: Log4j ${PATCHED} — Log4Shell mitigated. WAR unchanged. -->
<module xmlns="urn:jboss:module:1.9" name="com.redhat.demo.log4j">
  <resources>
    <resource-root path="log4j-api-${PATCHED}.jar"/>
    <resource-root path="log4j-core-${PATCHED}.jar"/>
  </resources>
  <dependencies>
    <module name="java.naming"/>
    <module name="java.management"/>
    <module name="java.xml"/>
    <module name="java.desktop"/>
    <module name="java.sql"/>
  </dependencies>
</module>
EOF
  type_cmd "diff -u module.xml.before module.xml.after"
  diff -u "${old_copy}" "${MODULE_DIR}/module.xml" --label module.xml.before --label module.xml.after || true
  rm -f "${old_copy}"

  narrate "Remove the old, vulnerable JARs from the module directory"
  local c3="rm -f ${MODULE_DIR}/log4j-api-${VULN}.jar ${MODULE_DIR}/log4j-core-${VULN}.jar"
  type_cmd "${c3}"; eval "${c3}"

  narrate "The files are swapped on disk, but Java caches the already-loaded library for the life of the process. A fresh process is what picks up the new module."
  start_server thin

  local after; after="$(sha256sum "${war_file}" | awk '{print $1}')"
  echo ""
  echo "   WAR after patch:  $(basename "${war_file}")  sha256=${after:0:16}..."
  if [[ "${before}" == "${after}" ]]; then
    echo "   ✅  IDENTICAL — the application was never rebuilt or redeployed."
  else
    echo "   ⚠️  WAR checksum changed — unexpected for this demo."
  fi
}

# =========================================================================================
# patch_fat — the Fat JAR contrast: developer edits pom.xml, rebuilds, redeploys.
# =========================================================================================
patch_fat() {
  narrate "Patch the Fat JAR: this means a developer editing pom.xml and rebuilding. Watch the WAR checksum CHANGE this time."
  echo "   Every step below is a developer action. Compare with the module swap above (automated, no rebuild)."

  local deployed="${DEPLOY_DIR}/decoupled-patching-demo-fat.war"
  local before=""
  if [[ -f "${deployed}" ]]; then
    before="$(sha256sum "${deployed}" | awk '{print $1}')"
    echo "${DIM}   Deployed WAR before: sha256=${before:0:16}...${RESET}"
  fi

  # sed -i syntax differs between GNU (Linux) and BSD (macOS) sed; -i.bak + rm is the one
  # syntax both actually accept.
  local cmd="sed -i.bak 's#<log4j.version>${VULN}</log4j.version>#<log4j.version>${PATCHED}</log4j.version>#' app-fat/pom.xml"
  type_cmd "${cmd}"
  sed -i.bak "s#<log4j.version>${VULN}</log4j.version>#<log4j.version>${PATCHED}</log4j.version>#" app-fat/pom.xml
  rm -f app-fat/pom.xml.bak
  echo "   (In a real repo this is a commit + PR — the version change must be tracked.)"

  type_cmd "( cd app-fat && mvn clean package )"
  ( cd app-fat && mvn -q clean package )
  local newwar="app-fat/target/decoupled-patching-demo-fat.war"
  local after; after="$(sha256sum "${newwar}" | awk '{print $1}')"
  echo "   Rebuilt WAR after: sha256=${after:0:16}..."
  if [[ -n "${before}" && "${before}" != "${after}" ]]; then
    echo "   >> CHANGED - this is a brand-new artifact. Your SBOM/scan must be re-derived from scratch."
  fi

  type_cmd "cp ${newwar} ${DEPLOY_DIR}/"
  cp "${newwar}" "${DEPLOY_DIR}/"
}

# =========================================================================================
# github_pr <patched> <vuln> — Renovate-style version-bump PR. Pushes and opens a REAL PR on
# GitHub if `gh` is installed, authenticated, and origin is a GitHub remote. Falls back to a
# local-only branch/commit (never pushed) otherwise.
# =========================================================================================
github_pr() {
  local patched="${1:-${PATCHED}}" vuln="${2:-${VULN}}"
  local branch="renovate/log4j-core-2.x"

  # HONEST CAVEAT: this demo's stand-in versions (2.14.1 -> 2.17.1) carry no Red Hat/
  # Lightwell qualifier and cross a semver MINOR boundary, so run for real against
  # renovate.json, this specific bump would NOT match the top-priority backport rule — it
  # would land in the routine "minor/major" bucket. Say so if presenting both together.

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "!! Not a git repository. Clone with git (not just unzip) to run this part of the demo."
    return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "!! Uncommitted changes — commit or stash first so this starts from a clean base:"
    git status --short | sed 's/^/     /'
    echo ""
    if git status --short | grep -qE '^\s*D\s'; then
      echo "   Looks like you just updated the demo scripts themselves (files show as deleted"
      echo "   because they moved/consolidated). If so, this is expected — just commit it:"
      echo "     git add -A && git commit -m 'update demo scripts'"
      echo "   Then re-run this."
    else
      echo "   If this is just build output that should have been ignored, add it to .gitignore"
      echo "   and commit that first. Otherwise:  git stash   (then re-run this)."
    fi
    return 1
  fi

  local base_branch; base_branch="$(git rev-parse --abbrev-ref HEAD)"
  local use_github=1
  if ! command -v gh >/dev/null 2>&1; then
    echo "${DIM}   'gh' CLI not found — this run will be local-only (see below).${RESET}"
    use_github=0
  elif ! gh auth status >/dev/null 2>&1; then
    echo "${DIM}   'gh' CLI not authenticated (run 'gh auth login') — this run will be local-only.${RESET}"
    use_github=0
  elif ! git remote get-url origin 2>/dev/null | grep -qi github.com; then
    echo "${DIM}   'origin' isn't a GitHub remote — this run will be local-only.${RESET}"
    use_github=0
  fi

  narrate "Simulating the automated dependency-bump PR (Renovate-style)"
  echo "   This is NOT what fixed the vulnerability — that already happened via the module"
  echo "   swap. This is purely paperwork: getting pom.xml to agree with what's running."

  type_cmd "git checkout -b ${branch}"
  git checkout -b "${branch}" >/dev/null 2>&1 || git checkout "${branch}"

  for pom in app/pom.xml app-fat/pom.xml; do
    [[ -f "${pom}" ]] || continue
    local cmd="sed -i.bak 's#<log4j.version>${vuln}</log4j.version>#<log4j.version>${patched}</log4j.version>#' ${pom}"
    type_cmd "${cmd}"
    sed -i.bak "s#<log4j.version>${vuln}</log4j.version>#<log4j.version>${patched}</log4j.version>#" "${pom}"
    rm -f "${pom}.bak"
  done

  type_cmd "git add app/pom.xml app-fat/pom.xml"
  git add app/pom.xml app-fat/pom.xml 2>/dev/null || true

  if git diff --cached --quiet; then
    echo "!! No changes to commit — pom.xml may already reference ${patched}."
    git checkout "${base_branch}" >/dev/null 2>&1
    return 1
  fi

  type_cmd "git commit -m 'chore(deps): update dependency ...log4j-core to v${patched}'"
  git commit -q -m "chore(deps): update dependency org.apache.logging.log4j:log4j-core to v${patched}

Backported security fix, already deployed via Project Lightwell and running in production.
This commit brings source control in line with the version already in service — it does
not gate or delay the fix, which shipped independently through the module-swap pipeline.

Automated by Renovate (simulated for this demo)."

  if [[ "${use_github}" -eq 1 ]]; then
    narrate "Push the branch and open a REAL pull request on GitHub"
    type_cmd "git push -u origin ${branch}"
    if ! git push -u origin "${branch}"; then
      echo "${RED}!! Push failed — check your GitHub remote/permissions. Falling back to local-only.${RESET}"
      use_github=0
    else
      local existing; existing="$(gh pr view "${branch}" --json url -q .url 2>/dev/null || true)"
      if [[ -n "${existing}" ]]; then
        echo "${DIM}   A PR already exists for this branch: ${existing}${RESET}"
      else
        type_cmd "gh pr create --title 'chore(deps): update log4j-core to v${patched}' --base ${base_branch}"
        gh pr create \
          --title "chore(deps): update dependency org.apache.logging.log4j:log4j-core to v${patched}" \
          --body "Backported security fix, already deployed via Project Lightwell and running in production. This PR brings source control in line with the version already in service — it does not gate or delay the fix. Simulated for a demo; see docs/ARCHITECTURE.md." \
          --base "${base_branch}" || true
      fi
      local pr_url; pr_url="$(gh pr view "${branch}" --json url -q .url 2>/dev/null || true)"
      echo "   PR: ${pr_url}"
      narrate "Open it in the browser — this is the part the audience actually recognizes"
      type_cmd "gh pr view --web"
      gh pr view "${branch}" --web 2>/dev/null || echo "${DIM}   (couldn't auto-open a browser here; open the URL above manually.)${RESET}"
    fi
  fi

  if [[ "${use_github}" -eq 0 ]]; then
    echo ""
    echo ">> This branch is LOCAL ONLY — nothing was pushed."
    echo "   To push and open it for real:  git push -u origin ${branch}  &&  gh pr create"
  fi
}

# =========================================================================================
# main — the full narrated demo, calling the functions above in order.
# =========================================================================================
main() {
  echo "${BOLD}============================================================${RESET}"
  echo "${BOLD} Decoupled Patching — VM / WildFly demo${RESET}"
  echo "${BOLD}============================================================${RESET}"

  build_thin; step_pause
  build_fat; step_pause
  setup_wildfly; step_pause

  narrate "Start the server — this command is run FOR you; nothing to type here yourself."
  start_server thin
  step_pause

  narrate "Confirm it's vulnerable — this is read live from the JVM, not a claim on a slide."
  type_cmd "curl -s localhost:8080/api/version | jq ."
  curl -s localhost:8080/api/version | jq .
  step_pause

  if [[ "${DEMO_SKIP_CALLBACK:-0}" != "1" ]]; then
    narrate "Optional, safe proof of exposure: a benign listener that only logs a connection attempt"
    type_cmd "scripts/callback-listener.py 1389 &"
    scripts/callback-listener.py 1389 >/tmp/callback-listener.log 2>&1 &
    local cbpid=$!
    disown
    sleep 1
    type_cmd "curl \"localhost:8080/api/log?msg=\\\${jndi:ldap://127.0.0.1:1389/x}\""
    curl -s "localhost:8080/api/log?msg=\${jndi:ldap://127.0.0.1:1389/x}" >/dev/null
    sleep 1
    grep -q "CALLBACK RECEIVED" /tmp/callback-listener.log 2>/dev/null \
      && echo "  ${RED}⚠️  CALLBACK RECEIVED — the vulnerable Log4j reached out, confirmed.${RESET}" \
      || echo "  (no callback seen — see /tmp/callback-listener.log)"
    kill -9 "${cbpid}" 2>/dev/null || true
    step_pause
  fi

  if [[ "${DEMO_SKIP_GATE:-0}" != "1" ]]; then
    compatibility_gate "${VULN}" "${PATCHED}" || echo "${DIM}   (compatibility gate needs internet — DEMO_SKIP_GATE=1 to skip)${RESET}"
    step_pause
  fi

  patch_vm; step_pause

  narrate "Confirm it's patched — same artifact, different library underneath."
  type_cmd "curl -s localhost:8080/api/version | jq ."
  curl -s localhost:8080/api/version | jq .
  step_pause

  github_pr "${PATCHED}" "${VULN}"; step_pause

  if [[ "${DEMO_SKIP_FATJAR:-0}" != "1" ]]; then
    narrate "Now the contrast: patch the SAME CVE the traditional Fat JAR way."
    rm -f "${DEPLOY_DIR}"/decoupled-patching-demo.war*
    cp app-fat/target/decoupled-patching-demo-fat.war "${DEPLOY_DIR}/" 2>/dev/null || true
    start_server fat
    step_pause

    narrate "Confirm the fat deployment is vulnerable too — same CVE, different packaging."
    type_cmd "curl -s localhost:8080/api/version | jq ."
    curl -s localhost:8080/api/version | jq .
    step_pause

    patch_fat
    narrate "WildFly's deployment scanner auto-detects the new WAR and redeploys it — no server restart needed for a full redeploy like this"
    wait_for_version "http://localhost:8080/api/version" "${PATCHED}" 30
    step_pause

    narrate "Confirm it's patched — but this time via a brand-new artifact."
    type_cmd "curl -s localhost:8080/api/version | jq ."
    curl -s localhost:8080/api/version | jq .

    echo ""
    echo "${BOLD}${GREEN}That's the whole contrast: same CVE, same fix, two different costs.${RESET}"
    echo "See docs/FATJAR-VS-DECOUPLED.md for the scoreboard."
  fi

  echo ""
  echo "${BOLD}Demo complete.${RESET} Server is still running at http://localhost:8080/"
  echo ""
  echo "To stop the server, run:"
  echo "  ${DIM}kill -9 \$(lsof -ti:8080 2>/dev/null || fuser 8080/tcp 2>/dev/null)${RESET}"
  echo ""
  echo "To reset and run the whole demo again from scratch, run:"
  echo "  ${DIM}scripts/demo-vm.sh${RESET}"
  echo "  ${DIM}(setup_wildfly reinstalls the vulnerable module before it patches again — not${RESET}"
  echo "  ${DIM}a command to run by itself.)${RESET}"
}

# ---- dispatcher: no args = full demo; a function name = just that step, for debugging ----
if [[ $# -eq 0 ]]; then
  main
else
  "$@"
fi
