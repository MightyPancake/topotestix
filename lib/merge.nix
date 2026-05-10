# TopoTestix Merge Module
#
# Config merging utilities for composing NixOS configurations.
#
# mkForceAttrs:
#   Recursively applies lib.mkForce to all leaf values in an attrset.
#   Nested attrsets are recursed into; all other values (ints, bools,
#   strings, lists) get mkForce.
#
#   This gives fuzzed values priority 50, overriding base config defaults.
#
# mergeConfigs:
#   Three-layer config composition: base ⊕ config ⊕ topology.
#   Base is kept plain. Config and topology are mkForce'd before merging.
#   Topology wins over config on key conflicts (last recursiveUpdate wins).
#
#   Both config and topology use mkForce (priority 50). On conflicts,
#   topology wins by position, not by priority. In practice, config
#   and topology fuzz different dimensions (services/resources vs
#   network/VLAN), so conflicts should not arise. See docs/merge.md.
#
# Example:
#
#   mergeConfigs {
#     base = { services.nginx.enable = true; virtualisation.memorySize = 1024; };
#     config = { virtualisation.memorySize = 4096; };
#     topology = { virtualisation.vlans = [1 10]; };
#   }
#   # => { services.nginx.enable = true;
#   #      virtualisation.memorySize = mkForce 4096;
#   #      virtualisation.vlans = mkForce [1 10]; }

{ lib }:

let
  mkForceAttrs = attrs:
    lib.mapAttrs (name: value:
      if builtins.isAttrs value then
        mkForceAttrs value
      else
        lib.mkForce value
    ) attrs;

  mergeConfigs = { base, config ? {}, topology ? {} }:
    lib.recursiveUpdate
      (lib.recursiveUpdate base (mkForceAttrs config))
      (mkForceAttrs topology);

in
{
  inherit mkForceAttrs mergeConfigs;
}