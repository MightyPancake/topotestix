{ lib }:

{
  helpers = {
    name = "postgresql-helpers";
    setup = ''
      import shlex
      import time

      def psql(machine, sql, host="127.0.0.1", db="postgres"):
          cmd = (
              f"psql -h {shlex.quote(host)} -U postgres -d {shlex.quote(db)} "
              f"-v ON_ERROR_STOP=1 -Atqc {shlex.quote(sql)}"
          )
          return machine.succeed(cmd).strip()

      def wait_for_sql(machine, sql, expected, host="127.0.0.1", db="postgres", timeout=120):
          deadline = time.time() + timeout
          last = None
          while time.time() < deadline:
              try:
                  out = psql(machine, sql, host=host, db=db)
                  if out == expected:
                      return out
                  last = out
              except Exception as exc:
                  last = str(exc)
              time.sleep(1)
          raise AssertionError(f"timed out waiting for SQL result {expected!r}; last={last!r}")
    '';
  };

  cluster_roles = {
    name = "postgresql-cluster-roles";
    setup = ''
      def check_primary_role(machine):
          out = psql(machine, "SELECT NOT pg_is_in_recovery()")
          if out != "t":
              raise AssertionError(f"expected primary, got {out!r}")

      def check_standby_role(machine):
          out = psql(machine, "SELECT pg_is_in_recovery()")
          if out != "t":
              raise AssertionError(f"expected standby, got {out!r}")

      def check_standby_signal(machine):
          machine.succeed(
              "test -f \"$(psql -h 127.0.0.1 -U postgres -d postgres -Atqc 'SHOW data_directory')/standby.signal\""
          )
    '';
    check = ''
      _check("postgresql-primary-role", check_primary_role, primary1)
      _check("postgresql-standby-role", check_standby_role, standby1)
      _check("postgresql-standby-signal", check_standby_signal, standby1)
    '';
  };

  replication_streaming = {
    name = "postgresql-replication-streaming";
    setup = ''
      def check_replication_streaming(primary, standby):
          wait_for_sql(primary, "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'", "1")
          wait_for_sql(standby, "SELECT status FROM pg_stat_wal_receiver", "streaming")
    '';
    check = ''
      _check("postgresql-replication-streaming", check_replication_streaming, primary1, standby1)
    '';
  };

  replicated_write_roundtrip = {
    name = "postgresql-replicated-write-roundtrip";
    setup = ''
      def check_replicated_write_roundtrip(primary, standby, key, value):
          psql(primary, "CREATE TABLE IF NOT EXISTS topotestix_replication (k text primary key, v text not null)")
          psql(
              primary,
              f"INSERT INTO topotestix_replication (k, v) VALUES ('{key}', '{value}') "
              f"ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v"
          )
          wait_for_sql(standby, f"SELECT v FROM topotestix_replication WHERE k = '{key}'", value)
    '';
    check = ''
      _check(
        "postgresql-replicated-write-roundtrip",
        check_replicated_write_roundtrip,
        primary1,
        standby1,
        "topotestix-kv",
        "value-1"
      )
    '';
  };

  standby_read_only = {
    name = "postgresql-standby-read-only";
    setup = ''
      def check_standby_read_only(machine):
          out = psql(machine, "SHOW transaction_read_only")
          if out != "on":
              raise AssertionError(f"expected transaction_read_only=on, got {out!r}")
    '';
    check = ''
      _check("postgresql-standby-read-only", check_standby_read_only, standby1)
    '';
  };

  zz_service_still_up_after_delay = {
    name = "postgresql-still-up-after-delay";
    setup = ''
      def check_postgresql_still_up(machine, expected_recovery):
          machine.succeed("sleep 20 && systemctl is-active postgresql")
          wait_for_sql(machine, "SELECT pg_is_in_recovery()", expected_recovery)
    '';
    check = ''
      _check("postgresql-primary-still-up", check_postgresql_still_up, primary1, "f")
      _check("postgresql-standby-still-up", check_postgresql_still_up, standby1, "t")
    '';
  };
}
