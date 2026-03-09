#!/usr/bin/env bash
set -euo pipefail

# Release script for Equaliser
# Usage: ./release.sh <version> [--dry-run]
# Example: ./release.sh 1.2.0
#          ./release.sh 1.2.0 --dry-run
#
# Prerequisites:
# - Run from within the nix devshell (nix develop, or direnv)
# - gh must be authenticated (gh auth login)

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_PATH="$ROOT_DIR/Sources/App/Info.plist"
APP_NAME="Equaliser"
RELEASE_DIR="$ROOT_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}==>${NC} $1"; }
dry() { echo -e "${BLUE}[DRY RUN]${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

# Parse arguments
DRY_RUN=false
VERSION=""

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$arg"
            fi
            ;;
    esac
done

# Validate arguments
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [--dry-run]"
    echo "Example: $0 1.2.0"
    echo "         $0 1.2.0 --dry-run"
    exit 1
fi

# Validate version format (basic semver check)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Invalid version format: $VERSION (expected X.Y.Z)"
fi

# Check for clean working tree
if [[ -n "$(git status --porcelain)" ]]; then
    error "Working tree is dirty. Please commit or stash changes first."
fi

# Check required tools are available
if ! command -v rsvg-convert &> /dev/null; then
    error "rsvg-convert not found. Run 'nix develop' or 'direnv allow' first."
fi

if ! command -v create-dmg &> /dev/null; then
    error "create-dmg not found. Run 'nix develop' or 'direnv allow' first."
fi

# gh auth only required for non-dry-run
if [[ "$DRY_RUN" != true ]]; then
    if ! command -v gh &> /dev/null; then
        error "gh (GitHub CLI) not found. Run 'nix develop' or 'direnv allow' first."
    fi

    if ! gh auth status &> /dev/null; then
        error "gh is not authenticated. Run 'gh auth login' first."
    fi
fi

# Get current values from Info.plist
CURRENT_VERSION=$(grep -A1 CFBundleShortVersionString "$PLIST_PATH" | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
CURRENT_BUILD=$(grep -A1 CFBundleVersion "$PLIST_PATH" | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')

# Get short git SHA for CFBundleVersion
GIT_SHA=$(git rev-parse --short HEAD)

if [[ "$DRY_RUN" == true ]]; then
    info "DRY RUN: Releasing $APP_NAME v$VERSION"
    echo ""
    dry "Current git SHA: $GIT_SHA"
    echo ""
    dry "Would update Info.plist:"
    echo "      CFBundleShortVersionString: $CURRENT_VERSION → $VERSION"
    echo "      CFBundleVersion: $CURRENT_BUILD → <new commit SHA>"
    echo ""
    dry "Would commit: \"chore: bump version to $VERSION\""
    dry "Would run: ./bundle.sh"
    dry "Would create: $APP_NAME-$VERSION.dmg"
    dry "Would create GitHub draft release: v$VERSION"
    echo ""
    info "DRY RUN: Proceeding with build but skipping GitHub release..."
fi

info "Releasing $APP_NAME v$VERSION"

# Get short git SHA for CFBundleVersion
info "Build version (git SHA): $GIT_SHA"

# Update Info.plist
if [[ "$DRY_RUN" != true ]]; then
    info "Updating Info.plist..."

    # Update CFBundleShortVersionString and CFBundleVersion using PlistBuddy
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_SHA" "$PLIST_PATH"

    # Commit the plist change
    info "Committing version bump..."
    git add "$PLIST_PATH"
    git commit -m "chore: bump version to $VERSION"

    # Get new SHA after commit (this is what will be in the release)
    GIT_SHA_NEW=$(git rev-parse --short HEAD)

    # Update CFBundleVersion with the new commit SHA
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_SHA_NEW" "$PLIST_PATH"

    # Amend the commit to include the updated SHA
    git add "$PLIST_PATH"
    git commit --amend --no-edit

    info "Final build version: $GIT_SHA_NEW"
fi

# Build the app bundle
info "Building app bundle..."
"$ROOT_DIR/bundle.sh"

# Verify build output
if [[ ! -d "$APP_BUNDLE" ]]; then
    error "Build failed: $APP_BUNDLE not found"
fi

# Create DMG
DMG_NAME="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
info "Creating $DMG_NAME..."
create-dmg \
    --volname "$APP_NAME" \
    --app-drop-link 140 120 \
    --icon "$APP_NAME.app" 420 120 \
    --window-size 560 400 \
    --icon-size 80 \
    "$DMG_NAME" \
    "$APP_BUNDLE"

if [[ "$DRY_RUN" == true ]]; then
    info "DRY RUN complete. DMG created at: $DMG_NAME"
    info "Skipped: GitHub release creation, git commit"
else
    # Create GitHub release (as draft)
    info "Creating GitHub release draft v$VERSION..."
    gh release create "v$VERSION" \
        --title "v$VERSION" \
        --generate-notes \
        --draft \
        "$DMG_NAME"

    # Clean up
    rm "$DMG_NAME"

    # Get release URL
    RELEASE_URL=$(gh release view "v$VERSION" --json url --jq '.url')

    info "Release draft created!"
    echo ""
    echo "Draft URL: $RELEASE_URL"
    echo ""
    echo "Next steps:"
    echo "  1. Open the URL above"
    echo "  2. Edit the release notes"
    echo "  3. Click 'Publish release'"
    echo ""
    echo "Note: Since this app is not notarized, users will need to"
    echo "right-click -> Open to bypass Gatekeeper on first launch."
fi
