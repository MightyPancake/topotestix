#!/usr/bin/env bash
# Run the nginx smoke test with a given seed.
#
# Usage:
#   ./run-smoke-test.sh          # default seed 5 (nginx enabled, should pass)
#   ./run-smoke-test.sh 1        # seed 1 (nginx disabled, expect failure)
#   ./run-smoke-test.sh 5        # seed 5 (nginx enabled, should pass)

set -euo pipefail

SEED="${1:-5}"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "============================================"
echo " TopoTestix nginx smoke test"
echo " Seed: ${SEED}"
echo "============================================"
echo ""

# Step 1: Evaluate and print the fuzzed config
echo "--- Fuzzed config for seed ${SEED} ---"
FUZZED_CONFIG=$(nix eval --impure --json --expr "
  let
    pkgs = import <nixpkgs> {};
    lib = pkgs.lib;
    topotestixLib = import ${PROJECT_ROOT}/lib { inherit lib; };
    nginxConfigTarget = import ${PROJECT_ROOT}/targets/nginx/config.nix { inherit lib; };
  in
  topotestixLib.fuzzer.fuzzer { seed = \"${SEED}\"; target = nginxConfigTarget; }
" 2>/dev/null)

if [ -z "$FUZZED_CONFIG" ]; then
  echo "ERROR: Failed to evaluate fuzzed config"
  exit 1
fi

echo "$FUZZED_CONFIG" | jq .

NGINX_ENABLED=$(echo "$FUZZED_CONFIG" | jq -r '.services.nginx.enable')

echo ""
echo "nginx.enable = ${NGINX_ENABLED}"

if [ "$NGINX_ENABLED" = "false" ]; then
  echo ""
  echo "WARNING: This seed disables nginx. The property will fail (expected behavior)."
  echo "  Seeds that enable nginx: 5, 6, 10. Try: ./run-smoke-test.sh 5"
fi

echo ""
echo "--- Building and running VM test (this takes a few minutes) ---"

# Step 2: Build the test with the given seed
TEMP_NIX=$(mktemp --suffix=.nix)

cat > "$TEMP_NIX" <<EOF
let
  nixpkgs = builtins.getFlake "nixpkgs";
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  lib = pkgs.lib;

  topotestixLib = import ${PROJECT_ROOT}/lib { inherit lib; };
  runner = import ${PROJECT_ROOT}/lib/runner.nix { inherit pkgs lib; testers = pkgs.testers; };

  nginxConfigTarget = import ${PROJECT_ROOT}/targets/nginx/config.nix { inherit lib; };
  nginxBaseModule = import ${PROJECT_ROOT}/targets/nginx/module.nix;
  nginxProperties = import ${PROJECT_ROOT}/targets/nginx/properties.nix { inherit lib; };
  nginxTestScript = builtins.readFile ${PROJECT_ROOT}/targets/nginx/test-script.py;

  fuzzedConfig = topotestixLib.fuzzer.fuzzer { seed = "${SEED}"; target = nginxConfigTarget; };
in
runner.run {
  nodeConfigs = {
    machine = { pkgs, ... }:
      topotestixLib.merge.mergeConfigs {
        base = nginxBaseModule { inherit pkgs; };
        config = fuzzedConfig;
      };
  };
  testScript = nginxTestScript;
  properties = [ nginxProperties.responds_to_http ];
  name = "nginx-smoke-seed-${SEED}";
}
EOF

RESULT_LINK="$PROJECT_ROOT/result-seed-${SEED}"

BUILD_OUTPUT=$(nix build --impure --expr "import $TEMP_NIX" -L -o "$RESULT_LINK" 2>&1) && BUILD_OK=true || BUILD_OK=false

rm -f "$TEMP_NIX"

echo ""

# Step 3: Check result
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
  echo "--- Report (result-seed-${SEED}/report.json) ---"
  jq . "$RESULT_LINK/report.json"
elif [ "$BUILD_OK" = false ]; then
  echo ""
  echo "No report.json found. Test may have crashed before report could be written."
  echo "Full logs: nix log $RESULT_LINK"
fi

# Step 4: Summary
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