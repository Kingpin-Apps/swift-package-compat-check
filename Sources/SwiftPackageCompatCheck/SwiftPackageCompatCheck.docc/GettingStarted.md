# Getting Started

Install `spcc`, run your first matrix, read the output.

## Overview

`spcc` is a single-binary CLI tool. This article walks through installing it, pointing it at a package, and reading the matrix it prints.

## Requirements

| Requirement | Version | Why |
|-------------|---------|-----|
| macOS       | 15+     | Required by the dependency stack; matches the rest of the Kingpin Swift packages. |
| Swift       | 6.3+    | `spcc` is built with `swift-tools-version: 6.3` and Swift 6 strict concurrency. |
| Xcode       | 26.4+   | For the `xcodebuild` cells (`ios`, `tvos`, `watchos`, `visionos`, `macos-xcodebuild`). |
| Docker      | Any modern release | For `linux`, `android`, `wasm` cells. Optional if you only care about Apple platforms. |

## Install

### With `just install` (recommended)

The project's `Justfile` bundles a complete universal-binary + codesign + install pipeline:

```bash
git clone https://github.com/Kingpin-Apps/swift-package-compat-check.git
cd swift-package-compat-check
CODESIGN_IDENTITY="Developer ID Application: …" just install
```

This builds a universal binary (arm64 + x86_64), codesigns it with your Developer ID, and copies it to `~/.local/bin/spcc`. Override the destination with `INSTALL_DIR=/usr/local/bin`.

For Homebrew-style distribution (notarised for Gatekeeper):

```bash
CODESIGN_IDENTITY="…" just notarize
```

### From source

```bash
git clone https://github.com/Kingpin-Apps/swift-package-compat-check.git
cd swift-package-compat-check
swift build -c release
cp .build/release/spcc ~/.local/bin/spcc
```

### Confirm the install

```bash
spcc --version
spcc --help
```

## Your first run

`cd` into any Swift package directory and run:

```bash
spcc run --dry-run
```

This prints the matrix that *would* run without actually building anything — useful for verifying scheme detection picked the right target and the platform/version filters look correct.

```
Package:   .
Scheme:    SwiftNaCl
Versions:  6.0, 6.1, 6.2, 6.3
Platforms: ios, macos-spm, macos-xcodebuild, visionos, tvos, watchos, linux, wasm, android

╭──────────────────┬───────────┬───────────┬───────────┬───────────╮
│ Platform         │ Swift 6.0 │ Swift 6.1 │ Swift 6.2 │ Swift 6.3 │
├──────────────────┼───────────┼───────────┼───────────┼───────────┤
│ ios              │ ?         │ ?         │ ?         │ ?         │
│ macos-spm        │ ?         │ ?         │ ?         │ ?         │
... (all cells `?` for runnable, `—` for SPI-skipped)
```

Drop `--dry-run` and `spcc` actually builds each cell.

## Reading the matrix

| Symbol | Meaning |
|--------|---------|
| `?`    | Cell is queued, not yet started (dry-run output, or live mode before the cell starts). |
| `⠋` `⠙` `⠹` `⠸` `⠼` `⠴` `⠦` `⠧` `⠇` `⠏` | Cell is running (10-frame braille spinner in live mode). |
| `—`    | SPI doesn't run this cell. Currently only `android × 6.0` and `wasm × 6.0`. |
| `✓`    | Build succeeded. |
| `✗`    | Build failed. The log path is printed below the matrix. |

When at least one cell fails, the matrix is followed by a `Failed cells:` summary listing the log path for each failure so you can drill in directly.

## A faster first run

If you don't want to wait for the full 34-cell matrix (cold first run can be 20+ minutes with cross-SDK Docker image pulls), narrow the scope:

```bash
# Just the macOS SPM cells — under a second per cell, no Docker needed
spcc run -p macos-spm -s 6.3

# Apple platforms only, current Swift only
spcc run -p ios,macos-spm,macos-xcodebuild,tvos,watchos,visionos -s 6.3

# One row of the matrix at a time
spcc run -p linux
```

## Next steps

- <doc:RunningTheMatrix> covers all flags + the three output modes (live / streaming / quiet).
- <doc:CacheManagement> covers the on-disk cache layout, `spcc clean*`, and how to reclaim Docker image disk.
- <doc:Troubleshooting> covers qemu hangs, scheme-detection failures, and the wasm SDK fallback.
