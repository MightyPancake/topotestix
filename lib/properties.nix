# TopoTestix Properties
#
# Compose PBT property definitions into Python fragments that can be injected
# into a NixOS testScript.
#
# A property is a Nix attribute set with two optional string fields:
#   - setup: Python code that defines helper functions (called once at test start)
#   - check: Python code that calls those functions (called at checkpoints)
#
# composeProperties takes a list of properties and merges all their setup and
# check fragments into two strings, ready for the runner to inject into testScript.
#
# Example — define properties in Nix:
#
#   properties = [
#     { name = "no-message-loss";
#       setup = ''
#         def check_no_message_lost(produced, consumed):
#             assert produced == consumed, f"Lost {produced - consumed} messages"
#       '';
#       check = ''
#         check_no_message_lost(produced, consumed)
#       '';
#     }
#     { name = "service-available";
#       setup = ''
#         def check_service_responds(machine, port=80):
#             machine.succeed(f"curl -s http://localhost:{port}")
#       '';
#       check = ''
#         check_service_responds(machine)
#       '';
#     }
#   ];
#
#   composeProperties properties
#   # => {
#   #   setup = "def check_no_message_lost(produced, consumed):\n    ...\ndef check_service_responds...\n";
#   #   check = "check_no_message_lost(produced, consumed)\ncheck_service_responds(machine)\n";
#   # }
#
# The runner then injects `setup` at the beginning and `check` at each checkpoint
# in the testScript.
#
# NOTE: This is currently a stub — the interface is correct but it has not been
# tested against actual NixOS test scripts yet. The runner integration (how setup/check
# get injected into testScript) also doesn't exist yet. This will become a real module
# when the properties framework is implemented in Phase 1 of the plan.
#
{ lib }:

{
  composeProperties = properties:
    let
      # Extract all "setup" fields (Python function definitions) and join them.
      # Each property's setup defines helper functions that check can call later.
      extractSetup = props: lib.concatStringsSep "\n" (map (p: p.setup or "") props);

      # Extract all "check" fields (Python assertion calls) and join them.
      # These are the actual invocations at test checkpoints.
      extractCheck = props: lib.concatStringsSep "\n" (map (p: p.check or "") props);
    in
    {
      setup = extractSetup properties;
      check = extractCheck properties;
    };
}
