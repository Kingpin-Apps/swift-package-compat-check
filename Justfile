# ── Configurable variables ───────────────────────────────────────────────────
# Developer ID Application certificate. Required by sign/notarize/install only;
# other recipes don't need it, so it's optional at the Justfile level. Set with
# CODESIGN_IDENTITY=... just sign  (or export it once in your shell).
CODESIGN_IDENTITY := env_var_or_default("CODESIGN_IDENTITY", "")

# Keychain profile for notarytool — set up once with:
#   xcrun notarytool store-credentials "spcc-notarytool" \
#     --apple-id <your-apple-id> --team-id <your-team-id> \
#     --password <app-specific-password>
NOTARYTOOL_PROFILE := env_var_or_default("NOTARYTOOL_PROFILE", "spcc-notarytool")

INSTALL_DIR := env_var_or_default("INSTALL_DIR", env_var("HOME") + "/.local/bin")

# ── Dev tasks ────────────────────────────────────────────────────────────────
run:
    swift run

build:
    swift build

clean:
    swift package clean

test:
    swift test

# Smoke-test spcc against the bundled HelloWorld fixture (macos-spm + linux, ~15s warm)
hello:
    swift run spcc run -p macos-spm,linux -s 6.3 Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Full 34-cell matrix against HelloWorld (slow on first run; pulls all SPI images)
hello-full:
    swift run spcc run Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Build for the current host architecture only (fast, for development)
release:
    swift build -c release

# ── Distribution tasks ───────────────────────────────────────────────────────

# Build universal binary (arm64 + x86_64) via lipo
release-universal:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Building arm64..."
    swift build -c release --arch arm64
    echo "Building x86_64..."
    swift build -c release --arch x86_64
    echo "Combining with lipo..."
    mkdir -p .build/universal/release
    lipo -create \
        -output .build/universal/release/spcc \
        .build/arm64-apple-macosx/release/spcc \
        .build/x86_64-apple-macosx/release/spcc
    echo "✓ Universal binary ready (architectures: $(lipo -archs .build/universal/release/spcc))"

# Codesign the universal binary
sign: release-universal
    #!/usr/bin/env bash
    set -euo pipefail
    BIN_PATH="{{ justfile_directory() }}/.build/universal/release"
    echo "Signing binary..."
    codesign --sign "{{ CODESIGN_IDENTITY }}" \
             --options runtime \
             --timestamp \
             --force \
             "$BIN_PATH/spcc"
    echo "Verifying..."
    codesign --verify --verbose "$BIN_PATH/spcc"
    echo "✓ Signed spcc (architectures: $(lipo -archs "$BIN_PATH/spcc"))"

# Notarize for Gatekeeper / Homebrew distribution (requires keychain profile — see above)
notarize: sign
    #!/usr/bin/env bash
    set -euo pipefail
    BIN_PATH="{{ justfile_directory() }}/.build/universal/release"
    STAGING=$(mktemp -d)
    trap 'rm -rf "$STAGING"' EXIT
    cp "$BIN_PATH/spcc" "$STAGING/"
    ZIPFILE=$(mktemp /tmp/spcc-notarize-XXXXXX.zip)
    ditto -c -k --keepParent "$STAGING" "$ZIPFILE"
    echo "Submitting to Apple Notary Service..."
    xcrun notarytool submit "$ZIPFILE" \
        --keychain-profile "{{ NOTARYTOOL_PROFILE }}" \
        --wait
    rm -f "$ZIPFILE"
    echo "✓ Notarization complete"

# Build universal binary, codesign, and install to $INSTALL_DIR
install: sign
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ INSTALL_DIR }}"
    cp "{{ justfile_directory() }}/.build/universal/release/spcc" "{{ INSTALL_DIR }}/spcc"
    echo "✓ Installed spcc to {{ INSTALL_DIR }}"

uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -f "{{ INSTALL_DIR }}/spcc"
    echo "✓ Uninstalled spcc from {{ INSTALL_DIR }}"

# ── Release management ───────────────────────────────────────────────────────

# Update changelog
changelog:
	cz ch

# Regenerate Version.swift from the current cz.json version
version-file:
	#!/usr/bin/env bash
	set -euo pipefail
	VERSION=$(jq -r '.commitizen.version' cz.json)
	echo "Generating Version.swift for v$VERSION..."
	swift package --allow-writing-to-package-directory version-file --create "$VERSION"

# Bump version according to changelog and regenerate Version.swift
bump: changelog
	cz bump
