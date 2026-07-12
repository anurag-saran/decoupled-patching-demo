#!/usr/bin/env bash
# build.sh — build the thin WAR, then prove it carries no Log4j.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ">> Building the thin WAR ..."
( cd "${ROOT}/app" && mvn -q clean package )

WAR="${ROOT}/app/target/decoupled-patching-demo.war"
echo ">> Built: ${WAR}"

echo ">> Proving the WAR is thin (no bundled Log4j LIBRARY) ..."
if unzip -l "${WAR}" | grep -iE 'log4j-(api|core).*\.jar'; then
  echo "   ⚠️  A Log4j JAR was FOUND inside the WAR — it is not thin. Check pom.xml scopes."
  exit 1
else
  echo "   ✅  No Log4j JAR inside the WAR. The library is supplied by the server module."
  echo "      (log4j2.xml — the app's own logging config — is expected to be present; that's not a library.)"
fi
