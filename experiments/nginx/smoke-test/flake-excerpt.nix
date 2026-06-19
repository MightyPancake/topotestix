# Flake excerpt: nginx-smoke test definition
#
# This shows how the flake.nix wires up the full pipeline:
#   fuzzer → merge → runner → NixOS test
#
# The actual flake.nix is in the project root. This is an annotated
# reference showing only the nginx-smoke test definition.

/*
  In flake.nix, these bindings are at the top of the `outputs` let-block:

    topotestixLib = import ./lib { inherit lib; };
    runner = import ./lib/runner.nix { inherit pkgs lib; testers = pkgs.testers; };
    nginxConfigTarget = import ./targets/nginx/config.nix { inherit lib; };
    nginxBaseModule = import ./targets/nginx/module.nix;
    nginxProperties = import ./targets/nginx/properties.nix { inherit lib; };
    nginxTestScript = builtins.readFile ./targets/nginx/test-script.py;
    fuzzedConfig = topotestixLib.fuzzer.fuzzer { seed = "5"; target = nginxConfigTarget; };

  And the test is in nixosTests:

    nixosTests.${system}.nginx-smoke = runner.run {
      nodeConfigs = {
        machine = { pkgs, ... }:
          topotestixLib.merge.mergeConfigs {
            base = nginxBaseModule { inherit pkgs; };
            config = fuzzedConfig;
          };
      };
      testScript = nginxTestScript;
      properties = [ nginxProperties.responds_to_http ];
      name = "nginx-smoke";
    };

  Key observations:

    - seed = "5" is hardcoded in the flake. The run-smoke-test.sh script
      builds the flake with a different seed by overriding this value.

    - nodeConfigs.machine is a module function { pkgs, ... }: ...
      because runNixOSTest requires module functions as node values.
      The merge happens INSIDE the module function, where pkgs is in scope.

    - nginxBaseModule { inherit pkgs; } calls the module function to get
      a plain attrset, which mergeConfigs can then merge with fuzzedConfig.

    - properties is a list containing one property: responds_to_http.
      The properties.nix returns an attrset, so we extract the individual
      property with .responds_to_http.

    - Built with: nix build .#nixosTests.x86_64-linux.nginx-smoke
      Report at: result/report.json
*/