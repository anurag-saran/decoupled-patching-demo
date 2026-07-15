#!/usr/bin/env bash
#
# demo-openshift.sh — THE ONE SCRIPT for the OpenShift window.
#
# Consolidated: build vulnerable, deploy, build patched, canary, promote, rollback, cleanup —
# all in one file, as named functions. Run with no arguments for the full narrated demo. Run
# with a function name as the first argument to run just that one step (e.g. `demo-openshift.sh
# cleanup`).
#
# Prereqs: logged into the cluster (`oc whoami`), in the target project (`oc project`).
#          Run from the repo root. Needs: oc, curl, jq.
#
# Flags (env vars):
#   DEMO_SKIP_GATE=1       skip the real japicmp compatibility-gate runs (needs internet)
#   DEMO_AUTOPLAY=1        don't wait for Enter — brief pause instead (see scripts/lib/demo-fx.sh)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
# shellcheck disable=SC1091
source scripts/lib/demo-fx.sh

APP=decoupled-patching-demo
VULN=2.14.1
PATCHED=2.17.1
MAVEN_BASE="https://repo1.maven.org/maven2/org/apache/logging/log4j"
# Must match openshift/buildconfig.yaml's output.to.name. Only used if that BuildConfig pushes
# to an external registry (Docker Hub) instead of the cluster's internal one — see
# openshift/buildconfig-internal-registry.yaml for the internal-registry alternative, which
# doesn't need this at all.
DOCKERHUB_IMAGE="docker.io/asaran/decoupled-patching-demo"

route()  { oc get route demo -o jsonpath='{.spec.host}' 2>/dev/null; }
version_now() { curl -s "http://$(route)/api/version" | jq -r '.log4jRunningNow + "  (" + .status + ")"'; }
poll() {
  local host; host="$(route)"
  if [[ -z "${host}" ]]; then
    echo "${RED}   Route not found yet — skipping poll. Run 'oc get route demo' to check.${RESET}"
    return 1
  fi
  for i in $(seq 1 "${1:-12}"); do curl -s "http://${host}/api/version" | jq -r '.log4jRunningNow // "no-response"'; sleep 0.5; done | sort | uniq -c
}
require() {
  local desc="$1" cmd="$2"
  if ! eval "${cmd}" >/dev/null 2>&1; then
    echo "${RED}!! ${desc}${RESET}"
    exit 1
  fi
}

# diagnose_build_failure — the build controller can reject a build before any pod even runs,
# in which case `oc logs` shows nothing useful. Pull the real reason from the Build object
# instead of just pointing at logs.
diagnose_build_failure() {
  local latest reason message

  # Distinguish "cluster is unreachable" from "build actually failed" — very different fixes.
  if ! oc whoami >/dev/null 2>&1; then
    echo "${RED}!! Can't reach the cluster right now (not a build failure) — check your network/VPN,${RESET}"
    echo "${RED}   then confirm with 'oc whoami' before retrying.${RESET}"
    return
  fi

  latest="$(oc get builds -l "buildconfig=${APP}" --sort-by=.metadata.creationTimestamp -o name 2>/dev/null | tail -1)"
  if [[ -z "${latest}" ]]; then
    echo "${RED}!! Build failed — no Build object found. Check 'oc logs -f bc/${APP}'.${RESET}"
    return
  fi
  reason="$(oc get "${latest}" -o jsonpath='{.status.reason}' 2>/dev/null)"
  message="$(oc get "${latest}" -o jsonpath='{.status.message}' 2>/dev/null)"
  echo "${RED}!! Build failed: ${reason:-unknown} — ${message:-see 'oc logs -f bc/${APP}'}${RESET}"
  if [[ "${reason}" == "InvalidOutputReference" ]]; then
    echo ""
    echo "   This specific error means the BuildConfig's output image couldn't be resolved —"
    echo "   almost always because this cluster's INTERNAL IMAGE REGISTRY isn't enabled or"
    echo "   exposed. Check with:"
    echo "     oc get imagestream ${APP} -o jsonpath='{.status.dockerImageRepository}'"
    echo "   If that prints nothing, the internal registry isn't available on this cluster —"
    echo "   ask your cluster admin to enable it, or point openshift/buildconfig.yaml's"
    echo "   output.to at an external registry instead (a DockerImage reference, not an"
    echo "   ImageStreamTag)."
  fi
}

# stage_build_context — `oc start-build --from-dir=.` uploads the ENTIRE repo root, including
# .git history and both app/target/ and app-fat/target/'s full Maven build artifacts — far more
# than the Dockerfile actually needs, and the real reason a build's "Uploading directory ..."
# step can take a long time. Stage only the 5 files the Dockerfile's COPY lines reference,
# preserving their relative paths, and build from that instead.
stage_build_context() {
  local stagedir; stagedir="$(mktemp -d)"
  mkdir -p "${stagedir}/openshift/module" "${stagedir}/app/target"
  cp openshift/Dockerfile "${stagedir}/openshift/Dockerfile"
  cp openshift/module/module.xml "${stagedir}/openshift/module/module.xml"
  cp openshift/module/log4j-api.jar "${stagedir}/openshift/module/log4j-api.jar"
  cp openshift/module/log4j-core.jar "${stagedir}/openshift/module/log4j-core.jar"
  cp app/target/decoupled-patching-demo.war "${stagedir}/app/target/decoupled-patching-demo.war"
  echo "${stagedir}"
}

