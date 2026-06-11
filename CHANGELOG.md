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
