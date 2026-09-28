#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" HiddenStart/Info.plist 2>/dev/null || echo "0.9.0")}"
TAG="v${VERSION}"
DMG_FILE="${PROJECT_ROOT}/dist/HiddenStart-${VERSION}.dmg"
SHA_FILE="${PROJECT_ROOT}/dist/HiddenStart-${VERSION}.dmg.sha256"

echo "============================================================"
echo " Preparing HiddenStart Release ${TAG}"
echo "============================================================"

# 1. Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "Warning: Working directory has uncommitted changes."
    read -r -p "Do you want to continue anyway? [y/N] " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# 2. Run unit tests
echo "==> Running test suite..."
"${SCRIPT_DIR}/test.sh"

# 3. Build DMG
echo "==> Building Release DMG..."
"${SCRIPT_DIR}/build_dmg.sh" "${VERSION}"

if [ ! -f "${DMG_FILE}" ]; then
    echo "Error: DMG file was not generated at ${DMG_FILE}" >&2
    exit 1
fi

# 4. Check gh CLI availability
if ! command -v gh >/dev/null 2>&1; then
    echo "==> GitHub CLI (gh) is not installed."
    echo "    Release artifacts are ready in ${PROJECT_ROOT}/dist/."
    exit 0
fi

# 5. Tag and Publish via gh CLI
echo ""
echo "Release artifacts ready:"
echo "  - ${DMG_FILE}"
echo "  - ${SHA_FILE}"
echo ""
read -r -p "Publish ${TAG} to GitHub Releases now? [y/N] " should_publish
if [[ "${should_publish}" =~ ^[Yy]$ ]]; then
    # Create git tag if it doesn't exist
    if ! git rev-parse "${TAG}" >/dev/null 2>&1; then
        echo "==> Creating git tag ${TAG}..."
        git tag -a "${TAG}" -m "Release ${TAG}"
        echo "==> Pushing tag ${TAG} to origin..."
        git push origin "${TAG}"
    fi

    echo "==> Creating GitHub Release..."
    gh release create "${TAG}" \
        "${DMG_FILE}" \
        "${SHA_FILE}" \
        --title "HiddenStart ${TAG}" \
        --generate-notes \
        --notes-start-tag "$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")"

    echo "==> Release published successfully!"
else
    echo "==> Skipped GitHub publication. Artifacts remain in dist/."
fi
