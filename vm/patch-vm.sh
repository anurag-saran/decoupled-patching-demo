#!/usr/bin/env bash
#
# patch-vm.sh — THE MONEY SHOT for the VM / app-server side.
#
# Patches Log4Shell by SWAPPING THE EXTERNAL MODULE and restarting WildFly.
# The application WAR is NOT rebuilt, NOT redeployed, NOT reopened. Same bytes on disk.
#
# This is the "Thin WAR + shared module" answer from the deck: the fix lands once in the
# server module that every deployment references.
set -euo pipefail

WILDFLY_HOME="${WILDFLY_HOME:-/opt/wildfly}"
PATCHED_LOG4J="${PATCHED_LOG4J:-2.17.1}"     # stand-in for "the Lightwell-supplied fixed artifact"
VULN_LOG4J="${VULN_LOG4J:-2.14.1}"
MAVEN_BASE="https://repo1.maven.org/maven2/org/apache/logging/log4j"
MODULE_DIR="${WILDFLY_HOME}/modules/com/redhat/demo/log4j/main"

echo ">> Patching Log4j in the server module: ${VULN_LOG4J}  ->  ${PATCHED_LOG4J}"
echo "   (In production this artifact comes backported from Lightwell's registry."
echo "    Here we use the public ${PATCHED_LOG4J} as a stand-in.)"
echo ""

# 1. Capture the WAR's checksum BEFORE, to prove it doesn't change.
WAR_FILE="$(ls "${WILDFLY_HOME}"/standalone/deployments/*.war | head -1)"
BEFORE_SUM="$(sha256sum "${WAR_FILE}" | awk '{print $1}')"
echo "   WAR before patch:  $(basename "${WAR_FILE}")  sha256=${BEFORE_SUM:0:16}..."

# 2. Drop in the patched JARs.
echo ">> Fetching patched Log4j ${PATCHED_LOG4J} ..."
curl -fSL "${MAVEN_BASE}/log4j-api/${PATCHED_LOG4J}/log4j-api-${PATCHED_LOG4J}.jar"   -o "${MODULE_DIR}/log4j-api-${PATCHED_LOG4J}.jar"
curl -fSL "${MAVEN_BASE}/log4j-core/${PATCHED_LOG4J}/log4j-core-${PATCHED_LOG4J}.jar" -o "${MODULE_DIR}/log4j-core-${PATCHED_LOG4J}.jar"

# 3. Repoint module.xml at the patched JARs.
echo ">> Updating module.xml to reference ${PATCHED_LOG4J} ..."
cat > "${MODULE_DIR}/module.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- PATCHED: Log4j ${PATCHED_LOG4J} — Log4Shell mitigated. WAR unchanged. -->
<module xmlns="urn:jboss:module:1.9" name="com.redhat.demo.log4j">
  <resources>
    <resource-root path="log4j-api-${PATCHED_LOG4J}.jar"/>
    <resource-root path="log4j-core-${PATCHED_LOG4J}.jar"/>
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

# 4. Remove the old vulnerable JARs.
rm -f "${MODULE_DIR}/log4j-api-${VULN_LOG4J}.jar" "${MODULE_DIR}/log4j-core-${VULN_LOG4J}.jar"

# 5. Restart WildFly so it re-links the module. (Restart the process/service — NOT a redeploy.)
echo ">> Restarting WildFly to re-link the module ..."
if systemctl list-units --type=service 2>/dev/null | grep -q wildfly; then
  sudo systemctl restart wildfly
else
  echo "   No systemd unit found. Reloading via jboss-cli (or restart standalone.sh manually)."
  "${WILDFLY_HOME}/bin/jboss-cli.sh" --connect --command=":reload" || \
    echo "   >> Could not auto-reload. Please restart standalone.sh manually."
fi

# 6. Prove the WAR did not change.
AFTER_SUM="$(sha256sum "${WAR_FILE}" | awk '{print $1}')"
echo ""
echo "   WAR after patch:   $(basename "${WAR_FILE}")  sha256=${AFTER_SUM:0:16}..."
if [[ "${BEFORE_SUM}" == "${AFTER_SUM}" ]]; then
  echo "   ✅  IDENTICAL — the application was never rebuilt or redeployed."
else
  echo "   ⚠️  WAR checksum changed — unexpected for this demo."
fi
echo ""
echo ">> Done. Verify the fix (should now report PATCHED):"
echo "     curl -s http://localhost:8080/api/version | jq ."
