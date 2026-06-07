import Foundation
import Noora

public enum CellState: Sendable, Equatable {
    case pending
    case running
    case skipped
    case pass
    case fail

    public var symbol: String {
        switch self {
        case .pending: "?"
        case .running: "⋯"
        case .skipped: "—"
        case .pass: "✓"
        case .fail: "✗"
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
            state: state
        )
        noora.table(headers: headers, rows: rows, renderer: Renderer())
    }

    /// Live updating render: paints the initial state once, then re-renders the
    /// table in place each time `updates` emits a fresh snapshot. The matrix
    /// stays anchored at its first-drawn position via ANSI cursor-up + erase-line
    /// codes, so consecutive renders feel like an animation.
    ///
    /// Important: while this is in flight nothing else can write to stdout —
    /// Noora's `Renderer` is stateful (tracks `lastRenderedContent` to know how
    /// many lines to erase), and any interleaved `print` would desynchronise it.
    public func renderLive<Updates: AsyncSequence & Sendable>(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        initialState: @escaping @Sendable (BuildPair) -> CellState,
        updates: Updates
    ) async where Updates.Element == [BuildPair: CellState], Updates.Failure == Never {
        let (headers, initialRows) = Self.headersAndRows(
            platforms: platforms,
            swiftVersions: swiftVersions,
            state: initialState
        )
        let columns = headers.map { TableColumn(title: $0) }
        let renderer = Renderer()

        let tableUpdates = updates.map { snapshot -> TableData in
            let (_, stringRows) = Self.headersAndRows(
                platforms: platforms,
                swiftVersions: swiftVersions
            ) { pair in
                snapshot[pair] ?? initialState(pair)
            }
            let tableRows: [TableRow] = stringRows.map { row in
                row.map { TerminalText(stringLiteral: $0) }
            }
            return TableData(columns: columns, rows: tableRows)
        }

        await noora.table(
            headers: headers,
            rows: initialRows,
            updates: tableUpdates,
            renderer: renderer
        )
    }

    private static func headersAndRows(
        platforms: [Platform],
        swiftVersions: [SwiftVersion],
        state: (BuildPair) -> CellState
    ) -> (headers: [String], rows: [[String]]) {
        let headers = ["Platform"] + swiftVersions.map { "Swift \($0.rawValue)" }
        let rows = platforms.map { platform -> [String] in
            var row = [platform.rawValue]
            for sv in swiftVersions {
                row.append(state(BuildPair(platform: platform, swiftVersion: sv)).symbol)
            }
            return row
        }
        return (headers, rows)
    }
}
