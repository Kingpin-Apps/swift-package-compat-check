import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

/// Streams that finish after a short delay so concurrent callers observably
/// queue on the same in-flight task. Records every argv it was handed.
final class DelayedPullRunner: CommandRunning, @unchecked Sendable {
    private(set) var calls: [[String]] = []
    private let delayNs: UInt64
    var failOnNext: Error?

    init(delayMs: UInt64 = 100) {
        self.delayNs = delayMs * 1_000_000
    }

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        calls.append(arguments)
        let failure = failOnNext
        failOnNext = nil
        let delay = delayNs
        return AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(nanoseconds: delay)
                if let failure {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

struct PullFailure: Error, Equatable {}

@Suite("ImagePullCoordinator")
struct ImagePullCoordinatorTests {
    @Test("docker runtime: ensurePulled is a no-op")
    func dockerNoOp() async throws {
        let runner = DelayedPullRunner(delayMs: 1)
        let coord = ImagePullCoordinator(runtime: .docker, runner: runner)
        try await coord.ensurePulled(image: "img", policy: .missing)
        try await coord.ensurePulled(image: "img", policy: .always)
        #expect(runner.calls.isEmpty)
    }

    @Test("container runtime: missing policy pulls once, then caches")
    func containerMissingCaches() async throws {
        let runner = DelayedPullRunner(delayMs: 1)
        let coord = ImagePullCoordinator(runtime: .container, runner: runner)

        try await coord.ensurePulled(image: "img", policy: .missing)
        try await coord.ensurePulled(image: "img", policy: .missing)
        try await coord.ensurePulled(image: "img", policy: .missing)

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0] == [
            "container", "image", "pull",
            "--platform", "linux/amd64",
            "img",
        ])
    }

    @Test("container runtime: concurrent calls for the same image dedup on the in-flight task")
    func containerConcurrentDedup() async throws {
        let runner = DelayedPullRunner(delayMs: 100)
        let coord = ImagePullCoordinator(runtime: .container, runner: runner)

        async let a: Void = coord.ensurePulled(image: "img", policy: .missing)
        async let b: Void = coord.ensurePulled(image: "img", policy: .missing)
        async let c: Void = coord.ensurePulled(image: "img", policy: .missing)
        _ = try await (a, b, c)

        #expect(runner.calls.count == 1)
    }

    @Test("container runtime: distinct images each get their own pull")
    func containerDistinctImagesPullSeparately() async throws {
        let runner = DelayedPullRunner(delayMs: 1)
        let coord = ImagePullCoordinator(runtime: .container, runner: runner)

        try await coord.ensurePulled(image: "img-a", policy: .missing)
        try await coord.ensurePulled(image: "img-b", policy: .missing)

        #expect(runner.calls.count == 2)
        #expect(runner.calls[0].last == "img-a")
        #expect(runner.calls[1].last == "img-b")
    }

    @Test("container runtime: failed pull clears the in-flight slot so retry can fire")
    func containerFailedPullRetriable() async throws {
        let runner = DelayedPullRunner(delayMs: 1)
        runner.failOnNext = PullFailure()
        let coord = ImagePullCoordinator(runtime: .container, runner: runner)

        await #expect(throws: (any Error).self) {
            try await coord.ensurePulled(image: "img", policy: .missing)
        }
        // Retry must now actually dispatch — the failure should NOT have
        // populated `pulled` and the inflight slot should be empty.
        try await coord.ensurePulled(image: "img", policy: .missing)
        #expect(runner.calls.count == 2)
    }

    @Test("container runtime: always policy pulls every time but still dedups concurrent callers")
    func containerAlwaysSerialises() async throws {
        let runner = DelayedPullRunner(delayMs: 100)
        let coord = ImagePullCoordinator(runtime: .container, runner: runner)

        async let a: Void = coord.ensurePulled(image: "img", policy: .always)
        async let b: Void = coord.ensurePulled(image: "img", policy: .always)
        _ = try await (a, b)
        #expect(runner.calls.count == 1)  // dedup'd via inflight

        try await coord.ensurePulled(image: "img", policy: .always)
        #expect(runner.calls.count == 2)  // no cache: subsequent call re-pulls
    }
}
