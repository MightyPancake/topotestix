# etcd-cluster sweep 1..50 summary

The 50-seed etcd sweep was completed in two commands because the first foreground command hit the 3-hour harness timeout after seed 37. Seeds 38..50 were completed in a continuation run.

## Aggregate

- Target: `etcd-cluster`
- Seeds: `1..50`
- Passed: 39
- Failed: 11
- Total: 50

## Failed seeds

5, 7, 20, 21, 25, 29, 30, 34, 38, 42, 49

## Failure class

All failures are startup/configuration failures: etcd rejects `election-timeout=1000` with `heartbeat-interval=250` because election timeout must be at least five times the heartbeat interval.

Representative etcd log message:

```text
failed to verify flags: --election-timeout[1000ms] should be at least as 5 times as --heartbeat-interval[250ms]
```

## Interpretation

This is a real etcd configuration constraint, not an etcd implementation bug. The target currently exposes an invalid timing combination, so the failures occur before post-start properties run (`0/0` property report). For a stronger thesis case study, either frame this as configuration validation discovery or remove the invalid combination and sweep again for runtime/data-plane failures.

## Logs

- `experiments/etcd-cluster-sweep-1-50-20260615.log`
- `experiments/etcd-cluster-sweep-38-50-20260616.log`

## Per-seed table

| Seed | Status | heartbeat ms | election ms | Class | Run dir |
|---:|---|---:|---:|---|---|
| 1 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-211934-etcd-cluster-seed-1-etcd-cluster-seed-1` |
| 2 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-211942-etcd-cluster-seed-2-etcd-cluster-seed-2` |
| 3 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-211951-etcd-cluster-seed-3-etcd-cluster-seed-3` |
| 4 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-212000-etcd-cluster-seed-4-etcd-cluster-seed-4` |
| 5 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-212148-etcd-cluster-seed-5-etcd-cluster-seed-5` |
| 6 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-213712-etcd-cluster-seed-6-etcd-cluster-seed-6` |
| 7 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-213903-etcd-cluster-seed-7-etcd-cluster-seed-7` |
| 8 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-215427-etcd-cluster-seed-8-etcd-cluster-seed-8` |
| 9 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-215618-etcd-cluster-seed-9-etcd-cluster-seed-9` |
| 10 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-215812-etcd-cluster-seed-10-etcd-cluster-seed-10` |
| 11 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-220005-etcd-cluster-seed-11-etcd-cluster-seed-11` |
| 12 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-220158-etcd-cluster-seed-12-etcd-cluster-seed-12` |
| 13 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-220347-etcd-cluster-seed-13-etcd-cluster-seed-13` |
| 14 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-220534-etcd-cluster-seed-14-etcd-cluster-seed-14` |
| 15 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-220725-etcd-cluster-seed-15-etcd-cluster-seed-15` |
| 16 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-220913-etcd-cluster-seed-16-etcd-cluster-seed-16` |
| 17 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-221059-etcd-cluster-seed-17-etcd-cluster-seed-17` |
| 18 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-221247-etcd-cluster-seed-18-etcd-cluster-seed-18` |
| 19 | passed | 100 | 2500 |  | `.topotestix/runs/20260615-221432-etcd-cluster-seed-19-etcd-cluster-seed-19` |
| 20 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-221620-etcd-cluster-seed-20-etcd-cluster-seed-20` |
| 21 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-223144-etcd-cluster-seed-21-etcd-cluster-seed-21` |
| 22 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-224703-etcd-cluster-seed-22-etcd-cluster-seed-22` |
| 23 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-224850-etcd-cluster-seed-23-etcd-cluster-seed-23` |
| 24 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-225033-etcd-cluster-seed-24-etcd-cluster-seed-24` |
| 25 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-225220-etcd-cluster-seed-25-etcd-cluster-seed-25` |
| 26 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-230739-etcd-cluster-seed-26-etcd-cluster-seed-26` |
| 27 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-230923-etcd-cluster-seed-27-etcd-cluster-seed-27` |
| 28 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-231112-etcd-cluster-seed-28-etcd-cluster-seed-28` |
| 29 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-231303-etcd-cluster-seed-29-etcd-cluster-seed-29` |
| 30 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-232826-etcd-cluster-seed-30-etcd-cluster-seed-30` |
| 31 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-234345-etcd-cluster-seed-31-etcd-cluster-seed-31` |
| 32 | passed | 100 | 1000 |  | `.topotestix/runs/20260615-234531-etcd-cluster-seed-32-etcd-cluster-seed-32` |
| 33 | passed | 250 | 2500 |  | `.topotestix/runs/20260615-234716-etcd-cluster-seed-33-etcd-cluster-seed-33` |
| 34 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260615-234901-etcd-cluster-seed-34-etcd-cluster-seed-34` |
| 35 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-000420-etcd-cluster-seed-35-etcd-cluster-seed-35` |
| 36 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-000607-etcd-cluster-seed-36-etcd-cluster-seed-36` |
| 37 | passed | 100 | 1000 |  | `.topotestix/runs/20260616-000753-etcd-cluster-seed-37-etcd-cluster-seed-37` |
| 38 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260616-001957-etcd-cluster-seed-38-etcd-cluster-seed-38` |
| 39 | passed | 100 | 2500 |  | `.topotestix/runs/20260616-003508-etcd-cluster-seed-39-etcd-cluster-seed-39` |
| 40 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-003700-etcd-cluster-seed-40-etcd-cluster-seed-40` |
| 41 | passed | 100 | 1000 |  | `.topotestix/runs/20260616-003855-etcd-cluster-seed-41-etcd-cluster-seed-41` |
| 42 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260616-004048-etcd-cluster-seed-42-etcd-cluster-seed-42` |
| 43 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-005609-etcd-cluster-seed-43-etcd-cluster-seed-43` |
| 44 | passed | 100 | 2500 |  | `.topotestix/runs/20260616-005805-etcd-cluster-seed-44-etcd-cluster-seed-44` |
| 45 | passed | 100 | 1000 |  | `.topotestix/runs/20260616-010000-etcd-cluster-seed-45-etcd-cluster-seed-45` |
| 46 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-010152-etcd-cluster-seed-46-etcd-cluster-seed-46` |
| 47 | passed | 100 | 2500 |  | `.topotestix/runs/20260616-010346-etcd-cluster-seed-47-etcd-cluster-seed-47` |
| 48 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-010550-etcd-cluster-seed-48-etcd-cluster-seed-48` |
| 49 | failed | 250 | 1000 | invalid-etcd-election-timeout-heartbeat-ratio | `.topotestix/runs/20260616-010747-etcd-cluster-seed-49-etcd-cluster-seed-49` |
| 50 | passed | 250 | 2500 |  | `.topotestix/runs/20260616-012308-etcd-cluster-seed-50-etcd-cluster-seed-50` |
