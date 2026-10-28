# Main rebos_shell package
{ pkgs, lib, self, system, version }:

let
  quickshellPkg = pkgs.quickshell;

  # Import sub-packages
  ttf-phosphor-icons = import ./phosphor-icons.nix { inherit pkgs; };

  # Import modular package lists
  corePkgs = import ./core.nix { inherit pkgs quickshellPkg; };
  toolsPkgs = import ./tools.nix { inherit pkgs; };
  mediaPkgs = import ./media.nix { inherit pkgs; };
  appsPkgs = import ./apps.nix { inherit pkgs; };
  fontsPkgs = import ./fonts.nix { inherit pkgs ttf-phosphor-icons; };

  # Combine all packages (NixOS-specific deps handled by the module)
  baseEnv = corePkgs
    ++ toolsPkgs
    ++ mediaPkgs
    ++ appsPkgs
    ++ fontsPkgs;

  envRebosShell = pkgs.buildEnv {
    name = "rebos_shell-env";
    paths = baseEnv;
  };

  # Create fontconfig configuration to find bundled fonts
  fontconfigConf = pkgs.writeTextDir "etc/fonts/conf.d/99-rebos_shell-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${envRebosShell}/share/fonts</dir>
    </fontconfig>
  '';

  # Copy shell sources to the Nix store
  shellSrc = pkgs.stdenv.mkDerivation {
    pname = "rebos_shell";
    inherit version;
    src = lib.cleanSource self;
    dontBuild = true;
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };

  launcher = pkgs.writeShellScriptBin "rebos_shell" ''
    export REBOS_SHELL_QS="${quickshellPkg}/bin/qs"
    export PATH="${envRebosShell}/bin:$PATH"

    # Set QML2_IMPORT_PATH to include modules from envRebosShell (like syntax-highlighting)
    export QML2_IMPORT_PATH="${envRebosShell}/lib/qt-6/qml:$QML2_IMPORT_PATH"
    export QML_IMPORT_PATH="$QML2_IMPORT_PATH"

    # Make bundled fonts available to fontconfig
    export FONTCONFIG_PATH="${fontconfigConf}/etc/fonts:''${FONTCONFIG_PATH:-}"

    # Delegate execution to CLI (now in the Nix store)
    exec ${shellSrc}/cli.sh "$@"
  '';

in pkgs.buildEnv {
  name = "rebos_shell-${version}";
  paths = [ envRebosShell launcher ];
  meta.mainProgram = "rebos_shell";
}
