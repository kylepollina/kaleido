#!/bin/bash
# Builds build/Kaleido-<version>.dmg for the site's download button.
#
# With KALEIDO_SIGN_IDENTITY set ("Developer ID Application: Name (TEAMID)") it signs and notarizes the app and
# the disk image, so both open without a warning, even offline. Store the notary login once first:
#   xcrun notarytool store-credentials kaleido-notary --apple-id <email> --team-id <TEAMID>
# Without the identity it makes an unsigned test image (ad-hoc app, no notarization) that won't open on other Macs.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Kaleido.app
NOTARY_PROFILE="${KALEIDO_NOTARY_PROFILE:-kaleido-notary}"
IDENTITY="${KALEIDO_SIGN_IDENTITY:-}"

./scripts/build.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Kaleido-$VERSION.dmg"

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ -n "$IDENTITY" ]; then
    # The ticket can't be stapled to an app already inside a disk image, so the app goes first.
    ditto -c -k --keepParent "$APP" build/Kaleido-notarize.zip
    notarize build/Kaleido-notarize.zip
    xcrun stapler staple "$APP"
    /bin/rm -f build/Kaleido-notarize.zip
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/kaleido-dmg.XXXXXX")"
trap '/bin/rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Kaleido.app"
ln -s /Applications "$STAGE/Applications"
/bin/rm -f "$DMG"
hdiutil create -quiet -volname Kaleido -srcfolder "$STAGE" -format ULFO -ov "$DMG"

if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
    echo "Built $DMG (signed and notarized)"
else
    echo "Built $DMG (unsigned test image: set KALEIDO_SIGN_IDENTITY for a real release)"
fi
