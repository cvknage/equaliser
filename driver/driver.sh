#!/usr/bin/env bash
#
# driver.sh - Build the Equaliser AudioServerPlugIn driver
#
# Usage:
#   ./driver.sh <command>
#
# Commands:
#   clean     - Remove build artifacts
#   compile   - Compile driver binaries only (no bundle)
#   bundle    - Build complete driver bundle
#   install   - Install driver to /Library/Audio/Plug-Ins/HAL/ (requires sudo)
#   uninstall - Remove driver from /Library/Audio/Plug-Ins/HAL/ (requires sudo)
#

set -euo pipefail

# Configuration
DRIVER_NAME="Equaliser"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
BUILD_DIR="${SCRIPT_DIR}/.build"
DRIVER_BUNDLE="${BUILD_DIR}/${DRIVER_NAME}.driver"
ICON_ICNS="${ROOT_DIR}/.build/AppIcon.icns"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Common compile flags
COMPILE_FLAGS="-bundle -mmacosx-version-min=10.13 -O2"
FRAMEWORKS="-framework CoreAudio -framework CoreFoundation -framework Accelerate"

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

compile_binary() {
  local arch="$1"
  local output="$2"

  clang ${QUIET} -arch "${arch}" ${COMPILE_FLAGS} ${FRAMEWORKS} \
    -o "${output}" "${SRC_DIR}/EqualiserDriver.c" || {
    log_error "Failed to compile driver for ${arch}"
    exit 1
  }
}

clean() {
  log_info "Cleaning build directory..."
  rm -rf "${BUILD_DIR}"
  log_info "Clean complete"
}

create_bundle_structure() {
  log_info "Creating bundle structure..."
  mkdir -p "${DRIVER_BUNDLE}/Contents/MacOS"
  mkdir -p "${DRIVER_BUNDLE}/Contents/Resources"
}

compile_driver() {
  log_info "Compiling driver for arm64 and x86_64..."
  compile_binary arm64 "${BUILD_DIR}/EqualiserDriver-arm64"
  compile_binary x86_64 "${BUILD_DIR}/EqualiserDriver-x86_64"

  log_info "Creating universal binary..."
  lipo -create \
    "${BUILD_DIR}/EqualiserDriver-arm64" \
    "${BUILD_DIR}/EqualiserDriver-x86_64" \
    -output "${DRIVER_BUNDLE}/Contents/MacOS/EqualiserDriver" || {
    log_error "Failed to create universal binary"
    exit 1
  }

  rm -f "${BUILD_DIR}/EqualiserDriver-arm64" "${BUILD_DIR}/EqualiserDriver-x86_64"
}

install_info_plist() {
  log_info "Installing Info.plist..."
  cp "${SRC_DIR}/Info.plist" "${DRIVER_BUNDLE}/Contents/Info.plist"
}

copy_resources() {
  # Check and copy icon
  if [[ ! -f "$ICON_ICNS" ]]; then
    log_info "Icon not found, generating..."
    "$ROOT_DIR/bundle.sh" icon || {
      log_error "Failed to generate icon"
      exit 1
    }
  fi

  cp "$ICON_ICNS" "${DRIVER_BUNDLE}/Contents/Resources/EqualiserDriver.icns"
  log_info "Icon copied to driver bundle"

  # Copy README
  if [[ -f "${SCRIPT_DIR}/README.md" ]]; then
    cp "${SCRIPT_DIR}/README.md" "${DRIVER_BUNDLE}/Contents/Resources/README.md"
  fi
}

sign_driver() {
  log_info "Code signing driver bundle..."

  codesign --force --deep --sign - \
    --identifier "net.knage.equaliser.driver" \
    "${DRIVER_BUNDLE}" || {
    log_error "Failed to code sign driver"
    exit 1
  }

  codesign --verify --deep --strict "${DRIVER_BUNDLE}" || {
    log_warn "Signature verification had warnings"
  }
}

