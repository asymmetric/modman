{ lib, pkgs, ... }:
{
  options.services.fixture = {
    enable = lib.mkEnableOption "the fixture service";
    port = lib.mkOption {
      type = lib.types.int;
      default = 8080;
      description = "Port the fixture service listens on.";
    };
    # Like real flakes whose packages are not in nixpkgs: the default fails to
    # evaluate, defaultText is shown instead.
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.modman-fixture-nonexistent;
      defaultText = lib.literalExpression "pkgs.modman-fixture-nonexistent";
      description = "Package providing the fixture service.";
    };
  };
}
