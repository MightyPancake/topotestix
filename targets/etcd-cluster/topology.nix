{ lib, ... }:

{
  roles.etcd = [ 3 ];
  etcdVlans = [ [ 1 ] ];
}
