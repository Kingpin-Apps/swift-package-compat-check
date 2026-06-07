# Troubleshooting

What to do when `spcc` disagrees with SPI's badge, a cell hangs, or scheme detection picks the wrong target.

## My matrix disagrees with the SPI badge

The most common reasons, in order of frequency:

1. **The badge is for an older tag.** SPI rebuilds on tag/default-branch push, but the badge image shows the latest result it has — which might be from a release before your fix landed. Compare against the package's "Builds" page at `swiftpackageindex.com/<org>/<pkg>/builds` rather than just the badge.
2. **iOS/tvOS/watchOS deployment-target drift.** SPI respects the `platforms:` declaration in `Package.swift`. A package that declares `.iOS(.v14)` but uses `Never: Decodable` (iOS 17+) or `Date.ISO8601Format` (iOS 15+) will fail `xcodebuild` on iOS. Run `grep -nE 'error:' <logfile>` to find the exact API and SDK floor.
3. **Linux failures specific to C interop.** SPI's `:basic-X.Y-latest` image preinstalls a curated dev-lib set — `libsodium-dev`, `libsqlite3-dev`, `libjemalloc-dev`, `libcurl4-openssl-dev`. If your package needs more, the build fails inside the container with `Could not find <library>` or `Package <pkg> was not found in the pkg-config search path`. The fix is to declare the dependency in the package's system module or add an apt step in your own custom image (`--linux-image-6.X`).
4. **Apple Silicon vs amd64 difference.** SPI's Linux runners are amd64; `spcc` runs the same `:basic-X.Y-latest` image with `--platform linux/amd64`, so under qemu emulation on Apple Silicon. Occasionally matters for C deps with arch-specific code (e.g. blst's asm path).

## Scheme detection picked the wrong target

`spcc` runs `swift package dump-package` and picks the first library product whose backing target is a regular Swift target. This skips system C targets like `Clibsodium` that alphabetically win against a real Swift library product.

When it still picks wrong (e.g. you have two library products and want the secondary), override with `-S`:

```bash
spcc run -S MyOtherLibrary
```

If detection fails entirely with `No library product backed by a regular Swift target found in package 'X'`, your package probably exposes only an executable product. `spcc` is library-shaped — it builds for compatibility, not for executable correctness. Pass `-S` with one of your target names to force a target build.

## A cell hangs

The most common cause is qemu emulation on Apple Silicon for Android/Wasm cells, where the integrated Swift driver's stdin/stdout IPC between `swift` and `swift-frontend` gets a corrupted byte. The build then dies with:

```
error: failed parsing the Swift compiler output: unexpected JSON message: {
```

`spcc` handles this automatically — its cross-SDK resolver detects this exact fingerprint and retries up to `SPCC_RETRY_MAX` times (default 2) before falling back. 

When you suspect a cell is genuinely stuck (not just slow), add a timeout as a safety net:

```bash
spcc run --timeout 1800   # kill any cell over 30 minutes
```

For Docker cells, `--timeout` actually kills the container via `docker kill --filter label=spcc-cell=<RUN_TS>-<platform>-<sv>` so it doesn't keep consuming CPU after `spcc` exits.

If you want to manually unstick a container `spcc` started:

```bash
docker ps --filter "name=spi-compat-" -q | xargs docker kill
```

## A cell is slow but making progress

Some cells genuinely take a long time, especially Android and Wasm under qemu emulation on Apple Silicon. Rough rules of thumb on an M-series Mac:

| Cell | Cold time (large package) | Warm time (rerun) |
|------|---|---|
| `macos-spm` | 1-10 s | 1-3 s |
| `ios` / `tvos` / `watchos` / `visionos` | 5-30 s | 2-10 s |
| `linux` | 30-60 s (incl. image pull) | 10-20 s |
| `android` | 60-300 s | 30-90 s |
| `wasm` | 60-300 s (longer if fallback URL kicks in) | 30-90 s |

If a cell is 5× slower than the table above, it's probably hitting the qemu retry path. Check the log for `Retry N/2 for SDK '<...>'` — if you see this, the retry mechanism is doing its job and the build IS making progress, just over multiple attempts.

## "No SDK found matching query …" on android/wasm

This means the SPI builder image at `:android-X.Y-latest` or `:wasm-X.Y-latest` doesn't have an SDK named exactly what SPI hardcodes in its Build Command panel (e.g. `aarch64-unknown-linux-android28`). It's not your package's fault.

`spcc` handles this with a fallback resolver inside the container:

1. Try the SPI-style hardcoded name first.
2. If that fails, list bundled SDKs (`swift sdk list`) and pick one matching the platform regex + compiler version.
3. If the picked SDK is a multi-architecture bundle, extract the specific triple matching SPI's intent (via the bundle's `swift-sdk.json` and python3) so you don't build for every arch in the bundle.
4. For wasm only: as a last resort, download a fallback SDK from `swiftwasm/swift` releases.

You should see one of these in the log:

- `Using SDK: swift-6.X.Y-RELEASE_wasm` — SPI's image had it; built directly.
- `Resolved bundle '…' to single triple '…' (avoiding multi-arch build)` — the resolver picked a triple from a multi-arch bundle.
- `Installing fallback SDK from: https://github.com/swiftwasm/...` — the resolver downloaded a fresh SDK bundle.

If none of these appear AND the cell failed with "No SDK found …", file an issue — that means the resolver chain itself broke.

## "Could not find executable named 'docker'"

Apple cells (`macos-spm`, `macos-xcodebuild`, `ios`, `tvos`, `watchos`, `visionos`) don't need Docker; they invoke `xcrun` and `xcodebuild` directly.

Docker-backed cells (`linux`, `android`, `wasm`) need Docker installed and running. The error means either:

- Docker isn't installed: install [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or [OrbStack](https://orbstack.dev/) on Apple Silicon, which is faster).
- Docker is installed but the daemon isn't running: open Docker Desktop / OrbStack.

Confirm with `docker info`. If it prints daemon info you're good.

## My logs are full of bash script content

If a cell fails AND the log contains a verbatim dump of the resolver bash script, that's tuist's `Command` reporting an error: when a subprocess exits non-zero, `Command.terminated` includes the full argv (which includes the embedded `bash -c '<script>'`). The script itself is innocent; the real error is usually at the top of the log (look for the first `error:` line).

Use the failed-cells footer to navigate directly:

```bash
spcc run -p android -s 6.1 --no-live
# ...
Failed cells (1):
  ✗ android × Swift 6.1   /Users/me/.cache/spi-compat-check/logs/swift-pkg/.../android-6.1.log

# Then read the actual failure
grep -A 3 "^error:" /Users/me/.cache/spi-compat-check/logs/swift-pkg/.../android-6.1.log
```

## See also

- <doc:RunningTheMatrix> for `--timeout`, `--pull-always`, `--no-live`, and other flags referenced above.
- <doc:CacheManagement> for clearing per-package state when a cell behaves strangely.