# =========================================================================================
# fetch_libs <version> — place Log4j api+core into the OpenShift build context as
# unversioned filenames. Container side: the whole image layer gets replaced atomically on
# rebuild, so (unlike the VM side) the filename doesn't need to carry the version.
# =========================================================================================
fetch_libs() {
  local version="${1:-${VULN}}"
  local dest="openshift/module"
  narrate "Fetch Log4j ${version} into the OpenShift build context"
  local c1="curl -fSL ${MAVEN_BASE}/log4j-api/${version}/log4j-api-${version}.jar -o ${dest}/log4j-api.jar"
  local c2="curl -fSL ${MAVEN_BASE}/log4j-core/${version}/log4j-core-${version}.jar -o ${dest}/log4j-core.jar"
  type_cmd "${c1}"; eval "${c1}"
  type_cmd "${c2}"; eval "${c2}"
  echo "${DIM}   Placed log4j ${version} as ${dest}/log4j-{api,core}.jar${RESET}"
}

# =========================================================================================
# cleanup — remove everything the demo created from the current project.
# =========================================================================================
cleanup() {
  narrate "Removing demo resources from project $(oc project -q 2>/dev/null)"
  type_cmd "oc delete -f openshift/canary.yaml openshift/deployment.yaml openshift/buildconfig.yaml"
  oc delete -f openshift/canary.yaml --ignore-not-found
  oc delete -f openshift/deployment.yaml --ignore-not-found
  oc delete -f openshift/buildconfig.yaml --ignore-not-found
  oc delete imagestreamtag "${APP}:vulnerable" "${APP}:patched" "${APP}:stable" --ignore-not-found 2>/dev/null || true
  echo ">> Done."
}

