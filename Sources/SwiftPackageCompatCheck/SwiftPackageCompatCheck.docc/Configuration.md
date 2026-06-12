# Configuration

Persist your default flags in a `.spi-compat.toml` (or JSON) file so you don't have to retype long flag strings every run.

## Overview

`spcc run` accepts a config file that pre-fills every CLI option. CLI flags still win at invocation time — config provides defaults, your flags override.

This is useful when a Swift package author wants to:

- Pin the matrix to a subset (e.g. only `ios`, `macos-spm`, `linux`) without making everyone remember the `-p` flag.
- Override scheme detection once at the project level.
- Set per-Swift-version Xcode/toolchain/image paths that are consistent across the team.
- Default `--test` on for packages that always want test verification, not just build.

## Resolution

Config-file lookup, highest precedence first:

1. **`--config <path>`** CLI flag (or `-c`).
2. **`$SPCC_CONFIG`** environment variable holding the path.
3. None — fall back to built-in defaults.

```bash
spcc run --config ./.spi-compat.toml
SPCC_CONFIG=~/.config/spcc.toml spcc run
```

`~` and other shell metacharacters are expanded.

If neither `--config` nor `$SPCC_CONFIG` is set, `spcc` doesn't try to read anything — there's no implicit "look in the current directory" search. Be explicit.

## File format

The extension picks the parser. `.toml` is recommended (it's the format the docs use and what the fixture's `.spi-compat.toml` is written in); `.json` also works.

Every field is optional. Missing fields fall through to the built-in defaults.

```toml
# Narrow the matrix axes
swift_versions = ["6.2", "6.3"]
platforms      = ["ios", "macos-spm", "linux"]

# Force scheme detection rather than relying on `swift package dump-package`
scheme = "MyLibrary"

# Defaults for the global flags
max_parallel = 4
timeout      = 600     # seconds
pull_always  = true
test         = true    # run `swift test` instead of `swift build`
test_no_parallel = true # run each cell's tests serially (only with test = true)
no_live      = false
verbose      = false

# Container runtime for linux/android/wasm cells: "docker" (default) or
# "container" (apple/container, experimental)
container_runtime = "docker"

# System packages the tests need (only applied when `test` / --test is on).
# Host packages install on the Mac via brew for Apple cells and persist;
# container packages install via apt inside each Linux/Android/Wasm container
# and are ephemeral.
install_host      = ["gnupg"]
install_container = ["gnupg", "libgcrypt20-dev"]

# Per-Swift-version Xcode overrides
[xcode]
"6.0" = "/Applications/Xcode-16.2.app"
"6.1" = "/Applications/Xcode-16.3.app"
"6.2" = "/Applications/Xcode-26.3.app"
"6.3" = "/Applications/Xcode-26.4.app"

# Per-Swift-version toolchain overrides for macos-spm cells
[toolchain]
"6.0" = "swift-6.0-RELEASE"

# Per-Swift-version SPI builder image overrides (Linux)
[linux_image]
"6.3" = "registry.gitlab.com/swiftpackageindex/spi-images:basic-6.3-latest"

# Per-Swift-version Android / Wasm image overrides
[android_image]
"6.3" = "registry.gitlab.com/swiftpackageindex/spi-images:android-6.3-latest"

[wasm_image]
"6.3" = "registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest"

# Per-Swift-version Wasm SDK fallback URLs
[wasm_sdk_url]
"6.3" = "https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.3-RELEASE/swift-wasm-6.3-RELEASE-wasm32-unknown-wasip1.artifactbundle.zip"
```

## Merge semantics

| Field | If CLI flag is set | Else if config has a value | Else |
|-------|--------------------|----------------------------|------|
| `swift_versions` (`-s`) | CLI wins | Use config's list | All four (6.0–6.3) |
| `platforms` (`-p`) | CLI wins | Use config's list | All nine |
| `scheme` (`-S`) | CLI wins | Use config's value | Auto-detect via `swift package dump-package` |
| `max_parallel` (`--max-parallel`) | CLI wins | Use config's value | `activeProcessorCount / 2` |
| `timeout` (`--timeout`) | CLI wins | Use config's value | No timeout |
| `container_runtime` (`--container-runtime`) | CLI wins | Use config's value | `docker` |
| `pull_always` (`--pull-always`) | CLI `||` config | Use config's value | `false` |
| `test` (`-t` / `--test`) | CLI `||` config | Use config's value | `false` |
| `test_no_parallel` (`--test-no-parallel`) | CLI `||` config | Use config's value | `false` (only with `--test`) |
| `no_live` (`--no-live`) | CLI `||` config | Use config's value | `false` (auto-pick by TTY) |
| `verbose` (`-v`) | CLI `||` config | Use config's value | `false` |
| `install_host` (`--install-host`) | CLI wins | Use config's list | Empty (only with `--test`) |
| `install_container` (`--install-container`) | CLI wins | Use config's list | Empty (only with `--test`) |
| `[xcode]`, `[toolchain]`, `[*_image]`, `[wasm_sdk_url]` | CLI value per-key wins | Config's value for absent CLI keys | Empty map |

Booleans use **logical OR** because every CLI flag is opt-in. If you set `test = true` in your config you can't disable it with a flag — drop the line from your config or unset `$SPCC_CONFIG`.

## When to commit a config file

A `.spi-compat.toml` checked into a Swift package's repo gives collaborators a one-command `spcc run` that always exercises the right matrix — handy for pre-flight before tagging.

Conversely, don't commit a config file that contains absolute Xcode paths or custom image URLs unique to one machine — keep those in `~/.config/spcc.toml` and point `$SPCC_CONFIG` at it instead.

## See also

- <doc:RunningTheMatrix> for every CLI flag and what it does.
- <doc:Troubleshooting> for what to check when a config-driven run behaves differently from a flag-driven one (usually a typo'd field name — `spcc` silently ignores unknown TOML keys).
