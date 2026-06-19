# etcd-cluster v2 sweep 1..50 summary

v2 removes the invalid startup-only timing combination from v1 and adds a final quota write-burst property.

## Aggregate

- Target: `etcd-cluster`
- Variant: `v2`
- Seeds: `1..50`
- Passed: 37
- Failed: 13
- Total: 50

## Failed seeds

3, 6, 12, 13, 14, 28, 33, 34, 38, 40, 41, 42, 43

## Failure classes

- `quota-backend-too-small-for-write-burst`: 13

## Quota correlation

| quota-backend-bytes | passed | failed |
|---:|---:|---:|
| 2097152 | 0 | 13 |
| 8388608 | 20 | 0 |
| 67108864 | 17 | 0 |

## Representative failure

Representative seed: `3`

Run directory: `.topotestix/runs/20260616-075438-etcd-cluster-seed-3-etcd-cluster-seed-3`

All basic checks passed first; only the final quota write-burst property failed.

Representative error:

```text
etcdserver: mvcc: database space exceeded
```

## Interpretation

This is not an etcd implementation bug. It is a workload/configuration incompatibility: the cluster starts and satisfies basic health, leader, KV, TTL, and delayed-health checks, but a multi-MiB write burst exceeds a small backend quota. This is stronger thesis evidence than the v1 startup-only timing-ratio failures.

## Per-seed table

