#!/usr/bin/env bash
#
# setup-wildfly.sh — one-time setup of the VM / app-server side of the demo.
#
# Installs WildFly on a RHEL (or any Linux) VM, installs Log4j 2.14.1 as an EXTERNAL
# server module, and deploys the thin WAR. After this, the app runs VULNERABLE — and
# patch-vm.sh will fix it by swapping the module, with no rebuild of the WAR.
#
# Run on the VM as a user that can write to $WILDFLY_HOME. Requires: curl, unzip, java 17+.
set -euo pipefail

# ---- config (override via env) ------------------------------------------------
WILDFLY_VERSION="${WILDFLY_VERSION:-31.0.1.Final}"
WILDFLY_HOME="${WILDFLY_HOME:-$HOME/wildfly-demo}"
VULN_LOG4J="${VULN_LOG4J:-2.14.1}"
MAVEN_BASE="https://repo1.maven.org/maven2/org/apache/logging/log4j"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAR="${REPO_ROOT}/app/target/decoupled-patching-demo.war"
MODULE_DIR="${WILDFLY_HOME}/modules/com/redhat/demo/log4j/main"
# -------------------------------------------------------------------------------

echo ">> Decoupled Patching demo — WildFly setup"
echo "   WildFly ${WILDFLY_VERSION}  ->  ${WILDFLY_HOME}"
echo "   Log4j (vulnerable) ${VULN_LOG4J}"

# 1. Install WildFly if not already present
if [[ ! -d "${WILDFLY_HOME}" ]]; then
  echo ">> Downloading WildFly ${WILDFLY_VERSION}..."
  tmp="$(mktemp -d)"
  curl -fSL "https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.zip" \
       -o "${tmp}/wildfly.zip"
  unzip -q "${tmp}/wildfly.zip" -d "$(dirname "${WILDFLY_HOME}")"
  mv "$(dirname "${WILDFLY_HOME}")/wildfly-${WILDFLY_VERSION}" "${WILDFLY_HOME}"
  rm -rf "${tmp}"
else
  echo ">> WildFly already present at ${WILDFLY_HOME}, skipping download."
fi

# 2. Install the external Log4j module (the swappable part)
echo ">> Installing Log4j ${VULN_LOG4J} as server module com.redhat.demo.log4j ..."
mkdir -p "${MODULE_DIR}"
cp "${REPO_ROOT}/vm/modules/com/redhat/demo/log4j/main/module.xml" "${MODULE_DIR}/module.xml"
curl -fSL "${MAVEN_BASE}/log4j-api/${VULN_LOG4J}/log4j-api-${VULN_LOG4J}.jar"   -o "${MODULE_DIR}/log4j-api-${VULN_LOG4J}.jar"
curl -fSL "${MAVEN_BASE}/log4j-core/${VULN_LOG4J}/log4j-core-${VULN_LOG4J}.jar" -o "${MODULE_DIR}/log4j-core-${VULN_LOG4J}.jar"

# 3. Deploy the thin WAR
if [[ ! -f "${WAR}" ]]; then
  echo "!! WAR not found at ${WAR}"
  echo "   Build it first:  (cd ${REPO_ROOT}/app && mvn clean package)"
  exit 1
fi
echo ">> Deploying thin WAR ..."
cp "${WAR}" "${WILDFLY_HOME}/standalone/deployments/"

# 4. Report
echo ""
echo ">> Setup complete. Start the server with:"
echo "     ${WILDFLY_HOME}/bin/standalone.sh -b 0.0.0.0"
echo ""
echo "   Then verify (should report VULNERABLE):"
echo "     curl -s http://localhost:8080/api/version | jq ."
echo ""
echo "   The WAR that just deployed carries NO log4j — confirm with:"
echo "     unzip -l ${WAR} | grep -i log4j   # (expect: no matches)"
