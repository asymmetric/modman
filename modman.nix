# Render the options declared by a flake's `nixosModules.default` as a manpage.
#
# Usage:
#   nix build --impure -f modman.nix --argstr flake github:owner/repo \
#     --argstr nixpkgs /nix/store/...-source --argstr system x86_64-linux
#
# nixpkgs: source path of the nixpkgs used to evaluate the module and render
# the page (modman's own pin; the target flake's inputs are not used).
{
  flake,
  nixpkgs,
  system,
}:
let
  src = builtins.getFlake flake;

  lib = import "${nixpkgs}/lib";

  eval = import "${nixpkgs}/nixos/lib/eval-config.nix" {
    # Set the platform modularly; eval-config's `system` argument is legacy.
    system = null;
    modules = [
      { nixpkgs.hostPlatform = system; }
      { system.stateVersion = "26.11"; }
      src.nixosModules.default
    ];
  };
  inherit (eval) pkgs;

  prefix = "${src.outPath}/";
  isOwn = decl: lib.hasPrefix prefix (toString decl);

  optionsDoc = pkgs.nixosOptionsDoc {
    inherit (eval) options;
    warningsAreErrors = false;
    # Hide every option not declared inside the flake source; show
    # declarations relative to the flake ref.
    transformOptions =
      opt:
      let
        own = lib.any isOwn opt.declarations;
      in
      opt
      // {
        visible = opt.visible && own;
      }
      // lib.optionalAttrs own {
        # Attrset form, so nixos-render-docs doesn't label them <nixpkgs/...>.
        declarations = map (
          d: if isOwn d then { name = "<${flake}/${lib.removePrefix prefix (toString d)}>"; } else d
        ) opt.declarations;
      };
  };

  header = builtins.toFile "header.roff" ''
    .TH "MODMAN" "5" "01/01/1980" "${flake}" "NixOS Module Options"
    .nh
    .ad l
    .cflags 4 /
    .SH "NAME"
    ${flake} \- NixOS options declared by nixosModules.default
    .SH "OPTIONS"
  '';
  footer = builtins.toFile "footer.roff" "";
in
pkgs.runCommand "modman.5"
  {
    nativeBuildInputs = [ pkgs.nixos-render-docs ];
    passthru = { inherit optionsDoc; };
  }
  ''
    nixos-render-docs -j1 options manpage \
      --revision ${lib.escapeShellArg (src.rev or src.dirtyRev or "unknown")} \
      --header ${header} \
      --footer ${footer} \
      ${optionsDoc.optionsJSON}/share/doc/nixos/options.json \
      $out
  ''
