import Foundation
import Testing
import FreshetCore
@testable import FreshetSim

struct SimulatedEngineTests {
    @Test func reportsTorrentsAndAppliesActions() async throws {
        let engine = SimulatedEngine(seed: 7, count: 5, tickInterval: 0.02)
        try await engine.start()
        var iterator = engine.events.makeAsyncIterator()
        var seen: [TorrentID: TorrentSnapshot] = [:]
        while seen.count < 5, let event = await iterator.next() {
            if case .statuses(let list) = event { for s in list { seen[s.id] = s } }
        }
        #expect(seen.count == 5)

        let id = seen.keys.sorted()[0]
        await engine.perform(.pause, on: [id])
        var paused = false
        for _ in 0..<200 {
            guard let event = await iterator.next() else { break }
            if case .statuses(let list) = event, let s = list.first(where: { $0.id == id }), s.isStopped {
                paused = true
                break
            }
        }
        #expect(paused)
        await engine.shutdown()
    }

    @Test func addsAMagnetAndRejectsDuplicates() async throws {
        let engine = SimulatedEngine(seed: 3, count: 0, tickInterval: 0.02)
        try await engine.start()
        let magnet = AddSource.magnet("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test")
        let preview = try await engine.preview(magnet)
        #expect(preview.name == "Test")
        #expect(preview.isMagnet)
        let first = try await engine.add(AddRequest(source: magnet, savePath: "/tmp"))
        let second = try await engine.add(AddRequest(source: magnet, savePath: "/tmp"))
        #expect(first == .added(preview.torrentID))
        #expect(second == .duplicate(preview.torrentID))
        await engine.shutdown()
    }
}
