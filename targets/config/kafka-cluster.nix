{ lib, ... }:

{
  virtualisation.memorySize = [ 2048 3072 4096 ];
  services.apache-kafka.jvmOptions = [
    [ "-Xms256m" "-Xmx512m" ]
    [ "-Xms512m" "-Xmx768m" ]
  ];
  services.apache-kafka.settings."num.network.threads" = [ 2 3 ];
  services.apache-kafka.settings."num.io.threads" = [ 4 6 ];
}
