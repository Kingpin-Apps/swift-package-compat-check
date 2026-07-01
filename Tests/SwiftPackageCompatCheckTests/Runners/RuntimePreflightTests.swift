import ArgumentParser
import Command
import Foundation
import Path
import Testing
@testable import SwiftPackageCompatCheck

/// Runner that classifies each command by its argv prefix into one of the three
/// probe outcomes — success (stream finishes clean), non-zero exit (finishes
/// with `.terminated`), or missing binary (finishes with `.executableNotFound`).
/// Lets the resolver be exercised without a real docker/container daemon.
final class ProbeStubRunner: CommandRunning, @unchecked Sendable {
    enum Outcome {
        case running
        case notRunning
        case notInstalled
    }

    /// Keyed by binary name (argv[0]): "docker" / "container".
    var outcomes: [String: Outcome] = [:]
    private(set) var calls: [[String]] = []

    func run(
        arguments: [String],
        environment: [String: String],
        workingDirectory: Path.AbsolutePath?
    ) -> AsyncThrowingStream<CommandEvent, any Error> {
        calls.append(arguments)
        let binary = arguments.first ?? ""
        let outcome = outcomes[binary] ?? .notInstalled
        return AsyncThrowingStream { continuation in
            switch outcome {
            case .running:
                continuation.finish()
            case .notRunning:
                continuation.finish(
                    throwing: CommandError.terminated(1, stderr: "daemon down", command: arguments)
                )
            case .notInstalled:
                continuation.finish(throwing: CommandError.executableNotFound(binary))
            }
        }
    }
}

@Suite("ContainerRuntime.availability")
struct ContainerRuntimeAvailabilityTests {
    @Test("exit-0 probe maps to .running")
    func running() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .running]
        #expect(await ContainerRuntime.docker.availability(runner: stub) == .running)
        // Uses `docker info` as the liveness probe.
        #expect(stub.calls[0] == ["docker", "info"])
    }

    @Test("non-zero exit maps to .installedNotRunning")
    func notRunning() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .notRunning]
        #expect(await ContainerRuntime.docker.availability(runner: stub) == .installedNotRunning)
    }

    @Test("executable-not-found maps to .notInstalled")
    func notInstalled() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .notInstalled]
        #expect(await ContainerRuntime.container.availability(runner: stub) == .notInstalled)
        // container's liveness probe is `container system status`.
        #expect(stub.calls[0] == ["container", "system", "status"])
    }

    @Test("podman probes via `podman info`, like docker")
    func podmanProbeUsesInfo() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["podman": .running]
        #expect(await ContainerRuntime.podman.availability(runner: stub) == .running)
        #expect(stub.calls[0] == ["podman", "info"])
    }

    @Test("podman down maps to .installedNotRunning")
    func podmanNotRunning() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["podman": .notRunning]
        #expect(await ContainerRuntime.podman.availability(runner: stub) == .installedNotRunning)
    }
}

@Suite("RunCommand.resolveContainerRuntime — preflight + auto-selection")
struct ResolveContainerRuntimeTests {
    // MARK: - Auto-detection (no flag, no config)

