# Base NixOS config for the nginx smoke test
#
# This is the "base" layer in the three-layer merge (base ⊕ config ⊕ topology).
# It defines the stable configuration that fuzzed values override via mkForce.
#
# Key points:
#   - services.nginx.enable = true  -- nginx is enabled by default
#   - virtualHosts."localhost" with default = true -- responds to curl localhost
#   - The fuzzed config may override nginx.enable to false (seed-dependent)
#   - /var/www is created in the testScript, not in the module

{ pkgs, ... }:

{
  services.nginx.enable = true;
  services.nginx.virtualHosts.localhost = {
    root = "/var/www";
    default = true;
  };

  environment.systemPackages = with pkgs; [
    curl
    vim
  ];
}