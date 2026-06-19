start_all()

for machine in [primary1, standby1]:
    machine.wait_for_unit("postgresql")
    machine.wait_for_open_port(5432)

primary1.wait_until_succeeds(
    "psql -h 127.0.0.1 -U postgres -d postgres -Atqc \"SELECT NOT pg_is_in_recovery()\" | grep '^t$'",
    timeout=120,
)
standby1.wait_until_succeeds(
    "psql -h 127.0.0.1 -U postgres -d postgres -Atqc \"SELECT pg_is_in_recovery()\" | grep '^t$'",
    timeout=120,
)
standby1.wait_until_succeeds(
    "test -f \"$(psql -h 127.0.0.1 -U postgres -d postgres -Atqc 'SHOW data_directory')/standby.signal\"",
    timeout=120,
)

primary1.succeed(
    "psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c \""
    "CREATE TABLE IF NOT EXISTS topotestix_smoke (id integer primary key, payload text not null); "
    "INSERT INTO topotestix_smoke (id, payload) VALUES (1, 'ready') "
    "ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload;"
    "\""
)
standby1.wait_until_succeeds(
    "psql -h 127.0.0.1 -U postgres -d postgres -Atqc \"SELECT payload FROM topotestix_smoke WHERE id = 1\" | grep '^ready$'",
    timeout=120,
)
