## 0.8.0 (2026-09-27)

### Note

- Linux cells now build natively by default: the official `swift:X.Y-jammy` image at this machine's architecture, instead of SPI's amd64 image under emulation (which on Apple Silicon was slow and could hang or corrupt compiler output). Use `--linux-mode spi` (or `linux_mode = "spi"`) for SPI's exact build. The native image lacks SPI's preinstalled C libraries, such as `libsodium-dev`.
- Linux, Android and Wasm cells now stop after 60 minutes (`--timeout`) or 15 minutes without output (`--stall-timeout`) by default; `0` turns either off. Previously there was no limit.
- Tab completion for zsh, bash and fish now completes paths, `--linux-mode`, `--container-runtime`, and the `-s` / `-p` lists.

### Feat

- complete paths, modes, runtimes and comma lists in shell completions
- build Linux cells natively by default and fail hung container cells

## 0.7.0 (2026-09-15)

### Feat

- add Swift 6.4 support

## 0.6.0 (2026-07-01)

### Feat

- add podman runtime with preflight and auto-selection

## 0.5.3 (2026-06-12)

### Refactor

- rename SPCC root command to SwiftPackageCompatCheck

## 0.5.2 (2026-06-11)

## 0.5.1 (2026-06-11)

## 0.5.0 (2026-06-11)

### Feat

- --install-host/--install-container and --test-no-parallel for test runs

### Fix

- show folder name instead of '.' in Package line

## 0.4.0 (2026-06-07)

### Feat

- opt-in --container-runtime flag for apple/container

### Fix

- change access level of defaultContainerMemory to internal
- cap apple/container cells at 8G memory (1GB default OOM-kills builds)

## 0.3.0 (2026-06-07)

### Feat

- --config flag / SPCC_CONFIG env var for persistent defaults

## 0.2.0 (2026-06-07)

### Feat

- add -t / --test flag to run `swift test` per cell

## 0.1.0 (2026-06-06)

### Feat

- print failed cells' log paths in a footer after the matrix
- animate .running cells with Noora's 10-frame braille spinner
- --timeout flag with docker-label-based container kill
- add --path / -P flag to clean for symmetry with run
- add --path / -P flag to run as an alternative to the positional
- live-updating matrix via Noora's async table API
- cleanup commands, log auto-trim, and --max-parallel
- Android and Wasm runners via SPI cross-SDK images
- Linux runner via SPI's public docker images
- Apple-platform runners (macos-spm + xcodebuild)
- matrix data model, scheme detection, and --dry-run

### Fix

- cross-SDK resolver retries qemu IPC errors and extracts triples
