# TopoTestix Fuzzer
#
# Deterministic, seed-based configuration generator.
#
# The fuzzer takes a seed and a target attribute set, and produces a resolved
# attribute set where every list has been replaced with a single deterministic
# value, along with a choices map recording which index was selected for each path.
#
# The choices map enables choice-based shrinking: each path maps to the index
# that the fuzzer selected. The shrinker can override specific indices to produce
# simpler configurations.
#
# How it works:
#   1. The seed is used as a prefix for the internal attribute path hash
#   2. The combinators.resolve function walks the target, replacing every list
#      with a deterministic choice based on the full path plus the seed prefix
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
#       services.openssh.enable = bool;
#     };
#   }
#   # => {
#   #   result = { virtualisation.memorySize = 2048; services.openssh.enable = false; };
#   #   choices = { ".virtualisation.memorySize" = 2; ".services.openssh.enable" = 0; };
#   # }
#
# Example — same target, different seed produces different results:
#
#   fuzzer {
#     seed = "99";
#     target = {
#       virtualisation.memorySize = [ 512 1024 2048 4096 ];
#       services.openssh.enable = bool;
#     };
#   }
#   # => { result = { ... }; choices = { ... }; }
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
#   # => {
#   #   result = { nodeCount = 3; brokerVlans = [ 1 ]; controllerVlans = [ 2 ]; };
#   #   choices = { ".nodeCount" = 1; ".brokerVlans" = 0; ".controllerVlans" = 0; };
#   # }
#   # (the fuzzer doesn't know or care that this is topology — it's just lists)
#
# The choices map is used by the shrinker to override specific indices during
# shrinking. See docs/shrinking.md for details.
#
# The orchestrator calls the fuzzer multiple times with different derived seeds:
#   - master_seed + 0  →  topology target (node count, roles, VLANs)
#   - master_seed + 1 + roleIndex  →  per-role config (alphabetical role order)
#
{ lib }:

let
  combinators = import ./combinators.nix { inherit lib; };
in
{
  fuzzer = { seed, target }:
    let
      resolved = combinators.resolveWithKeyPrefix seed "" target;
    in
    {
      result = resolved.value;
      choices = resolved.choices;
    };
}
