# TopoTestix Fuzzer
#
# Deterministic, seed-based configuration generator.
#
# The fuzzer takes a seed and a target attribute set, and produces a flat
# attribute set where every list has been resolved to a single deterministic
# value. The seed ensures that different seeds produce different configurations,
# while the same seed always produces the same configuration.
#
# How it works:
#   1. The seed is used as a prefix for the attribute path hash
#   2. The combinators.resolve function walks the target, replacing every list
#      with a deterministic choice based on the full path (including seed prefix)
#   3. Different seeds → different prefix → different hash → different choices
#   4. Same seed + same target → same result (reproducible)
#
# The fuzzer is pure: it has no side effects, no randomness, and no awareness
# of clusters or node naming. It simply resolves a target spec to concrete
# values based on a seed.
#
# Example — simple config target:
#
#   fuzzer {
#     seed = "42";
#     target = {
#       virtualisation.memorySize = [ 512 1024 2048 4096 ];
#       services.openssh.enable = [ true false ];
#     };
#   }
#   # => { virtualisation.memorySize = 2048; services.openssh.enable = false; }
#
# Example — same target, different seed produces different results:
#
#   fuzzer {
#     seed = "99";
#     target = {
#       virtualisation.memorySize = [ 512 1024 2048 4096 ];
#       services.openssh.enable = [ true false ];
#     };
#   }
#   # => { virtualisation.memorySize = 512; services.openssh.enable = true; }
#   # (different seed → different choices)
#
# Example — topology target (same mechanism, different domain):
#
#   fuzzer {
#     seed = "1";
#     target = {
#       nodeCount = [ 1 3 5 ];
#       brokerVlans = [ [ 1 ] [ 1 10 ] ];
#       controllerVlans = [ [ 2 ] [ 2 10 ] ];
#     };
#   }
#   # => { nodeCount = 3; brokerVlans = [ 1 ]; controllerVlans = [ 2 ]; }
#   # (the fuzzer doesn't know or care that this is topology — it's just lists)
#
# The orchestrator calls the fuzzer multiple times with different derived seeds:
#   - master_seed + 0  →  topology target (node count, roles, VLANs)
#   - master_seed + 1  →  broker1 config target
#   - master_seed + 2  →  broker2 config target
#   - ...etc
#
# Example see for yourself:
#
# nix eval --impure --json --expr  '''
# let pkgs = import <nixpkgs> {};
# lib = pkgs.lib;
# fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
# in {
# seed1 = fuzzer { seed = "1"; target = { x = [1 2 3]; y = [true false]; }; };
# seed2 = fuzzer { seed = "2"; target = { x = [1 2 3]; y = [true false]; }; };
# same = fuzzer { seed = "1"; target = { x = [1 2 3]; y = [true false]; }; };
# }
# ''' 2>&1
# # =>
# {
#   "same": {
#     "x": 3,
#     "y": true
#   },
#   "seed1": {
#     "x": 3,
#     "y": true
#   },
#   "seed2": {
#     "x": 2,
#     "y": true
#   }
# }
{ lib }:

let
  combinators = import ./combinators.nix { inherit lib; };
in
{
  fuzzer = { seed, target }:
    combinators.resolve seed target;
}
