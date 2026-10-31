import Foundation
import Testing
@testable import FreshetCore

struct QueryTests {
    func make(_ id: String, name: String, progress: Double = 0.4, state: Int = TorrentSnapshot.stateDownloading,
              paused: Bool = false, autoManaged: Bool = true, down: Int = 0, up: Int = 0) -> TorrentSnapshot {
        var t = TorrentSnapshot(id: id)
        t.name = name
        t.progress = progress
        t.libtorrentState = state
        t.isPaused = paused
        t.isAutoManaged = autoManaged
        t.downloadRate = down
        t.uploadRate = up
        if progress >= 1 {
            t.isFinished = true
            t.isSeeding = state == TorrentSnapshot.stateSeeding
        }
        return t
    }

    @Test func sidebarFilters() {
        let downloading = make("a", name: "Alpha", down: 1_000)
        let seeding = make("b", name: "Beta", progress: 1, state: TorrentSnapshot.stateSeeding, up: 500)
        let stopped = make("c", name: "Gamma", progress: 1, state: TorrentSnapshot.stateSeeding, paused: true, autoManaged: false)
        #expect(SidebarFilter.downloading.matches(downloading, label: nil))
        #expect(!SidebarFilter.downloading.matches(seeding, label: nil))
        #expect(SidebarFilter.seeding.matches(seeding, label: nil))
        #expect(!SidebarFilter.seeding.matches(stopped, label: nil))
        #expect(SidebarFilter.completed.matches(stopped, label: nil))
        #expect(SidebarFilter.active.matches(downloading, label: nil))
        #expect(SidebarFilter.inactive.matches(stopped, label: nil))
        #expect(SidebarFilter.label("Linux").matches(seeding, label: "Linux"))
        #expect(SidebarFilter.noLabel.matches(seeding, label: nil))
        #expect(!SidebarFilter.noLabel.matches(seeding, label: "Linux"))
    }

    @Test func statusNames() {
        #expect(make("a", name: "A", paused: true, autoManaged: true).activity == .queued)
        #expect(make("a", name: "A", paused: true, autoManaged: false).statusText == "Paused")
        #expect(make("a", name: "A", progress: 1, state: TorrentSnapshot.stateSeeding, paused: true, autoManaged: false).statusText == "Finished")
        #expect(make("a", name: "A", state: TorrentSnapshot.stateDownloadingMetadata).activity == .downloadingMetadata)
        var broken = make("a", name: "A")
        broken.errorMessage = "disk full"
        #expect(broken.statusText == "Error: disk full")
    }

    @Test func sortingAndSearch() {
        let list = [make("1", name: "ubuntu", down: 10), make("2", name: "Debian", down: 300), make("3", name: "arch", down: 200)]
        let byName = TorrentQuery.visible(list, filter: .all, search: "", labels: [:], sort: TorrentSortKey(field: .name, ascending: true))
        #expect(byName.map(\.name) == ["arch", "Debian", "ubuntu"])
        let bySpeed = TorrentQuery.visible(list, filter: .all, search: "", labels: [:], sort: TorrentSortKey(field: .downSpeed, ascending: false))
        #expect(bySpeed.map(\.id) == ["2", "3", "1"])
        let searched = TorrentQuery.visible(list, filter: .all, search: "DEB", labels: [:], sort: TorrentSortKey(field: .name, ascending: true))
        #expect(searched.map(\.id) == ["2"])
    }

    @Test func queueOrderPutsUnqueuedLast() {
        var first = make("1", name: "one")
        first.queuePosition = 1
        var second = make("2", name: "two")
        second.queuePosition = 0
        let seed = make("3", name: "seed", progress: 1, state: TorrentSnapshot.stateSeeding)
        let ordered = TorrentQuery.visible([first, seed, second], filter: .all, search: "", labels: [:],
                                           sort: TorrentSortKey(field: .queue, ascending: true))
        #expect(ordered.map(\.id) == ["2", "1", "3"])
    }

    @Test func labelBook() {
        var book = LabelBook()
        book.assign("Linux", to: ["1", "2"])
        book.assign("Movies", to: ["3"])
        book.assign(nil, to: ["2"])
        #expect(book.names == ["Linux", "Movies"])
        #expect(book.count(of: "Linux") == 1)
        book.removeLabel("Movies")
        #expect(book.assignments["3"] == nil)
        #expect(book.names == ["Linux"])
    }

    @Test func speedHistoryIsBounded() {
        var history = SpeedHistory(capacity: 3)
        for second in 0..<5 {
            history.append(SpeedSample(date: Date(timeIntervalSince1970: Double(second)), download: second, upload: 0))
        }
        #expect(history.samples.map(\.download) == [2, 3, 4])
    }
}
