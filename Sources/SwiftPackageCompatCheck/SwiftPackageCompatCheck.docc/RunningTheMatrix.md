# Running the Matrix

Every flag, every output mode, every override.

## Overview

`spcc run` is the default subcommand — bare `spcc` is equivalent to `spcc run`. It accepts the package path either positionally or via `--path`, plus a long list of flags for narrowing scope, overriding tools, controlling output, and configuring safety nets. This article is the narrative guide; a compact flag table lives in the `spcc` tool documentation's *spcc run* page.

## Specifying the package

```bash
spcc run                                       # cwd (default)
spcc run /path/to/pkg                          # positional argument
spcc run --path /path/to/pkg                   # equivalent
spcc run -P /path/to/pkg                       # equivalent (short form)
spcc run --path /a /b                          # --path wins, positional ignored
```

If both are given, `--path` wins.

## Narrowing scope

Comma-separated lists filter both axes of the matrix:

```bash
# Just two platforms
spcc run -p macos-spm,linux

# Just one Swift version
spcc run -s 6.3

# Just one cell
spcc run -p linux -s 6.3
```

Unknown values produce a `ValidationError` listing what's allowed, so typos fail fast:

```bash
$ spcc run -p iso
Error: Unknown platform: iso. Allowed: ios, macos-spm, macos-xcodebuild, visionos, tvos, watchos, linux, wasm, android.
```

## Overriding the scheme

`spcc` auto-detects a scheme by running `swift package dump-package` and picking the first library product whose backing target is a regular Swift target. This handles the common gotcha where a system C target like `Clibsodium` alphabetises ahead of the real Swift library.

When you need to override (e.g. a package with multiple library products), use `-S`:

```bash
spcc run -S SwiftNaCl
```

## Per-Swift-version overrides

When the same Swift version maps to a specific Xcode or toolchain on your machine:

```bash
spcc run \
  --xcode-6.0 /Applications/Xcode-16.2.app \
  --xcode-6.1 /Applications/Xcode-16.3.app \
  --xcode-6.2 /Applications/Xcode-26.3.app \
  --xcode-6.3 /Applications/Xcode-26.4.app
```

`--xcode-6.X` sets `DEVELOPER_DIR=<path>/Contents/Developer` for that Swift version's xcodebuild cells. Same shape for toolchain selection on `macos-spm`:

```bash
spcc run --toolchain-6.0 swift-6.0-RELEASE
```

This adds `xcrun --toolchain swift-6.0-RELEASE` to the `swift build` invocation.

## Per-image overrides

By default `spcc` uses SPI's own publicly-hosted builder images at `registry.gitlab.com/swiftpackageindex/spi-images:<platform>-<sv>-latest`. Override per platform per Swift version when you need to pin a specific digest or test against a custom image:

```bash
spcc run --linux-image-6.3 my-registry.example/swift:6.3-jammy
spcc run --android-image-6.2 registry.gitlab.com/.../spi-images@sha256:abc...
spcc run --wasm-image-6.1 alternate-wasm-image:tag
```

The Android and Wasm override flags exist for Swift 6.1–6.3 only — SPI doesn't run those platforms against Swift 6.0, so there's no cell to override.

For wasm specifically, the cross-SDK resolver inside the container falls back to downloading and installing a swiftwasm artifact bundle when the image's bundled SDK doesn't match. The default fallback URLs are the upstream swiftwasm release builds; override per Swift version:

```bash
spcc run --wasm-sdk-url-6.3 https://internal.example/sdk.zip
```

## Running tests instead of just building

By default each cell runs `swift build` (or `xcodebuild build`) — matching SPI's own matrix, which is build-compatibility only. To run the package's test suite per cell instead, pass `-t` / `--test`:

```bash
spcc run --test                              # whole matrix runs `swift test`
spcc run --test -p macos-spm,linux -s 6.3    # one row's worth of tests
```

What changes per platform:

