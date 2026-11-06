# Render the options declared by a flake's `nixosModules.<module>` as a manpage.
#
# Usage:
#   nix build --impure -f modman.nix --argstr flake github:owner/repo \
#     --argstr nixpkgs /nix/store/...-source --argstr system x86_64-linux
#
# flake: ref that is fetched (modman passes the locked URL).
# name: ref shown in the page header and declarations; defaults to flake
# (modman passes the flake ref as the user typed it).
# nixpkgs: source path of the nixpkgs used to evaluate the module and render
# the page (modman's own pin; the target flake's inputs are not used).
# module: attribute of the flake's `nixosModules` to render.
#
# Thin wrapper: fetches the flake and hands it to lib.nix's mkPage.
{
  flake,
  name ? flake,
  module ? "default",
  nixpkgs,
  system,
}:
(import ./lib.nix).mkPage {
  src = builtins.getFlake flake;
  inherit
    name
    module
    nixpkgs
    system
    ;
}
