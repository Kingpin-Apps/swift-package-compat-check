import Testing
@testable import SwiftPackageCompatCheck

@Suite("Shell completion")
struct CompletionsTests {
    let platforms = ["ios", "linux", "macos-spm", "macos-xcodebuild"]

    @Test("completes the first item")
    func firstItem() {
        #expect(commaSeparatedCompletions(prefix: "", values: platforms) == platforms)
        #expect(commaSeparatedCompletions(prefix: "mac", values: platforms)
                == ["macos-spm", "macos-xcodebuild"])
    }

    @Test("keeps what was typed and completes the last item")
    func laterItem() {
        #expect(commaSeparatedCompletions(prefix: "ios,mac", values: platforms)
                == ["ios,macos-spm", "ios,macos-xcodebuild"])
    }

    @Test("skips values already in the list")
    func skipsChosen() {
        #expect(commaSeparatedCompletions(prefix: "ios,linux,", values: platforms)
                == ["ios,linux,macos-spm", "ios,linux,macos-xcodebuild"])
    }
}
