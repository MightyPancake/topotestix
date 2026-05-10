{ lib }:

let
  combinators = import ../lib/combinators.nix { inherit lib; };
  fuzzerMod = import ../lib/fuzzer.nix { inherit lib; };
  expand-topology-mod = import ../lib/expand-topology.nix { inherit lib; };
  merge = import ../lib/merge.nix { inherit lib; };

  fuzzer = fuzzerMod.fuzzer;
  expandTopology = expand-topology-mod.expandTopology;
in
(import ./combinators-test.nix { inherit lib; combinators = combinators; })
//
(import ./fuzzer-test.nix { inherit lib; fuzzer = fuzzer; })
//
(import ./expand-topology-test.nix { inherit lib; expand-topology = expandTopology; })
//
(import ./merge-test.nix { inherit lib; merge = merge; })