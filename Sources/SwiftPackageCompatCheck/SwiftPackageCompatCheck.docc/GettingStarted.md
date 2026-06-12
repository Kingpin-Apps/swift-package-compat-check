# Getting Started

Install `spcc`, run your first matrix, read the output.

## Overview

`spcc` is a single-binary CLI tool. This article walks through installing it, pointing it at a package, and reading the matrix it prints.

## Requirements

| Requirement | Version | Why |
|-------------|---------|-----|
| macOS       | 15+     | `spcc` is a macOS-only tool. |
| Xcode       | 26.4+   | For the Apple-platform cells (`macos-spm`, `macos-xcodebuild`, `ios`, `tvos`, `watchos`, `visionos`). |
| Container runtime | Docker (any modern release) or [apple/container](https://github.com/apple/container) 0.12+ | For `linux`, `android`, `wasm` cells. Optional if you only care about Apple platforms. Docker is the default; apple/container is experimental opt-in via `--container-runtime container`. |
| Swift       | 6.2+    | Only needed to build `spcc` from source. |

## Install

Install with Homebrew:

```bash
brew install kingpin-apps/tap/spcc
```

Or build from source with Swift Package Manager:

```bash
git clone https://github.com/Kingpin-Apps/swift-package-compat-check.git
cd swift-package-compat-check
swift build -c release
cp .build/release/spcc ~/.local/bin/spcc
```

Make sure `~/.local/bin` is on your `$PATH` — or copy `spcc` somewhere else that is.

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

This prints the matrix that *would* run without actually building anything — useful for verifying scheme detection picked the right target and the platform/version filters look correct. Cells appear as `?` for "would run" and `—` for SPI-skipped pairs (currently `android × 6.0` and `wasm × 6.0`).

Drop `--dry-run` and `spcc` actually builds each cell. Here's a full matrix against the bundled HelloWorld fixture — every cell green:

![A full 34-cell matrix run against the HelloWorld fixture, every cell green.](hello-world-matrix)

The header shows what `spcc` resolved:

- **Package** — the path you pointed at (positional argument or `--path`).
- **Scheme** — auto-detected by `swift package dump-package`; override with `-S`.
- **Versions / Platforms** — the matrix axes after filtering.
- **Logs** — where the per-cell logfiles will land (one per cell, plus auto-trim to 5 runs per package — see <doc:CacheManagement>).
- **Parallel** — how many cells run concurrently within each Swift version (default `activeProcessorCount / 2`; override with `--max-parallel`).

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
