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

    /// The full bash resolver lifted verbatim from `spi-compat-check.sh`'s
    /// `run_cross_sdk` function. Embeds the resolver inside the container so it
    /// runs against the image's actual installed SDK list rather than guessing.
    static let resolverScript: String = #"""
        set -euo pipefail
        swift --version

        # Fast path: caller passed the exact `--swift-sdk` argument SPI uses.
        if [[ -n "${SDK_BUILD_ARG:-}" ]]; then
          echo "Trying SPI-style SDK arg: $SDK_BUILD_ARG"
          if swift build --swift-sdk "$SDK_BUILD_ARG" --scratch-path /build; then
            exit 0
          fi
          echo "SPI-style SDK arg failed; falling back to dynamic resolution."
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
        echo "Using SDK: $sdk_id"
        swift build --swift-sdk "$sdk_id" --scratch-path /build
        """#
}
