import ArgumentParser

extension CompletionKind {
    /// Completes the last item of a comma-separated list such as `-p ios,mac`,
    /// keeping what was already typed and skipping values already in the list.
    static func commaSeparated(_ values: [String]) -> CompletionKind {
        .custom { _, _, prefix in commaSeparatedCompletions(prefix: prefix, values: values) }
    }
}

/// `ios,mac` with `[ios, macos-spm, macos-xcodebuild]` → `ios,macos-spm`,
/// `ios,macos-xcodebuild`.
func commaSeparatedCompletions(prefix: String, values: [String]) -> [String] {
    let typed = prefix.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    let current = typed.last ?? ""
    let done = Set(typed.dropLast())
    let head = typed.dropLast().map { $0 + "," }.joined()
    return values
        .filter { $0.hasPrefix(current) && !done.contains($0) }
        .map { head + $0 }
}
