# spcc list-caches

Show disk usage of every spi-compat cache volume and log directory.

## Overview

`list-caches` is the read-only companion to the clean commands: a `du`-style report of the cache root broken down per package, followed by the `spi-compat-*` volumes and SPI builder images for every container runtime that's installed.

```bash
spcc list-caches
```

It takes no options.

## Sample output

```
Cache root: /Users/me/.cache/spi-compat-check
  Total:        33G
  logs/
       172K  swift-base58
        85M  swift-cardano-cips
  derived-data/
         0B  swift-base58
        16G  swift-cardano-cips
  cloned-packages/
         0B  swift-base58
       319M  swift-cardano-cips

[docker] volumes (spi-compat-*):
       1.2G  spi-compat-build-swift-nacl-6.3
       4.5G  spi-compat-build-swift-cardano-core-android-6.2
[docker] images (spi-images):
     5.66GB  registry.gitlab.com/swiftpackageindex/spi-images:basic-6.0-latest
     6.02GB  registry.gitlab.com/swiftpackageindex/spi-images:basic-6.1-latest
```

Runtimes whose CLI isn't installed (or that have nothing cached) are omitted, so on a Docker-only machine you'll see one `[docker]` section; with apple/container in use a `[container]` section follows.

## How sizes are measured

- Filesystem paths use `du -sh`.
- Volume sizes are measured by mounting each volume into a throwaway container and running `du` inside — accurate, but it means listing many volumes takes a few seconds each.
- Image sizes come from the runtime's own image listing.

## Reading the report

| You see | It means |
|---------|----------|
| Large `derived-data/<pkg>` | Warm xcodebuild caches — this is what makes repeat Apple cells fast. Usually worth keeping. |
| Large volumes for a package you're done with | `spcc clean <pkg>` reclaims them. |
| Tens of GB under images | `spcc images --remove` is the quickest disk win — see <doc:ImagesCommand>. |

## See also

- <doc:CleanCommand>, <doc:CleanAllCommand>, <doc:ImagesCommand> — the cleanup commands.
- *Cache Management* in the `SwiftPackageCompatCheck` library documentation — what each cache is for and when to clean it.
