import Foundation
import FreshetCore

/// A deterministic stand-in for libtorrent: fake torrents whose progress and speeds
/// change over time. Used for UI work (`Freshet --simulate`) and in tests.
public actor SimulatedEngine: EngineService {
    public nonisolated let events: AsyncStream<EngineEvent>
    private let continuation: AsyncStream<EngineEvent>.Continuation
    private let initialCount: Int
    private let tickInterval: TimeInterval
    private var random: SeededGenerator
    private var settings = EngineSettings()
    private var torrents: [TorrentID: SimTorrent] = [:]
    private var previews: [AddSource: TorrentPreview] = [:]
    private var task: Task<Void, Never>?
    private var nextQueuePosition = 0

    struct SimTorrent {
        var snapshot: TorrentSnapshot
        var files: [FileEntry]
        var trackers: [TrackerEntry]
        var baseRate: Int
        var activeTime: Double = 0
        var checkingTicks = 0
        var metadataTicks = 0
        var properties = TorrentProperties()
    }

    public init(seed: UInt64 = 42, count: Int = 24, tickInterval: TimeInterval = 0.5) {
        var captured: AsyncStream<EngineEvent>.Continuation?
        events = AsyncStream(bufferingPolicy: .bufferingNewest(10_000)) { captured = $0 }
        continuation = captured!
        initialCount = count
        self.tickInterval = tickInterval
        random = SeededGenerator(seed: seed)
    }

    // MARK: Lifecycle

    public func start() async throws {
        guard task == nil else { return }
        for index in 0..<initialCount {
            let torrent = makeTorrent(index: index)
            torrents[torrent.snapshot.id] = torrent
        }
        continuation.yield(.loaded(torrents.count))
        continuation.yield(.statuses(torrents.values.map(\.snapshot)))
        let nanoseconds = UInt64(max(0.01, tickInterval) * 1_000_000_000)
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard let self else { return }
                await self.tick()
            }
        }
    }

    public func shutdown() async {
        task?.cancel()
        task = nil
        continuation.finish()
    }

    public func apply(settings newSettings: EngineSettings) async {
        settings = newSettings
    }

    // MARK: Adding

    public func preview(_ source: AddSource) async throws -> TorrentPreview {
        if let cached = previews[source] { return cached }
        var name: String
        var isMagnet = false
        switch source {
        case .file(let url):
            name = url.deletingPathExtension().lastPathComponent
        case .data(_, let suggested):
            name = suggested.map { ($0 as NSString).deletingPathExtension } ?? "Downloaded torrent"
        case .magnet(let uri):
            isMagnet = true
            name = URLComponents(string: uri)?.queryItems?.first(where: { $0.name == "dn" })?.value ?? "Magnet link"
        }
        if name.isEmpty { name = "Untitled torrent" }
        let size: Int64 = isMagnet ? 0 : Int64(Int.random(in: 50_000_000...4_000_000_000, using: &random))
        let preview = TorrentPreview(name: name, infoHashV1: randomHash(), infoHashV2: "", totalSize: size,
                                     files: isMagnet ? [] : makeFiles(name: name, size: size, progress: 0),
                                     comment: "Simulated torrent", isPrivate: false, isMagnet: isMagnet)
        previews[source] = preview
        return preview
    }

    public func add(_ request: AddRequest) async throws -> AddResult {
        let preview = try await self.preview(request.source)
        let id = preview.torrentID
        if torrents[id] != nil { return .duplicate(id) }
        let size = preview.isMagnet ? Int64(1_500_000_000) : preview.totalSize
        var s = TorrentSnapshot(id: id)
        s.name = preview.name
        s.savePath = request.savePath
        s.hasMetadata = !preview.isMagnet
        s.totalWanted = size
        s.libtorrentState = preview.isMagnet ? TorrentSnapshot.stateDownloadingMetadata : TorrentSnapshot.stateDownloading
        s.isPaused = !request.start
        s.isAutoManaged = request.start
        s.addedDate = Date()
        s.queuePosition = nextQueue()
        s.currentTracker = "udp://tracker.example.org:6969/announce"
        var torrent = SimTorrent(snapshot: s, files: preview.isMagnet ? [] : preview.files,
                                 trackers: makeTrackers(seeds: 120, peers: 40),
                                 baseRate: Int.random(in: 300_000...3_000_000, using: &random))
        if preview.isMagnet { torrent.metadataTicks = 6 }
        if let priorities = request.filePriorities {
            for index in torrent.files.indices where torrent.files[index].index < priorities.count {
                torrent.files[index].priority = FilePriority(libtorrentValue: priorities[torrent.files[index].index])
            }
        }
        torrents[id] = torrent
        continuation.yield(.statuses([s]))
        return .added(id)
    }

    // MARK: Commands

    public func perform(_ action: TorrentAction, on ids: [TorrentID]) async {
        var changed: [TorrentID: TorrentSnapshot] = [:]
        for id in ids {
            guard var torrent = torrents[id] else { continue }
            switch action {
            case .start:
                torrent.snapshot.isPaused = false
                torrent.snapshot.isAutoManaged = true
                torrent.snapshot.errorMessage = nil
            case .pause:
                torrent.snapshot.isPaused = true
                torrent.snapshot.isAutoManaged = false
            case .forceStart:
                torrent.snapshot.isPaused = false
                torrent.snapshot.isAutoManaged = false
                torrent.snapshot.errorMessage = nil
            case .recheck:
                torrent.checkingTicks = 6
                torrent.snapshot.libtorrentState = TorrentSnapshot.stateCheckingFiles
            case .reannounce:
                continuation.yield(.log(LogEntry(torrentID: id, level: .info, message: "Announced to 2 trackers")))
            case .queueUp, .queueDown, .queueTop, .queueBottom:
                break
            }
            torrents[id] = torrent
            changed[id] = torrent.snapshot
        }
        switch action {
        case .queueUp, .queueDown, .queueTop, .queueBottom:
            for snapshot in moveInQueue(ids, action: action) { changed[snapshot.id] = snapshot }
        default:
            break
        }
        if !changed.isEmpty { continuation.yield(.statuses(Array(changed.values))) }
    }

    public func remove(_ ids: [TorrentID]) async {
        for id in ids where torrents.removeValue(forKey: id) != nil {
            continuation.yield(.removed(id))
        }
        let renumbered = renumberQueue()
        if !renumbered.isEmpty { continuation.yield(.statuses(renumbered)) }
    }

    public func setFilePriority(_ priority: FilePriority, files: [Int], in id: TorrentID) async {
        guard var torrent = torrents[id] else { return }
        let wanted = Set(files)
        for index in torrent.files.indices where wanted.contains(torrent.files[index].index) {
            torrent.files[index].priority = priority
        }
        torrents[id] = torrent
    }

    // MARK: Queries

    public func details(for id: TorrentID) async -> TorrentDetails? {
        guard let torrent = torrents[id] else { return nil }
        let s = torrent.snapshot
        let info = TorrentInfo(name: s.name, comment: "Simulated torrent", creator: "Freshet simulator",
                               infoHashV1: s.id, infoHashV2: "", totalSize: s.totalWanted,
                               creationDate: s.addedDate?.addingTimeInterval(-86_400), pieceLength: 4_194_304,
                               pieceCount: Int(max(1, s.totalWanted / 4_194_304)), fileCount: torrent.files.count,
                               isPrivate: false, hasMetadata: s.hasMetadata)
        let files = torrent.files.map { file -> FileEntry in
            var copy = file
            copy.downloaded = file.priority == .skip ? 0 : Int64(Double(file.size) * s.progress)
            return copy
        }
        return TorrentDetails(info: info, files: files, peers: makePeers(count: s.connectedPeers, seeds: s.connectedSeeds),
                              trackers: torrent.trackers)
    }

    public func magnetLink(for id: TorrentID) async -> String? {
        guard let torrent = torrents[id] else { return nil }
        let name = torrent.snapshot.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "magnet:?xt=urn:btih:\(id)&dn=\(name)"
    }

    // MARK: Simulation

    // MARK: Phase 2

    public func properties(for id: TorrentID) async -> TorrentProperties? { torrents[id]?.properties }

    public func setProperties(_ properties: TorrentProperties, for id: TorrentID) async {
        torrents[id]?.properties = properties
    }

    public func setTrackers(_ trackers: [TrackerEdit], for id: TorrentID) async {
        guard torrents[id] != nil else { return }
        torrents[id]?.trackers = trackers.map {
            TrackerEntry(url: $0.url, message: "", tier: $0.tier, status: .idle, seeds: -1, peers: -1, downloaded: -1, nextAnnounce: -1)
        }
    }

    public func addPeer(_ address: PeerAddress, to id: TorrentID) async -> Bool { torrents[id] != nil }

    public func clearPeers(of id: TorrentID) async {}

    public func moveStorage(of id: TorrentID, to path: String) async {
        guard torrents[id] != nil else { return }
        torrents[id]?.snapshot.savePath = path
        if let snapshot = torrents[id]?.snapshot { continuation.yield(.statuses([snapshot])) }
        continuation.yield(.moved(id, path: path, error: nil))
    }

    public func exportTorrent(_ id: TorrentID, to url: URL) async throws {
        throw EngineError.operationFailed("The simulator has no .torrent files to save.")
    }

    public func advancedSettings() async -> [AdvancedSetting] {
        [AdvancedSetting(name: "connections_limit", kind: .number, value: String(settings.maxConnections), defaultValue: "200"),
         AdvancedSetting(name: "enable_dht", kind: .toggle, value: settings.enableDHT ? "true" : "false", defaultValue: "true"),
         AdvancedSetting(name: "user_agent", kind: .text, value: "Freshet simulator", defaultValue: "libtorrent")]
            + settings.named.sorted { $0.key < $1.key }.map { AdvancedSetting(name: $0.key, kind: .text, value: $0.value, defaultValue: "") }
    }

    public func loadIPFilter(path: String?) async throws -> Int {
        guard let path else { return 0 }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw EngineError.operationFailed("Couldn't open the filter file.")
        }
        return text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") && $0.contains("-") }.count
    }

    private func tick() {
        var changed: [TorrentSnapshot] = []
        let downloading = torrents.values.filter { !$0.snapshot.isPaused && !$0.snapshot.isComplete && $0.snapshot.errorMessage == nil }.count
        let perTorrentCap = settings.downloadLimit > 0 ? max(1, settings.downloadLimit / max(1, downloading)) : Int.max
        for id in torrents.keys.sorted() {
            guard var torrent = torrents[id] else { continue }
            var s = torrent.snapshot
            let before = s
            if torrent.checkingTicks > 0 {
                torrent.checkingTicks -= 1
                if torrent.checkingTicks == 0 {
                    s.libtorrentState = s.totalWantedDone >= s.totalWanted ? TorrentSnapshot.stateSeeding : TorrentSnapshot.stateDownloading
                }
                s.downloadRate = 0
                s.uploadRate = 0
            } else if !s.isPaused && s.errorMessage == nil {
                let jitter = Double(Int.random(in: 55...145, using: &random)) / 100
                if torrent.metadataTicks > 0 {
                    torrent.metadataTicks -= 1
                    if torrent.metadataTicks == 0 {
                        s.hasMetadata = true
                        s.libtorrentState = TorrentSnapshot.stateDownloading
                        torrent.files = makeFiles(name: s.name, size: s.totalWanted, progress: 0)
                        continuation.yield(.metadataReceived(id))
                    }
                } else if !s.isComplete {
                    let rate = min(perTorrentCap, Int(Double(torrent.baseRate) * jitter))
                    let gained = Int64(Double(rate) * tickInterval)
                    s.downloadRate = rate
                    s.totalWantedDone = min(s.totalWanted, s.totalWantedDone + gained)
                    s.allTimeDownload += gained
                    s.connectedSeeds = Int.random(in: 1...30, using: &random)
                    s.connectedPeers = s.connectedSeeds + Int.random(in: 0...25, using: &random)
                    if s.totalWantedDone >= s.totalWanted {
                        s.isFinished = true
                        s.isSeeding = true
                        s.libtorrentState = TorrentSnapshot.stateSeeding
                        s.completedDate = Date()
                        s.downloadRate = 0
                        s.queuePosition = -1
                        continuation.yield(.finished(id))
                    }
                } else {
                    s.downloadRate = 0
                    s.connectedSeeds = 0
                    s.connectedPeers = Int.random(in: 0...12, using: &random)
                }
                let upload = s.connectedPeers > s.connectedSeeds ? Int(Double(torrent.baseRate / 6) * jitter) : 0
                s.uploadRate = settings.uploadLimit > 0 ? min(upload, settings.uploadLimit / 4) : upload
                s.allTimeUpload += Int64(Double(s.uploadRate) * tickInterval)
                torrent.activeTime += tickInterval
                s.activeSeconds = Int64(torrent.activeTime)
            } else {
                s.downloadRate = 0
                s.uploadRate = 0
                s.connectedSeeds = 0
                s.connectedPeers = 0
            }
            s.progress = s.totalWanted > 0 ? Double(s.totalWantedDone) / Double(s.totalWanted) : 0
            if s != before {
                torrent.snapshot = s
                changed.append(s)
            }
            torrents[id] = torrent
        }
        if !changed.isEmpty { continuation.yield(.statuses(changed)) }
        continuation.yield(.session(SessionSnapshot(dhtNodes: 280 + Int.random(in: 0...60, using: &random),
                                                    listenPort: settings.listenPort, isListening: true)))
    }

    private func nextQueue() -> Int {
        defer { nextQueuePosition += 1 }
        return nextQueuePosition
    }

    private func renumberQueue() -> [TorrentSnapshot] {
        let queued = torrents.values.map(\.snapshot).filter { $0.queuePosition >= 0 }.sorted { $0.queuePosition < $1.queuePosition }
        var changed: [TorrentSnapshot] = []
        for (position, snapshot) in queued.enumerated() where snapshot.queuePosition != position {
            torrents[snapshot.id]?.snapshot.queuePosition = position
            if let updated = torrents[snapshot.id]?.snapshot { changed.append(updated) }
        }
        nextQueuePosition = queued.count
        return changed
    }

    private func moveInQueue(_ ids: [TorrentID], action: TorrentAction) -> [TorrentSnapshot] {
        var order = torrents.values.map(\.snapshot).filter { $0.queuePosition >= 0 }
            .sorted { $0.queuePosition < $1.queuePosition }.map(\.id)
        let moving = Set(ids)
        switch action {
        case .queueTop:
            order = order.filter { moving.contains($0) } + order.filter { !moving.contains($0) }
        case .queueBottom:
            order = order.filter { !moving.contains($0) } + order.filter { moving.contains($0) }
        case .queueUp:
            for index in order.indices where index > 0 && moving.contains(order[index]) && !moving.contains(order[index - 1]) {
                order.swapAt(index, index - 1)
            }
        case .queueDown:
            for index in order.indices.reversed() where index < order.count - 1 && moving.contains(order[index]) && !moving.contains(order[index + 1]) {
                order.swapAt(index, index + 1)
            }
        default:
            break
        }
        var changed: [TorrentSnapshot] = []
        for (position, id) in order.enumerated() where torrents[id]?.snapshot.queuePosition != position {
            torrents[id]?.snapshot.queuePosition = position
            if let updated = torrents[id]?.snapshot { changed.append(updated) }
        }
        return changed
    }

    private func randomHash() -> String {
        var text = ""
        for _ in 0..<20 { text += String(format: "%02x", UInt8.random(in: 0...255, using: &random)) }
        return text
    }

    private static let catalog: [(String, Int64)] = [
        ("ubuntu-26.04-desktop-arm64.iso", 6_200_000_000),
        ("debian-13.2.0-arm64-netinst.iso", 720_000_000),
        ("Sintel (2010) Blender Open Movie 1080p", 1_300_000_000),
        ("Big Buck Bunny 60fps 4K", 7_800_000_000),
        ("Tears of Steel (2012) 4K", 6_700_000_000),
        ("Cosmos Laundromat", 2_100_000_000),
        ("archlinux-2026.10.01-x86_64.iso", 1_400_000_000),
        ("Fedora-Workstation-Live-44-aarch64.iso", 2_600_000_000),
        ("Prelinger Archives - Duck and Cover (1951)", 450_000_000),
        ("LibriVox - Pride and Prejudice", 610_000_000),
        ("enwiki-20261001-pages-articles.xml.bz2", 24_000_000_000),
        ("planet-261001.osm.pbf", 82_000_000_000),
        ("NASA Apollo 11 Mission Audio", 3_300_000_000),
        ("Project Gutenberg Top 100 EPUB", 95_000_000),
        ("FreeBSD-15.0-RELEASE-arm64-aarch64-dvd1.iso", 4_100_000_000),
        ("linuxmint-23-cinnamon-64bit.iso", 2_900_000_000),
        ("Spring (Blender Open Movie) 4K", 3_900_000_000),
        ("Agent 327 - Operation Barbershop", 1_100_000_000),
        ("Charge (Blender Studio) 4K", 5_200_000_000),
        ("Internet Archive - Grateful Dead 1977-05-08", 1_700_000_000),
        ("Godot_v4.6-stable_macos.universal.zip", 160_000_000),
        ("Blender-5.0-macos-arm64.dmg", 380_000_000),
        ("kali-linux-2026.3-installer-arm64.iso", 4_300_000_000),
        ("openSUSE-Tumbleweed-DVD-aarch64-Current.iso", 4_600_000_000),
    ]

    private func makeTorrent(index: Int) -> SimTorrent {
        let entry = Self.catalog[index % Self.catalog.count]
        var s = TorrentSnapshot(id: randomHash())
        s.name = entry.0
        s.savePath = NSString(string: "~/Downloads").expandingTildeInPath
        s.hasMetadata = true
        s.totalWanted = entry.1
        s.currentTracker = "udp://tracker.example.org:6969/announce"
        s.addedDate = Date().addingTimeInterval(-Double(Int.random(in: 3_600...2_000_000, using: &random)))
        s.swarmSeeds = Int.random(in: 0...900, using: &random)
        s.swarmPeers = Int.random(in: 0...400, using: &random)
        s.availability = Double(Int.random(in: 50...4_000, using: &random)) / 100
        let partial = Int64(Double(entry.1) * Double(Int.random(in: 1...85, using: &random)) / 100)
        switch index % 8 {
        case 0, 1, 2:
            s.libtorrentState = TorrentSnapshot.stateDownloading
            s.totalWantedDone = partial
            s.queuePosition = nextQueue()
        case 3, 4:
            s.libtorrentState = TorrentSnapshot.stateSeeding
            s.isSeeding = true
            s.isFinished = true
            s.totalWantedDone = entry.1
            s.completedDate = s.addedDate?.addingTimeInterval(1_800)
        case 5:
            s.libtorrentState = TorrentSnapshot.stateDownloading
            s.isPaused = true
            s.isAutoManaged = false
            s.totalWantedDone = partial
            s.queuePosition = nextQueue()
        case 6:
            s.libtorrentState = TorrentSnapshot.stateDownloading
            s.isPaused = true
            s.isAutoManaged = true
            s.totalWantedDone = partial
            s.queuePosition = nextQueue()
        default:
            s.libtorrentState = TorrentSnapshot.stateSeeding
            s.isSeeding = true
            s.isFinished = true
            s.isPaused = true
            s.isAutoManaged = false
            s.totalWantedDone = entry.1
            s.completedDate = s.addedDate?.addingTimeInterval(7_200)
        }
        if index == 9 {
            s.errorMessage = "No such file or directory (/Volumes/External/Linux)"
            s.isPaused = true
            s.isAutoManaged = false
        }
        s.progress = entry.1 > 0 ? Double(s.totalWantedDone) / Double(entry.1) : 0
        s.allTimeDownload = s.totalWantedDone
        s.allTimeUpload = Int64(Double(s.allTimeDownload) * Double(Int.random(in: 0...300, using: &random)) / 100)
        return SimTorrent(snapshot: s, files: makeFiles(name: entry.0, size: entry.1, progress: s.progress),
                          trackers: makeTrackers(seeds: s.swarmSeeds, peers: s.swarmPeers),
                          baseRate: Int.random(in: 80_000...4_000_000, using: &random))
    }

    private func makeFiles(name: String, size: Int64, progress: Double) -> [FileEntry] {
        let singleFileExtensions = ["iso", "zip", "dmg", "bz2", "pbf"]
        if singleFileExtensions.contains((name as NSString).pathExtension.lowercased()) {
            return [FileEntry(index: 0, path: name, size: size, downloaded: Int64(Double(size) * progress), priority: .normal)]
        }
        let main = Int64(Double(size) * 0.96)
        let rest = size - main
        let parts: [(String, Int64)] = [
            ("\(name)/\(name).mkv", main),
            ("\(name)/Subtitles/English.srt", rest / 4),
            ("\(name)/Subtitles/Spanish.srt", rest / 4),
            ("\(name)/poster.jpg", rest / 4),
            ("\(name)/README.txt", rest - 3 * (rest / 4)),
        ]
        return parts.enumerated().map { index, part in
            FileEntry(index: index, path: part.0, size: part.1, downloaded: Int64(Double(part.1) * progress), priority: .normal)
        }
    }

    private func makeTrackers(seeds: Int, peers: Int) -> [TrackerEntry] {
        [
            TrackerEntry(url: "udp://tracker.example.org:6969/announce", message: "", tier: 0, status: .working,
                         seeds: seeds, peers: peers, downloaded: Int.random(in: 100...90_000, using: &random),
                         nextAnnounce: Int.random(in: 60...1_800, using: &random)),
            TrackerEntry(url: "https://tracker.example.net/announce", message: "Connection timed out", tier: 1,
                         status: .error, seeds: -1, peers: -1, downloaded: -1, nextAnnounce: 900),
        ]
    }

    private func makePeers(count: Int, seeds: Int) -> [PeerEntry] {
        let clients = ["qBittorrent 5.1.2", "Transmission 4.1.0", "Deluge 2.2.0", "libtorrent 2.0.11", "BiglyBT 4.0.0.0", "rTorrent 0.15.0"]
        let flagSets = ["D U E P", "D E X", "U H", "D U P X", "d u", "D I E"]
        var peers: [PeerEntry] = []
        for index in 0..<min(count, 60) {
            let isSeed = index < seeds
            peers.append(PeerEntry(ip: "203.0.113.\(10 + index)", port: 6_881 + index * 7, client: clients[index % clients.count],
                                   flags: flagSets[index % flagSets.count].replacingOccurrences(of: " ", with: ""),
                                   progress: isSeed ? 1 : Double(Int.random(in: 0...99, using: &random)) / 100,
                                   downloadRate: Int.random(in: 0...400_000, using: &random),
                                   uploadRate: Int.random(in: 0...80_000, using: &random),
                                   totalDownload: Int64(Int.random(in: 0...900_000_000, using: &random)),
                                   totalUpload: Int64(Int.random(in: 0...200_000_000, using: &random)), isSeed: isSeed))
        }
        return peers
    }
}

/// xorshift64: small, fast and reproducible for a given seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
