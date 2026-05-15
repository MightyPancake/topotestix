{ lib, expand-topology, ... }:

{
  testExpandSimpleCluster = {
    expr = expand-topology {
      topology-map = {
        roles = { broker = 2; controller = 1; };
        brokerVlans = [ 1 ];
        controllerVlans = [ 2 ];
      };
    };
    expected = {
      nodeConfigs = {
        broker1 = { virtualisation.vlans = [ 1 ]; };
        broker2 = { virtualisation.vlans = [ 1 ]; };
        controller1 = { virtualisation.vlans = [ 2 ]; };
      };
      nodeRoles = {
        broker1 = "broker";
        broker2 = "broker";
        controller1 = "controller";
      };
    };
  };

  testExpandMixedVlans = {
    expr = expand-topology {
      topology-map = {
        roles = { broker = 1; controller = 1; };
        brokerVlans = [ 1 10 ];
        controllerVlans = [ 2 10 ];
      };
    };
    expected = {
      nodeConfigs = {
        broker1 = { virtualisation.vlans = [ 1 10 ]; };
        controller1 = { virtualisation.vlans = [ 2 10 ]; };
      };
      nodeRoles = {
        broker1 = "broker";
        controller1 = "controller";
      };
    };
  };

  testExpandPartlyMixedVlans = {
    expr = expand-topology {
      topology-map = {
        roles = { broker = 2; brokerMixed = 1; controller = 2; controllerMixed = 1; };
        brokerMixedVlans = [ 1 10 ];
        controllerMixedVlans = [ 2 10 ];
        brokerVlans = [ 1 ];
        controllerVlans = [ 2 ];
      };
    };
    expected = {
      nodeConfigs = {
        broker1 = { virtualisation.vlans = [ 1 ]; };
        broker2 = { virtualisation.vlans = [ 1 ]; };
        brokerMixed1 = { virtualisation.vlans = [ 1 10 ]; };
        controller1 = { virtualisation.vlans = [ 2 ]; };
        controller2 = { virtualisation.vlans = [ 2 ]; };
        controllerMixed1 = { virtualisation.vlans = [ 2 10 ]; };
      };
      nodeRoles = {
        broker1 = "broker";
        broker2 = "broker";
        brokerMixed1 = "brokerMixed";
        controller1 = "controller";
        controller2 = "controller";
        controllerMixed1 = "controllerMixed";
      };
    };
  };

  testExpandSingleNode = {
    expr = expand-topology {
      topology-map = {
        roles = { broker = 1; };
        brokerVlans = [ 1 ];
      };
    };
    expected = {
      nodeConfigs = {
        broker1 = { virtualisation.vlans = [ 1 ]; };
      };
      nodeRoles = {
        broker1 = "broker";
      };
    };
  };

  testNodeRolesMapsEachNodeToItsRole = {
    expr =
      let
        result = expand-topology {
          topology-map = {
            roles = { broker = 3; controller = 1; };
            brokerVlans = [ 1 ];
            controllerVlans = [ 2 ];
          };
        };
      in
      result.nodeRoles;
    expected = {
      broker1 = "broker";
      broker2 = "broker";
      broker3 = "broker";
      controller1 = "controller";
    };
  };

  testNodeConfigsAndNodeRolesHaveSameKeys = {
    expr =
      let
        result = expand-topology {
          topology-map = {
            roles = { broker = 2; controller = 1; };
            brokerVlans = [ 1 ];
            controllerVlans = [ 2 ];
          };
        };
      in
      builtins.attrNames result.nodeConfigs == builtins.attrNames result.nodeRoles;
    expected = true;
  };
}