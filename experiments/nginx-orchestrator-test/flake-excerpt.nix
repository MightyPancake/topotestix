# Flake excerpt: nginx-orchestrator test definition
#
# This shows how the flake.nix wires up the full pipeline using orchestrate.nix:
#   fuzzer → expandTopology → merge → runner → NixOS test
#
# The actual flake.nix is in the project root. This is an annotated
# reference showing the nginx-orchestrator test definition.

/*
  In flake.nix, these bindings are at the top of the `outputs` let-block:

    orchestrate = (import ./lib/orchestrate.nix { inherit pkgs lib; testers = pkgs.testers; }).orchestrate;
    topologyTarget = import ./targets/topology/single-machine.nix { inherit lib; };
    configTarget = import ./targets/config/nginx.nix { inherit lib; };
    baseModule = import ./targets/nginx/module.nix;
    nginxTestScript = builtins.readFile ./targets/nginx/test-script.py;
    propertiesMod = import ./targets/nginx/properties.nix { inherit lib; };

  And the test is in nixosTests:

    nixosTests.${system}.nginx-orchestrator = orchestrate {
      seed = 5;
      inherit topologyTarget configTarget baseModule testScript;
      properties = builtins.attrValues propertiesMod;
      name = "nginx-orchestrator";
    };

  Key observations:

    - orchestrate.nix handles the full pipeline: fuzzer (topology + per-role config),
      expandTopology, three-layer merge, and runner.

    - seed = 5 is hardcoded in the flake. The run-orchestrator-test.sh script
      builds with a different seed by generating a temp .nix file.

    - The topology target for single-node tests is single-machine.nix,
      which defines { roles.machine = 1; machineVlans = [ [1] ]; }.
      This produces node name "machine1" (always indexed naming).

    - properties = builtins.attrValues propertiesMod includes all
      properties from the module automatically.

    - Built with: nix build .#nixosTests.x86_64-linux.nginx-orchestrator
      Report at: result/report.json
*/