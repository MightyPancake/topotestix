# Fuzzer test suite
#
# Tests the fuzzer: seed + target → { result, choices }.
# All expected values are concrete — verified by evaluation.
#
{ lib, fuzzer, ... }:

{
  # Same seed + same target always produces the same result

  testFuzzerDeterministic = {
    expr = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; }).result;
    expected = { x = 3; };
  };

  # Same seed called twice must match — both result and choices

  testFuzzerDeterministicRepeatResult = {
    expr = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; }).result;
    expected = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; }).result;
  };

  testFuzzerDeterministicRepeatChoices = {
    expr = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; }).choices;
    expected = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; }; }).choices;
  };

  # Different seeds produce different results

  testFuzzerDifferentSeeds = {
    expr =
      let
        a = (fuzzer { seed = "1"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; }).result;
        b = (fuzzer { seed = "7"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; }).result;
      in a != b;
    expected = true;
  };

  # Nested attribute sets are resolved recursively

  testFuzzerNested = {
    expr = (fuzzer { seed = "1"; target = { a.b = [ true false ]; }; }).result;
    expected = { a = { b = true; }; };
  };

  # Scalar values pass through unchanged

  testFuzzerScalarPassthrough = {
    expr = (fuzzer { seed = "1"; target = { x = 42; y = "hello"; }; }).result;
    expected = { x = 42; y = "hello"; };
  };

  # Multiple attributes are resolved independently

  testFuzzerMultipleAttrs = {
    expr = (fuzzer { seed = "100"; target = { x = [ 1 2 3 ]; y = [ 512 1024 2048 ]; }; }).result;
    expected = { x = 1; y = 512; };
  };

  # Choices map contains paths and indices

  # Choices map contains target-relative paths and indices

  testFuzzerChoicesFlat = {
    expr = (fuzzer { seed = "1"; target = { x = [ 1 2 3 ]; y = [ 10 20 30 ]; }; }).choices;
    expected = { ".x" = 2; ".y" = 1; };
  };

  testFuzzerChoicesNested = {
    expr = (fuzzer { seed = "1"; target = { a.b = [ true false ]; c.d = [ 3 4 5 ]; }; }).choices;
    expected = { ".a.b" = 0; ".c.d" = 2; };
  };

  # Seeds affect indices, not public choice paths

  testFuzzerChoicesDifferentSeed = {
    expr =
      let
        a = (fuzzer { seed = "1"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; }).choices;
        b = (fuzzer { seed = "7"; target = { x = [ 1 2 3 4 5 6 7 8 9 10 ]; }; }).choices;
      in builtins.attrNames a == [ ".x" ] && builtins.attrNames b == [ ".x" ] && a != b;
    expected = true;
  };

  # Scalar values produce no choices

  testFuzzerChoicesNoScalars = {
    expr = (fuzzer { seed = "1"; target = { x = 42; y = "hello"; }; }).choices;
    expected = {};
  };
}
