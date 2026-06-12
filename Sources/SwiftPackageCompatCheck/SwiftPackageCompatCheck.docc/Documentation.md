# ``SwiftPackageCompatCheck``

Reproduce the [Swift Package Index](https://swiftpackageindex.com) build matrix locally — no push-and-wait required.

## Overview

`SwiftPackageCompatCheck` (the `spcc` executable) runs the same `(platform × Swift version)` matrix that SPI runs on its own builders. Same Docker images. Same `xcodebuild` destinations. Same `swift build --swift-sdk` invocations. The output is a `✓`/`✗` matrix you can diff against your package's SPI badge before pushing a tag.

![A full matrix run against the bundled HelloWorld fixture — all 34 cells green.](hello-world-matrix)

The default matrix is 9 platforms × 4 Swift versions = 36 cells, minus the 2 SPI doesn't run (android@6.0 and wasm@6.0, shown as `—`) = 34 cells.

## Why this exists

The SPI badge is the source of truth for whether your package builds across the matrix — but seeing a red badge means you've already pushed a tag, waited for SPI's CI queue (often 10-30 minutes), and learned your fix didn't land. `spcc` collapses that loop to a local `swift build` per cell, with the same toolchains and base images SPI uses, so you can iterate on cross-platform fixes in seconds instead of minutes.

## Topics

### Getting started

- <doc:GettingStarted>
- <doc:RunningTheMatrix>
- <doc:Configuration>

### Caches & cleanup

- <doc:CacheManagement>

### When things go wrong

- <doc:Troubleshooting>

### Library API

- ``SwiftPackageCompatCheck/SwiftPackageCompatCheck``
- ``BuildPair``
- ``Platform``
- ``SwiftVersion``
- ``CellState``
- ``CellOutcome``
- ``MatrixRenderer``
- ``MatrixDispatcher``
- ``SchemeDetector``
- ``CachePaths``
- ``CleanupOps``
- ``RunContext``
- ``RunOptions``