    @Test("auto prefers container when both runtimes are running")
    func autoPrefersContainer() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .running, "container": .running]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: nil, config: nil, runner: stub
        )
        #expect(runtime == .container)
    }

    @Test("auto falls back to docker when only docker is running")
    func autoFallsBackToDocker() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .running, "container": .notInstalled]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: nil, config: nil, runner: stub
        )
        #expect(runtime == .docker)
    }

    @Test("auto falls back to podman when only podman is running (last in chain)")
    func autoFallsBackToPodman() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .notInstalled, "docker": .notRunning, "podman": .running]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: nil, config: nil, runner: stub
        )
        #expect(runtime == .podman)
    }

    @Test("auto prefers docker over podman when both are running")
    func autoPrefersDockerOverPodman() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .notInstalled, "docker": .running, "podman": .running]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: nil, config: nil, runner: stub
        )
        #expect(runtime == .docker)
    }

    @Test("auto errors when no runtime is running")
    func autoErrorsWhenNoneRunning() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .notRunning, "container": .notInstalled, "podman": .notRunning]
        await #expect(throws: ValidationError.self) {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: nil, config: nil, runner: stub
            )
        }
    }

    // MARK: - Explicit runtime preflight

    @Test("explicit running runtime is honoured")
    func explicitRunning() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .running]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: "container", config: nil, runner: stub
        )
        #expect(runtime == .container)
    }

    @Test("explicit runtime that is installed-but-down throws an actionable error")
    func explicitNotRunning() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .notRunning]
        await #expect {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: "container", config: nil, runner: stub
            )
        } throws: { error in
            guard let validation = error as? ValidationError else { return false }
            let message = "\(validation)"
            // Distinct "installed but not running" message with a start hint.
            return message.contains("isn't running")
                && message.contains("container system start")
        }
    }

    @Test("explicit runtime that isn't installed throws a distinct not-found error")
    func explicitNotInstalled() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["container": .notInstalled]
        await #expect {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: "container", config: nil, runner: stub
            )
        } throws: { error in
            guard let validation = error as? ValidationError else { return false }
            return "\(validation)".contains("isn't installed")
        }
    }

    @Test("explicit podman that is down throws with `podman machine start` guidance")
    func explicitPodmanNotRunning() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["podman": .notRunning]
        await #expect {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: "podman", config: nil, runner: stub
            )
        } throws: { error in
            guard let validation = error as? ValidationError else { return false }
            let message = "\(validation)"
            return message.contains("isn't running")
                && message.contains("podman machine start")
        }
    }

    @Test("explicit running podman is honoured")
    func explicitPodmanRunning() async throws {
        let stub = ProbeStubRunner()
        stub.outcomes = ["podman": .running]
        let runtime = try await RunCommand.resolveContainerRuntime(
            cli: "podman", config: nil, runner: stub
        )
        #expect(runtime == .podman)
    }

    @Test("config-supplied runtime is preflighted like an explicit flag")
    func configRuntimePreflighted() async {
        let stub = ProbeStubRunner()
        stub.outcomes = ["docker": .notRunning]
        await #expect(throws: ValidationError.self) {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: nil, config: .docker, runner: stub
            )
        }
    }

    // MARK: - Regression guards

    @Test("unknown --container-runtime string still throws before any probe")
    func unknownFlagThrows() async {
        let stub = ProbeStubRunner()
        await #expect(throws: ValidationError.self) {
            _ = try await RunCommand.resolveContainerRuntime(
                cli: "nerdctl", config: nil, runner: stub
            )
        }
        // Rejected on parse — no daemon probe attempted.
        #expect(stub.calls.isEmpty)
    }

    @Test("isAutoSelectingRuntime is true only when neither CLI nor config specifies a runtime")
    func autoSelectionDetection() {
        #expect(RunCommand.isAutoSelectingRuntime(cli: nil, config: nil))
        #expect(RunCommand.isAutoSelectingRuntime(cli: "", config: nil))
        #expect(!RunCommand.isAutoSelectingRuntime(cli: "docker", config: nil))
        #expect(!RunCommand.isAutoSelectingRuntime(cli: nil, config: .container))
    }
}

@Suite("RunCommand.dryRunRuntimeLine — header without probing")
struct DryRunRuntimeLineTests {
    @Test("explicit flag shows the exact runtime, no auto note")
    func explicitFlag() throws {
        #expect(try RunCommand.dryRunRuntimeLine(cli: "container", config: nil) == "container")
    }

    @Test("config runtime shows the exact runtime when no flag is given")
    func configRuntime() throws {
        #expect(try RunCommand.dryRunRuntimeLine(cli: nil, config: .docker) == "docker")
    }

    @Test("auto shows the selection rule rather than a concrete runtime")
    func auto() throws {
        let line = try RunCommand.dryRunRuntimeLine(cli: nil, config: nil)
        #expect(line.contains("auto"))
        #expect(line.contains("apple/container"))
        #expect(line.contains("docker"))
    }

    @Test("unknown flag string is rejected even in dry-run")
    func unknownFlag() {
        #expect(throws: ValidationError.self) {
            _ = try RunCommand.dryRunRuntimeLine(cli: "nerdctl", config: nil)
        }
    }

    @Test("explicit podman shows the exact runtime")
    func explicitPodman() throws {
        #expect(try RunCommand.dryRunRuntimeLine(cli: "podman", config: nil) == "podman")
    }

    @Test("auto rule names podman as the last-in-chain fallback")
    func autoMentionsPodman() throws {
        #expect(try RunCommand.dryRunRuntimeLine(cli: nil, config: nil).contains("podman"))
    }
}
