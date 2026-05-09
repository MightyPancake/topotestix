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
      broker1 = { virtualisation.vlans = [ 1 ]; };
      broker2 = { virtualisation.vlans = [ 1 ]; };
      controller1 = { virtualisation.vlans = [ 2 ]; };
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
      broker1 = { virtualisation.vlans = [ 1 10 ]; };
      controller1 = { virtualisation.vlans = [ 2 10 ]; };
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
      broker1 = { virtualisation.vlans = [ 1 ]; };
      broker2 = { virtualisation.vlans = [ 1 ]; };
      brokerMixed1 = { virtualisation.vlans = [ 1 10 ]; };
      controller1 = { virtualisation.vlans = [ 2 ]; };
      controller2 = { virtualisation.vlans = [ 2 ]; };
      controllerMixed1 = { virtualisation.vlans = [ 2 10 ]; };
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
      broker1 = { virtualisation.vlans = [ 1 ]; };
    };
  };
}