| Platform | Build mode | Test mode |
|----------|------------|-----------|
| `macos-spm` | `xcrun swift build --arch arm64` | `xcrun swift test --arch arm64` |
| `macos-xcodebuild` | `xcodebuild build … -destination platform=macOS,arch=arm64` | `xcodebuild test …` (same destination — macOS is test-compatible) |
| `ios` / `tvos` / `watchos` / `visionos` | `xcodebuild build … -destination generic/platform=<SDK>` | `xcodebuild test … -destination generic/platform=<SDK> Simulator` (Simulator SDK required by `xcodebuild test`) |
| `linux` | `docker run … swift build --triple x86_64-unknown-linux-gnu` | `docker run … swift test --triple x86_64-unknown-linux-gnu` |
| `android` / `wasm` | `docker run … swift build --swift-sdk <triple>` | `docker run … swift test --swift-sdk <triple>` (SwiftPM compiles the test target but typically can't execute the binary without a target device — expect failures unless your package has cross-SDK test infrastructure) |

Caveats worth knowing:

- A cell fails with `error: no tests found; create a target in the 'Tests' directory` when the package has no test target. That's a real SwiftPM error, not a `spcc` bug — narrow with `-p` if you don't want every platform reporting it.
- Cross-SDK cells (`android`, `wasm`) typically fail in test mode because there's no native Linux/wasm runtime to execute the tests in. Narrow with `-p` to avoid noise, or use test mode only for Apple + Linux.

### Serial test execution

Modern Swift Testing runs test cases in parallel within a single process by default. For suites that share global state — a gnupg keyring, a fixed TCP port, a temp directory, a process-wide singleton — that parallelism causes flaky, order-dependent failures. `--test-no-parallel` forces each cell's tests to run serially:

```bash
spcc run --test --test-no-parallel -p macos-spm,linux -s 6.3
```

| Platform | Effect |
|----------|--------|
| `macos-spm`, `linux`, `android`, `wasm` | appends `--no-parallel` to `swift test` |
| `macos-xcodebuild`, `ios`, `tvos`, `watchos`, `visionos` | appends `-parallel-testing-enabled NO` to `xcodebuild test` |

**This is not `--max-parallel`.** `--max-parallel` bounds how many *cells* of the matrix run concurrently (one process per cell); `--test-no-parallel` bounds parallelism *inside* a single cell's test process. They're independent — you can run 4 cells at once where each runs its tests serially. The flag only applies with `--test`; in build mode it's a no-op (a note is printed if you pass it without `--test`).

## Installing test dependencies

Some packages' tests need a system binary or library that the bare SPI images and a stock Mac don't ship — e.g. swift-gnupg shells out to `gpg`, or a C-wrapper needs `-dev` headers to build the test target. Two flags pull those in, each targeting the environment its cells actually run in:

```bash
spcc run --test \
  --install-host gnupg \                       # brew install on the Mac (Apple cells)
  --install-container "gnupg,libgcrypt20-dev" \ # apt-get inside each container (linux/android/wasm)
  -p macos-spm,linux -s 6.3
```

| Flag | Manager | Where | Lifetime | When it runs |
|------|---------|-------|----------|--------------|
| `--install-host` | `brew install` | the host Mac, shared by all Apple cells | **persists** on your machine | once, up front, before the matrix — only if an Apple platform is selected |
| `--install-container` | `apt-get install` | inside each Linux/Android/Wasm container | ephemeral (container is `--rm`) | per cell, before that cell's build/test body |

Both take a comma-separated list and both are **gated behind `--test`** — a plain `spcc run` build installs nothing, and passing them without `--test` prints a note and ignores them. The same lists can live in a config file as `install_host` / `install_container` (see <doc:Configuration>).

Notes worth knowing:

- Host installs persist. `brew install gnupg` leaves gnupg on your Mac after the run — that's by design (so repeat runs are fast), but it's a real side effect, unlike the throwaway container installs.
- A `brew install` failure is **non-fatal**: it's reported and the run continues so container cells still execute. A container `apt-get` failure fails that cell (the install runs under `set -euo pipefail` before the build).
- Package names differ across managers (brew `gnupg` vs apt `gnupg` happen to match, but brew `libsodium` ≈ apt `libsodium-dev`), which is why the two lists are separate rather than one shared list.
- Names are validated to ASCII letters/digits and `. _ + -` (no leading `-`) before they're spliced into the `apt`/`brew` invocations.

## Concurrency and timeouts

```bash
# Run up to 3 cells in parallel within each Swift version
spcc run --max-parallel 3

# Kill any cell that exceeds 10 minutes; for Docker cells the container is killed by label
spcc run --timeout 600
```

`--max-parallel` defaults to `activeProcessorCount / 2`. The fan-out axis is per-Swift-version: Swift versions run sequentially (so each version's Docker image is pulled and warmed once), but platforms within a version run concurrently up to the cap.

`--timeout` is a hard wall-clock budget. For container-backed cells, on timeout `spcc` actually kills the container — under Docker it discovers the container id via `docker ps --filter label=spcc-cell=<RUN_TS>-<platform>-<sv> -q` and runs `docker kill` on it; under apple/container it runs `container kill` against the deterministic container name set at launch. The cell is then marked `✗` with `timed out after Ns; container killed` written to the log. Apple cells (xcrun/xcodebuild) aren't covered — they rarely hang in practice, and tuist's `Command` doesn't expose the underlying `Process` for a clean kill.

## Choosing the container runtime

Linux / Android / Wasm cells dispatch through a host-side container runtime. The default is Docker; [apple/container](https://github.com/apple/container) (Apple Silicon, `Virtualization.framework`) is an experimental opt-in:

```bash
spcc run --container-runtime container
```

Or persist it in a config file with `container_runtime = "container"` (see <doc:Configuration>).

apple/container reuses the same SPI builder images and produces identical pass/fail results in `spcc`'s smoke tests, but it hasn't been validated against as wide a range of real-world packages as Docker. Pulls happen as an explicit pre-step (deduped across concurrent cells), and `spcc` raises apple/container's 1 GB default memory cap to 8 GB per cell so non-trivial builds don't get OOM-killed. Pair it with `--timeout` when running long matrices unattended.

## Output modes

`spcc` has three output modes, picked automatically:

| Mode | When | Output shape |
|------|------|---|
| **Live** | TTY + no `-q` + no `--no-live` | Matrix paints once, then redraws in place as cells transition `?` → `⠋⠙…` → `✓`/`✗`. No streaming progress lines. |
| **Streaming** | `--no-live` set, or stdout is piped/non-TTY | One `✓ ios × Swift 6.3 (9.2s)` line per cell as it completes, then the final canonical matrix at the end. |
| **Quiet** | `-q` | Just the final matrix. No streaming, no progress. |

Force streaming when you want a grep-friendly log:

```bash
spcc run --no-live > matrix.log
```

Note: under live mode, **nothing else can write to stdout** while the renderer is active. Noora's `Renderer` is stateful — it tracks `lastRenderedContent` to know how many lines to erase on the next render — so any interleaved `print` would desynchronise the cursor math. `spcc` honours this by collecting cell-state changes into an actor and yielding through an `AsyncStream` consumed by Noora, instead of printing per cell.

## Failed cell logs

Whether the matrix renders live, streamed, or quietly, failed cells get an automatic footer:

```
Failed cells (1):
  ✗ wasm × Swift 6.3   /Users/me/.cache/spi-compat-check/logs/swift-nacl/20260606T192821/wasm-6.3.log
```

Cells are listed in matrix order (Swift version then platform) so the footer visually mirrors the table. Cell labels are column-padded so log paths line up.

## Examples

### Pre-flight before pushing a tag

```bash
spcc run -p ios,macos-spm,linux -s 6.3
```

Catches the common pattern of "everything works on macOS, then SPI badge goes red because something broke on Linux."

### Iterate on a single failing cell

After SPI shows a red badge for `linux × Swift 6.2`:

```bash
spcc run -p linux -s 6.2 --pull-always
```

The `--pull-always` is the equivalent of `docker run --pull=always` — useful when you want to make sure you're running against SPI's exact current `:basic-6.2-latest` digest rather than whatever's cached locally.

### Compare against SPI's badge

When `spcc` shows green for a cell that SPI's badge shows red (or vice versa), the discrepancy is usually one of:

1. SPI's matrix on the badge is for an older tag. Compare against the package's "Builds" page on swiftpackageindex.com, not just the badge.
2. The Apple-platform `platforms:` declaration in `Package.swift`. If your package declares `.iOS(.v14)` but uses a Swift API introduced in iOS 17, `xcodebuild -destination generic/platform=iOS` will fail with a real error.
3. Linux failures around C dependencies (e.g. `libsodium`). SPI's `:basic-X.Y-latest` image preinstalls a curated dev-lib set; if your package needs more, the build fails. `grep "error:" <logfile>` finds the exact missing symbol.

### Use in CI

`spcc` exits non-zero if any cell failed, so it composes cleanly:

```yaml
# .github/workflows/spi-pre-flight.yml
- run: spcc run -p macos-spm,linux,wasm -s 6.3 --no-live
```

The `--no-live` is important — CI logs aren't a TTY anyway, but being explicit means the matrix output is identical between local runs and CI runs (handy when copy-pasting failures into bug reports).

## See also

- <doc:CacheManagement> for managing the on-disk cache and Docker volumes/images.
- <doc:Troubleshooting> for what to do when the matrix output disagrees with SPI's badge or a cell hangs.
