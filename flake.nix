{
  description = "Show the NixOS module options of a flake as a manpage";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      modmanLib = import ./lib.nix;

      # Load tests/fixtures/NAME as a flake without getFlake (unavailable in the
      # build sandbox). Modules are imported from the same store copy as
      # outPath, so lib.nix's declaration-prefix filter sees them as own.
      loadFixture =
        name:
        let
          root = "${./tests/fixtures + "/${name}"}";
          fixture = (import "${root}/flake.nix").outputs { self = fixture; } // {
            outPath = root;
          };
        in
        fixture;
    in
    {
      packages = forAllSystems (pkgs: {
        modman = pkgs.stdenvNoCC.mkDerivation {
          pname = "modman";
          version = "0.1.0";

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./modman
              ./modman.nix
              ./lib.nix
            ];
          };

          nativeBuildInputs = [ pkgs.makeWrapper ];
          nativeCheckInputs = [ pkgs.shellcheck ];

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            shellcheck modman
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 modman $out/bin/modman
            install -Dm644 modman.nix $out/share/modman/modman.nix
            install -Dm644 lib.nix $out/share/modman/lib.nix
            # --suffix: prefer the user's own nix (matching their daemon).
            wrapProgram $out/bin/modman \
              --set MODMAN_NIX $out/share/modman/modman.nix \
              --set MODMAN_NIXPKGS ${nixpkgs.outPath} \
              --set MODMAN_SYSTEM ${pkgs.stdenv.hostPlatform.system} \
              --suffix PATH : ${
                lib.makeBinPath [
                  pkgs.jq
                  pkgs.man
                  pkgs.nix
                ]
              }
            runHook postInstall
          '';

          meta = {
            description = "Show the NixOS module options of a flake as a manpage";
            mainProgram = "modman";
            platforms = systems;
          };
        };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.modman;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          meta.description = "Show the NixOS module options of a flake as a manpage";
        };
      });

      checks = forAllSystems (pkgs: {
        # Building the package runs shellcheck in its checkPhase.
        modman = self.packages.${pkgs.stdenv.hostPlatform.system}.modman;

        # CLI tests: source modman and test its functions (no nix calls).
        cli =
          pkgs.runCommand "modman-cli-tests"
            {
              src = lib.fileset.toSource {
                root = ./.;
                fileset = lib.fileset.unions [
                  ./modman
                  ./tests/cli.bats
                ];
              };
              nativeBuildInputs = [
                pkgs.bats
                pkgs.coreutils
              ];
            }
            ''
              cp -r "$src" src
              chmod -R u+w src
              cd src
              # No /usr/bin/env in the sandbox; one test executes the script.
              patchShebangs modman
              MODMAN=$PWD/modman bats tests/cli.bats
              touch $out
            '';

        # Nix tests: render pages of the fixture flakes in tests/fixtures/.
        nix =
          let
            page =
              fixture: args:
              modmanLib.mkPage (
                {
                  src = loadFixture fixture;
                  name = "fixture:${fixture}";
                  nixpkgs = nixpkgs.outPath;
                  inherit (pkgs.stdenv.hostPlatform) system;
                }
                // args
              );
            # tryEval can't see the throw message; only failure is checked.
            evalFails = p: !(builtins.tryEval p.drvPath).success;
          in
          assert !evalFails (page "multi" { });
          assert evalFails (page "multi" { module = "nope"; });
          assert evalFails (page "none" { });
          pkgs.runCommand "modman-nix-tests"
            {
              pathModule = page "path-module" { };
              valueModule = page "value-module" { };
              multiOther = page "multi" { module = "other"; };
            }
            ''
              # Grep a copy without roff escapes (\& before dots, \- for dashes).
              # A file, not a pipe: grep's early exit would fail sed under pipefail.
              plain() { sed -e 's/\\&//g' -e 's/\\-/-/g' "$1" >plain; }
              has() {
                plain "$1"
                grep -qF -- "$2" plain || { echo "$1: missing: $2" >&2; exit 1; }
              }
              lacks() {
                plain "$1"
                ! grep -qF -- "$2" plain || { echo "$1: unexpected: $2" >&2; exit 1; }
              }

              # Path module: own options only, declarations relative to the name.
              has $pathModule services.fixture.enable
              has $pathModule services.fixture.port
              has $pathModule services.fixture.package
              has $pathModule '<fixture:path-module/module.nix>'
              has $pathModule 'fixture:path-module - NixOS options declared by nixosModules.default'
              lacks $pathModule services.nginx.enable
              lacks $pathModule boot.loader

              # Value module: options kept via the _file wrapper.
              has $valueModule services.valuefix.enable
              has $valueModule services.valuefix.foo
              has $valueModule '<fixture:value-module/flake.nix#nixosModules.default>'
              lacks $valueModule boot.loader

              # Module selection.
              has $multiOther services.multiother.enable
              has $multiOther 'declared by nixosModules.other'
              lacks $multiOther services.multidefault

              touch $out
            '';
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.shellcheck
            pkgs.nixfmt
            pkgs.bats
            pkgs.jq
          ];
        };
      });
    };
}
