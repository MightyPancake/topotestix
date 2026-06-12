# TopoTestix Shrinker
#
# Pure Nix module for choice-based shrinking. Reduces individual choice indices
# toward 0 (lower index = simpler value) in fuzzer-generated configurations.
#
# The shrinker operates on three inputs:
#   - target: the original target spec (contains option lists)
#   - fuzzed: the fuzzer's resolved output (contains concrete values)
#   - choices_override: a map from path strings to indices (only overrides)
#
# When choices_override is empty, the shrinker is the identity function — it
# returns the fuzzed output unchanged. This means the normal (un-shrunk) pipeline
# works without any shrinking logic.
#
# Convention: lower index = simpler value. Target spec authors must order option
# lists from simplest to most complex. The shrinker always moves toward index 0.
#
# See docs/shrinking.md for full design documentation.

{ lib }:

let
  # getValueByPath : attrset -> string -> value
  #
  # Navigate a nested attrset using a dot-separated path string.
  # Example: getValueByPath { a = { b = 42; }; } ".a.b" => 42
  #
  # The path format uses dot-separated keys starting with a dot,
  # matching the format produced by combinators.resolve's choices map.
  # For example, ".virtualisation.memorySize" navigates to
  # attrset.virtualisation.memorySize.
  #
  normalizePath = path:
    if !(builtins.isString path) || path == "" || builtins.substring 0 1 path != "." then
      builtins.throw "shrinker: invalid path '${toString path}', expected a target-relative path like .virtualisation.memorySize"
    else
      builtins.substring 1 (builtins.stringLength path - 1) path;

  getValueByPath = attrs: path:
    let
      pathStr = normalizePath path;
      parts = lib.splitString "." pathStr;
    in
    lib.foldl' (acc: part:
      if builtins.isAttrs acc && acc ? ${part} then
        acc.${part}
      else
        builtins.throw "shrinker: path ${path} does not exist in target"
    ) attrs parts;

  # setValueByPath : attrset -> string -> value -> attrset
  #
  # Set a value at a nested path in an attrset, creating intermediate attrsets as needed.
  # Returns a new attrset with the value set at the specified path.
  #
  setValueByPath = attrs: path: value:
    let
      pathStr = normalizePath path;
      parts = lib.splitString "." pathStr;
    in
    if builtins.length parts == 1 then
      attrs // { ${builtins.head parts} = value; }
    else
      let
        head = builtins.head parts;
        tail = builtins.tail parts;
        existing = if attrs ? ${head} then attrs.${head} else {};
        pathForTail = "." + builtins.concatStringsSep "." tail;
      in
      attrs // { ${head} = setValueByPath existing pathForTail value; };

  # applyOverrides : target -> fuzzed -> choices_override -> attrset
  #
  # Walk the target spec and the fuzzed result simultaneously. For paths
  # present in choices_override, use the overridden index to pick from the
  # target's option list. For paths not in choices_override, use the fuzzed
  # value unchanged.
  #
  applyOverrides = target: fuzzed: choices_override:
    let
      paths = builtins.attrNames choices_override;
    in
    if paths == [] then fuzzed
    else
      lib.foldl' (acc: path:
        let
          idx = choices_override.${path};
          value = valueAtChecked target path idx;
        in
        setValueByPath acc path value
      ) fuzzed paths;

  # collectChoicePaths : string -> value -> [string]
  #
  # Walk a target spec and collect all paths where the value is a list.
  # Returns a list of dot-separated paths suitable for use as keys in
  # the choices map.
  #
  # Functions are called with { lib; } and their return value is recursed into,
  # matching the behavior of combinators.resolve.
  #
  collectChoicePaths = prefix: value:
    if builtins.isList value then
      if value == [] then
        builtins.throw "shrinker.choicePaths: empty choice list at ${prefix}"
      else
      [ prefix ]
    else if builtins.isAttrs value then
      lib.concatLists (lib.mapAttrsToList (n: v: collectChoicePaths "${prefix}.${n}" v) value)
    else if builtins.isFunction value then
      collectChoicePaths prefix (value { inherit lib; })
    else
      [];

  valueAtChecked = target: path: index:
    let
      options = getValueByPath target path;
    in
    if !(builtins.isList options) then
      builtins.throw "shrinker: path ${path} is not a choice list"
    else
      let
        len = builtins.length options;
      in
      if len == 0 then
        builtins.throw "shrinker: empty choice list at ${path}"
      else if index < 0 || index >= len then
        builtins.throw "shrinker: index ${toString index} out of range for ${path} (0..${toString (len - 1)})"
      else
        builtins.elemAt options index;

in
{
  # apply : target -> fuzzed -> choices_override -> attrset
  #
  # Apply choice overrides to fuzzed output. For each path in choices_override,
  # replace the fuzzed value with the value at the specified index in the target's
  # option list. Paths not in choices_override are left unchanged.
  #
  # Identity when choices_override is empty: apply target fuzzed {} == fuzzed.
  #
  # Example:
  #   target = { memorySize = [ 512 1024 2048 4096 ]; enable = [ false true ]; };
  #   fuzzed  = { memorySize = 2048; enable = true; };
  #   apply target fuzzed { ".memorySize" = 0; }
  #   # => { memorySize = 512; enable = true; }
  #
  apply = target: fuzzed: choices_override:
    applyOverrides target fuzzed choices_override;

  # choicePaths : target -> [string]
  #
  # List all choice paths in a target spec. A choice path is a path where the
  # value is a list — i.e., a place where the fuzzer makes a choice.
  #
  # Example:
  #   choicePaths { virtualisation.memorySize = [ 512 1024 2048 ]; services.nginx.enable = bool; }
  #   # => [ ".services.nginx.enable" ".virtualisation.memorySize" ]
  #
  # Returned in alphabetical order for deterministic iteration.
  #
  choicePaths = target:
    lib.naturalSort (collectChoicePaths "" target);

  # valueAt : target -> path -> index -> value
  #
  # Get the value at a specific index in a target's option list.
  # Used by the Python orchestrator to understand what each index maps to.
  #
  # Example:
  #   valueAt { memorySize = [ 512 1024 2048 4096 ]; } ".memorySize" 0
  #   # => 512
  #
  valueAt = target: path: index:
    valueAtChecked target path index;

  # optionsFor : target -> path -> [value]
  #
  # Get the full option list for a path in the target spec.
  # Used by the Python orchestrator to know the range of valid indices.
  #
  # Example:
  #   optionsFor { memorySize = [ 512 1024 2048 4096 ]; } ".memorySize"
  #   # => [ 512 1024 2048 4096 ]
  #
  optionsFor = target: path:
    getValueByPath target path;
}
