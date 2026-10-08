import Foundation

/// What a native (``LinuxMode/native``) Android or Wasm cell needs: an official
/// `swift:<patch>-jammy` image run at the host's architecture, plus the Swift
/// SDK built for exactly that compiler.
///
/// A Swift SDK only loads into the compiler release it was built with
/// ("module compiled with Swift 6.1.3 cannot be imported by the Swift 6.2
/// compiler"), so each entry pins the image to the patch release its SDK
/// targets rather than the floating `swift:X.Y-jammy` tag.
///
/// Official swift.org SDKs exist for Wasm from 6.2 and Android from 6.3.
/// Earlier versions use the community bundles SPI's own images were built
/// from: swiftwasm for Wasm 6.1, finagolfin's swift-android-sdk for Android
/// 6.1 and 6.2. Checksums come from swift.org's `releases.json` and the GitHub
/// release assets.
public struct NativeCrossSDK: Sendable, Equatable {
    /// The official builder image, pinned to the SDK's compiler patch.
    public let image: String
    /// The SDK artifact-bundle archive.
    public let sdkURL: String
    /// SHA-256 of the archive at `sdkURL`.
    public let sdkSHA256: String
    /// The ID `swift sdk list` reports once the bundle is installed.
    public let sdkID: String
    /// The `--swift-sdk` argument: one target triple for Android, so SwiftPM
    /// doesn't build every triple in the bundle; the SDK ID for Wasm.
    public let sdkSelector: String
    /// The NDK whose sysroot the Android SDK links against; `nil` for Wasm.
    public let ndk: AndroidNDK?

    /// The pinned entry for `platform` × `swiftVersion`, or `nil` when no SDK
    /// exists (non-cross platforms, and Swift 6.0, which SPI skips too).
    public static func entry(for platform: Platform, swiftVersion: SwiftVersion) -> NativeCrossSDK? {
        switch (platform, swiftVersion) {
        case (.android, .v6_1):
            return finagolfin(
                tag: "6.1.3", compiler: "6.1.3",
                sha256: "440d09d539bda5b94807598b00696ac5d3893cb515b24715ac8868d62130b6d5"
            )
        case (.android, .v6_2):
            return finagolfin(
                tag: "6.2", compiler: "6.2.0",
                sha256: "c26ebfd4e32c0ca1beabcc45729b62042da57ee76d7d043f63f2235da90dc491"
            )
        case (.android, .v6_3):
            return official(
                .android, release: "6.3.3",
                sha256: "d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5"
            )
        case (.android, .v6_4):
            return official(
                .android, release: "6.4.0",
                sha256: "21fb555122a3d801ad943d48df7ebffdd8824de61c25c180bb792d3edaee0b43"
            )
        case (.wasm, .v6_1):
            return NativeCrossSDK(
                image: "swift:6.1.3-jammy",
                sdkURL: "https://github.com/swiftwasm/swift/releases/download/swift-wasm-6.1-RELEASE/swift-wasm-6.1-RELEASE-wasm32-unknown-wasi.artifactbundle.zip",
                sdkSHA256: "7550b4c77a55f4b637c376f5d192f297fe185607003a6212ad608276928db992",
                sdkID: "6.1-RELEASE-wasm32-unknown-wasi",
                sdkSelector: "6.1-RELEASE-wasm32-unknown-wasi",
                ndk: nil
            )
        case (.wasm, .v6_2):
            return official(
                .wasm, release: "6.2.4",
                sha256: "32fdb8772d73bb174f77b5c59bc88a0d55003d75712832129394d3465158fb43"
            )
        case (.wasm, .v6_3):
            return official(
                .wasm, release: "6.3.3",
                sha256: "cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7"
            )
        case (.wasm, .v6_4):
            return official(
                .wasm, release: "6.4.0",
                sha256: "f07b7be3c586d92d7a07051fc6d303b87ebea67eadc40640ba59d5a8b79aa86d"
            )
        default:
            return nil
        }
    }

    /// The Android triple native cells build, matching SPI's
    /// `aarch64-unknown-linux-android28` where the bundle offers it.
    static let androidTriple = "aarch64-unknown-linux-android28"

    /// A swift.org SDK: `swift-<release>-RELEASE_<kind>.artifactbundle.tar.gz`.
    private static func official(_ platform: Platform, release: String, sha256: String) -> NativeCrossSDK {
        let kind = platform == .android ? "android" : "wasm"
        let id = "swift-\(release)-RELEASE_\(kind)"
        return NativeCrossSDK(
            image: "swift:\(release)-jammy",
            sdkURL: "https://download.swift.org/swift-\(release)-release/\(kind)-sdk/swift-\(release)-RELEASE/\(id).artifactbundle.tar.gz",
            sdkSHA256: sha256,
            sdkID: id,
            sdkSelector: platform == .android ? androidTriple : id,
            ndk: platform == .android ? .r27d : nil
        )
    }

    /// A finagolfin/swift-android-sdk bundle (release `tag`, e.g. `6.2`, built
    /// for compiler `compiler`, e.g. `6.2.0`). These target API 24, the lowest
    /// level they ship, so the triple is `…-android24`.
    private static func finagolfin(tag: String, compiler: String, sha256: String) -> NativeCrossSDK {
        let id = "swift-\(tag)-RELEASE-android-24-0.1"
        return NativeCrossSDK(
            image: "swift:\(compiler)-jammy",
            sdkURL: "https://github.com/finagolfin/swift-android-sdk/releases/download/\(tag)/\(id).artifactbundle.tar.gz",
            sdkSHA256: sha256,
            sdkID: id,
            sdkSelector: "aarch64-unknown-linux-android24",
            ndk: .r27d
        )
    }
}

/// An Android NDK release. Google only ships a Linux x86_64 NDK, but the
/// Android Swift SDKs only need its target sysroot and clang resource headers,
/// which are the same for every host, so the resolver extracts just those and
/// the x86_64 zip works on an arm64 host.
public struct AndroidNDK: Sendable, Equatable {
    public let url: String
    /// SHA-256 of the zip. Google publishes SHA-1 only; this was computed from
    /// a download whose SHA-1 matched Google's.
    public let sha256: String
    /// The zip's top-level directory.
    public let directory: String

    /// The NDK the swift.org Android SDK documents (27 is its minimum).
    public static let r27d = AndroidNDK(
        url: "https://dl.google.com/android/repository/android-ndk-r27d-linux.zip",
        sha256: "601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9",
        directory: "android-ndk-r27d"
    )
}
