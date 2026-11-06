{ foo }:
{ lib, ... }:
{
  options.services.valuefix = {
    enable = lib.mkEnableOption "the valuefix service";
    foo = lib.mkOption {
      type = lib.types.str;
      default = foo;
      description = "Value passed when the module was imported.";
    };
  };
}
