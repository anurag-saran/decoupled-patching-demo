#!/usr/bin/env bash
# cleanup-openshift.sh — remove everything the demo created from the current project.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo ">> Removing demo resources from project $(oc project -q) ..."
oc delete -f "${ROOT}/openshift/canary.yaml"      --ignore-not-found
oc delete -f "${ROOT}/openshift/deployment.yaml"  --ignore-not-found
oc delete -f "${ROOT}/openshift/buildconfig.yaml" --ignore-not-found
oc delete imagestreamtag decoupled-patching-demo:vulnerable decoupled-patching-demo:patched decoupled-patching-demo:stable --ignore-not-found 2>/dev/null || true
echo ">> Done."
