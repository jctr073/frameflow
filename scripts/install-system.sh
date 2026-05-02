#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/app/Frameflow.app"
DESTINATION="/Applications/Frameflow.app"

"$ROOT_DIR/scripts/build-app.sh"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Expected app bundle was not created: $APP_PATH" >&2
    exit 1
fi

run_install_command() {
    if [[ -w "/Applications" ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

run_install_command rm -rf "$DESTINATION"
run_install_command ditto "$APP_PATH" "$DESTINATION"
run_install_command chmod -R a+rX "$DESTINATION"

if command -v xattr >/dev/null 2>&1; then
    run_install_command xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true
fi

echo "$DESTINATION"
