{ pkgs, nodeName, ... }:

let
  lib = pkgs.lib;
  isPrimary = nodeName == "primary1";
  isStandby = nodeName == "standby1";
  pgPackage = pkgs.postgresql_17;
  dataDir = "/var/lib/postgresql/17";
  port = 5432;
in
{
  system.stateVersion = "24.05";

  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 2048;

  networking.firewall.allowedTCPPorts = [ port ];

  environment.systemPackages = [ pgPackage ];

  services.postgresql = {
    enable = true;
    package = pgPackage;
    enableTCPIP = true;
    authentication = ''
      local all postgres peer map=postgres
      local all all peer
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128 trust
      host  all all 0.0.0.0/0 trust
      host  all all ::0/0 trust
      host  replication all 0.0.0.0/0 trust
      host  replication all ::0/0 trust
    '';
    dataDir = dataDir;
    settings = {
      port = port;
      wal_level = "replica";
      hot_standby = true;
      max_connections = 50;
      shared_buffers = "128MB";
      work_mem = "4MB";
      maintenance_work_mem = "64MB";
      wal_keep_size = "64MB";
      max_wal_senders = 5;
      max_wal_size = "1GB";
    };
  };

  systemd.services.postgresql.preStart = lib.mkIf isStandby (lib.mkBefore ''
    if ! test -e ${dataDir}/PG_VERSION; then
      rm -rf ${dataDir}/*

      for attempt in $(seq 1 60); do
        if pg_isready -h primary1 -p ${toString port} -U postgres >/dev/null 2>&1; then
          break
        fi
        sleep 1
      done

      for attempt in $(seq 1 10); do
        if pg_basebackup \
          -h primary1 \
          -p ${toString port} \
          -U postgres \
          -D ${dataDir} \
          -R \
          -X stream \
          -c fast
        then
          break
        fi
        if [ "$attempt" -eq 10 ]; then
          echo "pg_basebackup failed after repeated attempts" >&2
          exit 1
        fi
        sleep 2
      done

      test -f ${dataDir}/standby.signal
    fi
  '');

  assertions = [
    {
      assertion = isPrimary || isStandby;
      message = "postgresql target expects nodeName to be primary1 or standby1";
    }
  ];
}
