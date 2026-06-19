{ lib, ... }:

{
  roles.kafka = [ 3 ];
  kafkaVlans = [ [ 1 ] ];
}
