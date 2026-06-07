import Command
import Foundation

/// Deduplicates `container image pull` calls across concurrent cells. Without
/// this, every cell that targets the same builder image races to pull on cold
/// caches; on warm caches the docker path no-ops anyway via inline `--pull=`.
///
/// Behaviour by runtime:
///
/// - **docker**: `ensurePulled` is a no-op. Docker honours `--pull=missing` /
///   `--pull=always` inline on `run`, so explicit pulls would be wasted work.
/// - **container** (`policy = .missing`): first cell to request an image awaits
///   a one-shot `container image pull`; concurrent cells await the same
///   task; subsequent cells (after success) no-op. Failures clear the cache
///   so a later attempt can retry.
/// - **container** (`policy = .always`): every request pulls, but concurrent
///   requests for the same image still serialise on one in-flight task to
///   prevent stampede.
public actor ImagePullCoordinator {
    private let runtime: ContainerRuntime
    private let runner: any CommandRunning
    private var inflight: [String: Task<Void, Error>] = [:]
    private var pulled: Set<String> = []

    public init(
        runtime: ContainerRuntime,
        runner: any CommandRunning = CommandRunner()
    ) {
        self.runtime = runtime
        self.runner = runner
    }

    /// Ensure `image` is available locally according to `policy`. Throws if
    /// the underlying pull command fails. Multiple concurrent calls for the
    /// same image share a single pull task.
    public func ensurePulled(image: String, policy: PullPolicy) async throws {
        guard let argv = runtime.pullArgv(image: image) else { return }

        let cacheKey = image
        if policy == .missing, pulled.contains(cacheKey) {
            return
        }

        if let existing = inflight[cacheKey] {
            try await existing.value
            return
        }

        let task = Task {
            try await dispatch(arguments: argv)
        }
        inflight[cacheKey] = task

        do {
            try await task.value
            inflight.removeValue(forKey: cacheKey)
            pulled.insert(cacheKey)
        } catch {
            inflight.removeValue(forKey: cacheKey)
            throw error
        }
    }

    private func dispatch(arguments: [String]) async throws {
        for try await _ in runner.run(arguments: arguments) {
            // Drain — pull progress goes to stdout/stderr, we just need exit
            // status. A non-zero exit causes the stream to throw.
        }
    }
}
