import Foundation

/// Pure argv constructors for the Android + Wasm docker invocations.
///
/// ``native(packagePath:packageBasename:platform:swiftVersion:image:sdk:pullPolicy:cellLabel:runTests:runtime:installPackages:noParallel:)``
/// (the default, ``LinuxMode/native``) runs an official `swift` image at the
/// host's architecture and installs a pinned ``NativeCrossSDK`` into a shared
/// cache volume.
///
/// ``android(packagePath:packageBasename:swiftVersion:image:pullPolicy:cellLabel:runTests:runtime:useRosetta:installPackages:noParallel:)``
/// and ``wasm(packagePath:packageBasename:swiftVersion:image:pullPolicy:fallbackURL:cellLabel:runTests:runtime:useRosetta:installPackages:noParallel:)``
/// (``LinuxMode/spi``) share the `run_cross_sdk` shape from
/// `spi-compat-check.sh`: a docker run against an SPI builder image whose body
/// is a bash resolver that
///
///   1. tries the SPI-verbatim `--swift-sdk <name>` (fast path)
///   2. falls back to runtime `swift sdk list` matching by SDK_MATCH + compiler version
///   3. optionally downloads a fallback artifact bundle (wasm only)
///
/// `SDK_MATCH`, `SDK_BUILD_ARG`, and `SDK_FALLBACK_URL` are passed in via `-e` so
/// the resolver body stays platform-agnostic.
public enum CrossSDKArgvBuilders {
    public static let packageMountPath = LinuxArgvBuilders.packageMountPath
    public static let scratchMountPath = LinuxArgvBuilders.scratchMountPath

    /// Per-`(package, platform, swift-version, mode)` volume so cross-SDK runs
    /// don't share `/build` state with Linux or each other. Native volumes get a
    /// `-native` suffix, as Linux's do: arm64 products must never be reused by
    /// an amd64 SPI build.
    public static func volumeName(
        packageBasename: String,
        platform: Platform,
        swiftVersion: SwiftVersion,
        mode: LinuxMode = .spi
    ) -> String {
        let base = "spi-compat-build-\(packageBasename)-\(platform.rawValue)-\(swiftVersion.rawValue)"
        return mode == .native ? base + "-native" : base
    }

    /// Volume shared by every native cross-SDK cell: downloaded SDK archives,
    /// the extracted NDK sysroot, and SDKs installed per compiler version. The
    /// `spi-compat` prefix puts it under `list-caches` and `clean-all`.
    public static let sdkCacheVolume = "spi-compat-sdk-cache"

    /// Mount point of ``sdkCacheVolume`` inside the container.
    public static let sdkCacheMountPath = "/sdk-cache"

    /// The `<runtime> run ...` argv for a native (``LinuxMode/native``) Android
    /// or Wasm cell: `image` (normally `sdk.image`) at the host's architecture,
    /// which installs `sdk` into the shared cache volume once and builds with it.
    public static func native(
        packagePath: URL,
        packageBasename: String,
        platform: Platform,
        swiftVersion: SwiftVersion,
        image: String,
        sdk: NativeCrossSDK,
        pullPolicy: PullPolicy,
        cellLabel: String? = nil,
        runTests: Bool = false,
        runtime: ContainerRuntime = .docker,
        installPackages: [String] = [],
        noParallel: Bool = false
    ) -> [String] {
        let volume = volumeName(
            packageBasename: packageBasename,
            platform: platform,
            swiftVersion: swiftVersion,
            mode: .native
        )
        var argv: [String] = runtime.runArgvHead(
            cellLabel: cellLabel ?? "",
            pullPolicy: pullPolicy,
            platform: LinuxMode.native.containerPlatform
        )
        argv.append(contentsOf: [
            "-v", "\(packagePath.path):\(packageMountPath)",
            "-w", packageMountPath,
            "-v", "\(volume):\(scratchMountPath)",
            "-v", "\(sdkCacheVolume):\(sdkCacheMountPath)",
            "-e", "SPI_BUILD=1",
            "-e", "SPI_PROCESSING=1",
            "-e", "SDK_URL=\(sdk.sdkURL)",
            "-e", "SDK_SHA256=\(sdk.sdkSHA256)",
            "-e", "SDK_ID=\(sdk.sdkID)",
            "-e", "SDK_SELECTOR=\(sdk.sdkSelector)",
            "-e", "NDK_URL=\(sdk.ndk?.url ?? "")",
            "-e", "NDK_SHA256=\(sdk.ndk?.sha256 ?? "")",
            "-e", "NDK_DIR=\(sdk.ndk?.directory ?? "")",
            "-e", "SDK_ACTION=\(runTests ? "test" : "build")",
            "-e", "SDK_TEST_ARGS=\((runTests && noParallel) ? "--no-parallel" : "")",
        ])
        if let label = cellLabel {
            argv.append(contentsOf: ["--label", "spcc-cell=\(label)"])
        }
        argv.append(image)
        let install = ContainerInstall.aptPreamble(packages: installPackages)
        argv.append(contentsOf: ["bash", "-c", install + nativeResolverScript])
        return argv
    }

