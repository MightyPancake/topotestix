# Nginx Smoke Test

End-to-end validation of the TopoTestix pipeline: fuzzer → merge → runner → NixOS VM test → report.json.

## How it works

The smoke test wires up the full TopoTestix pipeline for a single nginx service:

```
seed="5"
    │
    ▼
fuzzer(seed, configTarget)  ──→  fuzzedConfig (plain attrset)
    │
    ▼
mergeConfigs(base, config=fuzzedConfig)  ──→  merged nodeConfig (with mkForce on fuzzed values)
    │
    ▼
runner.run(nodeConfigs, testScript, properties, name)  ──→  NixOS VM test derivation
    │
    ▼
nix build  ──→  VM boots, testScript runs, _check() evaluates properties, report.json written
    │
    ▼
result/report.json  ──→  [{"name": "nginx-responds-to-http", "status": "passed"}]
```

### Configuration space

The config target (`targets/config/nginx.nix`) defines the fuzzable dimensions:

| Option | Variants |
|---|---|
| `virtualisation.memorySize` | 512, 1024, 2048, 4096 |
| `services.openssh.enable` | true, false |
| `services.nginx.enable` | true, false |

Total configurations: 4 × 2 × 2 = **16**. Different seeds produce different selections from this space.

### Seed selection

Seed `"5"` produces `services.nginx.enable = true`, which is required for the nginx property to pass. Seeds that disable nginx will correctly produce a `failed` report — that's PBT working as intended.

### Pipeline components

1. **Fuzzer** (`lib/fuzzer.nix`): `fuzzer { seed = "5"; target = configTarget; }` → resolves all lists in the target to single deterministic values
2. **Merge** (`lib/merge.nix`): `mergeConfigs { base = nginxBase; config = fuzzedConfig; }` → applies `mkForce` to fuzzed values, merges on top of base config
3. **Runner** (`lib/runner.nix`): `runner.run { ... }` → composes testScript with harness preamble, property setup, property checks, and report footer; calls `runNixOSTest`
4. **Properties** (`targets/nginx/properties.nix`): defines `_check()` calls that wrap assertions in the reporting harness
5. **Report**: written inside the VM as base64-encoded JSON, copied out via `copy_from_machine`

### Key files

| File | Purpose |
|---|---|
| `targets/nginx/module.nix` | Base NixOS config: enables nginx with localhost virtualHost |
| `targets/nginx/test-script.py` | Python test procedure: create web root, wait for nginx |
| `targets/nginx/properties.nix` | Property: `responds_to_http` — checks HTTP 200 on localhost |
| `targets/config/nginx.nix` | Fuzz target spec: memory size, ssh, nginx enable |
| `flake.nix` | Wires fuzzer → merge → runner, exposes `nixosTests.nginx-smoke` |

### Composed testScript

The runner composes the final Python testScript from:

1. **Harness preamble**: imports, `_report`, `_check()` definition
2. **Property setup**: `def check_nginx_responds(machine, port=80): ...`
3. **User testScript**: `machine.succeed("mkdir -p /var/www")`, etc.
4. **Property check**: `_check("nginx-responds-to-http", check_nginx_responds, machine)`
5. **Report footer**: base64-encode report, write to `/tmp/report.json`, copy out, assert on failures

### What a failing seed looks like

```
seed="1" → services.nginx.enable = false

Report:
[{"name": "nginx-responds-to-http", "status": "failed", 
  "message": "command `systemctl start nginx` failed (exit code 1)"}]

Test derivation: FAILS (AssertionError: Failed properties: nginx-responds-to-http)
```

This is correct behavior — the property detects that nginx was not available.

## Running the smoke test

Use the provided script:

```bash
cd experiments/nginx-smoke-test
./run-smoke-test.sh        # default seed 5 (nginx enabled, should pass)
./run-smoke-test.sh 1       # seed 1 (nginx disabled, expect failure)
./run-smoke-test.sh 5       # seed 5 (nginx enabled, should pass)
./run-smoke-test.sh 10      # seed 10 (nginx enabled, should pass)
```

The script:
1. Evaluates and prints the fuzzed config for the given seed (formatted with `jq`)
2. Shows whether `nginx.enable` is true or false for that seed
3. Builds and runs the NixOS VM test
4. Prints build output on failure
5. Prints the report.json contents (formatted with `jq`)
6. Exits with code 1 on failure