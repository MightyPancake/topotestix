machine.succeed("mkdir -p /var/www")
machine.succeed("echo 'hello from topotestix' > /var/www/index.html")
machine.wait_for_unit("nginx")