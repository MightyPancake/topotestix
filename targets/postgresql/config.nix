{ lib, ... }:

{
  # v1 fixed fuzz surface: 9 knobs total.
  virtualisation.memorySize = [ 1024 2048 ];
  virtualisation.diskSize = [ 2048 4096 ];

  services.postgresql.settings.checkpoint_timeout = [ "5min" "10min" ];
  services.postgresql.settings.shared_buffers = [ "128MB" "256MB" ];
  services.postgresql.settings.work_mem = [ "4MB" "16MB" ];
  services.postgresql.settings.maintenance_work_mem = [ "64MB" "128MB" ];
  services.postgresql.settings.wal_keep_size = [ "64MB" "256MB" ];
  services.postgresql.settings.checkpoint_completion_target = [ 0.5 0.9 ];
  services.postgresql.settings.max_wal_size = [ "1GB" "2GB" ];
}
