# TopoTestiX expandTopology
#
# Deterministic expansion of a topology-map into per-node VLAN configurations.
#
# This function takes a flat topology-map (typically the output of a fuzzer call
# with a topology target spec) and mechanically expands it into per-node NixOS
# attribute sets containing `virtualisation.vlans` assignments.
#
# It is NOT a fuzzer — it has no seed, no randomness, no choices. It takes the
# decisions already made by the fuzzer (how many brokers, which VLANs per role)
# and turns them into individual node configs.
#
# The naming convention is: <role><index>, where index starts at 1.
# e.g. 2 brokers → broker1, broker2
# e.g. 1 controller → controller1
#
# VLAN membership model:
#   - Nodes on the same VLAN can communicate with each other
#   - Nodes on different VLANs cannot communicate
#   - A node can be on multiple VLANs (enables mixed topologies)
#   - e.g. brokerVlans = [1 10] means brokers are on VLAN 1 AND VLAN 10
#   - This allows patterns like: isolated role networks + shared communication VLAN
#
# Example — simple isolated topology:
#
#   expandTopology {
#     topology-map = {
#       roles = { broker = 2; controller = 1; };
#       brokerVlans = [ 1 ];
#       controllerVlans = [ 2 ];
#     };
#   }
#   # => {
#   #   nodeConfigs = {
#   #     broker1     = { virtualisation.vlans = [ 1 ]; };
#   #     broker2     = { virtualisation.vlans = [ 1 ]; };
#   #     controller1 = { virtualisation.vlans = [ 2 ]; };
#   #   };
#   #   nodeRoles = {
#   #     broker1     = "broker";
#   #     broker2     = "broker";
#   #     controller1 = "controller";
#   #   };
#   # }
#   # Brokers on VLAN 1, controller on VLAN 2 — they cannot reach each other.
#
# Example — mixed topology with shared VLAN:
#
#   expandTopology {
#     topology-map = {
#       roles = { broker = 2; controller = 1; };
#       brokerVlans = [ 1 10 ];
#       controllerVlans = [ 2 10 ];
#     };
#   }
#   # => {
#   #   nodeConfigs = {
#   #     broker1     = { virtualisation.vlans = [ 1 10 ]; };
#   #     broker2     = { virtualisation.vlans = [ 1 10 ]; };
#   #     controller1 = { virtualisation.vlans = [ 2 10 ]; };
#   #   };
#   #   nodeRoles = {
#   #     broker1     = "broker";
#   #     broker2     = "broker";
#   #     controller1 = "controller";
#   #   };
#   # }
#   # Brokers on VLAN 1 + shared VLAN 10, controller on VLAN 2 + shared VLAN 10.
#   # VLAN 10 allows cross-role communication while VLANs 1 and 2 isolate role traffic.
#
# Example — partitioned topology (broker isolated from controller):
#
#   Fuzzer picks a topology where brokers only have their role VLAN,
#   but the controller has a shared VLAN that brokers don't:
#
#   expandTopology {
#     topology-map = {
#       roles = { broker = 1; controller = 1; };
#       brokerVlans = [ 1 ];         # broker only on VLAN 1
#       controllerVlans = [ 2 10 ];  # controller on VLAN 2 + shared VLAN 10
#     };
#   }
#   # => {
#   #   nodeConfigs = {
#   #     broker1     = { virtualisation.vlans = [ 1 ]; };
#   #     controller1 = { virtualisation.vlans = [ 2 10 ]; };
#   #   };
#   #   nodeRoles = {
#   #     broker1     = "broker";
#   #     controller1 = "controller";
#   #   };
#   # }
#   # broker1 is on VLAN 1 only, controller1 is on VLANs 2 and 10.
#   # They cannot communicate — this simulates a partition.
#
# Example — single node:
#
#   expandTopology {
#     topology-map = {
#       roles = { broker = 1; };
#       brokerVlans = [ 1 ];
#     };
#   }
#   # => {
#   #   nodeConfigs = { broker1 = { virtualisation.vlans = [ 1 ]; }; };
#   #   nodeRoles = { broker1 = "broker"; };
#   # }
#
# How this fits in the pipeline:
#
#   1. Fuzzer:     fuzzer { seed = "42"; target = topologySpec; }
#                  → { nodeCount = 3; roles.broker = 2; roles.controller = 1;
#                      brokerVlans = [ 1 ]; controllerVlans = [ 2 ]; }
#
#   2. expandTopology: takes the fuzzer output and expands it into per-node configs
#                  → { nodeConfigs = { broker1.vlans = [1]; broker2.vlans = [1]; controller1.vlans = [2]; };
#                      nodeRoles = { broker1 = "broker"; broker2 = "broker"; controller1 = "controller"; }; }
#
#   3. Orchestrator: merges per-node topology configs with base + fuzzer configs
#                  → final node configs ready for NixOS test runner
#
# Note: The VLAN naming convention for role keys follows the pattern <role>Vlans.
# For a role named "broker", the VLAN key is "brokerVlans". If no VLAN key exists
# for a role, it defaults to an empty list (no network connectivity).
#
# Current limitation: VLAN assignment is per-role, not per-node. All nodes with the
# same role get the same VLANs. For per-node VLAN variation (e.g., broker1 on
# VLAN 1 but broker2 on VLANs 1 and 10), the fuzzer handles this via per-node
# config seeds — the orchestrator can assign different VLAN sets to individual
# nodes after expansion by overriding their configs in the three-layer merge.
#
# Output structure:
#
#   expandTopology returns { nodeConfigs, nodeRoles } where:
#   - nodeConfigs: attrset mapping node names to their VLAN configs
#   - nodeRoles: attrset mapping node names to their role names
#
#   The nodeRoles mapping is needed by orchestrate.nix to look up which role
#   config applies to each node during the three-layer merge.
#
{ lib }:

