{ lib, merge, ... }:

let
  inherit (merge) mkForceAttrs mergeConfigs;
in
{
  testMkForceAttrsFlat = {
    expr = mkForceAttrs { x = 1; y = true; z = "hello"; };
    expected = { x = lib.mkForce 1; y = lib.mkForce true; z = lib.mkForce "hello"; };
  };

  testMkForceAttrsNested = {
    expr = mkForceAttrs { services.nginx.enable = true; virtualisation.memorySize = 2048; };
    expected = { services = { nginx = { enable = lib.mkForce true; }; }; virtualisation = { memorySize = lib.mkForce 2048; }; };
  };

  testMkForceAttrsList = {
    expr = mkForceAttrs { virtualisation.vlans = [ 1 10 ]; };
    expected = { virtualisation = { vlans = lib.mkForce [ 1 10 ]; }; };
  };

  testMkForceAttrsEmpty = {
    expr = mkForceAttrs {};
    expected = {};
  };

  testMkForceAttrsKeepsMkIfWhole = {
    expr = mkForceAttrs { services.nginx = lib.mkIf true { enable = true; }; };
    expected = { services = { nginx = lib.mkForce (lib.mkIf true { enable = true; }); }; };
  };

  testMkForceAttrsKeepsMkMergeWhole = {
    expr = mkForceAttrs { services.nginx = lib.mkMerge [ { enable = true; } ]; };
    expected = { services = { nginx = lib.mkForce (lib.mkMerge [ { enable = true; } ]); }; };
  };

  testMergeConfigsBaseAndConfig = {
    expr = mergeConfigs {
      base = { services.nginx.enable = true; virtualisation.memorySize = 1024; };
      config = { virtualisation.memorySize = 4096; };
    };
    expected = { services = { nginx = { enable = true; }; }; virtualisation = { memorySize = lib.mkForce 4096; }; };
  };

  testMergeConfigsAllThreeLayers = {
    expr = mergeConfigs {
      base = { services.nginx.enable = true; virtualisation.memorySize = 1024; };
      config = { virtualisation.memorySize = 4096; };
      topology = { virtualisation.vlans = [ 1 10 ]; };
    };
    expected = {
      services = { nginx = { enable = true; }; };
      virtualisation = { memorySize = lib.mkForce 4096; vlans = lib.mkForce [ 1 10 ]; };
    };
  };

  testMergeConfigsTopologyOverridesConfig = {
    expr = mergeConfigs {
      base = { x = 1; y = 2; };
      config = { y = 3; };
      topology = { y = 4; };
    };
    expected = { x = 1; y = lib.mkForce 4; };
  };

  testMergeConfigsBaseOnly = {
    expr = mergeConfigs {
      base = { services.nginx.enable = true; };
    };
    expected = { services = { nginx = { enable = true; }; }; };
  };

  testMergeConfigsEmptyConfigAndTopology = {
    expr = mergeConfigs {
      base = { x = 1; };
      config = {};
      topology = {};
    };
    expected = { x = 1; };
  };
}
