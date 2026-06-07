import Command
import CryptoKit
import Foundation

/// Pull policy for builder images. Docker honours these inline via `--pull=`;
/// apple/container has no `--pull` on `run` and the `ImagePullCoordinator`
/// drives an explicit pre-step in its place.
public enum PullPolicy: String, Sendable, CaseIterable, Codable {
    case missing
    case always
}

/// Host-side container runtime that backs Linux / Android / Wasm cells.
///
/// `docker` is the historical default and stays byte-identical to pre-runtime
/// spcc behaviour. `container` (apple/container, Virtualization.framework-backed)
/// drops the qemu translation layer in favour of Rosetta and removes the
/// Docker Desktop daemon footprint, at the cost of a slightly thinner CLI.
///
/// All runtime-specific variance lives as extension methods here so the
/// argv builders, runners, and cleanup ops stay runtime-agnostic.
public enum ContainerRuntime: String, Sendable, CaseIterable, Codable {
    case docker
    case container

    /// The CLI binary invoked on the host. Both runtimes expose a single
    /// top-level executable.
    public var binary: String { rawValue }
}

public extension ContainerRuntime {
    /// Leading argv slice for the per-cell `run` invocation. Stops before the
    /// `-v <pkg>:/host -w /host` middle that every cell shares, so the
    /// `LinuxArgvBuilders` / `CrossSDKArgvBuilders` can append their constants
    /// unchanged.
    ///
    /// Docker carries `--pull=<policy>` inline; container 0.12 has no
    /// `run --pull` so `ImagePullCoordinator` runs `container image pull`
    /// as a pre-step (see `pullArgv(image:)`).
    ///
    /// Docker discovers containers to kill via `--label`; container has no
    /// `list --filter label=`, so the launcher sets `--name <sanitised>`
    /// for direct kill-by-name.
    ///
    /// `useRosetta` is only meaningful on container; docker emulates amd64
    /// via its own qemu path regardless.
    func runArgvHead(
        cellLabel: String,
        pullPolicy: PullPolicy,
        useRosetta: Bool = false
    ) -> [String] {
        switch self {
        case .docker:
            return [
                binary, "run",
                "--pull=\(pullPolicy.rawValue)",
                "--rm",
                "--platform", "linux/amd64",
            ]
        case .container:
            var head: [String] = [
                binary, "run",
                "--rm",
                "--platform", "linux/amd64",
                "--name", Self.sanitiseCellName(cellLabel),
            ]
            if useRosetta {
                head.append("--rosetta")
            }
            return head
        }
    }

    /// `<binary> image pull --platform linux/amd64 <image>` for runtimes that
    /// need an explicit pre-run pull step. Returns `nil` for docker, which
    /// handles pulling inline via `--pull=` on `run`.
    func pullArgv(image: String) -> [String]? {
        switch self {
        case .docker: return nil
        case .container:
            return [binary, "image", "pull", "--platform", "linux/amd64", image]
        }
    }

    /// Argv to remove a single named volume.
    func removeVolumeArgv(name: String) -> [String] {
        switch self {
        case .docker: return [binary, "volume", "rm", name]
        case .container: return [binary, "volume", "delete", name]
        }
    }

    /// Argv to remove a single image by reference.
    func removeImageArgv(reference: String) -> [String] {
        switch self {
        case .docker: return [binary, "rmi", reference]
        case .container: return [binary, "image", "delete", reference]
        }
    }

    /// Argv to list volumes whose name starts with `prefix`. Docker filters
    /// server-side via `--filter name=`; container has no filter so it emits
    /// JSON and `parseVolumeList(_:prefix:)` filters client-side.
    func listVolumesArgv(prefix: String) -> [String] {
        switch self {
        case .docker:
            return [
                binary, "volume", "ls",
                "--filter", "name=\(prefix)",
                "--format", "{{.Name}}",
            ]
        case .container:
            return [binary, "volume", "list", "--format", "json"]
        }
    }