{
  expandTopology = { topology-map }:
    let
      # All role names from the topology-map (e.g. ["broker", "controller"])
      roleNames = builtins.attrNames topology-map.roles;

      # expandRole : string -> { configs : attrset, roles : attrset }
      #
      # For a given role name, generate N node entries where N is the
      # count specified in topology-map.roles.
      #
      # Returns both the node configs (for VLAN assignment) and the
      # node-to-role mapping (for orchestrator per-role config lookup).
      #
      # Step by step, for expandRole "broker" with:
      #   topology-map.roles.broker    = 2
      #   topology-map.brokerVlans     = [ 1 10 ]
      #
      #   1. count = 2                                — we need 2 broker nodes
      #   2. vlanKey = "brokerVlans"                  — derive VLAN key from role name
      #   3. vlans = [ 1 10 ]                         — look up VLANs in topology-map
      #   4. mkNode 0 => { name = "broker1"; value = { virtualisation.vlans = [ 1 10 ]; }; }
      #      mkNode 1 => { name = "broker2"; value = { virtualisation.vlans = [ 1 10 ]; }; }
      #   5. configs => { broker1 = { virtualisation.vlans = [ 1 10 ]; };
      #                   broker2 = { virtualisation.vlans = [ 1 10 ]; }; }
      #      roles   => { broker1 = "broker"; broker2 = "broker"; }
      #
      # All nodes of the same role get identical VLANs — network topology is
      # a property of the role, not the individual node. Per-node variation
      # is handled by the orchestrator's three-layer merge.
      #
      expandRole = roleName:
        let
          count = topology-map.roles.${roleName};

          vlanKey = "${roleName}Vlans";

          vlans = topology-map.${vlanKey} or [];

          mkNode = idx: {
            name = "${roleName}${toString (idx + 1)}";
            value = { virtualisation.vlans = vlans; };
          };

          nodeNames = map (idx: "${roleName}${toString (idx + 1)}") (lib.range 0 (count - 1));
        in
        {
          configs = builtins.listToAttrs (lib.genList mkNode count);
          roles = builtins.listToAttrs (map (name: { inherit name; value = roleName; }) nodeNames);
        };

      # Merge all role expansions into a single result.
      #
      # Starting from { nodeConfigs = {}; nodeRoles = {}; }, for each role name,
      # expand it and merge both configs and roles into the accumulators.
      #
      #   { nodeConfigs = {}; nodeRoles = {}; }
      #     // expandRole "broker"
      #   => { nodeConfigs = { broker1 = ...; broker2 = ...; };
      #        nodeRoles   = { broker1 = "broker"; broker2 = "broker"; }; }
      #     // expandRole "controller"
      #   => { nodeConfigs = { broker1 = ...; broker2 = ...; controller1 = ...; };
      #        nodeRoles   = { broker1 = "broker"; broker2 = "broker"; controller1 = "controller"; }; }
      #
      mergeExpansion = acc: roleName:
        let
          expansion = expandRole roleName;
        in
        {
          nodeConfigs = acc.nodeConfigs // expansion.configs;
          nodeRoles = acc.nodeRoles // expansion.roles;
        };

      initial = { nodeConfigs = {}; nodeRoles = {}; };

    in
    builtins.foldl' mergeExpansion initial roleNames;
}