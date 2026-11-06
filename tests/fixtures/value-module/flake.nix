# Fixture: nixosModules.default is a value, not a path (a function applied to
# arguments, as in `import ./m.nix { inherit self; }`).
{
  outputs = _: {
    nixosModules.default = import ./m.nix { foo = "x"; };
  };
}
