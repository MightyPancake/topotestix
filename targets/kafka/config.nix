{ lib, ... }:

{
  virtualisation.memorySize = with lib; [ 1024 2048 3072 4096 ];

  services.apache-kafka.enable = [ false true ];
  services.apache-kafka.jvmOptions = [
    [ "-Xms128m" "-Xmx256m" ]
    [ "-Xms256m" "-Xmx512m" ]
  ];
  services.apache-kafka.settings."num.network.threads" = [ 2 3 4 ];
  services.apache-kafka.settings."num.io.threads" = [ 4 6 8 ];
}
