{ lib, ... }:

{
  virtualisation.memorySize = with lib; [ 512 1024 2048 4096 ];

  services.openssh.enable = [ false true ];

  services.nginx.enable = [ false true ];
}