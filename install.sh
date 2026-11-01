#!/usr/bin/env bash
set -euo pipefail

# === Configuration ===
REPO_URL="${REBOS_SHELL_REPO_URL:-https://github.com/Rebo-NS4U/rebos_shell.git}"
INSTALL_PATH="${REBOS_SHELL_INSTALL_PATH:-$HOME/.local/src/rebos_shell}"
BIN_DIR="${REBOS_SHELL_BIN_DIR:-$HOME/.local/bin}"
QUICKSHELL_REPO="https://git.outfoxxed.me/outfoxxed/quickshell"

# === Helpers ===
GREEN='\033[0;32m' BLUE='\033[0;34m' YELLOW='\033[1;33m' RED='\033[0;31m' NC='\033[0m'
log_info() { echo -e "${BLUE}ℹ  $1${NC}" >&2; }
log_success() { echo -e "${GREEN}✔  $1${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠  $1${NC}" >&2; }
log_error() { echo -e "${RED}✖  $1${NC}" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_theme() { [[ -d "/usr/share/themes/$1" ]] || [[ -d "$HOME/.themes/$1" ]] || [[ -d "/usr/share/themes/${1}-dark" ]]; }
has_font() { local fonts; fonts=$(fc-list 2>/dev/null) || return; grep -qi "$1" <<< "$fonts"; }

[[ "$EUID" -eq 0 ]] && {
  log_error "Do not run as root. Use sudo where needed."
  exit 1
}

# === Distro Detection ===
detect_distro() {
  [[ -f /etc/NIXOS ]] && echo "nixos" && return
  has_cmd pacman && echo "arch" && return
  has_cmd dnf && echo "fedora" && return
  has_cmd apt && echo "debian" && return
  echo "unknown"
}

DISTRO=$(detect_distro)
log_info "Detected: $DISTRO"

# === Package Filtering ===
# Maps packages to their binary/check - only for conflict-prone packages
declare -A BINARY_CHECK=(
  ["matugen"]="matugen"
  ["quickshell"]="qs"
  ["kitty"]="kitty"
  ["tmux"]="tmux"
  ["fuzzel"]="fuzzel"
  ["brightnessctl"]="brightnessctl"
  ["ddcutil"]="ddcutil"

  ["jq"]="jq"
  ["playerctl"]="playerctl"
  ["wtype"]="wtype"
  ["mpvpaper"]="mpvpaper"
  ["pipx"]="pipx"
  ["python-pipx"]="pipx"
  ["zenity"]="zenity"
)

declare -A THEME_CHECK=(
  ["adw-gtk-theme"]="adw-gtk3"
  ["adw-gtk3-theme"]="adw-gtk3"
)

declare -A FONT_CHECK=(
  ["ttf-phosphor-icons"]="Phosphor"
)

filter_packages() {
  local pkgs=("$@")
  local needed=()

  for pkg in "${pkgs[@]}"; do
    local skip=0

    if [[ -n "${BINARY_CHECK[$pkg]:-}" ]] && has_cmd "${BINARY_CHECK[$pkg]:-}"; then
      log_info "Skipping $pkg (${BINARY_CHECK[$pkg]:-} found)"
      skip=1
    elif [[ -n "${THEME_CHECK[$pkg]:-}" ]] && has_theme "${THEME_CHECK[$pkg]:-}"; then
      log_info "Skipping $pkg (theme ${THEME_CHECK[$pkg]:-} found)"
      skip=1
    elif [[ -n "${FONT_CHECK[$pkg]:-}" ]] && has_font "${FONT_CHECK[$pkg]:-}"; then
      log_info "Skipping $pkg (font ${FONT_CHECK[$pkg]:-} found)"
      skip=1
    fi

    [[ $skip -eq 0 ]] && needed+=("$pkg")
  done

  echo "${needed[@]}"
}

# === Dependency Installation ===
install_dependencies() {
  case "$DISTRO" in
  nixos)
    local FLAKE_URI="${1:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"
    nix profile list | grep -q "ddcutil" && nix profile remove ddcutil 2>/dev/null || true

    if nix profile list | grep -q "rebos_shell"; then
      log_info "Updating rebos_shell..."
      nix profile upgrade rebos_shell --refresh --impure
    else
      log_info "Installing rebos_shell..."
      nix profile add "$FLAKE_URI" --impure
    fi
    ;;

  fedora)
    log_info "Enabling COPR repositories..."
    sudo dnf install -y --best --allowerasing --setopt=install_weak_deps=False dnf-plugins-core
    sudo dnf -y copr enable errornointernet/quickshell
    sudo dnf -y copr enable zirconium/packages
    sudo dnf -y copr enable iucar/cran

    local PKGS=(
      kitty tmux fuzzel network-manager-applet blueman
      pipewire wireplumber playerctl
      qt6-qtbase qt6-qtdeclarative qt6-qtwayland qt6-qtsvg qt6-qttools
      qt6-qtimageformats qt6-qtmultimedia qt6-qtshadertools
      kf6-syntax-highlighting kf6-breeze-icons hicolor-icon-theme
      brightnessctl ddcutil fontconfig jq sqlite upower
      wl-clipboard wlsunset wtype glib2 pipx zenity power-profiles-daemon
      python3.12 libnotify flatpak
      jetbrains-mono-fonts dejavu-sans-fonts liberation-fonts
      google-noto-fonts-common google-noto-cjk-fonts google-noto-emoji-fonts
      mpvpaper matugen R-CRAN-phosphoricons adw-gtk3-theme quickshell unzip curl
    )

    log_info "Installing dependencies..."
    # shellcheck disable=SC2046
    sudo dnf install -y --best --allowerasing --setopt=install_weak_deps=False $(filter_packages "${PKGS[@]}")

    install_phosphor_fonts
    ;;

  arch)
    if ! has_cmd git || ! has_cmd makepkg; then
      log_info "Installing git and base-devel..."
      sudo pacman -S --needed --noconfirm git base-devel
    fi

    AUR_HELPER=""
    if has_cmd yay; then
      AUR_HELPER="yay"
    elif has_cmd paru; then
      AUR_HELPER="paru"
    else
      log_info "Installing yay-bin..."
      local YAY_TMP
      YAY_TMP="$(mktemp -d)"
      git clone "https://aur.archlinux.org/yay-bin.git" "$YAY_TMP"
      (cd "$YAY_TMP" && makepkg -si --noconfirm)
      rm -rf "$YAY_TMP"
      AUR_HELPER="yay"
    fi

    local PKGS=(
      kitty tmux fuzzel network-manager-applet blueman
      pipewire wireplumber pavucontrol ffmpeg x264 playerctl
      qt6-base qt6-declarative qt6-wayland qt6-svg qt6-tools qt6-imageformats qt6-multimedia qt6-shadertools
      libwebp libavif syntax-highlighting breeze-icons hicolor-icon-theme
      brightnessctl ddcutil fontconfig jq sqlite upower
      wl-clipboard wlsunset wtype glib2 python-pipx zenity inetutils power-profiles-daemon
      python312 libnotify
      ttf-jetbrains-mono ttf-dejavu ttf-liberation noto-fonts noto-fonts-cjk noto-fonts-emoji
      ttf-nerd-fonts-symbols
      matugen wl-clip-persist mpvpaper
      quickshell ttf-phosphor-icons ttf-league-gothic adw-gtk-theme
    )

    log_info "Installing dependencies with $AUR_HELPER..."
    local FILTERED
    # shellcheck disable=SC2207
    FILTERED=($(filter_packages "${PKGS[@]}"))

    if [[ ${#FILTERED[@]} -gt 0 ]]; then
      $AUR_HELPER -S --needed --noconfirm "${FILTERED[@]}"
    else
      log_info "All packages already installed"
    fi
    ;;

  *)
    log_error "Unsupported distribution: $DISTRO"
    log_warn "Please install dependencies manually (see nix/packages/)."
    return 1
    ;;
  esac
}

install_phosphor_fonts() {
  has_font "Phosphor" && return

  log_info "Installing Phosphor Icons..."
  local VERSION="2.1.2"
  local TEMP_DIR FONT_DIR
  TEMP_DIR="$(mktemp -d)"
  FONT_DIR="$HOME/.local/share/fonts/phosphor"

  curl -fsSL "https://github.com/phosphor-icons/web/archive/refs/tags/v${VERSION}.zip" -o "$TEMP_DIR/phosphor.zip"
  unzip -q "$TEMP_DIR/phosphor.zip" -d "$TEMP_DIR"
  mkdir -p "$FONT_DIR"
  find "$TEMP_DIR" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
  rm -rf "$TEMP_DIR"
  fc-cache -f "$FONT_DIR"
  log_success "Phosphor Icons installed"
}

# === Repository Setup ===
setup_repo() {
  [[ "$DISTRO" == "nixos" ]] && return

  if [[ ! -e "$INSTALL_PATH" ]]; then
    log_info "Cloning rebos_shell to $INSTALL_PATH..."
    mkdir -p "$(dirname "$INSTALL_PATH")"
    git clone -- "$REPO_URL" "$INSTALL_PATH"
    return
  fi

  local checkout_root
  checkout_root=$(git -C "$INSTALL_PATH" rev-parse --show-toplevel 2>/dev/null) || {
    log_error "$INSTALL_PATH exists but is not a Git checkout. Choose another REBOS_SHELL_INSTALL_PATH."
    return 1
  }
  [[ $(cd -- "$INSTALL_PATH" && pwd -P) == "$checkout_root" ]] || {
    log_error "$INSTALL_PATH must be the root of its own Git checkout."
    return 1
  }
  # Use the same backed-up, preference-preserving path as explicit updates.
  bash "$(dirname -- "${BASH_SOURCE[0]}")/update.sh" --path "$INSTALL_PATH" --repo "$REPO_URL"

}

# === Quickshell Build ===
install_quickshell() {
  [[ "$DISTRO" == "nixos" || "$DISTRO" == "fedora" || "$DISTRO" == "arch" ]] && return
  has_cmd qs && {
    log_info "Quickshell already installed"
    return
  }

  log_info "Building Quickshell from source..."
  local BUILD_DIR
  BUILD_DIR="$(mktemp -d)"
  git clone --recursive "$QUICKSHELL_REPO" "$BUILD_DIR"
  (
    cd "$BUILD_DIR"
    cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
    cmake --build build
    cmake --install build
  )
  rm -rf "$BUILD_DIR"
  log_success "Quickshell installed to ~/.local/bin/qs"
}

# === Python Tools ===
install_python_tools() {
  [[ "$DISTRO" == "nixos" ]] && return
  has_cmd pipx || {
    log_warn "pipx not found, skipping Python tools"
    return
  }

  log_info "Installing Python tools..."

  pipx ensurepath 2>/dev/null || true
}

# === Service Configuration ===
configure_services() {
  [[ "$DISTRO" == "nixos" ]] && return

  if has_cmd systemctl; then
    log_info "Configuring systemd services..."

    if systemctl is-enabled --quiet iwd 2>/dev/null || systemctl is-active --quiet iwd 2>/dev/null; then
      log_warn "Disabling iwd (conflicts with NetworkManager)..."
      sudo systemctl stop iwd
      sudo systemctl disable iwd
    fi

    systemctl is-enabled --quiet NetworkManager 2>/dev/null || {
      log_info "Enabling NetworkManager..."
      sudo systemctl enable --now NetworkManager
    }

    systemctl is-enabled --quiet bluetooth 2>/dev/null || {
      log_info "Enabling Bluetooth..."
      sudo systemctl enable --now bluetooth
    }

  elif has_cmd rc-service; then
    log_info "Configuring OpenRC services..."
    rc-update show | grep -q "iwd" && {
      sudo rc-service iwd stop 2>/dev/null || true
      sudo rc-update del iwd default 2>/dev/null || true
    }
    sudo rc-update add NetworkManager default 2>/dev/null || true
    sudo rc-service NetworkManager start 2>/dev/null || true
    sudo rc-update add bluetooth default 2>/dev/null || true
    sudo rc-service bluetooth start 2>/dev/null || true

  elif has_cmd sv; then
    log_info "Configuring runit services..."
    local SV_DIR="/var/service"
    [[ -L "$SV_DIR/iwd" ]] && sudo rm "$SV_DIR/iwd"
    [[ -d "/etc/sv/NetworkManager" && ! -L "$SV_DIR/NetworkManager" ]] && sudo ln -s /etc/sv/NetworkManager "$SV_DIR/"
    [[ -d "/etc/sv/bluetooth" && ! -L "$SV_DIR/bluetooth" ]] && sudo ln -s /etc/sv/bluetooth "$SV_DIR/"

  else
    log_warn "Unknown init system. Please enable NetworkManager and Bluetooth manually."
  fi
}

# === Launcher Setup ===
setup_launcher() {
  [[ "$DISTRO" == "nixos" ]] && return

  mkdir -p "$BIN_DIR"
  local LAUNCHER="$BIN_DIR/rebos_shell"
  if [[ -e "$LAUNCHER" && ! -f "$LAUNCHER" || -L "$LAUNCHER" ]]; then
    log_error "Refusing to replace a linked or non-file launcher: $LAUNCHER"
    return 1
  fi
  if [[ -f "$LAUNCHER" ]]; then
    cp -p -- "$LAUNCHER" "$LAUNCHER.backup.$(date +%s).$$"
  fi
  log_info "Creating launcher at $LAUNCHER..."
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'export PATH=%q:"$PATH"\n' "$HOME/.local/bin"
    printf 'export QML2_IMPORT_PATH=%q:"${QML2_IMPORT_PATH:-}"\n' "$HOME/.local/lib/qml"
    printf 'export QML_IMPORT_PATH="$QML2_IMPORT_PATH"\n'
    printf 'exec %q "$@"\n' "$INSTALL_PATH/cli.sh"
  } > "$LAUNCHER"
  chmod +x "$LAUNCHER"
  python3 - "$LAUNCHER" "$INSTALL_PATH" "$HOME" <<'PY'
from pathlib import Path
import sys
launcher, source, home = map(Path, sys.argv[1:])
entry = home / ".local/share/applications/rebos-shell-settings.desktop"
entry.parent.mkdir(parents=True, exist_ok=True)
# Desktop Exec uses its own escaping rules, not shell quoting.
command = str(launcher)
for character in ('\\', '"', '`', '$'):
    command = command.replace(character, '\\' + character)
entry.write_text('[Desktop Entry]\nType=Application\nName=rebos_shell Settings\n'
                 f'Exec="{command}" run settings\n'
                 f'Icon={source / "assets/rebos_shell/settings.svg"}\nCategories=Settings;\n')
PY
  log_success "Launcher created"

}

# === Main ===
main() {
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf '%s\n' 'Install standalone rebos_shell (Arch, Fedora or NixOS).'
    printf '%s\n' 'For the complete Arch desktop use the rebos_enclosure installer.'
    printf '%s\n' 'Overrides: REBOS_SHELL_REPO_URL, REBOS_SHELL_INSTALL_PATH, REBOS_SHELL_BIN_DIR.'
    return
  fi
  install_dependencies "${1:-}"
  setup_repo
  install_quickshell
  install_python_tools
  configure_services
  setup_launcher
  log_success "Installation complete!"
  [[ "$DISTRO" == "nixos" ]] || log_info "Run $BIN_DIR/rebos_shell to start."
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
