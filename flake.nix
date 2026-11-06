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
