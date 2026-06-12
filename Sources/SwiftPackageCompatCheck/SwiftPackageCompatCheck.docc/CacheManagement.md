# Cache Management

The on-disk cache layout, the four cleanup subcommands, and how to reclaim Docker disk.

## Overview

`spcc` keeps a stable per-package cache root so repeat runs are fast — `xcodebuild`'s incremental rebuilds work, SwiftPM checkouts are reused, and Docker volumes persist between runs. This article shows what's on disk, how to read `spcc list-caches`, and when to reach for `clean` / `clean-all` / `images`.

## Cache layout

The cache root is `~/.cache/spi-compat-check/` by default. Override with the `SPI_COMPAT_CACHE` environment variable:

```bash
SPI_COMPAT_CACHE=/Volumes/big-disk/spi-compat spcc run
```

Under the root:

```
~/.cache/spi-compat-check/
├── derived-data/<pkg>/<platform>-<sv>/    ← xcodebuild -derivedDataPath, per cell
├── cloned-packages/<pkg>/                 ← -IDEClonedSourcePackagesDirPathOverride, shared
└── logs/<pkg>/<RUN_TS>/<platform>-<sv>.log
```

Plus Docker named volumes (which don't live under the cache root — `spcc` does not control where Docker stores them):

| Volume name | Used by | Holds |
|---|---|---|
| `spi-compat-build-<pkg>-<sv>` | Linux runner | `--scratch-path /build` for `swift build` |
| `spi-compat-build-<pkg>-android-<sv>` | Android runner | Same, per-platform |
| `spi-compat-build-<pkg>-wasm-<sv>` | Wasm runner | Same, plus the downloaded fallback SDK at `/build/sdk-cache` |

## Why the Docker volumes matter

Without a per-`(package, swift-version)` named volume at `/build`, `swift build` inside the Linux container would try to use the bind-mounted package's `.build/checkouts/` directory — which was populated by macOS-flavoured SwiftPM. It fails immediately with:

```
error: 'X': invalid access to /host/.build/checkouts/...
```

The named volume isolates the container's SwiftPM state from the host's, so:

- The first run cold-fetches dependencies into the volume (slow).
- Subsequent runs reuse them (10×+ faster).

This is the same trick SPI uses internally, just adapted to a local bind-mount setup.

## Log auto-trim

Each `spcc run` writes one log directory per run, timestamped `YYYYMMDDTHHMMSS`. The 5 most recent are kept per package; older ones are removed at the start of every new run.

The current run is always preserved regardless of mtime ordering — important if you've just touched `mtime` on an older directory for some reason.

## Inspecting the cache

```bash
spcc list-caches
```

Sample output:

```
Cache root: /Users/me/.cache/spi-compat-check
  Total:         33G
  logs/
         172K  swift-base58
          85M  swift-cardano-cips
          ...
  derived-data/
           0B  swift-base58
          16G  swift-cardano-cips
          ...
  cloned-packages/
           0B  swift-base58
         319M  swift-cardano-cips

[docker] volumes (spi-compat-*):
       1.2G  spi-compat-build-swift-nacl-6.3
       4.5G  spi-compat-build-swift-cardano-core-android-6.2
       ...
[docker] images (spi-images):
     5.66GB  registry.gitlab.com/swiftpackageindex/spi-images:basic-6.0-latest
     6.02GB  registry.gitlab.com/swiftpackageindex/spi-images:basic-6.1-latest
       ...
```

Volumes and images are reported per installed container runtime — a `[container]` section follows the `[docker]` one if you've used apple/container. Sizes are pulled from `du -sh` (for filesystem paths) and a throwaway `alpine du -sh /data` container (for volumes). Image sizes come from the runtime's own image listing.

## Cleaning up

| Command | What it removes |
|---------|----|
| `spcc clean [path]` | One package's logs/derived-data/cloned-packages + its `spi-compat-build-<pkg>-*` volumes. |
| `spcc clean-all` | The entire cache root + every `spi-compat-*` volume across all installed runtimes. |
| `spcc clean-all --remove-images` | Above, plus the SPI builder images. |
| `spcc images` | Lists cached SPI builder images. |
| `spcc images --remove` | Removes cached SPI builder images (preserves the cache root). |

Each command has a reference page in the `spcc` tool documentation (the `spcc` target's `spcc.docc` catalog).

The SPI builder images are the heaviest single category — 10 images at 5-11 GB each can occupy 60+ GB. They're typically what you want to drop first when reclaiming disk, before touching per-package state.

```bash
# Reclaim image disk only
spcc images --remove

# Reclaim everything except the images (per-package state)
spcc clean-all

# Nuke it all
spcc clean-all --remove-images
```

## When to clean

| Symptom | Try |
|---------|-----|
| `xcodebuild` cells take longer than expected | None — the derived-data cache is what makes them fast. Leave it. |
| Docker volume disk usage growing without bound | `spcc clean <pkg>` for packages you no longer iterate on. |
| `swift build` inside container errors with "invalid manifest cache" | `spcc clean <pkg>` to drop the per-`(pkg, sv)` volume and re-fetch fresh. |
| Disk full | `spcc list-caches` to see the biggest consumers; usually `spcc images --remove` is the quickest win. |
| Want a clean apples-to-apples run vs SPI | `spcc clean-all --remove-images && spcc run --pull-always` |

## See also

- <doc:RunningTheMatrix> for the `--pull-always` flag (forces `docker run --pull=always` instead of the default `--pull=missing`).
- <doc:Troubleshooting> for the per-cell log format and how to read a failure.
