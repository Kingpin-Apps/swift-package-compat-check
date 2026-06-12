# spcc clean

Remove cache volumes and logs for one package.

## Overview

`clean` drops everything `spcc` has cached for a single package — its log directories, xcodebuild derived data, the shared SourcePackages checkout, and its per-`(package, swift-version)` container volumes — while leaving every other package's caches and the SPI builder images untouched.

```bash
spcc clean [<path>] [options]
spcc clean --help
```

## What it removes

For the package at `<path>` (default: the current directory), keyed by the directory's basename:

| Location | Contents |
|----------|----------|
| `<cache root>/logs/<pkg>/` | Per-run cell logs. |
| `<cache root>/derived-data/<pkg>/` | xcodebuild incremental build state. |
| `<cache root>/cloned-packages/<pkg>/` | SourcePackages cache shared across xcodebuild cells. |
| `spi-compat-build-<pkg>-*` volumes | The container-side SwiftPM scratch path for Linux/Android/Wasm cells. |

The cache root is `~/.cache/spi-compat-check` by default, or `$SPI_COMPAT_CACHE` if set. Each removal is echoed as it happens.

## Options

| Flag | Effect |
|------|--------|
| `<path>` (positional) | Path to the Swift package. Defaults to the current directory. |
| `-P, --path <path>` | Same as the positional argument. Wins if both are given. |
| `--container-runtime <name>` | Which runtime's volumes to clean: `docker` (default) or `container` (apple/container). |

Note that `clean` only sweeps volumes for the one runtime you select. If you've run the package under both Docker and apple/container, run `clean` once per runtime — or use <doc:CleanAllCommand>, which sweeps both.

## When to use it

- The first build after `clean` cold-fetches all dependencies again, so reach for it when a package's cached state is the *problem* — e.g. an "invalid manifest cache" error inside a container — not as routine hygiene.
- It's also the right scope for reclaiming disk from packages you no longer iterate on, without losing the warm caches of those you do.

## Examples

```bash
# Clean the package in the current directory
spcc clean

# Clean a specific package
spcc clean ~/Projects/swift-nacl

# Clean a package's apple/container volumes
spcc clean --container-runtime container
```

## See also

- <doc:CleanAllCommand> — wipe every package's caches at once.
- <doc:ListCachesCommand> — see what's on disk before deciding what to clean.
- *Cache Management* in the `SwiftPackageCompatCheck` library documentation — the full cache layout and when to clean what.
