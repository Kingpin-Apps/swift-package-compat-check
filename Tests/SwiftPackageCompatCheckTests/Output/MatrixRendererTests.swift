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

    @Test(".running rotates through 10 braille frames (Noora's spinner set)")
    func runningSymbolRotates() {
        let frame0 = CellState.running.symbol(frame: 0)
        let frame1 = CellState.running.symbol(frame: 1)
        let frame9 = CellState.running.symbol(frame: 9)
        let frame10 = CellState.running.symbol(frame: 10)  // wraps to frame 0
        let frameNeg = CellState.running.symbol(frame: -1) // wraps cleanly too
        #expect(frame0 == "⠋")
        #expect(frame1 == "⠙")
        #expect(frame9 == "⠏")
        #expect(frame10 == frame0)
        #expect(frameNeg == "⠏")
        #expect(CellState.runningFrames.count == 10)
    }

    @Test("Non-running states ignore the frame parameter")
    func nonRunningStatesStable() {
        #expect(CellState.pending.symbol(frame: 5) == "?")
        #expect(CellState.skipped.symbol(frame: 5) == "—")
        #expect(CellState.pass.symbol(frame: 5) == "✓")
        #expect(CellState.fail.symbol(frame: 5) == "✗")
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
