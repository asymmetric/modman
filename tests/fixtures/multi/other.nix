{ lib, ... }:
{
  options.services.multiother.enable = lib.mkEnableOption "the multiother service";
}
