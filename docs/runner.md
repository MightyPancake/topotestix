# TopoTestix Runner

Based on NixOS `testers.runNixOSTest`. Thin Nix wrapper that composes inputs into a runnable test, injects property helpers, and produces a structured report.

## Interface

```nix
# lib/runner.nix
{ pkgs, lib, testers }:

{ nodeConfigs        # attrset of NixOS module functions: { broker1 = {pkgs,...}: {...}; ... }
, testScript         # Python string — user's test procedure
, properties ? []    # list of property attrsets from lib/properties.nix
, name               # string: test name (e.g. "nginx-test-seed-42")
, reportNode ? null  # string: node name that writes report.json (defaults to first node in nodeConfigs)
}:
```

## Modules

### `lib/runner.nix` — Test runner

Composes the full testScript and calls `testers.runNixOSTest`.

**`composeTestScript`**: Merges property setup, user testScript, and report harness into a single Python string. Does NOT auto-append `composedProps.check` — the user calls `_check()` explicitly at checkpoints.

**`run`**: Calls `testers.runNixOSTest` with composed testScript and provided nodeConfigs.

### Report harness

Injected into every testScript. Provides:

```python
_report = []
_all_passed = True

def _check(name, fn, *args, **kwargs):
    global _all_passed
    try:
        fn(*args, **kwargs)
        _report.append({"name": name, "status": "passed"})
    except Exception as e:
        _report.append({"name": name, "status": "failed", "message": str(e)})
        _all_passed = False
```

- `_check()` catches ALL exceptions and does NOT re-raise. The testScript continues after property failures.
- All properties are always evaluated. A failing property logs the error and continues.
- Bare `machine.succeed()` calls outside `_check()` still stop execution on failure — that is expected. Wrapping in `_check()` makes a check non-fatal.

### Report writing

At the end of the testScript, the harness writes report.json inside the VM and copies it out using `copy_from_machine` (replaces deprecated `copy_from_vm`):

```python
import base64
encoded = base64.b64encode(json.dumps(_report).encode()).decode()
machine.succeed(f"echo '{encoded}' | base64 -d > /tmp/report.json")
machine.copy_from_machine("/tmp/report.json")
```

The report lands at `$out/report.json` (accessible as `result/report.json` after `nix build`).

After writing the report, if any property failed:

```python
if not _all_passed:
    failed_names = ", ".join(r["name"] for r in _report if r["status"] == "failed")
    raise AssertionError(f"Failed properties: {failed_names}")
```

This makes the test derivation fail (non-zero exit), while the report.json is still available in the output.

### `reportNode` parameter

Specifies which VM node writes the report. Defaults to the first node in `nodeConfigs`. For single-node tests this is `"machine"`. For multi-node tests, the user can specify which node should collect and write the report.

```nix
reportNode = lib.head (builtins.attrNames nodeConfigs)  # default
```

## Composition flow

```
User provides:
  baseConfig     (NixOS module — e.g. targets/nginx/module.nix)
  testScript     (Python string — e.g. targets/nginx/test-script.py)
  properties     (list of attrsets — e.g. targets/nginx/properties.nix)
  configTarget   (fuzz target spec — e.g. targets/config/nginx.nix)
  seed           (integer)

Flow:
  1. fuzzer(seed, configTarget) → fuzzedConfig (flat attrset)
  2. mergeConfigs(base=baseConfig, config=fuzzedConfig) → nodeConfig
     (for single-node; multi-node adds topology layer)
  3. runner.run(nodeConfigs, testScript, properties, name) → NixOS test derivation
  4. nix build → result/report.json
```

## Example: composed testScript

Given:

```nix
properties = [
  { name = "nginx-responds-to-http";
    setup = ''
      def check_nginx_responds(machine, port=80):
          machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:" + str(port) + " | grep 200")
    '';
    check = ''
      _check("nginx-responds-to-http", check_nginx_responds, machine)
    '';
  }
];
```

And a user testScript:

```python
machine.succeed("nginx -t")
machine.succeed("systemctl start nginx")
machine.wait_for_unit("nginx")
```

The runner composes:

```python
import json
import base64

_report = []
_all_passed = True

def _check(name, fn, *args, **kwargs):
    global _all_passed
    try:
        fn(*args, **kwargs)
        _report.append({"name": name, "status": "passed"})
    except Exception as e:
        _report.append({"name": name, "status": "failed", "message": str(e)})
        _all_passed = False

# --- property setup ---
def check_nginx_responds(machine, port=80):
    machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:" + str(port) + " | grep 200")

# --- user testScript ---
machine.succeed("nginx -t")
machine.succeed("systemctl start nginx")
machine.wait_for_unit("nginx")

# --- auto-appended property check ---
_check("nginx-responds-to-http", check_nginx_responds, machine)

# --- report writing ---
encoded = base64.b64encode(json.dumps(_report).encode()).decode()
machine.succeed(f"echo '{encoded}' | base64 -d > /tmp/report.json")
machine.copy_from_machine("/tmp/report.json")

if not _all_passed:
    failed_names = ", ".join(r["name"] for r in _report if r["status"] == "failed")
    raise AssertionError(f"Failed properties: {failed_names}")
```

## Design decisions

| Decision | Choice | Rationale |
|---|---|---|
| `_check()` catches exceptions, does NOT re-raise | Test continues after property failures | All properties always get evaluated; report captures everything |
| No `try/finally` wrapper around user testScript | If bare `succeed()` fails before report, no report.json (test still fails) | Keeping it simple; `try/finally` can be added later |
| `composedProps.check` auto-appended | Runner appends checks after the user script | Explicit checkpoints are future work |
| Report via `copy_from_machine` | report.json lands in `$out/report.json` | More reliable than stdout parsing; replaces deprecated `copy_from_vm` |
| JSON via base64 encoding | Avoids shell escaping issues in `machine.succeed()` | JSON contains quotes, newlines, etc. |
| mkForce only on fuzzed layers | Base config is plain, fuzzed config and topology get mkForce | Fuzzer outputs pure attrsets; priority is applied at merge time (see [merge.md](merge.md)) |
| `reportNode` defaults to first node | Configurable for multi-node tests | Single-node tests just work; multi-node tests specify which node writes the report |
