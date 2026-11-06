# Core of modman: render the options declared by a loaded flake's
# `nixosModules.<module>` as a manpage. No `getFlake`, so it also runs inside
# the build sandbox (see the `nix` check in flake.nix); modman.nix wraps it.
{
  # src: a loaded flake (attrset with `outPath` and optionally `nixosModules`).
  #   Only options declared under `src.outPath` are kept.
  # name: ref shown in the page header.
  # module: attribute of `src.nixosModules` to render.
  # nixpkgs: source path of the nixpkgs used to evaluate the module and render
  #   the page.
  mkPage =
    {
      src,
      name,
      module ? "default",
      nixpkgs,
      system,
    }:
    let
      lib = import "${nixpkgs}/lib";

      available = lib.concatStringsSep ", " (lib.attrNames src.nixosModules);
      selected =
        if !(src ? nixosModules) then
          throw "modman: ${name} has no nixosModules output"
        else if !(src.nixosModules ? ${module}) then
          throw "modman: ${name} has no nixosModules.${module}; available: ${available}"
        else
          src.nixosModules.${module};

      eval = import "${nixpkgs}/nixos/lib/eval-config.nix" {
        # Set the platform modularly; eval-config's `system` argument is legacy.
        system = null;
        modules = [
          { nixpkgs.hostPlatform = system; }
          { system.stateVersion = "26.11"; }
          # A module given as a value (e.g. `import ./m.nix { inherit self; }`)
          # has no file of its own, so its declarations would be attributed to
          # this file and filtered out. _file places them inside the flake source
          # (at flake.nix, where the value is defined). Path modules keep their
          # own file names.
          {
            _file = "${src.outPath}/flake.nix";
            imports = [ selected ];
          }
        ];
      };
      inherit (eval) pkgs;

      prefix = "${src.outPath}/";
      isOwn = decl: lib.hasPrefix prefix (toString decl);

      optionsDoc = pkgs.nixosOptionsDoc {
        inherit (eval) options;
        warningsAreErrors = false;
        # Hide every option not declared inside the flake source. Declarations
        # stay as store paths, which can be opened locally.
        transformOptions = opt: opt // { visible = opt.visible && lib.any isOwn opt.declarations; };
      };

      header = builtins.toFile "header.roff" ''
        .TH "MODMAN" "5" "01/01/1980" "${name}" "NixOS Module Options"
        .nh
        .ad l
        .cflags 4 /
        .SH "NAME"
        ${name} \- NixOS options declared by nixosModules.${module}
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
      '';
}