| Seed | Status | quota bytes | heartbeat ms | election ms | Failed checks | Run dir |
|---:|---|---:|---:|---:|---|---|
| 1 | passed | 67108864 | 100 | 1250 |  | `.topotestix/runs/20260616-075420-etcd-cluster-seed-1-etcd-cluster-seed-1` |
| 2 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-075429-etcd-cluster-seed-2-etcd-cluster-seed-2` |
| 3 | failed | 2097152 | 100 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-075438-etcd-cluster-seed-3-etcd-cluster-seed-3` |
| 4 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-075447-etcd-cluster-seed-4-etcd-cluster-seed-4` |
| 5 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-075641-etcd-cluster-seed-5-etcd-cluster-seed-5` |
| 6 | failed | 2097152 | 100 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-075837-etcd-cluster-seed-6-etcd-cluster-seed-6` |
| 7 | passed | 67108864 | 250 | 1250 |  | `.topotestix/runs/20260616-080029-etcd-cluster-seed-7-etcd-cluster-seed-7` |
| 8 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-080227-etcd-cluster-seed-8-etcd-cluster-seed-8` |
| 9 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-080425-etcd-cluster-seed-9-etcd-cluster-seed-9` |
| 10 | passed | 67108864 | 100 | 2500 |  | `.topotestix/runs/20260616-080619-etcd-cluster-seed-10-etcd-cluster-seed-10` |
| 11 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-080812-etcd-cluster-seed-11-etcd-cluster-seed-11` |
| 12 | failed | 2097152 | 100 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-081007-etcd-cluster-seed-12-etcd-cluster-seed-12` |
| 13 | failed | 2097152 | 250 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-081201-etcd-cluster-seed-13-etcd-cluster-seed-13` |
| 14 | failed | 2097152 | 100 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-081357-etcd-cluster-seed-14-etcd-cluster-seed-14` |
| 15 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-081546-etcd-cluster-seed-15-etcd-cluster-seed-15` |
| 16 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-081738-etcd-cluster-seed-16-etcd-cluster-seed-16` |
| 17 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-081931-etcd-cluster-seed-17-etcd-cluster-seed-17` |
| 18 | passed | 67108864 | 100 | 1250 |  | `.topotestix/runs/20260616-082130-etcd-cluster-seed-18-etcd-cluster-seed-18` |
| 19 | passed | 67108864 | 100 | 2500 |  | `.topotestix/runs/20260616-082321-etcd-cluster-seed-19-etcd-cluster-seed-19` |
| 20 | passed | 67108864 | 250 | 1250 |  | `.topotestix/runs/20260616-082514-etcd-cluster-seed-20-etcd-cluster-seed-20` |
| 21 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-082706-etcd-cluster-seed-21-etcd-cluster-seed-21` |
| 22 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-082903-etcd-cluster-seed-22-etcd-cluster-seed-22` |
| 23 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-083058-etcd-cluster-seed-23-etcd-cluster-seed-23` |
| 24 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-083250-etcd-cluster-seed-24-etcd-cluster-seed-24` |
| 25 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-083443-etcd-cluster-seed-25-etcd-cluster-seed-25` |
| 26 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-083645-etcd-cluster-seed-26-etcd-cluster-seed-26` |
| 27 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-083841-etcd-cluster-seed-27-etcd-cluster-seed-27` |
| 28 | failed | 2097152 | 250 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-084033-etcd-cluster-seed-28-etcd-cluster-seed-28` |
| 29 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-084226-etcd-cluster-seed-29-etcd-cluster-seed-29` |
| 30 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-084417-etcd-cluster-seed-30-etcd-cluster-seed-30` |
| 31 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-084609-etcd-cluster-seed-31-etcd-cluster-seed-31` |
| 32 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-084801-etcd-cluster-seed-32-etcd-cluster-seed-32` |
| 33 | failed | 2097152 | 250 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-084952-etcd-cluster-seed-33-etcd-cluster-seed-33` |
| 34 | failed | 2097152 | 250 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-085144-etcd-cluster-seed-34-etcd-cluster-seed-34` |
| 35 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-085338-etcd-cluster-seed-35-etcd-cluster-seed-35` |
| 36 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-085532-etcd-cluster-seed-36-etcd-cluster-seed-36` |
| 37 | passed | 8388608 | 100 | 1250 |  | `.topotestix/runs/20260616-085725-etcd-cluster-seed-37-etcd-cluster-seed-37` |
| 38 | failed | 2097152 | 250 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-085917-etcd-cluster-seed-38-etcd-cluster-seed-38` |
| 39 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-090109-etcd-cluster-seed-39-etcd-cluster-seed-39` |
| 40 | failed | 2097152 | 250 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-090303-etcd-cluster-seed-40-etcd-cluster-seed-40` |
| 41 | failed | 2097152 | 100 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-090453-etcd-cluster-seed-41-etcd-cluster-seed-41` |
| 42 | failed | 2097152 | 250 | 1250 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-090642-etcd-cluster-seed-42-etcd-cluster-seed-42` |
| 43 | failed | 2097152 | 250 | 2500 | etcd-quota-write-burst-etcd1 | `.topotestix/runs/20260616-090829-etcd-cluster-seed-43-etcd-cluster-seed-43` |
| 44 | passed | 8388608 | 100 | 2500 |  | `.topotestix/runs/20260616-091021-etcd-cluster-seed-44-etcd-cluster-seed-44` |
| 45 | passed | 67108864 | 100 | 1250 |  | `.topotestix/runs/20260616-091215-etcd-cluster-seed-45-etcd-cluster-seed-45` |
| 46 | passed | 8388608 | 250 | 2500 |  | `.topotestix/runs/20260616-091410-etcd-cluster-seed-46-etcd-cluster-seed-46` |
| 47 | passed | 67108864 | 100 | 2500 |  | `.topotestix/runs/20260616-091608-etcd-cluster-seed-47-etcd-cluster-seed-47` |
| 48 | passed | 67108864 | 250 | 2500 |  | `.topotestix/runs/20260616-091802-etcd-cluster-seed-48-etcd-cluster-seed-48` |
| 49 | passed | 8388608 | 250 | 1250 |  | `.topotestix/runs/20260616-091955-etcd-cluster-seed-49-etcd-cluster-seed-49` |
| 50 | passed | 8388608 | 250 | 2500 |  | `.topotestix/runs/20260616-092147-etcd-cluster-seed-50-etcd-cluster-seed-50` |