# =========================================================================================
# main — the full narrated demo.
# =========================================================================================
main() {
  narrate "Checking prerequisites"
  require "Not logged into an OpenShift cluster — run 'oc login <cluster>' first." "oc whoami"
  local project; project="$(oc project -q 2>/dev/null)"
  if [[ -z "${project}" ]]; then
    echo "${RED}!! No active project — run 'oc new-project <name>' or 'oc project <existing>' first.${RESET}"
    exit 1
  fi
  require "'jq' is required but not found on PATH." "command -v jq"
  echo "${DIM}   Logged in as $(oc whoami), project: ${project}${RESET}"

  if [[ ! -f app/target/decoupled-patching-demo.war ]]; then
    narrate "WAR not found — building it first."
    type_cmd "scripts/demo-vm.sh build_thin"
    scripts/demo-vm.sh build_thin
  fi

  echo "${BOLD}============================================================${RESET}"
  echo "${BOLD} Decoupled Patching — OpenShift demo   (project: ${project})${RESET}"
  echo "${BOLD}============================================================${RESET}"

  narrate "Create the ImageStream + BuildConfig"
  type_cmd "oc apply -f openshift/buildconfig.yaml"
  oc apply -f openshift/buildconfig.yaml
  step_pause

  narrate "Build the app image with the VULNERABLE Log4j ${VULN}"
  fetch_libs "${VULN}"
  local ctx1; ctx1="$(stage_build_context)"
  type_cmd "oc start-build ${APP} --from-dir=<staged: Dockerfile + module JARs + WAR only> --follow"
  if ! oc start-build "${APP}" --from-dir="${ctx1}" --follow; then
    rm -rf "${ctx1}"
    diagnose_build_failure
    echo "${RED}   Stopping so we don't tag a broken image.${RESET}"
    exit 1
  fi
  rm -rf "${ctx1}"
  narrate "Import the pushed image into local tags :vulnerable and :stable"
  type_cmd "oc tag ${DOCKERHUB_IMAGE}:latest ${APP}:vulnerable --reference-policy=source"
  if ! oc tag "${DOCKERHUB_IMAGE}:latest" "${APP}:vulnerable" --reference-policy=source; then
    echo "${RED}!! Could not import the image into ${APP}:vulnerable. Check the DOCKERHUB_IMAGE${RESET}"
    echo "${RED}   variable near the top of this script actually matches what was just pushed.${RESET}"
    exit 1
  fi
  if ! oc tag "${DOCKERHUB_IMAGE}:latest" "${APP}:stable" --reference-policy=source; then
    echo "${RED}!! Could not import the image into ${APP}:stable. Stopping before deploying.${RESET}"
    exit 1
  fi
  step_pause

  narrate "Deploy the app (3 replicas) + Service + Route"
  type_cmd "oc apply -f openshift/deployment.yaml"
  oc apply -f openshift/deployment.yaml
  if ! oc rollout status deploy/demo --timeout=180s; then
    echo "${RED}!! Rollout didn't complete — check 'oc get pods' and 'oc describe deploy/demo'.${RESET}"
    exit 1
  fi
  echo "  Route: http://$(route)/"
  echo "  Log4j running now: $(version_now)"
  echo "  ^ VULNERABLE, as expected."
  step_pause

  if [[ "${DEMO_SKIP_GATE:-0}" != "1" ]]; then
    narrate "Real compatibility gate: japicmp against a real z-stream security backport"
    echo "   2.12.1 -> 2.12.2 was Log4j's own emergency backport of the Log4Shell fix"
    echo "   (CVE-2021-44228, plus CVE-2021-45046) onto the older Java-7-compatible line —"
    echo "   a genuine patch-level release, not a hypothetical. Whatever the verdict below"
    echo "   says is the real answer for a real case, it isn't scripted."
    compatibility_gate "2.12.1" "2.12.2" || echo "${DIM}   (compatibility gate needs internet — DEMO_SKIP_GATE=1 to skip)${RESET}"
    step_pause
  fi

  narrate "Patch: rebuild with Log4j ${PATCHED}. Only the dependency layer rebuilds; the thin app layer is copied, not recompiled."
  fetch_libs "${PATCHED}"
  local ctx2; ctx2="$(stage_build_context)"
  type_cmd "oc start-build ${APP} --from-dir=<staged: Dockerfile + module JARs + WAR only> --follow"
  if ! oc start-build "${APP}" --from-dir="${ctx2}" --follow; then
    rm -rf "${ctx2}"
    diagnose_build_failure
    echo "${RED}   Stopping so we don't canary a broken image.${RESET}"
    exit 1
  fi
  rm -rf "${ctx2}"
  narrate "Import the pushed image into local tag :patched"
  type_cmd "oc tag ${DOCKERHUB_IMAGE}:latest ${APP}:patched --reference-policy=source"
  if ! oc tag "${DOCKERHUB_IMAGE}:latest" "${APP}:patched" --reference-policy=source; then
    echo "${RED}!! Could not import the image into ${APP}:patched. Stopping before canary.${RESET}"
    exit 1
  fi
  echo "  Built :patched. The fleet is still on :stable (vulnerable) — nothing has rolled yet."
  step_pause

  narrate "Canary: bring up ONE patched pod behind the same Service (~25% of traffic)"
  type_cmd "oc apply -f openshift/canary.yaml"
  oc apply -f openshift/canary.yaml
  if ! oc rollout status deploy/demo-canary --timeout=180s; then
    echo "${RED}!! Canary didn't come up healthy — check 'oc get pods -l track=canary'.${RESET}"
    exit 1
  fi
  echo "  Sampling live traffic across the fleet (expect a MIX of ${VULN} and ${PATCHED}):"
  poll 16
  step_pause

  narrate "Canary looks healthy. Promote fleet-wide by moving :stable to the patched image"
  type_cmd "oc tag ${APP}:patched ${APP}:stable"
  oc tag "${APP}:patched" "${APP}:stable"
  oc rollout status deploy/demo --timeout=180s
  oc delete -f openshift/canary.yaml --ignore-not-found
  echo "  Sampling again (expect ALL ${PATCHED}):"
  poll 12
  echo "  Log4j running now: $(version_now)"
  echo "  ^ PATCHED, fleet-wide."
  step_pause

  check_drift "http://$(route)" "app/pom.xml"
  echo "   (This script doesn't open a PR itself — scripts/demo-vm.sh's github_pr step does"
  echo "   exactly that, closing this same gap. Same drift, same fix, either deployment target.)"
  step_pause

  narrate "Show the safety net: instant rollback to the last known-good"
  type_cmd "oc tag ${APP}:vulnerable ${APP}:stable"
  oc tag "${APP}:vulnerable" "${APP}:stable"
  oc rollout status deploy/demo --timeout=180s
  echo "  Log4j running now: $(version_now)"
  echo "  ^ Rolled back in one step. (Re-run the promote step to go patched again.)"

  echo ""
  echo ""
  echo "${BOLD}Demo complete.${RESET} App is running at http://$(route)/"
  echo ""
  echo "To check current status, run:"
  echo "  ${DIM}oc get pods${RESET}"
  echo ""
  echo "To reset and run the whole demo again from scratch (safe to re-run — everything here"
  echo "is idempotent), run:"
  echo "  ${DIM}scripts/demo-openshift.sh${RESET}"
  echo ""
  echo "To fully tear down everything this demo created, run:"
  echo "  ${DIM}scripts/demo-openshift.sh cleanup${RESET}"
}

# ---- dispatcher: no args = full demo; a function name = just that step, for debugging ----
if [[ $# -eq 0 ]]; then
  main
else
  "$@"
fi
