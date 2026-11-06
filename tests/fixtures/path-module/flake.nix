# Fixture: nixosModules.default is a path module.
{
  outputs = _: {
    nixosModules.default = ./module.nix;
  };
}
