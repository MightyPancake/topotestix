{ lib, ... }:

{
  roles.primary = [ 1 ];
  roles.standby = [ 1 ];

  primaryVlans = [ [ 1 ] ];
  standbyVlans = [ [ 1 ] ];
}
