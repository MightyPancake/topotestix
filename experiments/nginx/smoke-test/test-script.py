# Nginx test script
#
# This is the user-provided testScript that the runner injects between
# property setup and property checks. It prepares the VM for the property
# to verify.
#
# Order in the composed testScript:
#   1. Harness preamble (_report, _check)
#   2. Property setup (check_nginx_responds definition)
#   3. THIS FILE (user testScript)
#   4. Property check (_check("nginx-responds-to-http", ...))
#   5. Report footer (base64 + copy_from_machine + assert)

machine.succeed("mkdir -p /var/www")
machine.succeed("echo 'hello from topotestix' > /var/www/index.html")
machine.wait_for_unit("nginx")