    /// Parse the volume-list stdout into bare volume names. Docker stdout is
    /// already filtered server-side (one name per line); container JSON is
    /// filtered here.
    func parseVolumeList(_ stdout: String, prefix: String) -> [String] {
        switch self {
        case .docker:
            return stdout
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
                .filter { $0.hasPrefix(prefix) }
        case .container:
            guard let data = stdout.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data)
                    as? [[String: Any]]
            else { return [] }
            return entries.compactMap { entry in
                guard let name = entry["name"] as? String,
                      name.hasPrefix(prefix) else { return nil }
                return name
            }
        }
    }

    /// Argv to list images. Docker takes the repository positionally; container
    /// emits JSON and `parseImageList(_:repository:)` filters client-side.
    func listImagesArgv(repository: String) -> [String] {
        switch self {
        case .docker:
            return [
                binary, "images", repository,
                "--format", "{{.Repository}}:{{.Tag}}|{{.Size}}",
            ]
        case .container:
            return [binary, "image", "list", "--format", "json"]
        }
    }

    /// Parse image-list stdout into `(reference, size)` pairs filtered to
    /// the SPI repository. Docker emits the `repo:tag|size` shape we asked
    /// for; container emits JSON with byte-counted sizes — formatted to a
    /// docker-style suffix string so the cleanup commands' output matches
    /// regardless of runtime.
    func parseImageList(
        _ stdout: String, repository: String
    ) -> [(reference: String, size: String)] {
        switch self {
        case .docker:
            return stdout
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    let parts = line.split(separator: "|", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (reference: String(parts[0]), size: String(parts[1]))
                }
        case .container:
            guard let data = stdout.data(using: .utf8),
                  let entries = try? JSONSerialization.jsonObject(with: data)
                    as? [[String: Any]]
            else { return [] }
            return entries.compactMap { entry in
                guard let reference = entry["reference"] as? String,
                      reference.hasPrefix(repository) else { return nil }
                return (reference: reference, size: Self.containerImageSize(entry))
            }
        }
    }

    private static func containerImageSize(_ entry: [String: Any]) -> String {
        if let bytes = entry["size"] as? Int {
            return formatBytes(bytes)
        }
        if let bytesStr = entry["size"] as? String, let bytes = Int(bytesStr) {
            return formatBytes(bytes)
        }
        return "?"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let units: [(threshold: Double, suffix: String)] = [
            (1024 * 1024 * 1024, "GB"),
            (1024 * 1024, "MB"),
            (1024, "KB"),
        ]
        let d = Double(bytes)
        for (t, s) in units where d >= t {
            return String(format: "%.1f%@", d / t, s)
        }
        return "\(bytes)B"
    }
}

public extension ContainerRuntime {
    /// Convert a cell label (e.g. `20260607T152300-linux-6.3`) into a valid
    /// container name. Container names must match `[a-zA-Z0-9][a-zA-Z0-9_.-]*`
    /// and are capped at 255 chars. Existing spcc labels already comply; this
    /// is defence-in-depth against future label-shape changes.
    static func sanitiseCellName(_ label: String) -> String {
        let allowed = Set(
            "abcdefghijklmnopqrstuvwxyz" +
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ" +
            "0123456789_.-"
        )
        let replaced = String(label.map { allowed.contains($0) ? $0 : "-" })
        var collapsed = replaced
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        // Trim leading/trailing dashes so the name starts on an alnum.
        collapsed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let prefix = "spcc-cell-"
        let maxBody = 240 - prefix.count
        if collapsed.count > maxBody {
            let hash = SHA256.hash(data: Data(label.utf8))
            let hex = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8)
            let head = String(collapsed.prefix(maxBody - 9))
            return prefix + head + "-" + hex
        }
        return prefix + collapsed
    }
}

public extension ContainerRuntime {
    /// Timeout-kill closure to hand to `LogStreamer.run(..., onTimeout:)`. Both
    /// runtimes spawn a fresh `CommandRunner` internally — argv assertions
    /// happen against the pure helpers above (`runArgvHead`, `pullArgv`,
    /// `removeVolumeArgv`, …) rather than this closure.
    ///
    /// Docker: `docker ps --filter label=spcc-cell=<label> -q` → `docker kill`
    /// per discovered id. Container: single `container kill <sanitised-name>`
    /// because the launcher set `--name` deterministically at start.
    var killClosure: @Sendable (String) async -> Void {
        switch self {
        case .docker:
            return Self.dockerKillByLabel
        case .container:
            return Self.containerKillByName
        }
    }

    @Sendable
    private static func dockerKillByLabel(_ label: String) async {
        let runner = CommandRunner()
        let ids = await Self.captureLines(
            runner: runner,
            arguments: [
                "docker", "ps",
                "--filter", "label=spcc-cell=\(label)",
                "-q",
            ]
        )
        for id in ids {
            _ = await Self.captureLines(
                runner: runner, arguments: ["docker", "kill", id]
            )
        }
    }

    @Sendable
    private static func containerKillByName(_ label: String) async {
        let runner = CommandRunner()
        let name = sanitiseCellName(label)
        _ = await Self.captureLines(
            runner: runner, arguments: ["container", "kill", name]
        )
    }

    private static func captureLines(
        runner: any CommandRunning, arguments: [String]
    ) async -> [String] {
        var stdout = Data()
        do {
            for try await event in runner.run(arguments: arguments) {
                if case .standardOutput(let bytes) = event {
                    stdout.append(contentsOf: bytes)
                }
            }
        } catch { return [] }
        return String(data: stdout, encoding: .utf8)?
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init) ?? []
    }
}
