# Fixture: several modules with distinct options.
{
  outputs = _: {
    nixosModules = {
      default = ./default.nix;
      other = ./other.nix;
    };
  };
}
