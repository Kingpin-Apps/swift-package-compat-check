import Command
import Foundation
import Testing
@testable import SwiftPackageCompatCheck

@Suite("HostInstaller")
struct HostInstallerTests {
    @Test("Empty package list is a no-op success and launches nothing")
    func emptyNoOp() async {
        let recorder = RecordingCommandRunner()
        let ok = await HostInstaller(commandRunner: recorder).brewInstall([], quiet: true)
        #expect(ok)
        #expect(recorder.calls.isEmpty)
    }

    @Test("Dispatches `brew install <packages>`")
    func dispatchesBrew() async {
        let recorder = RecordingCommandRunner()
        let ok = await HostInstaller(commandRunner: recorder)
            .brewInstall(["gnupg", "libsodium"], quiet: true)
        #expect(ok)
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0].arguments == ["brew", "install", "gnupg", "libsodium"])
    }

    @Test("A brew failure is reported as false rather than thrown")
    func failureIsNonFatal() async {
        let recorder = RecordingCommandRunner()
        recorder.failOnNext = CommandError.terminated(1, stderr: "boom", command: ["brew"])
        let ok = await HostInstaller(commandRunner: recorder)
            .brewInstall(["nonexistent-pkg"], quiet: true)
        #expect(!ok)
    }
}
