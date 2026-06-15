# Testing TopoTestix

## Test Framework

Tests use [nix-unit](https://github.com/nix-community/nix-unit), a Nix unit testing framework that evaluates attribute sets of test expressions and compares them against expected values.

For interpretation of the Kafka empirical sweep results, see [empirical-kafka-cluster.md](empirical-kafka-cluster.md). That document explains why the Kafka findings should be framed as production-relevant configuration/workload incompatibilities rather than Kafka implementation bugs.

## Installing nix-unit

### Option 1: Build from source

```bash
nix build github:nix-community/nix-unit
./result/bin/nix-unit --help
```

### Option 2: Use the dev shell

The project flake includes nix-unit in its dev shell:

```bash
nix develop
nix-unit --help
```

### Option 3: Install via nix profile

```bash
nix profile install github:nix-community/nix-unit
```

## Running Tests

### Manually with nix-unit

The simplest way to run all tests:

```bash
nix-unit --expr 'import ./tests { lib = (import <nixpkgs> {}).lib; }'
```

This evaluates the test attribute set from `tests/default.nix`, which composes all individual test files.

#### What is `--eval-store`?

Nix needs a store to evaluate expressions. By default it uses `/nix/store`, but when running `nix-unit` outside of a `nix build`, Nix may need a writable store directory. `--eval-store` tells Nix where to store evaluation results (derivations, closures).

You can specify a local directory as the eval store:

```bash
nix-unit --eval-store "$(pwd)/eval-store" --expr 'import ./tests { lib = (import <nixpkgs> {}).lib; }'
```

This creates a local store in your project directory, which:
- Avoids permission issues with `/nix/store`
- Keeps evaluation artifacts local to the project
- Is the recommended approach from nix-unit's documentation

If you get warnings like `unknown setting 'allowed-users'`, that's normal with a local eval store. The tests still work correctly.

If you skip `--eval-store`, nix-unit falls back to the default store and may show warnings. Both approaches work.

### Via `nix flake check`

The project flake includes a check that runs nix-unit:

```bash
nix flake check
```

This builds a derivation that runs `nix-unit` inside a `runCommand`. Note: `nix flake check` does show build logs for successful checks but only for first build. To see test results, use:

```bash
# Build the check derivation directly with -L to see logs
nix build .#checks.x86_64-linux.default -L

# Or view logs after a successful check
nix log /nix/store/<hash>-tests.drv
```

Or is you want to see test results every time use nix-unit command.

The relevant section in `flake.nix`:

```nix
checks.${system} = {
  default = pkgs.runCommand "tests" {
    nativeBuildInputs = [ nix-unit.packages.${system}.default ];
  } ''
    export HOME="$TMPDIR"
    mkdir -p "$HOME/.cache/nix"
    nix-unit --eval-store "$TMPDIR/eval-store" \
      --extra-experimental-features flakes \
      --override-input nixpkgs ${nixpkgs} \
      --flake ${self}#tests
    touch $out
  '';
};
```

The `runCommand` approach:
1. Sets `HOME` to `$TMPDIR` (writable sandbox directory) so nix-unit can write its cache
2. Creates `$HOME/.cache/nix` for nix-unit's cache
3. Uses `$TMPDIR/eval-store` as the eval store (ephemeral — cleaned up after build)
4. Overrides the nixpkgs input so the derivation can find it during build
5. Runs `nix-unit` against the `tests` flake output
6. Creates `$out` on success (the build succeeds only if all tests pass)

### Via the dev shell

```bash
nix develop -c nix-unit --expr 'import ./tests { lib = (import <nixpkgs> {}).lib; }'
```

### Running a single test file

```bash
nix-unit --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; combinators = import ./lib/combinators.nix { inherit lib; }; in import ./tests/combinators-test.nix { inherit lib; inherit combinators; }'
```

### Expected output

On success:

```
✅ testBool
✅ testChooseDeterministic
✅ testChooseDifferentKeysDifferentResults
...
🎉 29/29 successful
```

On failure:

```
✅ testBool
❌ testChooseDeterministic
/tmp/nix-.../expected.nix --- 1/2 --- Nix
1 2
/tmp/nix-.../expected.nix --- 2/2 --- Nix
1 1
...
😢 28/29 successful
error: Tests failed
```

## Test File Conventions

### File naming

Test files live in `tests/` and must be named `*-test.nix`:

```
tests/
├── default.nix              # Composes all test files
├── combinators-test.nix     # Tests for lib/combinators.nix
├── fuzzer-test.nix          # Tests for lib/fuzzer.nix
└── expand-topology-test.nix # Tests for lib/expand-topology.nix
```

### Test format

Each test is an attribute prefixed with `test` containing `expr` and `expected`:

```nix
{
  testAddition = {
    expr = 1 + 1;
    expected = 2;
  };

  testStringConcat = {
    expr = "hello" + " world";
    expected = "hello world";
  };
}
```

nix-unit evaluates `expr` and compares it to `expect `expected`. If they differ, the test fails with a diff.

Tests can also compare two expressions for equality:

```nix
{
  testDeterministic = {
    expr = someFunction "input";
    expected = someFunction "input";  # same call, must produce same result
  };
}
```

### Compositional tests

Some tests verify structural properties rather than concrete values. These use comments to explain the relationship:

```nix
{
  testResolveDelegatesToChoose = {
    expr = combinators.resolve "" { x = [1 2 3]; };
    expected = { x = 3; };

    # Compositional: resolve "" { x = [1 2 3]; }
    #   == { x = choose ".x" [1 2 3]; }
    #   == { x = 3; }
  };
}
```

### Adding new tests

1. Create `tests/your-module-test.nix` with `test*` attributes
2. Import it in `tests/default.nix`
3. The test file receives the modules it needs as function arguments

Example `tests/default.nix`:

```nix
{ lib }:

let
  combinators = import ../lib/combinators.nix { inherit lib; };
  fuzzerMod = import ../lib/fuzzer.nix { inherit lib; };
in
(import ./combinators-test.nix { inherit lib; combinators = combinators; })
//
(import ./fuzzer-test.nix { inherit lib; fuzzer = fuzzerMod.fuzzer; })
```

## Verifying Test Values

When writing tests, you need concrete expected values. Use `nix eval --impure` to evaluate expressions and find the correct values:

```bash
# Evaluate a function to find its output
nix eval --impure --expr 'let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
in fuzzer { seed = "1"; target = { x = [1 2 3]; }; }'

# => { x = 3; }
```

```bash
# Test that different seeds produce different results
nix eval --impure --expr 'let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  fuzzer = (import ./lib/fuzzer.nix { inherit lib; }).fuzzer;
in fuzzer { seed = "1"; target = { x = [1 2 3 4 5 6 7 8 9 10]; }; } !=
   fuzzer { seed = "7"; target = { x = [1 2 3 4 5 6 7 8 9 10]; }; }'

# => true
```

### Important: use large enough option spaces

When testing that different seeds produce different results, use a list with enough options. With only `[1 2 3]`, two different seeds may collide on the same value. Use at least 10 options:

```nix
# BAD — may collide (only 3 options)
expr = fuzzer { seed = "1"; target = { x = [1 2 3]; }; }
    != fuzzer { seed = "7"; target = { x = [1 2 3]; }; };

# GOOD — unlikely to collide (10 options)
expr = fuzzer { seed = "1"; target = { x = [1 2 3 4 5 6 7 8 9 10]; }; }
    != fuzzer { seed = "7"; target = { x = [1 2 3 4 5 6 7 8 9 10]; }; };
```
