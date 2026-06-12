# TopoTestix Combinators
#
# Deterministic, seed-based value selection for Nix attribute sets.
#
# The core idea: given a string key and a list of options, `choose` deterministically
# picks one option. The `resolve` function walks an attribute set and replaces every
# list it encounters with a `choose` call, using the attribute path as the key.
# This makes the entire selection reproducible — the same input always produces
# the same output.
#
# The key mechanism is hashing the path (e.g. "virtualisation.memorySize") to get
# a deterministic index into the option list. Different paths produce different
# choices, but the same path always produces the same choice.
#
# Example usage:
#
#   resolve "" { virtualisation.memorySize = [ 512 1024 2048 ]; }
#   # => { virtualisation.memorySize = 1024; }
#   # (the path "virtualisation.memorySize" hashes to an index that picks 1024)
#
#   resolve "" { services.openssh.enable = [ true false ]; }
#   # => { services.openssh.enable = false; }
#
# Nested structures work too:
#
#   resolve "" {
#     virtualisation = {
#       memorySize = [ 512 1024 2048 ];
#       diskSize = [ 1024 2048 5120 ];
#     };
#   }
#   # => { virtualisation = { memorySize = 1024; diskSize = 2048; }; }
#
{ lib }:

let
  # hash : string -> string
  #
  # SHA-256 hash of a string. Used as the basis for deterministic value selection.
  # The hash is not used directly — it feeds into `toInt` which produces an integer
  # suitable for indexing into option lists.
  #
  # Example:
  #   hash "hello"  # => "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
  #   hash "hello"  # => same result (deterministic)
  #   hash "world"  # => different result (different input)
  #
  hash = s: builtins.hashString "sha256" s;

  # toInt : string -> int
  #
  # Convert a string to a deterministic integer by hashing it and folding
  # the resulting bytes. The result is used as an index for `choose`.
  #
  # The algorithm:
  #   1. Hash the input string with SHA-256
  #   2. Convert each byte of the hash to its numeric value
  #   3. Fold left: accumulate = (accumulate * 256 + byte) mod 1_000_000_000
  #
  # The modulo keeps the result within a manageable range while preserving
  # good distribution across the output space.
  #
  # Example:
  #   toInt "virtualisation.memorySize"  # => 48291037
  #   toInt "services.openssh.enable"     # => 73829165
  #   toInt "virtualisation.memorySize"   # => 48291037 (same input, same output)
  #
  toInt = s:
    lib.foldl' (acc: c:
      lib.mod (acc * 256 + lib.strings.charToInt c) 1000000000
    ) 0 (lib.stringToCharacters (hash s));

  # choose : string -> [a] -> a
  #
  # Deterministically select one element from a list based on a string key.
  # The key is hashed to produce an index into the list. The same key always
  # selects the same element from the same list.
  #
  # This is the fundamental building block. The `resolve` function calls `choose`
  # with the full attribute path as the key, ensuring that different paths make
  # independent choices.
  #
  # Example:
  #   choose "x" [1 2 3]      # => 1  (deterministic)
  #   choose "y" [1 2 3]      # => 3  (different key, different choice)
  #   choose "x" [1 2 3]      # => 1  (same key, same choice)
  #   choose "x" [10 20 30]   # => 10 (same key, different list)
  #
  choose = name: options:
    if options == [] then
      builtins.throw "combinators.choose: options must not be empty"
    else
    let
      n = toInt name;
      idx = lib.mod n (builtins.length options);
    in
    builtins.elemAt options idx;

  resolveWithKeyPrefix = keyPrefix: pathPrefix: value:
    if builtins.isList value then
      if value == [] then
        builtins.throw "combinators.resolve: empty choice list at ${pathPrefix}"
      else
        let
          idx = lib.mod (toInt (keyPrefix + pathPrefix)) (builtins.length value);
        in
        { value = builtins.elemAt value idx; choices = { "${pathPrefix}" = idx; }; }
    else if builtins.isAttrs value then
      let
        result = lib.mapAttrs (n: v: resolveWithKeyPrefix keyPrefix (pathPrefix + "." + n) v) value;
      in
      {
        value = lib.mapAttrs (n: v: v.value) result;
        choices = lib.foldl' (acc: v: acc // v.choices) {} (lib.attrValues result);
      }
    else if builtins.isFunction value then
      resolveWithKeyPrefix keyPrefix pathPrefix (value { inherit lib; })
    else
      { value = value; choices = {}; };

  # resolve : string -> value -> { value, choices }
  #
  # Walk an attribute set and replace every list with a deterministic choice.
  # Also tracks which index was chosen for each path, returning both the
  # resolved value and a choices map.
  #
  # Returns { value = <resolved attrset>; choices = { ".path" = index; ... }; }
  #
  # The `prefix` argument tracks the current dot-separated path (e.g. ".virtualisation.memorySize")
  # so that each list gets a unique, deterministic key independent of other lists.
  #
  # Important: use an empty string "" as the initial prefix when calling resolve
  # on a top-level target. The function appends dot-separated keys internally,
  # so the paths in choices will be like ".virtualisation.memorySize".
  #
  # Example — simple flat target:
  #
  #   resolve "" {
  #     virtualisation.memorySize = [ 512 1024 2048 4096 ];
  #     services.openssh.enable = bool;
  #   }
  #   # => {
  #   #   value = { virtualisation.memorySize = 2048; services.openssh.enable = false; };
  #   #   choices = { ".virtualisation.memorySize" = 2; ".services.openssh.enable" = 0; };
  #   # }
  #
  # Example — nested target:
  #
  #   resolve "" {
  #     virtualisation = {
  #       memorySize = [ 512 1024 2048 ];
  #       diskSize = [ 1024 2048 5120 ];
  #     };
  #   }
  #   # => {
  #   #   value = { virtualisation = { memorySize = 1024; diskSize = 2048; }; };
  #   #   choices = { ".virtualisation.memorySize" = 1; ".virtualisation.diskSize" = 1; };
  #   # }
  #
  resolve = prefix: value:
    resolveWithKeyPrefix "" prefix value;

