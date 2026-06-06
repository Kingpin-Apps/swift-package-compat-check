# ── Dev tasks ────────────────────────────────────────────────────────────────
run:
    swift run

build:
    swift build

clean:
    swift package clean

test:
    swift test

release:
    swift build -c release

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
