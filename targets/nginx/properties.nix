{ lib }:

{
  responds_to_http = {
    name = "nginx-responds-to-http";
    setup = ''
      def check_nginx_responds(machine, port=80):
          machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:" + str(port) + " | grep 200")
    '';
    check = ''
      _check("nginx-responds-to-http", check_nginx_responds, machine1)
    '';
  };
}