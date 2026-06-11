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

# Same as `just hello` but exercises --test (HelloWorld fixture has a real test target)
hello-test:
    swift run spcc run --test -p macos-spm,linux -s 6.3 Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Smoke-test --config via the fixture's checked-in .spi-compat.toml
hello-config:
    swift run spcc run \
        --config Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld/.spi-compat.toml \
        Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Full 34-cell matrix against HelloWorld (slow on first run; pulls all SPI images)
hello-full:
    swift run spcc run Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Smoke-test the apple/container runtime path against HelloWorld (requires `container` 0.12+ + `container system start`)
hello-container:
    swift run spcc run --container-runtime container -p macos-spm,linux -s 6.3 Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld

# Run HelloWorld under both runtimes and confirm cell pass/fail matches. Fails non-zero on any divergence.
hello-parity:
    #!/usr/bin/env bash
    set -euo pipefail
    PKG=Tests/SwiftPackageCompatCheckTests/Fixtures/HelloWorld
    PLATFORMS="macos-spm,linux,android"
    SV="6.3"
    DOCKER_OUT=$(mktemp /tmp/spcc-parity-docker.XXXXXX.txt)
    CONTAINER_OUT=$(mktemp /tmp/spcc-parity-container.XXXXXX.txt)
    trap 'rm -f "$DOCKER_OUT" "$CONTAINER_OUT"' EXIT
    echo "▶ docker runtime"
    swift run spcc run --container-runtime docker -p "$PLATFORMS" -s "$SV" --no-live "$PKG" | tee "$DOCKER_OUT"
    echo ""
    echo "▶ container runtime"
    swift run spcc run --container-runtime container -p "$PLATFORMS" -s "$SV" --no-live "$PKG" | tee "$CONTAINER_OUT"
    echo ""
    # Compare just the rows of the final matrix box (the canonical pass/fail
    # report). Skip the per-cell streaming lines whose timings naturally differ
    # between runtimes — what matters is the verdict, not the wall-clock.
    DOCKER_MATRIX=$(grep '│' "$DOCKER_OUT" || true)
    CONTAINER_MATRIX=$(grep '│' "$CONTAINER_OUT" || true)
    if [ "$DOCKER_MATRIX" = "$CONTAINER_MATRIX" ]; then
        echo "✓ parity green — matrices match"
    else
        echo "✗ parity FAILED — runtimes diverge"
        diff <(printf '%s\n' "$DOCKER_MATRIX") <(printf '%s\n' "$CONTAINER_MATRIX") || true
        exit 1
    fi

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

# Tarball notarized binary, create GitHub release, upload asset. Reads version from cz.json.
publish: notarize
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION=$(jq -r '.commitizen.version' cz.json)
    BIN_PATH="{{ justfile_directory() }}/.build/universal/release"
    TARBALL="$BIN_PATH/spcc-${VERSION}-macos-universal.tar.gz"
    NOTES=$(mktemp /tmp/spcc-release-notes-XXXXXX.md)
    trap 'rm -f "$NOTES"' EXIT
    echo "Tarballing → $TARBALL"
    (cd "$BIN_PATH" && tar -czf "spcc-${VERSION}-macos-universal.tar.gz" spcc)
    shasum -a 256 "$TARBALL"
    awk -v v="^## ${VERSION//./\\.}" '$0 ~ v {flag=1; print; next} /^## /{flag=0} flag' CHANGELOG.md > "$NOTES"
    if [ ! -s "$NOTES" ]; then
        echo "✗ No CHANGELOG entry found for $VERSION" >&2
        exit 1
    fi
    echo "Creating GitHub release $VERSION..."
    gh release create "$VERSION" \
        --title "$VERSION" \
        --notes-file "$NOTES" \
        "$TARBALL"
    echo "✓ Released $VERSION"

# Bump the Homebrew tap formula (Kingpin-Apps/homebrew-tap) to a released version.
# Patches only the url + sha256 lines, preserving the rest of the formula. Computes
# sha256 from `tarball` if given, otherwise downloads the published release asset.
# Uses your gh auth locally, or $GH_TOKEN in CI (needs write access to the tap repo).
# Run manually to recover a release: `just tap-bump 0.5.0`
tap-bump version tarball="":
    #!/usr/bin/env bash
    set -euo pipefail
    VERSION="{{ version }}"
    TARBALL="{{ tarball }}"
    TAP="Kingpin-Apps/homebrew-tap"
    FORMULA="Formula/spcc.rb"
    URL="https://github.com/Kingpin-Apps/swift-package-compat-check/releases/download/${VERSION}/spcc-${VERSION}-macos-universal.tar.gz"
    WORK=$(mktemp -d)
    trap 'rm -rf "$WORK"' EXIT
    if [ -n "$TARBALL" ] && [ -f "$TARBALL" ]; then
        SHA256=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
    else
        echo "Downloading release asset to compute sha256..."
        curl --fail --location --silent --show-error -o "$WORK/asset.tar.gz" "$URL"
        SHA256=$(shasum -a 256 "$WORK/asset.tar.gz" | awk '{print $1}')
    fi
    gh api "repos/${TAP}/contents/${FORMULA}" > "$WORK/resp.json"
    jq -r '.content' "$WORK/resp.json" | base64 --decode > "$WORK/formula.rb"
    FILE_SHA=$(jq -r '.sha' "$WORK/resp.json")
    sed -i.bak -E "s|^( *url )\".*\"|\\1\"${URL}\"|" "$WORK/formula.rb"
    sed -i.bak -E "s|^( *sha256 )\".*\"|\\1\"${SHA256}\"|" "$WORK/formula.rb"
    rm -f "$WORK/formula.rb.bak"
    echo "→ formula now:"
    grep -E '^[[:space:]]*(url|sha256) ' "$WORK/formula.rb"
    gh api "repos/${TAP}/contents/${FORMULA}" -X PUT \
        -f message="spcc ${VERSION}" \
        -f content="$(base64 -i "$WORK/formula.rb" | tr -d '\n')" \
        -f sha="$FILE_SHA" \
        -f branch="main"
    echo "✓ Bumped ${TAP} → ${VERSION}"

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
