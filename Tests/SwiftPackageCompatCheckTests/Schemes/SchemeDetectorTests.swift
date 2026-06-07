import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("SchemeDetector")
struct SchemeDetectorTests {
    @Test("Detects HelloWorld as the scheme in the bundled fixture")
    func helloWorldFixture() async throws {
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "HelloWorld", withExtension: nil, subdirectory: "Fixtures"),
            "HelloWorld fixture must be bundled via resources: [.copy(\"Fixtures\")]"
        )
        let scheme = try await SchemeDetector().detectScheme(packagePath: fixtureURL.path)
        #expect(scheme == "HelloWorld")
    }

    @Test("pickScheme skips system C targets even when they alphabetize first")
    func skipsSystemTargets() throws {
        // Mirrors the swift-nacl layout: a Clibsodium system target alongside the real
        // SwiftNaCl library. The C target alphabetizes first; we must pick the Swift one.
        let manifest = PackageManifest(
            name: "swift-nacl",
            products: [
                .init(name: "Clibsodium", type: .library, targets: ["Clibsodium"]),
                .init(name: "SwiftNaCl", type: .library, targets: ["SwiftNaCl"]),
            ],
            targets: [
                .init(name: "Clibsodium", type: .system),
                .init(name: "SwiftNaCl", type: .regular),
            ]
        )
        #expect(try SchemeDetector.pickScheme(from: manifest) == "SwiftNaCl")
    }

    @Test("pickScheme throws when no library is backed by a regular target")
    func noLibraryProduct() {
        let manifest = PackageManifest(
            name: "Empty",
            products: [],
            targets: []
        )
        #expect(throws: SchemeDetectionError.self) {
            try SchemeDetector.pickScheme(from: manifest)
        }
    }
}
