import Foundation

/// Pure argv constructors for the Android + Wasm docker invocations. Both platforms
/// share the same `run_cross_sdk` shape from `spi-compat-check.sh`: a docker run
/// against an SPI builder image whose body is a bash resolver that
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

    /// Per-`(package, platform, swift-version)` volume so cross-SDK runs don't
    /// share `/build` state with Linux or each other.
    public static func volumeName(
        packageBasename: String,
        platform: Platform,
        swiftVersion: SwiftVersion
    ) -> String {
        "spi-compat-build-\(packageBasename)-\(platform.rawValue)-\(swiftVersion.rawValue)"
    }

    public static func android(
        packagePath: URL,
        packageBasename: String,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: String
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
            sdkFallbackURL: ""
        )
    }

    public static func wasm(
        packagePath: URL,
        packageBasename: String,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: String,
        fallbackURL: String?
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
            sdkFallbackURL: fallbackURL ?? ""
        )
    }

    static func crossSDK(
        packagePath: URL,
        packageBasename: String,
        platform: Platform,
        swiftVersion: SwiftVersion,
        image: String,
        pullPolicy: String,
        sdkMatch: String,
        sdkBuildArg: String,
        sdkFallbackURL: String
    ) -> [String] {
        let volume = volumeName(
            packageBasename: packageBasename,
            platform: platform,
            swiftVersion: swiftVersion
        )
        return [
            "docker", "run",
            "--pull=\(pullPolicy)",
            "--rm",
            "--platform", "linux/amd64",
            "-v", "\(packagePath.path):\(packageMountPath)",
            "-w", packageMountPath,
            "-v", "\(volume):\(scratchMountPath)",
            "-e", "JAVA_HOME=/root/.sdkman/candidates/java/current",
            "-e", "SPI_BUILD=1",
            "-e", "SPI_PROCESSING=1",
            "-e", "SDK_MATCH=\(sdkMatch)",
            "-e", "SDK_BUILD_ARG=\(sdkBuildArg)",
            "-e", "SDK_FALLBACK_URL=\(sdkFallbackURL)",
            image,
            "bash", "-c", resolverScript,
        ]
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
            swift build --swift-sdk "$sdk" --scratch-path /build 2>&1 | tee "$tmplog"
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
