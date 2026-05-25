#!/bin/sh

set -eu

usage() {
  cat <<'EOF'
Usage: Scripts/build_runtime.sh [--install]

Build the bundled RuntimeWeb assets into
Sources/SwiftTerminal/Resources/TerminalRuntime.

Options:
  --install  Run `npm ci` before building. The script also installs
             dependencies automatically when `RuntimeWeb/node_modules`
             is missing.
  --help     Show this help text.
EOF
}

install_dependencies=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --install)
      install_dependencies=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if ! command -v npm >/dev/null 2>&1; then
  printf 'error: `npm` is required to build RuntimeWeb.\n' >&2
  exit 1
fi

SCRIPT_DIR=$(
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
)
PACKAGE_ROOT=$(
  CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd
)
RUNTIME_DIR="$PACKAGE_ROOT/RuntimeWeb"

if [ ! -f "$RUNTIME_DIR/package.json" ]; then
  printf 'error: missing RuntimeWeb/package.json at %s\n' "$RUNTIME_DIR" >&2
  exit 1
fi

if [ "$install_dependencies" = true ] || [ ! -d "$RUNTIME_DIR/node_modules" ]; then
  printf 'Installing RuntimeWeb dependencies with npm ci...\n'
  (
    cd "$RUNTIME_DIR"
    npm ci
  )
fi

printf 'Building RuntimeWeb into Sources/SwiftTerminal/Resources/TerminalRuntime...\n'
(
  cd "$RUNTIME_DIR"
  npm run build:swiftterminal
)