in
{
  inherit choose resolve hash toInt resolveWithKeyPrefix;

  # bool : [bool]
  #
  # Convenience combinator for boolean options. Equivalent to [ false true ].
  #
  # Ordered so that index 0 = false (simpler). This convention supports
  # choice-based shrinking: lower index = simpler value. A disabled service
  # is simpler than an enabled one.
  #
  # Example:
  #   resolve "" { services.openssh.enable = bool; }
  #   # => { services.openssh.enable = false; } or { services.openssh.enable = true; }
  #
  bool = [ false true ];

  # range : int -> int -> int -> [int]
  #
  # Generate a list of integers from min to max with a given step.
  # Useful as a fuzz target for numeric options where you want regular spacing.
  #
  # Note: for irregular values (e.g. powers of 2: 512, 1024, 2048, 4096),
  # use oneOf instead — range only produces arithmetic sequences.
  #
  # Example:
  #   range 0 10 1    # => [ 0 1 2 3 4 5 6 7 8 9 10 ]
  #   range 0 10 2    # => [ 0 2 4 6 8 10 ]
  #   range 0 10 5    # => [ 0 5 10 ]
  #   range 512 512 1 # => [ 512 ] (single option, always chosen)
  #
  # Usage in target spec:
  #   resolve "" { virtualisation.memorySize = range 512 4096 512; }
  #   # => { virtualisation.memorySize = 1024; } (one of [512 1024 ... 4096])
  #
  #   # For powers of 2, use oneOf:
  #   resolve "" { virtualisation.memorySize = oneOf [ 512 1024 2048 4096 ]; }
  #
  range = min: max: step:
    if step == 0 then
      builtins.throw "combinators.range: step must not be 0"
    else if min < max && step < 0 then
      builtins.throw "combinators.range: positive bounds require a positive step"
    else if min > max && step > 0 then
      builtins.throw "combinators.range: descending bounds require a negative step"
    else
      let
        count = (max - min) / step + 1;
      in
      lib.genList (i: min + i * step) count;

  # oneOf : [a] -> [a]
  #
  # Identity combinator. Returns the list unchanged. Exists for readability
  # in target specs to make the intent explicit: "choose one of these values".
  #
  # Example:
  #   oneOf [ "star" "ring" "mesh" ]
  #   # => [ "star" "ring" "mesh" ]
  #
  #   resolve "" { topology = oneOf [ "star" "ring" "mesh" ]; }
  #   # => { topology = "ring"; } (one value chosen deterministically)
  #
  oneOf = options:
    if options == [] then
      builtins.throw "combinators.oneOf: options must not be empty"
    else
      options;
}
