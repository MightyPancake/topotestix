#!/usr/bin/env bash
# Run the nginx orchestrator test with a given seed.
#
# This uses the full orchestrate.nix pipeline:
#   fuzzer → expandTopology → merge → runner
#
# Usage:
#   ./run-orchestrator-test.sh          # default seed 5 (nginx enabled, should pass)
#   ./run-orchestrator-test.sh 1        # seed 1 (may disable nginx, expect failure)
#   ./run-orchestrator-test.sh 5        # seed 5 (nginx enabled, should pass)

set -euo pipefail

SEED="${1:-5}"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "============================================"
echo " TopoTestix nginx orchestrator test"
echo " Seed: ${SEED}"
echo "============================================"
echo ""

echo "--- Building and running VM test via orchestrator (this takes a few minutes) ---"

TEMP_NIX=$(mktemp --suffix=.nix)

cat > "$TEMP_NIX" <<EOF
let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  orchestrate = (import ${PROJECT_ROOT}/lib/orchestrate.nix { inherit pkgs lib; testers = pkgs.testers; }).orchestrate;

  topologyTarget = import ${PROJECT_ROOT}/targets/nginx/topology.nix { inherit lib; };
  configTarget = import ${PROJECT_ROOT}/targets/nginx/config.nix { inherit lib; };
  baseModule = import ${PROJECT_ROOT}/targets/nginx/module.nix;
  testScript = builtins.readFile ${PROJECT_ROOT}/targets/nginx/test-script.py;
  propertiesMod = import ${PROJECT_ROOT}/targets/nginx/properties.nix { inherit lib; };
in
orchestrate {
  seed = ${SEED};
  inherit topologyTarget configTarget baseModule testScript;
  properties = builtins.attrValues propertiesMod;
  name = "nginx-orchestrator-seed-${SEED}";
}
EOF

RESULT_LINK="$PROJECT_ROOT/result-orchestrator-seed-${SEED}"

BUILD_OUTPUT=$(nix build --impure --expr "import $TEMP_NIX" -L -o "$RESULT_LINK" 2>&1) && BUILD_OK=true || BUILD_OK=false

rm -f "$TEMP_NIX"

echo ""

if [ "$BUILD_OK" = true ]; then
  echo "✅ VM test SUCCEEDED"
else
  echo "❌ VM test FAILED"
  echo ""
  echo "--- Last lines of build output ---"
  echo "$BUILD_OUTPUT" | tail -20
fi

if [ -f "$RESULT_LINK/report.json" ]; then
  echo ""
  echo "--- Report (result-orchestrator-seed-${SEED}/report.json) ---"
  jq . "$RESULT_LINK/report.json"
elif [ "$BUILD_OK" = false ]; then
  echo ""
  echo "No report.json found. Test may have crashed before report could be written."
  echo "Full logs: nix log $RESULT_LINK"
fi

echo ""
echo "============================================"
echo " Done. Seed: ${SEED}"
echo " Result: $RESULT_LINK"
if [ -f "$RESULT_LINK/report.json" ]; then
  jq -r '.[] | "\(.name): \(.status)"' "$RESULT_LINK/report.json"
else
  echo " No report.json available"
fi
echo "============================================"

if [ "$BUILD_OK" = false ]; then
  exit 1
fi