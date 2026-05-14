{ lib, ... }:

{
  virtualisation.memorySize = with lib; [ 512 1024 2048 4096 ];

  services.openssh.enable = [ true false ];

  services.nginx.enable = [ true false ];
}