    /// Installs the SDK (and, for Android, the parts of the NDK it links
    /// against) into the shared cache under a lock, then builds. The official images
    /// have no `curl`, so downloads go through `python3`; every archive is
    /// checked against its SHA-256 before use. SDKs install under a directory
    /// per compiler version, so `--swift-sdk <triple>` can never pick up a
    /// bundle built for another compiler.
    static let nativeResolverScript: String = #"""
        set -euo pipefail
        swift --version

        cache=/sdk-cache
        compiler_v="$(swift --version 2>/dev/null | head -1 | awk '/Swift version/ {print $3}')"
        sdks="$cache/swift-sdks/$compiler_v"
        mkdir -p "$cache/downloads" "$sdks"

        fetch() {
          local url="$1" sha="$2" out="$3"
          if [[ -f "$out" ]] && echo "$sha  $out" | sha256sum -c --status; then
            echo "Using cached $(basename "$out")"
            return 0
          fi
          echo "Downloading $url"
          python3 - "$url" "$out.part" <<'PY'
        import shutil, sys, urllib.request
        with urllib.request.urlopen(sys.argv[1]) as r, open(sys.argv[2], "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        PY
          if ! echo "$sha  $out.part" | sha256sum -c --status; then
            echo "ERROR: checksum mismatch for $url (expected $sha, got $(sha256sum "$out.part" | cut -d' ' -f1))"
            rm -f "$out.part"
            return 1
          fi
          mv "$out.part" "$out"
        }

        (
          flock 9
          if [[ -n "$NDK_DIR" && ! -f "$cache/$NDK_DIR/.spcc-complete" ]]; then
            zip="$cache/downloads/$(basename "$NDK_URL")"
            fetch "$NDK_URL" "$NDK_SHA256" "$zip"
            echo "Extracting the NDK sysroot, clang resources and metadata"
            rm -rf "$cache/$NDK_DIR" "$cache/$NDK_DIR.part"
            mkdir -p "$cache/$NDK_DIR.part"
            unzip -q "$zip" "$NDK_DIR/source.properties" "$NDK_DIR/meta/*" \
              "$NDK_DIR/toolchains/llvm/prebuilt/*/sysroot/*" \
              "$NDK_DIR/toolchains/llvm/prebuilt/*/lib/clang/*" \
              -d "$cache/$NDK_DIR.part"
            # Swift Build (SwiftPM's default from 6.4) links with the NDK's
            # ld.lld, an x86_64 binary; point it at the image's own lld.
            for prebuilt in "$cache/$NDK_DIR.part/$NDK_DIR"/toolchains/llvm/prebuilt/*; do
              mkdir -p "$prebuilt/bin"
              ln -s /usr/bin/ld.lld "$prebuilt/bin/ld.lld"
            done
            touch "$cache/$NDK_DIR.part/$NDK_DIR/.spcc-complete"
            mv "$cache/$NDK_DIR.part/$NDK_DIR" "$cache/$NDK_DIR"
            rm -rf "$cache/$NDK_DIR.part" "$zip"
          fi
          if ! swift sdk list --swift-sdks-path "$sdks" 2>/dev/null | grep -qx "$SDK_ID"; then
            archive="$cache/downloads/$(basename "$SDK_URL")"
            fetch "$SDK_URL" "$SDK_SHA256" "$archive"
            swift sdk install "$archive" --swift-sdks-path "$sdks"
            rm -f "$archive"
            if [[ -n "$NDK_DIR" ]]; then
              find "$sdks" -path '*/scripts/setup-android-sdk.sh' -print0 \
                | xargs -0 -r -n1 env ANDROID_NDK_HOME="$cache/$NDK_DIR" bash
            fi
          fi
        ) 9>"$cache/.lock"

        # Swift Build finds the NDK through ANDROID_NDK_HOME when it builds.
        if [[ -n "$NDK_DIR" ]]; then
          export ANDROID_NDK_HOME="$cache/$NDK_DIR"
        fi

        echo "Using SDK: $SDK_ID ($SDK_SELECTOR)"
        swift "${SDK_ACTION:-build}" ${SDK_TEST_ARGS:-} --swift-sdks-path "$sdks" --swift-sdk "$SDK_SELECTOR" --scratch-path /build
        """#

    public static func android(
        packagePath: URL,
        packageBasename: String,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: PullPolicy,
        cellLabel: String? = nil,
        runTests: Bool = false,
        runtime: ContainerRuntime = .docker,
        useRosetta: Bool = false,
        installPackages: [String] = [],
        noParallel: Bool = false
    ) -> [String] {
        crossSDK(
            packagePath: packagePath,
            packageBasename: packageBasename,
            platform: .android,
            swiftVersion: swiftVersion,
            image: image,
            pullPolicy: pullPolicy,
            sdkMatch: "android",
            sdkBuildArg: "aarch64-unknown-linux-android28",
            sdkFallbackURL: "",
            cellLabel: cellLabel,
            runTests: runTests,
            runtime: runtime,
            useRosetta: useRosetta,
            installPackages: installPackages,
            noParallel: noParallel
        )
    }

    public static func wasm(
        packagePath: URL,
        packageBasename: String,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: PullPolicy,
        fallbackURL: String?,
        cellLabel: String? = nil,
        runTests: Bool = false,
        runtime: ContainerRuntime = .docker,
        useRosetta: Bool = false,
        installPackages: [String] = [],
        noParallel: Bool = false
    ) -> [String] {
        crossSDK(
            packagePath: packagePath,
            packageBasename: packageBasename,
            platform: .wasm,
            swiftVersion: swiftVersion,
            image: image,
            pullPolicy: pullPolicy,
            sdkMatch: "wasi$|wasip1$|_wasm$",
            sdkBuildArg: "swift-\(swiftVersion.rawValue)-RELEASE_wasm",
            sdkFallbackURL: fallbackURL ?? "",
            cellLabel: cellLabel,
            runTests: runTests,
            runtime: runtime,
            useRosetta: useRosetta,
            installPackages: installPackages,
            noParallel: noParallel
        )
    }

    static func crossSDK(
        packagePath: URL,
        packageBasename: String,
        platform: Platform,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: PullPolicy,
        sdkMatch: String,
        sdkBuildArg: String,
        sdkFallbackURL: String,
        cellLabel: String? = nil,
        runTests: Bool = false,
        runtime: ContainerRuntime = .docker,
        useRosetta: Bool = false,
        installPackages: [String] = [],
        noParallel: Bool = false
    ) -> [String] {
        let volume = volumeName(
            packageBasename: packageBasename,
            platform: platform,
            swiftVersion: swiftVersion
        )
        var argv: [String] = runtime.runArgvHead(
            cellLabel: cellLabel ?? "",
            pullPolicy: pullPolicy,
            useRosetta: useRosetta
        )
        argv.append(contentsOf: [
            "-v", "\(packagePath.path):\(packageMountPath)",
            "-w", packageMountPath,
            "-v", "\(volume):\(scratchMountPath)",
            "-e", "JAVA_HOME=/root/.sdkman/candidates/java/current",
            "-e", "SPI_BUILD=1",
            "-e", "SPI_PROCESSING=1",
            "-e", "SDK_MATCH=\(sdkMatch)",
            "-e", "SDK_BUILD_ARG=\(sdkBuildArg)",
            "-e", "SDK_FALLBACK_URL=\(sdkFallbackURL)",
            "-e", "SDK_ACTION=\(runTests ? "test" : "build")",
            "-e", "SDK_TEST_ARGS=\((runTests && noParallel) ? "--no-parallel" : "")",
        ])
        if let label = cellLabel {
            argv.append(contentsOf: ["--label", "spcc-cell=\(label)"])
        }
        argv.append(image)
        let install = ContainerInstall.aptPreamble(packages: installPackages)
        argv.append(contentsOf: ["bash", "-c", install + resolverScript])
        return argv
    }

    /// The full bash resolver lifted from `spi-compat-check.sh`'s `run_cross_sdk`
    /// function with two spcc-specific improvements over the bash original:
    ///
    /// 1. **Retry on transient qemu IPC errors.** When `swift build` dies with
    ///    "failed parsing the Swift compiler output: unexpected JSON message"
    ///    (a qemu emulation artifact under Apple Silicon, not a real build
    ///    failure), the resolver retries up to `SPCC_RETRY_MAX` times before
    ///    falling back to a different SDK strategy. Without this, transient
    ///    failures cascade into the multi-triple bundle build that triggered
    ///    the original swift-cardano-cips android-6.1 hang.
    /// 2. **Extract a specific triple from a multi-arch bundle.** When the
    ///    fallback resolver picks a bundle (e.g. `swift-6.1-RELEASE-android-24-0.1`),
    ///    SwiftPM otherwise builds for EVERY targetTriple inside it (armv7 +
    ///    aarch64 + x86_64 × several API levels = 3-9× the work, all under
    ///    qemu). We parse the bundle's `swift-sdk.json` with python3 and pick
    ///    the triple closest to `SDK_BUILD_ARG`'s architecture + API level.
    static let resolverScript: String = #"""
        set -euo pipefail
        swift --version

        : "${SPCC_RETRY_MAX:=2}"

        # Run `swift build` and tee its output to a temp log so we can grep the
        # log for transient-error fingerprints. Returns 0 on success; 1 on a
        # permanent error; 2 on a transient error worth retrying.
        try_build() {
          local sdk="$1" tmplog="$2"
          rm -f "$tmplog"
          set +e
          (
            set -o pipefail
            swift "${SDK_ACTION:-build}" ${SDK_TEST_ARGS:-} --swift-sdk "$sdk" --scratch-path /build 2>&1 | tee "$tmplog"
          )
          local rc=$?
          set -e
          if [[ $rc -eq 0 ]]; then
            return 0
          fi
          if grep -qE "failed parsing the Swift compiler output|unexpected JSON message" "$tmplog"; then
            echo "Detected transient IPC error (qemu corruption)." >&2
            return 2
          fi
          return 1
        }

        # Run try_build with up to SPCC_RETRY_MAX retries on transient errors.
        build_with_retry() {
          local sdk="$1"
          local tmplog
          tmplog="$(mktemp /tmp/spcc-build.XXXXXX.log)"
          local attempt=1 max=$((SPCC_RETRY_MAX + 1))
          while [[ $attempt -le $max ]]; do
            if [[ $attempt -gt 1 ]]; then
              echo "Retry $((attempt - 1))/$SPCC_RETRY_MAX for SDK '$sdk'..."
            fi
            try_build "$sdk" "$tmplog"
            local rc=$?
            if [[ $rc -eq 0 ]]; then
              rm -f "$tmplog"
              return 0
            fi
            if [[ $rc -eq 1 ]]; then
              rm -f "$tmplog"
              return 1
            fi
            attempt=$((attempt + 1))
          done
          rm -f "$tmplog"
          return 1
        }

        # Fast path: caller passed the exact `--swift-sdk` argument SPI uses.
        if [[ -n "${SDK_BUILD_ARG:-}" ]]; then
          echo "Trying SPI-style SDK arg: $SDK_BUILD_ARG"
          if build_with_retry "$SDK_BUILD_ARG"; then
            exit 0
          fi
          echo "SPI-style SDK arg failed permanently; falling back to dynamic resolution."
        fi

        compiler_v="$(swift --version | head -1 | awk "/Swift version/ {print \$3}")"
        if [[ -z "$compiler_v" ]]; then
          echo "ERROR: could not determine host Swift compiler version"
          exit 1
        fi
        escaped_v="${compiler_v//./\\.}"
        version_match="(^|[^0-9.])${escaped_v}([^0-9.]|$)"

        minor_v="$(echo "$compiler_v" | awk -F. "{print \$1\".\"\$2}")"
        if [[ "$minor_v" != "$compiler_v" ]]; then
          escaped_minor="${minor_v//./\\.}"
          minor_version_match="(^|[^0-9.])${escaped_minor}([^0-9.]|$)"
        else
          minor_version_match=""
        fi

        pick_matching_sdk() {
          local sdk
          sdk="$(swift sdk list | grep -E "$SDK_MATCH" | grep -E "$version_match" | head -1)"
          if [[ -n "$sdk" ]]; then
            printf "%s\n" "$sdk"
            return
          fi
          if [[ -n "$minor_version_match" ]]; then
            sdk="$(swift sdk list | grep -E "$SDK_MATCH" | grep -E "$minor_version_match" | head -1)"
            if [[ -n "$sdk" ]]; then
              echo "Note: no SDK at compiler patch $compiler_v; falling back to major.minor ($minor_v)." >&2
              printf "%s\n" "$sdk"
            fi
          fi
        }

        # When `pick_matching_sdk` returns a multi-triple bundle (e.g.
        # `swift-6.1-RELEASE-android-24-0.1`), passing the bundle name to
        # `swift build --swift-sdk` triggers a build for EVERY targetTriple in
        # the bundle. On Apple Silicon under qemu this means 3-9× the work and
        # 3-9× the chance of IPC corruption. Extract a single matching triple
        # from the bundle's swift-sdk.json instead.
        extract_bundle_triple() {
          local sdk_id="$1" hint="${SDK_BUILD_ARG:-}"
          local bundle_path="/root/.swiftpm/swift-sdks/${sdk_id}.artifactbundle"
          if [[ ! -d "$bundle_path" ]]; then
            printf '%s' "$sdk_id"
            return
          fi
          python3 - <<PYEOF
        import json, glob, os, re, sys
        bundle = "$bundle_path"
        hint = "$hint"
        manifests = glob.glob(os.path.join(bundle, "*", "swift-sdk.json"))
        if not manifests:
            print("$sdk_id")
            sys.exit(0)
        with open(manifests[0]) as f:
            data = json.load(f)
        triples = list(data.get("targetTriples", {}).keys())
        if not triples:
            print("$sdk_id")
            sys.exit(0)
        if hint in triples:
            print(hint)
            sys.exit(0)
        # Same architecture as the hint; closest API level <= hint's, else highest available.
        hint_arch = hint.split("-", 1)[0] if hint else ""
        def api_level(triple):
            m = re.search(r"(\d+)$", triple)
            return int(m.group(1)) if m else 0
        hint_api = api_level(hint)
        same_arch = [t for t in triples if t.startswith(hint_arch + "-")]
        if same_arch:
            le_hint = [t for t in same_arch if api_level(t) <= hint_api]
            pick = max(le_hint, key=api_level) if le_hint else max(same_arch, key=api_level)
            print(pick)
            sys.exit(0)
        print(triples[0])
        PYEOF
        }

        sdk_id="$(pick_matching_sdk || true)"

        if [[ -z "$sdk_id" ]]; then
          echo "No bundled SDK matches both /$SDK_MATCH/ and compiler $compiler_v."
          echo "Image-bundled SDKs:"
          swift sdk list | sed "s/^/  /" || true
          if [[ -n "$SDK_FALLBACK_URL" ]]; then
            echo "Installing fallback SDK from: $SDK_FALLBACK_URL"
            mkdir -p /build/sdk-cache
            tmp_zip="/build/sdk-cache/$(basename "$SDK_FALLBACK_URL")"
            if [[ ! -f "$tmp_zip" ]]; then
              curl --fail --location --silent --show-error -o "$tmp_zip.part" "$SDK_FALLBACK_URL"
              mv "$tmp_zip.part" "$tmp_zip"
            else
              echo "Reusing cached SDK bundle: $tmp_zip"
            fi
            swift sdk install "$tmp_zip" 2>&1 | tee /tmp/sdk-install.log || {
              grep -q "already installed" /tmp/sdk-install.log || exit 1
            }
            sdk_id="$(pick_matching_sdk || true)"
          fi
        fi

        if [[ -z "$sdk_id" ]]; then
          echo "ERROR: SDK matching /$SDK_MATCH/ for compiler $compiler_v not found"
          swift sdk list
          exit 1
        fi

        # Resolve a bundle name down to a specific triple if applicable.
        resolved_sdk="$(extract_bundle_triple "$sdk_id")"
        if [[ "$resolved_sdk" != "$sdk_id" ]]; then
          echo "Resolved bundle '$sdk_id' to single triple '$resolved_sdk' (avoiding multi-arch build)."
          sdk_id="$resolved_sdk"
        fi

        echo "Using SDK: $sdk_id"
        build_with_retry "$sdk_id"
        """#
}
