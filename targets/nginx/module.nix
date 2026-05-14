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