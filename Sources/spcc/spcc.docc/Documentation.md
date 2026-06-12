# ``spcc``

The `spcc` command-line tool — reproduce the Swift Package Index build matrix locally.

## Overview

`spcc` runs the same `(platform × Swift version)` matrix that [Swift Package Index](https://swiftpackageindex.com) runs on its own builders, so you can validate cross-platform compatibility without pushing a tag and waiting for SPI's CI queue.

```bash
brew install kingpin-apps/tap/spcc
spcc run
```

The tool has five subcommands. `run` is the default — bare `spcc` is equivalent to `spcc run` — and the other four manage the on-disk caches that make repeat runs fast.

These pages are the per-command reference. The full user guide — getting started, running the matrix, configuration files, cache management, and troubleshooting — lives in the `SwiftPackageCompatCheck` library documentation.

## Topics

### Commands

- <doc:RunCommand>
- <doc:CleanCommand>
- <doc:CleanAllCommand>
- <doc:ListCachesCommand>
- <doc:ImagesCommand>
