{
  description = "TopoTestix — environment-aware property-based testing for distributed systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self, nixpkgs, nix-unit }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      topotestixLib = import ./lib { inherit lib; };

      runner = import ./lib/runner.nix { inherit pkgs lib; testers = pkgs.testers; };

      nginxConfigTarget = import ./targets/config/nginx.nix { inherit lib; };
      nginxBaseModule = import ./targets/nginx/module.nix;
      nginxProperties = import ./targets/nginx/properties.nix { inherit lib; };
      nginxTestScript = builtins.readFile ./targets/nginx/test-script.py;

      fuzzedConfig = topotestixLib.fuzzer.fuzzer { seed = "5"; target = nginxConfigTarget; };

    in
    {
      lib = topotestixLib;

      tests = import ./tests { inherit lib; };

      packages.${system} = {
        default = pkgs.emptyDirectory;
      };

      nixosTests.${system} = {
        nginx-smoke = runner.run {
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
      };

      checks.${system} = {
        default = pkgs.runCommand "tests" {
          nativeBuildInputs = [ nix-unit.packages.${system}.default ];
        } ''
          export HOME="$TMPDIR"
          mkdir -p "$HOME/.cache/nix"
          nix-unit --eval-store "$TMPDIR/eval-store" \
            --extra-experimental-features flakes \
            --override-input nixpkgs ${nixpkgs} \
            --flake ${self}#tests
          touch $out
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nix-unit.packages.${system}.default
          python3
        ];

        shellHook = ''
          alias runtest='nix-unit --expr "import ./tests { lib = (import <nixpkgs> {}).lib; }"'
        '';
      };
    };
}
