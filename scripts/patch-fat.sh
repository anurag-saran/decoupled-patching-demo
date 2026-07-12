#!/usr/bin/env bash
#
# patch-fat.sh - the FAT JAR contrast to vm/patch-vm.sh.
#
# Patching a Fat WAR means: a developer edits the version in source control, rebuilds,
# and ships a brand-new artifact. Watch the WAR checksum CHANGE (the thin build's stays
# identical) - and note that a human did every step.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WILDFLY_HOME="${WILDFLY_HOME:-$HOME/wildfly-demo}"
PATCHED_LOG4J="${PATCHED_LOG4J:-2.17.1}"
VULN_LOG4J="${VULN_LOG4J:-2.14.1}"
POM="${ROOT}/app-fat/pom.xml"
DEPLOYED="${WILDFLY_HOME}/standalone/deployments/decoupled-patching-demo-fat.war"

echo ">> FAT JAR patch: ${VULN_LOG4J} -> ${PATCHED_LOG4J}"
echo "   Every step below is a developer action. Compare with vm/patch-vm.sh (automated, no rebuild)."
echo ""

# 1. Checksum BEFORE.
if [[ -f "${DEPLOYED}" ]]; then
  BEFORE="$(sha256sum "${DEPLOYED}" | awk '{print $1}')"
  echo "   Deployed WAR before:  sha256=${BEFORE:0:16}..."
fi

# 2. DEVELOPER STEP: edit the pinned version in source control (this is your PR diff).
echo ">> [developer] Editing app-fat/pom.xml: log4j.version ${VULN_LOG4J} -> ${PATCHED_LOG4J}"
sed -i "s#<log4j.version>${VULN_LOG4J}</log4j.version>#<log4j.version>${PATCHED_LOG4J}</log4j.version>#" "${POM}"
echo "   (In a real repo this is a commit + PR — the version change must be tracked.)"

# 3. DEVELOPER STEP: rebuild the whole artifact.
echo ">> [developer] Rebuilding the Fat WAR ..."
( cd "${ROOT}/app-fat" && mvn -q clean package )
NEWWAR="${ROOT}/app-fat/target/decoupled-patching-demo-fat.war"

# 4. Checksum AFTER - it CHANGED (new, opaque artifact to re-scan).
AFTER="$(sha256sum "${NEWWAR}" | awk '{print $1}')"
echo "   Rebuilt WAR after:    sha256=${AFTER:0:16}..."
if [[ -n "${BEFORE:-}" && "${BEFORE}" != "${AFTER}" ]]; then
  echo "   >> CHANGED - this is a brand-new artifact. Your SBOM/scan must be re-derived from scratch."
fi

# 5. DEVELOPER STEP: redeploy the new artifact.
echo ">> [developer] Redeploying the new artifact ..."
cp "${NEWWAR}" "${WILDFLY_HOME}/standalone/deployments/"

echo ""
echo ">> Done. Verify (set DEMO_PACKAGING=fat on the server so it labels itself):"
echo "     curl -s http://localhost:8080/api/version | jq ."
echo ""
echo "   Tally for the scoreboard:"
echo "     - Who did the work?      a developer (edit + rebuild + redeploy)"
echo "     - Artifact changed?      YES (new checksum, new opaque bundle)"
echo "     - Source-control change? YES (pom.xml bump = a PR)"
echo "   Compare vm/patch-vm.sh:    automation swaps a module; WAR checksum identical."
