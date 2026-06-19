# Nginx property: responds_to_http
#
# Defines a single PBT property that checks whether nginx responds with HTTP 200.
# The `setup` field defines the Python helper function.
# The `check` field calls it via _check() — the runner's property harness.
#
# _check() catches exceptions and does NOT re-raise, so all properties
# are always evaluated even if one fails. Results are recorded in _report.

{ lib }:

{
  responds_to_http = {
    name = "nginx-responds-to-http";
    setup = ''
      def check_nginx_responds(machine, port=80):
          machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:" + str(port) + " | grep 200")
    '';
    check = ''
      _check("nginx-responds-to-http", check_nginx_responds, machine)
    '';
  };
}