compile() {
  QUIET=""
  if [[ "${2:-}" == "--quiet" ]]; then
    QUIET="-w"
  fi

  log_info "Compiling ${DRIVER_NAME} driver binaries..."

  mkdir -p "${BUILD_DIR}"

  compile_binary arm64 "${BUILD_DIR}/EqualiserDriver-arm64"
  compile_binary x86_64 "${BUILD_DIR}/EqualiserDriver-x86_64"

  log_info "Creating universal binary..."
  lipo -create \
    "${BUILD_DIR}/EqualiserDriver-arm64" \
    "${BUILD_DIR}/EqualiserDriver-x86_64" \
    -output "${BUILD_DIR}/EqualiserDriver" || {
    log_error "Failed to create universal binary"
    exit 1
  }

  rm -f "${BUILD_DIR}/EqualiserDriver-arm64" "${BUILD_DIR}/EqualiserDriver-x86_64"

  log_info "Compile complete"
  log_info "  arm64:    ${BUILD_DIR}/EqualiserDriver-arm64"
  log_info "  x86_64:   ${BUILD_DIR}/EqualiserDriver-x86_64"
  log_info "  universal:${BUILD_DIR}/EqualiserDriver"
}

bundle() {
  QUIET=""
  if [[ "${2:-}" == "--quiet" ]]; then
    QUIET="-w"
  fi

  log_info "Building ${DRIVER_NAME} driver..."

  rm -rf "${BUILD_DIR}"
  create_bundle_structure
  compile_driver
  install_info_plist
  copy_resources
  sign_driver

  log_info "Build complete: ${DRIVER_BUNDLE}"
  log_info "Bundle size: $(du -sh "${DRIVER_BUNDLE}" | cut -f1)"
}

install() {
  if [[ ! -d "${DRIVER_BUNDLE}" ]]; then
    log_error "Driver not built. Run './driver.sh bundle' first."
    exit 1
  fi

  log_info "Installing driver to /Library/Audio/Plug-Ins/HAL/..."

  # Remove old version if exists
  if [[ -d "/Library/Audio/Plug-Ins/HAL/${DRIVER_NAME}.driver" ]]; then
    log_info "Removing existing driver..."
    sudo rm -rf "/Library/Audio/Plug-Ins/HAL/${DRIVER_NAME}.driver"
  fi

  # Copy new driver
  sudo cp -R "${DRIVER_BUNDLE}" "/Library/Audio/Plug-Ins/HAL/"

  # Set correct permissions
  sudo chown -R root:wheel "/Library/Audio/Plug-Ins/HAL/${DRIVER_NAME}.driver"
  sudo chmod -R 755 "/Library/Audio/Plug-Ins/HAL/${DRIVER_NAME}.driver"

  log_info "Driver installed successfully"
  log_info "Restarting coreaudiod to load the driver..."
  sudo killall coreaudiod

  log_info "Installation complete. The driver should appear in Audio MIDI Setup."
}

uninstall() {
  local driver_path="/Library/Audio/Plug-Ins/HAL/${DRIVER_NAME}.driver"

  if [[ ! -d "${driver_path}" ]]; then
    log_info "Driver not installed at ${driver_path}"
    return 0
  fi

  log_info "Uninstalling driver from /Library/Audio/Plug-Ins/HAL/..."

  sudo rm -rf "${driver_path}"

  log_info "Restarting coreaudiod to unload the driver..."
  sudo killall coreaudiod

  log_info "Uninstall complete"
}

show_usage() {
  echo "Usage: $0 <command> [--quiet]"
  echo ""
  echo "Commands:"
  echo "  clean     - Remove build artifacts"
  echo "  compile   - Compile driver binaries only (no bundle)"
  echo "  bundle    - Build complete driver bundle"
  echo "  install   - Install driver to /Library/Audio/Plug-Ins/HAL/ (requires sudo)"
  echo "  uninstall - Remove driver from /Library/Audio/Plug-Ins/HAL/ (requires sudo)"
  echo ""
  echo "Options:"
  echo "  --quiet   - Suppress compiler warnings (for compile and bundle commands)"
}

# Main
if [[ $# -eq 0 ]]; then
  show_usage
  exit 1
fi

case "$1" in
  clean)
    clean
    ;;
  compile)
    compile "$@"
    ;;
  bundle)
    bundle "$@"
    ;;
  install)
    install
    ;;
  uninstall)
    uninstall
    ;;
  *)
    show_usage
    exit 1
    ;;
esac
