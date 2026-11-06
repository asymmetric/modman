# Fixture: no nixosModules output.
{
  outputs = _: {
    lib.answer = 42;
  };
}
