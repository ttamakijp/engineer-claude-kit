#!/usr/bin/env bash
# bootstrap.sh
# Cross-platform entry point for engineer-claude-kit on macOS and Linux.
# Installs pwsh (PowerShell 7+) if not present, then delegates to bootstrap.ps1.
# On Windows, run bootstrap.ps1 directly in PowerShell instead.
# ASCII only. See ADR-0001 section I.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install_pwsh_macos() {
    if ! command -v brew &>/dev/null; then
        echo "[error] Homebrew not found. Install it from https://brew.sh then re-run."
        exit 1
    fi
    echo "[info] Installing PowerShell via Homebrew..."
    # Try stable cask first; fall back to preview if stable is unavailable.
    if ! brew install --cask powershell 2>/dev/null; then
        brew install --cask powershell@preview
    fi
    # The .pkg installer places pwsh under /usr/local/microsoft but may not add it
    # to PATH. Create a symlink when needed.
    if ! command -v pwsh &>/dev/null; then
        PWSH_BIN="$(find /usr/local/microsoft /opt/microsoft -name pwsh -type f 2>/dev/null | head -1 || true)"
        if [ -z "$PWSH_BIN" ]; then
            echo "[error] pwsh binary not found after installation. Check Homebrew output."
            exit 1
        fi
        sudo ln -sf "$PWSH_BIN" /usr/local/bin/pwsh
        echo "[ok] symlink: /usr/local/bin/pwsh -> $PWSH_BIN"
    fi
}

install_pwsh_linux() {
    if command -v apt-get &>/dev/null; then
        # Debian / Ubuntu
        echo "[info] Installing PowerShell via apt..."
        DISTRO_VERSION="$(lsb_release -rs 2>/dev/null || echo '22.04')"
        PKG_URL="https://packages.microsoft.com/config/ubuntu/${DISTRO_VERSION}/packages-microsoft-prod.deb"
        TMP_DEB="$(mktemp /tmp/packages-microsoft-prod.XXXXXX.deb)"
        curl -fsSL "$PKG_URL" -o "$TMP_DEB"
        sudo dpkg -i "$TMP_DEB"
        rm -f "$TMP_DEB"
        sudo apt-get update -q
        sudo apt-get install -y powershell
    elif command -v dnf &>/dev/null; then
        # Fedora / RHEL 8+
        echo "[info] Installing PowerShell via dnf..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo dnf install -y powershell
    elif command -v yum &>/dev/null; then
        # CentOS / older RHEL
        echo "[info] Installing PowerShell via yum..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        sudo yum install -y powershell
    else
        echo "[error] Unsupported Linux distribution."
        echo "        Install PowerShell manually and re-run:"
        echo "        https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
        exit 1
    fi
}

# --- main ---

OS="$(uname -s)"

if command -v pwsh &>/dev/null; then
    echo "[ok] pwsh found: $(command -v pwsh)"
else
    echo "[info] pwsh not found. Installing PowerShell..."
    case "$OS" in
        Darwin) install_pwsh_macos ;;
        Linux)  install_pwsh_linux ;;
        *)
            echo "[error] Unsupported OS: $OS. Run bootstrap.ps1 directly in PowerShell."
            exit 1
            ;;
    esac
    echo "[ok] PowerShell installed: $(pwsh --version)"
fi

# Forward all arguments to bootstrap.ps1
exec pwsh -File "$SCRIPT_DIR/bootstrap.ps1" "$@"
