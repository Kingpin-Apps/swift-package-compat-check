import Foundation
import Testing
import SwiftPackageCompatCheck

@Suite("CellState symbols")
struct CellStateSymbolTests {
    @Test("All five states have distinct symbols")
    func symbolsAreDistinct() {
        let symbols: [CellState] = [.pending, .running, .skipped, .pass, .fail]
        let strings = Set(symbols.map(\.symbol))
        #expect(strings.count == 5)
    }

    @Test(".running maps to a horizontal ellipsis (⋯)")
    func runningSymbol() {
        #expect(CellState.running.symbol == "⋯")
    }
}

@Suite("MatrixRenderer.renderLive")
struct MatrixRendererLiveTests {
    @Test("Live update stream completes cleanly when finished without emissions")
    func emptyStream() async {
        // Consumer should not hang or crash if the stream finishes immediately.
        let (stream, continuation) = AsyncStream<[BuildPair: CellState]>.makeStream()
        continuation.finish()

        await MatrixRenderer().renderLive(
            platforms: [.macosSPM],
            swiftVersions: [.v6_3],
            initialState: { _ in .pending },
            updates: stream
        )
    }

    @Test("Live update stream processes multiple emissions without throwing")
    func multipleEmissions() async {
        let (stream, continuation) = AsyncStream<[BuildPair: CellState]>.makeStream()
        let renderTask = Task {
            await MatrixRenderer().renderLive(
                platforms: [.macosSPM, .linux],
                swiftVersions: [.v6_3],
                initialState: { _ in .pending },
                updates: stream
            )
        }
        let pairA = BuildPair(platform: .macosSPM, swiftVersion: .v6_3)
        let pairB = BuildPair(platform: .linux, swiftVersion: .v6_3)
        continuation.yield([pairA: .running])
        continuation.yield([pairA: .pass, pairB: .running])
        continuation.yield([pairA: .pass, pairB: .fail])
        continuation.finish()
        await renderTask.value
    }
}
