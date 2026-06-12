# spcc run

Run the SPI build matrix against a package.

## Overview

`run` is the default subcommand — bare `spcc` is equivalent to `spcc run`. It builds (or tests, with `--test`) the package across the selected `(platform × Swift version)` matrix and prints a `✓`/`✗` table, exiting non-zero if any cell failed.

```bash
spcc run [<path>] [options]
spcc run --help
```

This page is the flag reference. The narrative guide — output modes, test mode, overrides, CI usage — is the *Running the Matrix* article in the `SwiftPackageCompatCheck` library documentation.

## Specifying the package

| Flag | Effect |
|------|--------|
| `<path>` (positional) | Path to the Swift package. Defaults to the current directory. |
| `-P, --path <path>` | Same as the positional argument. Wins if both are given. |

## Narrowing the matrix

| Flag | Effect |
|------|--------|
| `-s, --swift <list>` | Comma-separated Swift versions (default: `6.0,6.1,6.2,6.3`). |
| `-p, --platforms <list>` | Comma-separated platforms (default: all nine). |
| `-S, --scheme <name>` | Override the auto-detected scheme used by xcodebuild cells. |
| `--dry-run` | Print the matrix that would run without building anything. |

## Test mode

| Flag | Effect |
|------|--------|
| `-t, --test` | Run `swift test` / `xcodebuild test` per cell instead of building. |
| `--test-no-parallel` | Run each cell's tests serially. No effect without `--test`. |
| `--install-host <list>` | `brew install` these packages on the Mac before Apple test cells. Persists on your machine. Only applied with `--test`. |
| `--install-container <list>` | `apt-get install` these packages inside each Linux/Android/Wasm container. Ephemeral. Only applied with `--test`. |

## Per-Swift-version overrides

Each of these exists once per Swift version — substitute `6.X` with a concrete version. Xcode, toolchain, and Linux-image overrides cover 6.0–6.3; Android/Wasm overrides cover 6.1–6.3 (SPI doesn't run those platforms on Swift 6.0).

| Flag | Effect |
|------|--------|
| `--xcode-6.X <path>` | Xcode.app to use for that version's xcodebuild cells. |
| `--toolchain-6.X <id>` | Toolchain identifier for that version's `macos-spm` cells. |
| `--linux-image-6.X <ref>` | Override the Linux builder image. |
| `--android-image-6.X <ref>` | Override the Android builder image (6.1–6.3 only). |
| `--wasm-image-6.X <ref>` | Override the Wasm builder image (6.1–6.3 only). |
| `--wasm-sdk-url-6.X <url>` | Override the Wasm SDK fallback download URL (6.1–6.3 only). |

## Execution control

| Flag | Effect |
|------|--------|
| `--max-parallel <n>` | Max cells running concurrently within each Swift version (default: `activeProcessorCount / 2`). |
| `--timeout <seconds>` | Per-cell wall-clock timeout; hung containers are killed. Default: no timeout. |
| `--container-runtime <name>` | `docker` (default) or `container` (apple/container, experimental). |
| `--pull-always` | Pass `--pull=always` to the container runtime (default: `--pull=missing`). |

## Output

| Flag | Effect |
|------|--------|
| `--no-live` | Disable the live-updating matrix; stream one line per cell + final matrix. |
| `-q, --quiet` | Suppress everything except the final matrix. |
| `-v, --verbose` | Verbose output. |

## Configuration

| Flag | Effect |
|------|--------|
| `-c, --config <path>` | TOML/JSON file with default flag values. Falls back to `$SPCC_CONFIG`; CLI flags override the file. The *Configuration* article in the library documentation covers the file format. |

## Exit status

`spcc run` exits `0` when every cell passed, non-zero when any cell failed — so it composes directly into CI pipelines and shell scripts.

## Examples

```bash
# Full matrix against the current directory
spcc run

# One row for fast iteration
spcc run -p linux -s 6.3

# Tests with a system dependency, serially
spcc run --test --test-no-parallel --install-container gnupg -p linux -s 6.3
```

## See also

- <doc:CleanCommand> — reset a package's caches when stale build state is the problem.
- *Running the Matrix* and *Getting Started* in the `SwiftPackageCompatCheck` library documentation — the full guide, including how to read the matrix output.
