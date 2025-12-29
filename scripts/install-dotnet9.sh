#!/usr/bin/env bash
set -euo pipefail

# Installs the .NET 9 runtime using the official dot.net bootstrapper.
# You can override DOTNET_INSTALL_DIR to change where the runtime is placed.

DOTNET_INSTALL_DIR="${DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
SCRIPT_URL="https://dot.net/v1/dotnet-install.sh"

curl -sSL "$SCRIPT_URL" -o /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh

# Install the shared runtime (no SDK) from the 9.0 channel.
/tmp/dotnet-install.sh \
  --runtime dotnet \
  --channel 9.0 \
  --install-dir "$DOTNET_INSTALL_DIR"

echo "Installed .NET runtime to $DOTNET_INSTALL_DIR"
