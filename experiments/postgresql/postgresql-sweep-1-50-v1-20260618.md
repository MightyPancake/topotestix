# PostgreSQL v1 sweep 1..50

Target: `postgresql`

Date: 2026-06-18

Command:

```bash
nix-shell -p python3 python3Packages.textual --run \
  "python3 -m topotestix.cli orchestrator sweep postgresql --seeds 1..50 --project-root . --json"
```

Raw log:

- `experiments/postgresql/postgresql-sweep-1-50-v1-20260618-175119.log`

## Result

```json
{
  "completed": 50,
  "failed": 0,
  "failures": [],
  "skipped": 0,
  "target": "postgresql",
  "total": 50
}
```

Summary:

- Passed: 50
- Failed: 0
- Skipped: 0

## Interpretation

The PostgreSQL v1 primary/standby target is green across the first 50 seeds. The current v1 fuzz surface avoids known hot-standby-sensitive GUCs that require standby values to be at least primary values.

The configuration compatibility constraint found during bring-up is documented in [`postgresql-v1-findings.md`](postgresql-v1-findings.md).
