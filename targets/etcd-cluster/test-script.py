start_all()

for machine in [etcd1, etcd2, etcd3]:
    machine.wait_for_unit("etcd")
    machine.wait_for_open_port(2379)
    machine.wait_for_open_port(2380)

etcd1.succeed("etcdctl endpoint health --cluster")
etcd1.succeed("etcdctl put topotestix-key topotestix-value")
etcd2.succeed("etcdctl get topotestix-key | grep '^topotestix-value$'")
