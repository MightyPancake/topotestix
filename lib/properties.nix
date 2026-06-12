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
# The runner injects `setup` near the beginning of the test script and appends
# `check` after the user test script. Future work may add explicit checkpoints.
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
