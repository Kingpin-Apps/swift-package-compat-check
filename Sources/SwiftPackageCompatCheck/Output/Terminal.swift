import Darwin

/// Whether stdout is connected to a terminal (TTY). False when piped to a file,
/// captured by `$()`, or running in a CI environment that detaches stdout.
public func isStdoutTTY() -> Bool {
    isatty(fileno(stdout)) != 0
}
