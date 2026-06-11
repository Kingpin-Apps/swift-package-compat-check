import Foundation

/// Builds the apt-get preamble that installs extra system packages inside a
/// Linux / Android / Wasm builder container before the `swift build`/`swift test`
/// body runs. Used by `LinuxArgvBuilders` and `CrossSDKArgvBuilders` so a package
/// whose tests shell out to a binary (e.g. swift-gnupg needing `gpg`) or whose
/// C target needs `-dev` headers can pull them in.
///
/// Containers are `--rm` and freshly created per cell, so the install is
/// ephemeral — nothing leaks onto the host or persists between runs. The SPI
/// builder images run as root, so `apt-get` needs no `sudo`.
///
/// Package names are validated by the CLI parser before they reach here (ASCII
/// letters/digits and `. _ + -`, never leading `-`), which is why it's safe to
/// splice them straight into the `bash -c` body.
public enum ContainerInstall {
    /// A self-contained bash block that installs `packages` via apt, or the empty
    /// string when there's nothing to install. The block sets its own
    /// `set -euo pipefail` so a failed install aborts the cell before the build
    /// body runs, and ends with a trailing newline so it can be prepended
    /// directly to an existing script body.
    public static func aptPreamble(packages: [String]) -> String {
        guard !packages.isEmpty else { return "" }
        let joined = packages.joined(separator: " ")
        let lines = [
            "set -euo pipefail",
            "echo \"spcc: installing apt packages: \(joined)\"",
            "export DEBIAN_FRONTEND=noninteractive",
            "apt-get update -qq",
            "apt-get install -y --no-install-recommends \(joined)",
            "",
        ]
        return lines.joined(separator: "\n")
    }
}
