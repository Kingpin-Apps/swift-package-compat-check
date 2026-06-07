# swift-package-compat-check (`spcc`)

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FKingpin-Apps%2Fswift-package-compat-check%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Kingpin-Apps/swift-package-compat-check)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FKingpin-Apps%2Fswift-package-compat-check%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Kingpin-Apps/swift-package-compat-check)

Run the [Swift Package Index](https://swiftpackageindex.com) build matrix against your Swift package locally, so you don't have to push a tag and wait for SPI's CI queue to find out a platform broke.

`spcc` reproduces the same `(platform × Swift version)` recipe SPI runs on its own builders — same Docker images, same `xcodebuild` destinations, same `swift build --swift-sdk` invocations — and prints a `✓`/`✗` matrix you can diff against the SPI badge.

```
╭──────────────────┬───────────┬───────────┬───────────┬───────────╮
│ Platform         │ Swift 6.0 │ Swift 6.1 │ Swift 6.2 │ Swift 6.3 │
├──────────────────┼───────────┼───────────┼───────────┼───────────┤
│ ios              │ ✓         │ ✓         │ ✓         │ ✓         │
│ macos-spm        │ ✓         │ ✓         │ ✓         │ ✓         │
│ macos-xcodebuild │ ✓         │ ✓         │ ✓         │ ✓         │
│ visionos         │ ✓         │ ✓         │ ✓         │ ✓         │
│ tvos             │ ✓         │ ✓         │ ✓         │ ✓         │
│ watchos          │ ✓         │ ✓         │ ✓         │ ✓         │
│ linux            │ ✗         │ ✗         │ ✗         │ ✗         │
│ wasm             │ —         │ ✓         │ ✓         │ ✓         │
│ android          │ —         │ ✓         │ ✓         │ ✓         │
╰──────────────────┴───────────┴───────────┴───────────┴───────────╯
```

---

## Requirements

| Requirement | Version | Why |
|-------------|---------|-----|
| macOS       | 15+     | Required by `swift-configuration-toml`; matches the rest of the Kingpin Swift stack. |
| Swift       | 6.3+    | `swift-tools-version: 6.3` and Swift 6 strict concurrency. |
| Xcode       | 26.4+   | For `xcodebuild` cells. Multiple Xcodes can be selected per Swift version via `--xcode-6.X`. |
| Docker      | Any modern release | For `linux`, `android`, `wasm` cells. Apple cells don't need it. |

---

## Installation

### Option 1 — `just install` (recommended)

The Justfile bundles a full universal-binary + codesign + install pipeline:

```bash
git clone https://github.com/Kingpin-Apps/swift-package-compat-check.git
cd swift-package-compat-check
CODESIGN_IDENTITY="Developer ID Application: ..." just install
```

By default this installs to `~/.local/bin/spcc`. Override with `INSTALL_DIR=/usr/local/bin`.

For Homebrew-style distribution (notarised for Gatekeeper):

```bash
CODESIGN_IDENTITY="..." just notarize
```

### Option 2 — Build from source

```bash
git clone https://github.com/Kingpin-Apps/swift-package-compat-check.git
cd swift-package-compat-check
swift build -c release
cp .build/release/spcc ~/.local/bin/spcc
```

---

## Quick start

```bash
# Show the matrix that would run without actually building anything
spcc run --dry-run

# Run the full matrix against the package in the current directory
spcc run

# Run a subset for fast iteration
spcc run -p macos-spm,linux -s 6.3

# Run against a package elsewhere
spcc run --path ~/Projects/swift-nacl

# Smoke-test spcc itself against the bundled HelloWorld fixture
just hello
```

When a cell fails, its log path is printed below the matrix so you can drill in:

```
Failed cells (1):
  ✗ wasm × Swift 6.3   /Users/me/.cache/spi-compat-check/logs/swift-nacl/.../wasm-6.3.log
```

---

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `spcc run [path]` | Run the matrix (default subcommand — bare `spcc` is equivalent). |
| `spcc clean [path]` | Remove the package's caches (Docker volumes + log/derived-data/cloned-packages dirs). |
| `spcc clean-all [--remove-images]` | Wipe every spi-compat cache globally. `--remove-images` also drops cached SPI builder images (typically 50+ GB). |
| `spcc list-caches` | `du`-style report of all caches + Docker volumes + builder images. |
| `spcc images [--remove]` | List or remove cached SPI builder images. |

Run `spcc <subcommand> --help` for the full flag list.

---

## What it actually runs

Each cell of the matrix reproduces SPI's own Build Command panel verbatim:

| Platform | Command |
|----------|---------|
| `linux` | `docker run … spi-images:basic-X.Y-latest swift build --triple x86_64-unknown-linux-gnu` |
| `macos-spm` | `xcrun swift build --arch arm64` |
| `macos-xcodebuild` | `xcrun xcodebuild build -scheme <s> -destination platform=macOS,arch=arm64` |
| `ios` / `tvos` / `watchos` / `visionos` | `xcrun xcodebuild build -scheme <s> -destination generic/platform=<SDK>` |
| `android` | `docker run … spi-images:android-X.Y-latest swift build --swift-sdk aarch64-unknown-linux-android28` |
| `wasm` | `docker run … spi-images:wasm-X.Y-latest swift build --swift-sdk swift-X.Y-RELEASE_wasm` |

Apple cells use whichever Xcode `xcode-select` points at by default. Linux / Android / Wasm cells use SPI's own publicly-hosted builder images at `registry.gitlab.com/swiftpackageindex/spi-images:<platform>-X.Y-latest`, so the SDKs and apt packages match SPI exactly.

For full documentation including all flags, caching behaviour, and troubleshooting, see the **[`SwiftPackageCompatCheck` DocC catalog](Sources/SwiftPackageCompatCheck/SwiftPackageCompatCheck.docc/Documentation.md)**.

---

## Caches

`spcc` keeps a stable per-package cache so repeat runs are fast:

```
~/.cache/spi-compat-check/
├── derived-data/<pkg>/<platform>-<sv>/    ← xcodebuild incremental state
├── cloned-packages/<pkg>/                 ← SourcePackages cache shared across xcodebuild cells
└── logs/<pkg>/<RUN_TS>/<platform>-<sv>.log
```

Plus Docker volumes named `spi-compat-build-<pkg>-<sv>` (Linux) and `spi-compat-build-<pkg>-<platform>-<sv>` (Android/Wasm) holding the cross-SDK scratch path.

Logs auto-trim to the latest 5 runs per package. Use `spcc list-caches` to see total disk usage, `spcc clean <pkg>` to drop one package's caches, `spcc clean-all` to nuke everything.

Override the cache root with `SPI_COMPAT_CACHE=/custom/path spcc run`.

---

## Features

- **Live updating matrix** under a TTY — cells transition `?` → `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` (braille spinner) → `✓`/`✗` in place, no scrollback.
- **Scheme auto-detection** via `swift package dump-package` — skips system C targets like `Clibsodium` that alphabetically win against the real Swift library product.
- **Per-Swift-version overrides** — `--xcode-6.X`, `--toolchain-6.X`, `--linux-image-6.X`, `--android-image-6.X`, `--wasm-image-6.X`, `--wasm-sdk-url-6.X`.
- **Bounded concurrent fan-out** — `--max-parallel N` runs cells in parallel within each Swift version. Defaults to `activeProcessorCount / 2`.
- **Timeout safety net** — `--timeout SECONDS` kills hung Docker containers by label.
- **Qemu IPC retry** — the cross-SDK resolver detects transient "failed parsing the Swift compiler output" errors under qemu emulation and retries the build before falling back. Critical for Android/Wasm cells against large packages on Apple Silicon.
- **Multi-arch bundle extraction** — when an Android SDK bundle ships multiple triples (the finagolfin/swift-android-sdk case), `spcc` extracts the specific triple matching SPI's intent rather than building for every architecture in the bundle.

---

## Comparison to `spi-compat-check.sh`

This package supersedes the [`spi-compat-check.sh`](https://gist.github.com/...) bash script that previously served the same role internally at Kingpin Apps. Feature parity reached as of 2026-06-06; the bash script is retained as a sanity-check fallback only.

Improvements over the bash original:
- Qemu IPC retry + multi-arch bundle triple extraction (fixes hangs the bash script can also hit).
- Per-cell timeout with Docker label-based container kill.
- Live updating matrix.
- Unit tests against every runner.
- Distributable as a single binary via Homebrew tap.

---

## Development

```bash
just test           # Unit tests
just hello          # Smoke-test spcc against the bundled HelloWorld fixture
just hello-full     # Full 34-cell matrix against HelloWorld (slow on first run)
just build          # Debug build
just release        # Release build for current host arch
just bump           # Cut a release: `cz bump` then push --follow-tags
```

See the DocC catalog for the architecture overview and how runners are layered.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
