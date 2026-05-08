{ lib }:

let
  combinators = import ./combinators.nix { inherit lib; };
  fuzzer = import ./fuzzer.nix { inherit lib; };
  expand-topology = import ./expand-topology.nix { inherit lib; };
  properties = import ./properties.nix { inherit lib; };
in
{
  inherit combinators fuzzer expand-topology properties;
}