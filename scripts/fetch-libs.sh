#!/usr/bin/env bash
# fetch-libs.sh <version> — place Log4j api+core into the OpenShift build context
# as unversioned filenames (log4j-api.jar / log4j-core.jar). Run before an image build.
set -euo pipefail
VERSION="${1:-2.14.1}"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/openshift/module"
BASE="https://repo1.maven.org/maven2/org/apache/logging/log4j"

echo ">> Fetching Log4j ${VERSION} into build context ..."
curl -fSL "${BASE}/log4j-api/${VERSION}/log4j-api-${VERSION}.jar"   -o "${DEST}/log4j-api.jar"
curl -fSL "${BASE}/log4j-core/${VERSION}/log4j-core-${VERSION}.jar" -o "${DEST}/log4j-core.jar"
echo "   Placed log4j ${VERSION} as ${DEST}/log4j-{api,core}.jar"
