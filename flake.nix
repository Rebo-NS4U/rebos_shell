{
  description = "rebos_shell — a Niri-first Wayland desktop shell built with Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      rebosShellLib = import ./nix/lib.nix { inherit nixpkgs; };
      version = nixpkgs.lib.removeSuffix "\n" (builtins.readFile ./version);
    in {
      nixosModules.default = { pkgs, lib, ... }: {
        imports = [ ./nix/modules ];
        programs.rebos_shell.enable = lib.mkDefault true;
        programs.rebos_shell.package = lib.mkDefault self.packages.${pkgs.system}.default;
      };

      packages = rebosShellLib.forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          lib = nixpkgs.lib;

          rebos_shell = import ./nix/packages {
            inherit pkgs lib self system version;
          };
        in {
          default = rebos_shell;
          rebos_shell = rebos_shell;
        }
      );

      devShells = rebosShellLib.forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          rebos_shell = self.packages.${system}.default;
        in {
          default = pkgs.mkShell {
            packages = [ rebos_shell ];
            shellHook = ''
              export QML2_IMPORT_PATH="${rebos_shell}/lib/qt-6/qml:$QML2_IMPORT_PATH"
              export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
              echo "rebos_shell dev environment loaded."
            '';
          };
        }
      );

      apps = rebosShellLib.forAllSystems (system:
        let
          rebos_shell = self.packages.${system}.default;
        in {
          default = {
            type = "app";
            program = "${rebos_shell}/bin/rebos_shell";
          };
        }
      );
    };
}
