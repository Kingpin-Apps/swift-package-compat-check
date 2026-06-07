import Foundation
import Noora

public enum CellState: Sendable, Equatable {
    case pending
    case skipped
    case pass
    case fail

    public var symbol: String {
        switch self {
        case .pending: "?"
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
        let headers = ["Platform"] + swiftVersions.map { "Swift \($0.rawValue)" }
        let rows = platforms.map { platform -> [String] in
            var row = [platform.rawValue]
            for sv in swiftVersions {
                let pair = BuildPair(platform: platform, swiftVersion: sv)
                row.append(state(pair).symbol)
            }
            return row
        }
        noora.table(headers: headers, rows: rows, renderer: Renderer())
    }
}
