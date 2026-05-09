# Fuzzer test suite
#
# Tests the fuzzer: seed + target → flat attrset.
# All expected values are concrete — verified by evaluation.
#
{ lib, fuzzer, ... }:

{
  # Same seed + same target always produces the same result

  testFuzzerDeterministic = {
    expr = fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; };
    expected = { x = 3; };
  };

  # Same seed called twice must match

  testFuzzerDeterministicRepeat = {
    expr = fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; };
    expected = fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; };
  };

  # Different seeds produce different results

  testFuzzerDifferentSeeds = {
    # With only 3 options, two different seeds may pick the same value.
    # Use a larger option space to reliably get different results.
    expr =
      let
        a = fuzzer { seed = "1"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; };
        b = fuzzer { seed = "7"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; };
      in a != b;
    expected = true;
  };

  # Nested attribute sets are resolved recursively

  testFuzzerNested = {
    expr = fuzzer { seed = "1"; target = { a.b = [ true false ]; }; };
    expected = { a = { b = true; }; };
  };

  # Scalar values pass through unchanged

  testFuzzerScalarPassthrough = {
    expr = fuzzer { seed = "1"; target = { x = 42; y = "hello"; }; };
    expected = { x = 42; y = "hello"; };
  };

  # Multiple attributes are resolved independently

  testFuzzerMultipleAttrs = {
    expr = fuzzer { seed = "100"; target = { x = [ 1 2 3 ]; y = [ 512 1024 2048 ]; }; };
    expected = { x = 1; y = 512; };
  };
}