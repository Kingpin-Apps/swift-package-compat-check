import Foundation
import Noora

public enum CellState: Sendable, Equatable {
    case pending
    case running
    case skipped
    case pass
    case fail

    /// 10-frame braille spinner — same set Noora's own `Spinner` uses, so the
    /// matrix's running cells feel consistent with the rest of the Noora UI.
    public static let runningFrames: [String] = [
        "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
    ]

    public var symbol: String { symbol(frame: 0) }

    /// Per-frame symbol. `.running` rotates through `runningFrames`; everything
    /// else ignores the frame parameter.
    public func symbol(frame: Int) -> String {
        switch self {
        case .pending: return "?"
        case .running:
            let i = ((frame % Self.runningFrames.count) + Self.runningFrames.count) % Self.runningFrames.count
            return Self.runningFrames[i]
        case .skipped: return "—"
        case .pass: return "✓"
        case .fail: return "✗"
        }
    }
}

public struct MatrixRenderer {
    private let noora: Noora

    public init(noora: Noora = Noora()) {
        self.noora = noora
    }

    public func render(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        state: (BuildPair) -> CellState
    ) {
        let (headers, rows) = Self.headersAndRows(
            platforms: platforms,
            swiftVersions: swiftVersions,
            frame: 0,
            state: state
        )
        noora.table(headers: headers, rows: rows, renderer: Renderer())
    }

    /// Live updating render: paints the initial state once, then re-renders the
    /// table in place each time `updates` emits a fresh snapshot AND on every
    /// `animationInterval` tick (which advances the spinner frame for any cells
    /// in `.running` state). The matrix stays anchored at its first-drawn
    /// position via ANSI cursor-up + erase-line codes, so consecutive renders
    /// feel like an animation.
    ///
    /// Important: while this is in flight nothing else can write to stdout —
    /// Noora's `Renderer` is stateful (tracks `lastRenderedContent` to know how
    /// many lines to erase), and any interleaved `print` would desynchronise it.
    public func renderLive<Updates: AsyncSequence & Sendable>(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        initialState: @escaping @Sendable (BuildPair) -> CellState,
        updates: Updates,
        animationInterval: Duration = .milliseconds(100)
    ) async where Updates.Element == [BuildPair: CellState], Updates.Failure == Never {
        let (headers, initialRows) = Self.headersAndRows(
            platforms: platforms,
            swiftVersions: swiftVersions,
            frame: 0,
            state: initialState
        )
        let renderer = Renderer()

        // Two producer tasks feed a single (snapshot, frame) stream. The
        // consumer (noora.table) runs in renderLive's own context outside
        // the TaskGroup — we can't put noora into the addTask closures
        // because Noora isn't Sendable and TableData isn't either.
        let (pairsStream, continuation) = AsyncStream<MatrixFrame>.makeStream()
        let state = LiveTableState(platforms: platforms, swiftVersions: swiftVersions)
        for pair in state.allPairs { await state.setCell(pair, to: initialState(pair)) }

        let producers = Task { [continuation] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await snapshot in updates {
                        await state.setSnapshot(snapshot)
                        let frame = await state.frame
                        continuation.yield(.init(snapshot: await state.snapshot, frame: frame))
                    }
                    continuation.finish()
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: animationInterval)
                        if Task.isCancelled { break }
                        await state.advanceFrame()
                        guard await state.hasRunningCell() else { continue }
                        let snap = await state.snapshot
                        let frame = await state.frame
                        continuation.yield(.init(snapshot: snap, frame: frame))
                    }
                }
                _ = await group.next()
                group.cancelAll()
            }
        }

        let tableUpdates = pairsStream.map { mf in
            Self.makeTableData(
                headers: headers,
                platforms: platforms,
                swiftVersions: swiftVersions,
                frame: mf.frame,
                snapshot: mf.snapshot,
                initialState: initialState
            )
        }
        await noora.table(
            headers: headers,
            rows: initialRows,
            updates: tableUpdates,
            renderer: renderer
        )
        _ = await producers.value
    }

    private static func makeTableData(
        headers: [String],
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        frame: Int,
        snapshot: [BuildPair: CellState],
        initialState: (BuildPair) -> CellState
    ) -> TableData {
        let columns = headers.map { TableColumn(title: $0) }
        let rows = platforms.map { platform -> [String] in
            var row = [platform.rawValue]
            for sv in swiftVersions {
                let pair = BuildPair(platform: platform, swiftVersion: sv)
                let cell = snapshot[pair] ?? initialState(pair)
                row.append(cell.symbol(frame: frame))
            }
            return row
        }
        let tableRows: [TableRow] = rows.map { row in
            row.map { TerminalText(stringLiteral: $0) }
        }
        return TableData(columns: columns, rows: tableRows)
    }

    private static func headersAndRows(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        frame: Int,
        state: (BuildPair) -> CellState
    ) -> (headers: [String], rows: [[String]]) {
        let headers = ["Platform"] + swiftVersions.map { "Swift \($0.rawValue)" }
        let rows = platforms.map { platform -> [String] in
            var row = [platform.rawValue]
            for sv in swiftVersions {
                let s = state(BuildPair(platform: platform, swiftVersion: sv))
                row.append(s.symbol(frame: frame))
            }
            return row
        }
        return (headers, rows)
    }
}

/// Sendable payload moved across `renderLive`'s producer / consumer boundary.
/// Tuples of Sendable types are Sendable; this struct is just for naming.
private struct MatrixFrame: Sendable {
    let snapshot: [BuildPair: CellState]
    let frame: Int
}

/// Actor-backed shared state for `renderLive`'s two producer tasks.
/// One holds the current snapshot of cell states; the other advances the spinner
/// frame counter on a timer. The Noora consumer reads both per emission.
actor LiveTableState {
    private(set) var snapshot: [BuildPair: CellState] = [:]
    private(set) var frame: Int = 0
    let allPairs: [BuildPair]

    init(platforms: [Platform], swiftVersions: [SwiftVersion]) {
        self.allPairs = swiftVersions.flatMap { sv in
            platforms.map { BuildPair(platform: $0, swiftVersion: sv) }
        }
    }

    func setSnapshot(_ new: [BuildPair: CellState]) { snapshot = new }
    func setCell(_ pair: BuildPair, to state: CellState) { snapshot[pair] = state }
    func advanceFrame() { frame &+= 1 }
    func hasRunningCell() -> Bool { snapshot.values.contains { $0 == .running } }
}
