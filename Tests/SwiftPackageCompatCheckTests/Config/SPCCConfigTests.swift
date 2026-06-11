import Configuration
import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("SPCCConfig.load resolution")
struct SPCCConfigResolutionTests {
    @Test("Returns nil when neither --config nor $SPCC_CONFIG is set")
    func returnsNilWhenAbsent() async throws {
        let config = try await SPCCConfig.load(explicitPath: nil, env: [:])
        #expect(config == nil)
    }

    @Test("Returns nil when $SPCC_CONFIG is empty string")
    func emptyEnvVarIgnored() async throws {
        let config = try await SPCCConfig.load(explicitPath: nil, env: ["SPCC_CONFIG": ""])
        #expect(config == nil)
    }

    @Test("Loads from explicit path when --config is set")
    func loadsFromExplicitPath() async throws {
        let url = try writeTOML("""
            scheme = "MyLib"
            swift_versions = ["6.2", "6.3"]
            """)
        let config = try await SPCCConfig.load(explicitPath: url.path)
        #expect(config?.scheme == "MyLib")
        #expect(config?.swiftVersions == [.v6_2, .v6_3])
    }

    @Test("Explicit --config path wins over $SPCC_CONFIG env var")
    func explicitWinsOverEnv() async throws {
        let envFile = try writeTOML("scheme = \"FromEnv\"")
        let explicitFile = try writeTOML("scheme = \"FromExplicit\"")
        let config = try await SPCCConfig.load(
            explicitPath: explicitFile.path,
            env: ["SPCC_CONFIG": envFile.path]
        )
        #expect(config?.scheme == "FromExplicit")
    }

    @Test("Throws fileNotFound when the explicit path doesn't exist")
    func throwsWhenMissing() async throws {
        do {
            _ = try await SPCCConfig.load(explicitPath: "/nonexistent/spcc.toml")
            Issue.record("expected fileNotFound to throw")
        } catch SPCCConfigError.fileNotFound {
            // expected
        }
    }

    private func writeTOML(_ contents: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-config-\(UUID().uuidString).toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@Suite("SPCCConfig field parsing")
struct SPCCConfigFieldTests {
    @Test("Decodes scalar fields from TOML")
    func scalars() async throws {
        let url = try Self.writeTOML("""
            scheme = "MyLib"
            max_parallel = 4
            timeout = 600
            pull_always = true
            test = true
            no_live = false
            verbose = true
            """)
        let config = try await SPCCConfig.load(from: url)
        #expect(config.scheme == "MyLib")
        #expect(config.maxParallel == 4)
        #expect(config.timeoutSeconds == 600)
        #expect(config.pullAlways == true)
        #expect(config.test == true)
        #expect(config.noLive == false)
        #expect(config.verbose == true)
    }

    @Test("Decodes swift_versions and platforms arrays")
    func arrays() async throws {
        let url = try Self.writeTOML("""
            swift_versions = ["6.2", "6.3"]
            platforms = ["ios", "macos-spm", "linux"]
            """)
        let config = try await SPCCConfig.load(from: url)
        #expect(config.swiftVersions == [.v6_2, .v6_3])
        #expect(config.platforms == [.ios, .macosSPM, .linux])
    }

    @Test("Decodes per-Swift-version override tables (xcode, toolchain, linux_image, etc.)")
    func perVersionTables() async throws {
        let url = try Self.writeTOML("""
            [xcode]
            "6.2" = "/Applications/Xcode-26.3.app"
            "6.3" = "/Applications/Xcode-26.4.app"

            [toolchain]
            "6.2" = "swift-6.2-RELEASE"

            [linux_image]
            "6.3" = "registry.example/swift:6.3-jammy"

            [wasm_sdk_url]
            "6.3" = "https://internal.example/sdk.zip"
            """)
        let config = try await SPCCConfig.load(from: url)
        #expect(config.xcode[.v6_2] == "/Applications/Xcode-26.3.app")
        #expect(config.xcode[.v6_3] == "/Applications/Xcode-26.4.app")
        #expect(config.toolchain[.v6_2] == "swift-6.2-RELEASE")
        #expect(config.linuxImage[.v6_3] == "registry.example/swift:6.3-jammy")
        #expect(config.wasmSDKURL[.v6_3] == "https://internal.example/sdk.zip")
        #expect(config.xcode[.v6_0] == nil)
    }

    @Test("Missing fields stay nil/empty")
    func missingFieldsStayDefault() async throws {
        let url = try Self.writeTOML("scheme = \"OnlyScheme\"")
        let config = try await SPCCConfig.load(from: url)
        #expect(config.scheme == "OnlyScheme")
        #expect(config.swiftVersions == nil)
        #expect(config.platforms == nil)
        #expect(config.maxParallel == nil)
        #expect(config.pullAlways == nil)
        #expect(config.xcode.isEmpty)
        #expect(config.toolchain.isEmpty)
        #expect(config.containerRuntime == nil)
    }

    @Test("Decodes container_runtime as the typed ContainerRuntime enum")
    func containerRuntimeKey() async throws {
        let docker = try await SPCCConfig.load(
            from: Self.writeTOML(#"container_runtime = "docker""#)
        )
        #expect(docker.containerRuntime == .docker)
        let container = try await SPCCConfig.load(
            from: Self.writeTOML(#"container_runtime = "container""#)
        )
        #expect(container.containerRuntime == .container)
        // Unknown values silently become nil (CLI is the validation seam).
        let bogus = try await SPCCConfig.load(
            from: Self.writeTOML(#"container_runtime = "podman""#)
        )
        #expect(bogus.containerRuntime == nil)
    }

    @Test("Decodes test_no_parallel boolean")
    func testNoParallelKey() async throws {
        let on = try await SPCCConfig.load(from: Self.writeTOML("test_no_parallel = true"))
        #expect(on.testNoParallel == true)
        let absent = try await SPCCConfig.load(from: Self.writeTOML("scheme = \"X\""))
        #expect(absent.testNoParallel == nil)
    }

    @Test("Decodes install_host and install_container string arrays")
    func installLists() async throws {
        let url = try Self.writeTOML("""
            install_host = ["gnupg", "libsodium"]
            install_container = ["libgcrypt20-dev", "jq"]
            """)
        let config = try await SPCCConfig.load(from: url)
        #expect(config.installHost == ["gnupg", "libsodium"])
        #expect(config.installContainer == ["libgcrypt20-dev", "jq"])
    }

    @Test("Missing install lists stay nil")
    func installListsAbsent() async throws {
        let config = try await SPCCConfig.load(from: Self.writeTOML("scheme = \"X\""))
        #expect(config.installHost == nil)
        #expect(config.installContainer == nil)
    }

    static func writeTOML(_ contents: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spcc-config-\(UUID().uuidString).toml")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
