# spcc clean-all

Remove all spi-compat cache volumes and logs globally.

## Overview

`clean-all` wipes the entire cache root — every package's logs, derived data, and cloned packages — plus every `spi-compat-*` volume across **all installed container runtimes** (Docker and apple/container). The SPI builder images are kept unless you pass `--remove-images`.

```bash
spcc clean-all [--remove-images]
spcc clean-all --help
```

## Options

| Flag | Effect |
|------|--------|
| `--remove-images` | Also remove the cached SPI builder images. |

Without `--remove-images`, a summary line tells you how many builder images were kept. The images are the heaviest single category — 10 images at 5–11 GB each can occupy 60+ GB — but they're also the slowest thing to re-download, so they're preserved by default.

## What survives

Only the SPI builder images (without `--remove-images`). Everything else — per-package directories under the cache root and every `spi-compat-build-*` volume — is removed. The next `spcc run` against any package starts cold: dependencies re-fetch into fresh volumes and xcodebuild rebuilds from scratch.

## Examples

```bash
# Reset all per-package state, keep the builder images
spcc clean-all

# Nuke everything, images included
spcc clean-all --remove-images

# A clean apples-to-apples run against SPI's current images
spcc clean-all --remove-images && spcc run --pull-always
```

## See also

- <doc:ImagesCommand> — remove only the builder images, keeping warm per-package caches.
- <doc:CleanCommand> — clean a single package instead.
- *Cache Management* in the `SwiftPackageCompatCheck` library documentation — the full cache layout and when to clean what.
