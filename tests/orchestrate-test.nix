{ lib, fuzzer, expand-topology, merge }:

let
  singleMachineTopology = {
    roles.machine = [ 1 ];
    machineVlans = [ [ 1 ] ];
  };

  fixedTopologyMap = {
    roles = { broker = 2; controller = 1; };
    brokerVlans = [ 1 ];
    controllerVlans = [ 2 10 ];
  };

  configTarget = {
    virtualisation.memorySize = [ 512 1024 2048 4096 ];
    services.openssh.enable = [ true false ];
  };

  baseConfig = {
    services.nginx.enable = true;
  };

  expansion = expand-topology { topology-map = fixedTopologyMap; };

  roleNamesSorted = builtins.sort (a: b: a < b) (builtins.attrNames fixedTopologyMap.roles);

  roleConfigs = builtins.listToAttrs (lib.imap0 (idx: roleName:
    {
      name = roleName;
      value = fuzzer { seed = toString (10 + idx); target = configTarget; };
    }
  ) roleNamesSorted);

in
{
  testSeedDerivationTopology = {
    expr = toString 10;
    expected = "10";
  };

  testSeedDerivationFirstRole = {
    expr = toString (10 + 1 + 0);
    expected = "11";
  };

  testSeedDerivationSecondRole = {
    expr = toString (10 + 1 + 1);
    expected = "12";
  };

  testRoleNamesAlphabetical = {
    expr = roleNamesSorted;
    expected = [ "broker" "controller" ];
  };

  testExpansionNodeConfigs = {
    expr = builtins.attrNames expansion.nodeConfigs;
    expected = [ "broker1" "broker2" "controller1" ];
  };

  testExpansionNodeRoles = {
    expr = expansion.nodeRoles;
    expected = {
      broker1 = "broker";
      broker2 = "broker";
      controller1 = "controller";
    };
  };

  testExpansionBrokerVlans = {
    expr = expansion.nodeConfigs.broker1.virtualisation.vlans;
    expected = [ 1 ];
  };

  testExpansionControllerVlans = {
    expr = expansion.nodeConfigs.controller1.virtualisation.vlans;
    expected = [ 2 10 ];
  };

  testSingleMachineNodeNames = {
    expr =
      let
        exp = expand-topology { topology-map = { roles = { machine = 1; }; machineVlans = [ 1 ]; }; };
      in
      builtins.attrNames exp.nodeConfigs;
    expected = [ "machine1" ];
  };

  testSingleMachineNodeRoles = {
    expr =
      let
        exp = expand-topology { topology-map = { roles = { machine = 1; }; machineVlans = [ 1 ]; }; };
      in
      exp.nodeRoles.machine1;
    expected = "machine";
  };

  testDifferentSeedsProduceDifferentRoleConfigs = {
    expr =
      roleConfigs.broker != roleConfigs.controller;
    expected = true;
  };

  testSameSeedProducesSameConfig = {
    expr =
      (fuzzer { seed = "11"; target = configTarget; })
      ==
      (fuzzer { seed = "11"; target = configTarget; });
    expected = true;
  };

  }