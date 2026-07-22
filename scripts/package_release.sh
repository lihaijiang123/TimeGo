#!/usr/bin/env bash
# Build a distributable TimeGo.app zip for GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="TimeGo"
PROJECT="TimeGo.xcodeproj"
DERIVED="${ROOT}/build/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' TimeGo/Info.plist 2>/dev/null || echo "1.0.0")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' TimeGo/Info.plist 2>/dev/null || echo "1")"
OUT_DIR="${ROOT}/dist"
ZIP_NAME="TimeGo-${VERSION}-b${BUILD}.zip"

echo "==> Cleaning ${DERIVED}"
rm -rf "${DERIVED}"
mkdir -p "${OUT_DIR}"

echo "==> Building ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED}" \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="${DERIVED}/Build/Products/${CONFIGURATION}/TimeGo.app"
if [[ ! -d "${APP}" ]]; then
  echo "error: expected app not found at ${APP}" >&2
  exit 1
fi

# Prefer a real AppIcon.icns in the bundle when present (helps Finder / notifications).
if [[ -f "TimeGo/Resources/AppIcon.icns" ]]; then
  mkdir -p "${APP}/Contents/Resources"
  cp -f "TimeGo/Resources/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing ${APP}"
codesign --force --deep --sign - "${APP}"

echo "==> Verifying signature"
codesign --verify --verbose=2 "${APP}" || true
spctl --assess --type execute --verbose=4 "${APP}" 2>&1 || true

STAGE="${OUT_DIR}/staging"
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
ditto "${APP}" "${STAGE}/TimeGo.app"

ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
rm -f "${ZIP_PATH}"
echo "==> Zipping → ${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${STAGE}/TimeGo.app" "${ZIP_PATH}"

# Also keep a plain .app copy for local install
rm -rf "${OUT_DIR}/TimeGo.app"
ditto "${APP}" "${OUT_DIR}/TimeGo.app"

echo
echo "Done."
echo "  App : ${OUT_DIR}/TimeGo.app"
echo "  Zip : ${ZIP_PATH}"
echo
echo "GitHub Release tip:"
echo "  gh release create v${VERSION} \"${ZIP_PATH}\" --title \"TimeGo ${VERSION}\" --notes \"See README for install steps.\""
echo
echo "Install tip for friends:"
echo "  1) Unzip and drag TimeGo.app to /Applications"
echo "  2) First launch: right-click → Open (Gatekeeper)"
