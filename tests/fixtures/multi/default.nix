{ lib, ... }:
{
  options.services.multidefault.enable = lib.mkEnableOption "the multidefault service";
}
