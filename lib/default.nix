{ lib }:

let
  combinators = import ./combinators.nix { inherit lib; };
  fuzzer = import ./fuzzer.nix { inherit lib; };
  expand-topology = import ./expand-topology.nix { inherit lib; };
  merge = import ./merge.nix { inherit lib; };
  properties = import ./properties.nix { inherit lib; };
  shrinker = import ./shrinker.nix { inherit lib; };
in
{
  inherit combinators fuzzer expand-topology merge properties shrinker;
}