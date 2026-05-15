machine1.succeed("mkdir -p /var/www")
machine1.succeed("echo 'hello from topotestix' > /var/www/index.html")
machine1.wait_for_unit("nginx")
machine1.wait_for_open_port(80)