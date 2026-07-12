#!/usr/bin/env bash
#
# demo-openshift.sh — the guided OpenShift walk-through.
#
# Deploys the app vulnerable, patches Log4j by rebuilding the thin layer, canary-rolls it,
# promotes fleet-wide, and shows an instant rollback. Paced with pauses so you drive it live.
#
# Prereqs: logged into the cluster (`oc whoami`), in the target project (`oc project`).
#          Run from the repo root. Needs: oc, curl, jq.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
APP=decoupled-patching-demo
VULN=2.14.1
PATCHED=2.17.1

pause() { echo; read -rp "  ⏎  $1"; echo; }
route()  { oc get route demo -o jsonpath='{.spec.host}' 2>/dev/null; }
version_now() { curl -s "http://$(route)/api/version" | jq -r '.log4jRunningNow + "  (" + .status + ")"'; }
poll() { for i in $(seq 1 "${1:-12}"); do curl -s "http://$(route)/api/version" | jq -r '.log4jRunningNow'; sleep 0.5; done | sort | uniq -c; }

# Ensure the thin WAR exists (needed in the build context).
if [[ ! -f app/target/decoupled-patching-demo.war ]]; then
  echo ">> WAR not found — building it first."
  scripts/build.sh
fi

echo "============================================================"
echo " Decoupled Patching — OpenShift demo   (project: $(oc project -q))"
echo "============================================================"

# --- 0. Build config -----------------------------------------------------------
pause "Create the ImageStream + BuildConfig"
oc apply -f openshift/buildconfig.yaml

# --- 1. Build the VULNERABLE image --------------------------------------------
pause "Build the app image with the VULNERABLE Log4j ${VULN}"
scripts/fetch-libs.sh "${VULN}"
oc start-build "${APP}" --from-dir=. --follow
oc tag "${APP}:latest" "${APP}:vulnerable"
oc tag "${APP}:latest" "${APP}:stable"     # stable starts on the vulnerable build

# --- 2. Deploy -----------------------------------------------------------------
pause "Deploy the app (3 replicas) + Service + Route"
oc apply -f openshift/deployment.yaml
oc rollout status deploy/demo --timeout=180s
echo "  Route: http://$(route)/"
echo "  Log4j running now: $(version_now)"
echo "  ^ VULNERABLE, as expected."

# --- 3. Build the PATCHED image (only the dependency layer changes) -----------
pause "Patch: rebuild with Log4j ${PATCHED}. Watch — only the dependency layer rebuilds; the thin app layer is cache-reused."
scripts/fetch-libs.sh "${PATCHED}"
oc start-build "${APP}" --from-dir=. --follow
oc tag "${APP}:latest" "${APP}:patched"
echo "  Built :patched. The fleet is still on :stable (vulnerable) — nothing has rolled yet."

# --- 4. CANARY -----------------------------------------------------------------
pause "Canary: bring up ONE patched pod behind the same Service (~25% of traffic)"
oc apply -f openshift/canary.yaml
oc rollout status deploy/demo-canary --timeout=180s
echo "  Sampling live traffic across the fleet (expect a MIX of ${VULN} and ${PATCHED}):"
poll 16

# --- 5. Health gate + PROMOTE --------------------------------------------------
pause "Canary looks healthy. Promote fleet-wide by moving :stable to the patched image"
oc tag "${APP}:patched" "${APP}:stable"
oc rollout status deploy/demo --timeout=180s
oc delete -f openshift/canary.yaml
echo "  Sampling again (expect ALL ${PATCHED}):"
poll 12
echo "  Log4j running now: $(version_now)"
echo "  ^ PATCHED, fleet-wide."

# --- 6. ROLLBACK (safety net) --------------------------------------------------
pause "Show the safety net: instant rollback to the last known-good (here: back to vulnerable, just to prove reversibility)"
oc tag "${APP}:vulnerable" "${APP}:stable"
oc rollout status deploy/demo --timeout=180s
echo "  Log4j running now: $(version_now)"
echo "  ^ Rolled back in one step. (Re-run step 5's tag to go patched again.)"
echo
echo ">> Demo complete. Clean up with: scripts/cleanup-openshift.sh"
