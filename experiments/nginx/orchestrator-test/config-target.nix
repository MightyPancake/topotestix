# Nginx config fuzz target
#
# This is the "config target" fed to the fuzzer. Each list represents a
# dimension the fuzzer can explore. The fuzzer resolves every list to a
# single value based on the seed.
#
# Total configuration space: 4 × 2 × 2 = 16 variants
#
# Some seeds disable nginx (services.nginx.enable = false), which will
# cause the property to correctly fail. This is PBT working as intended.

{ lib, ... }:

{
  virtualisation.memorySize = with lib; [ 512 1024 2048 4096 ];

  services.openssh.enable = [ true false ];

  services.nginx.enable = [ true false ];
}