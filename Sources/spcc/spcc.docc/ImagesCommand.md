# spcc images

List or remove cached SPI builder images.

## Overview

The Linux/Android/Wasm cells pull SPI's builder images from `registry.gitlab.com/swiftpackageindex/spi-images`, and at 5–11 GB each they dominate `spcc`'s disk footprint. `images` shows what's cached and — with `--remove` — drops them, across **all installed container runtimes**.

```bash
spcc images [--remove]
spcc images --help
```

## Options

| Flag | Effect |
|------|--------|
| `--remove` | Remove the cached images instead of just listing them. |

Without `--remove`, each image is listed with its size, grouped under a `[docker]` / `[container]` header per runtime:

```
[docker]
5.66GB	registry.gitlab.com/swiftpackageindex/spi-images:basic-6.0-latest
6.02GB	registry.gitlab.com/swiftpackageindex/spi-images:basic-6.1-latest
2.9GB	registry.gitlab.com/swiftpackageindex/spi-images:wasm-6.3-latest
```

If nothing is cached, it prints `No SPI builder images cached locally.`

## When to use it

Removing images is the quickest disk win and the *least* destructive cleanup: per-package build caches (volumes, derived data) stay warm, so subsequent runs only pay the image re-pull, not a full dependency re-fetch. Reach for `images --remove` before `clean`/`clean-all` when disk space is the only problem.

The next `spcc run` re-pulls whatever images its cells need — combine with `--pull-always` if you specifically want SPI's current `-latest` digests:

```bash
spcc images --remove && spcc run --pull-always
```

## See also

- <doc:ListCachesCommand> — see image sizes alongside the other caches.
- <doc:CleanAllCommand> — `--remove-images` folds this into a full wipe.
- *Cache Management* in the `SwiftPackageCompatCheck` library documentation — the full disk-usage picture.
