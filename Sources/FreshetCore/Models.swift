import Foundation

public typealias TorrentID = String

/// What a torrent is doing right now, as shown in the Status column.
public enum TorrentActivity: String, Sendable, CaseIterable {
    case checking
    case downloadingMetadata
    case downloading
    case finished
    case seeding
    case queued
    case queuedSeed
    case paused
    case error
}

/// One torrent's state as reported by the engine. Value type, safe to pass between actors.
public struct TorrentSnapshot: Identifiable, Hashable, Sendable {
    public static let stateCheckingFiles = 1
    public static let stateDownloadingMetadata = 2
    public static let stateDownloading = 3
    public static let stateFinished = 4
    public static let stateSeeding = 5
    public static let stateCheckingResume = 7

    public let id: TorrentID
    public var name: String = ""
    public var savePath: String = ""
    public var currentTracker: String = ""
    public var errorMessage: String? = nil
    public var libtorrentState: Int = 0
    public var isPaused = false
    public var isAutoManaged = true
    public var hasMetadata = false
    public var isSeeding = false
    public var isFinished = false
    public var hasIncoming = false
    public var isMovingStorage = false
    public var progress: Double = 0
    public var totalWanted: Int64 = 0
    public var totalWantedDone: Int64 = 0
    public var allTimeDownload: Int64 = 0
    public var allTimeUpload: Int64 = 0
    public var downloadRate: Int = 0
    public var uploadRate: Int = 0
    /// Connected seeds.
    public var connectedSeeds: Int = 0
    /// All connected peers, seeds included.
    public var connectedPeers: Int = 0
    /// Seeds in the whole swarm according to trackers, -1 when unknown.
    public var swarmSeeds: Int = -1
    /// Downloaders in the whole swarm according to trackers, -1 when unknown.
    public var swarmPeers: Int = -1
    public var availability: Double = -1
    public var queuePosition: Int = -1
    public var addedDate: Date? = nil
    public var completedDate: Date? = nil
    public var activeSeconds: Int64 = 0
    public var seedingSeconds: Int64 = 0
    public var piecesHave: Int = 0

    public init(id: TorrentID) {
        self.id = id
    }
}

extension TorrentSnapshot {
    public var activity: TorrentActivity {
        if errorMessage != nil { return .error }
        if libtorrentState == Self.stateCheckingFiles || libtorrentState == Self.stateCheckingResume { return .checking }
        if isPaused {
            if isAutoManaged { return isComplete ? .queuedSeed : .queued }
            return .paused
        }
        switch libtorrentState {
        case Self.stateDownloadingMetadata: return .downloadingMetadata
        case Self.stateFinished: return .finished
        case Self.stateSeeding: return .seeding
        default: return .downloading
        }
    }

    /// Everything wanted is on disk (fully seeding, or finished with some files skipped).
    public var isComplete: Bool { isFinished || isSeeding }
    /// Stopped by the user, as opposed to queued by the automatic queue.
    public var isStopped: Bool { isPaused && !isAutoManaged }
    public var remaining: Int64 { max(0, totalWanted - totalWantedDone) }
    public var isActive: Bool { downloadRate > 0 || uploadRate > 0 }
    public var connectedLeechers: Int { max(0, connectedPeers - connectedSeeds) }

    public var ratio: Double {
        if allTimeDownload > 0 { return Double(allTimeUpload) / Double(allTimeDownload) }
        return allTimeUpload > 0 ? .infinity : 0
    }

    /// Seconds left at the current speed, or nil when there is no estimate.
    public var eta: TimeInterval? {
        guard !isComplete, downloadRate > 0, remaining > 0 else { return nil }
        return Double(remaining) / Double(downloadRate)
    }

    public var displayName: String { name.isEmpty ? id : name }

    public var statusText: String {
        switch activity {
        case .checking: return String(format: "Checking %.1f %%", progress * 100)
        case .downloadingMetadata: return "Downloading metadata"
        case .downloading: return "Downloading"
        case .finished: return "Finished"
        case .seeding: return "Seeding"
        case .queued: return "Queued"
        case .queuedSeed: return "Queued Seed"
        case .paused: return isComplete ? "Finished" : "Paused"
        case .error: return "Error: \(errorMessage ?? "")"
        }
    }
}

public enum FilePriority: Int, Sendable, CaseIterable, Comparable {
    case skip = 0
    case low = 1
    case normal = 4
    case high = 7

    public init(libtorrentValue: Int) {
        switch libtorrentValue {
        case ...0: self = .skip
        case 1...3: self = .low
        case 4...5: self = .normal
        default: self = .high
        }
    }

    public var title: String {
        switch self {
        case .skip: return "Don't Download"
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }

    public static func < (lhs: FilePriority, rhs: FilePriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var index: Int
    public var path: String
    public var size: Int64
    public var downloaded: Int64
    public var priority: FilePriority

    public init(index: Int, path: String, size: Int64, downloaded: Int64, priority: FilePriority) {
        self.index = index
        self.path = path
        self.size = size
        self.downloaded = downloaded
        self.priority = priority
    }

    public var id: Int { index }
    public var progress: Double { size > 0 ? min(1, Double(downloaded) / Double(size)) : 1 }
    public var name: String { (path as NSString).lastPathComponent }
    public var priorityRank: Int { priority.rawValue }
}

public struct PeerEntry: Identifiable, Hashable, Sendable {
    public var ip: String
    public var port: Int
    public var client: String
    public var flags: String
    public var progress: Double
    public var downloadRate: Int
    public var uploadRate: Int
    public var totalDownload: Int64
    public var totalUpload: Int64
    public var isSeed: Bool

    public init(ip: String, port: Int, client: String, flags: String, progress: Double, downloadRate: Int,
                uploadRate: Int, totalDownload: Int64, totalUpload: Int64, isSeed: Bool) {
        self.ip = ip
        self.port = port
        self.client = client
        self.flags = flags
        self.progress = progress
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.totalDownload = totalDownload
        self.totalUpload = totalUpload
        self.isSeed = isSeed
    }

    public var id: String { "\(ip):\(port)" }
    public var address: String { ip.contains(":") ? "[\(ip)]:\(port)" : "\(ip):\(port)" }
}

public enum TrackerStatus: Int, Sendable {
    case idle = 0
    case working = 1
    case updating = 2
    case error = 3

    public var title: String {
        switch self {
        case .idle: return "Not contacted yet"
        case .working: return "Working"
        case .updating: return "Updating…"
        case .error: return "Error"
        }
    }
}

public struct TrackerEntry: Identifiable, Hashable, Sendable {
    public var url: String
    public var message: String
    public var tier: Int
    public var status: TrackerStatus
    public var seeds: Int
    public var peers: Int
    public var downloaded: Int
    /// Seconds until the next announce, -1 when unknown.
    public var nextAnnounce: Int

    public init(url: String, message: String, tier: Int, status: TrackerStatus, seeds: Int, peers: Int,
                downloaded: Int, nextAnnounce: Int) {
        self.url = url
        self.message = message
        self.tier = tier
        self.status = status
        self.seeds = seeds
        self.peers = peers
        self.downloaded = downloaded
        self.nextAnnounce = nextAnnounce
    }

    public var id: String { "\(tier)|\(url)" }
    public var statusTitle: String { message.isEmpty ? status.title : "\(status.title): \(message)" }
}

public struct TorrentInfo: Hashable, Sendable {
    public var name: String
    public var comment: String
    public var creator: String
    public var infoHashV1: String
    public var infoHashV2: String
    public var totalSize: Int64
    public var creationDate: Date?
    public var pieceLength: Int
    public var pieceCount: Int
    public var fileCount: Int
    public var isPrivate: Bool
    public var hasMetadata: Bool

    public init(name: String, comment: String, creator: String, infoHashV1: String, infoHashV2: String,
                totalSize: Int64, creationDate: Date?, pieceLength: Int, pieceCount: Int, fileCount: Int,
                isPrivate: Bool, hasMetadata: Bool) {
        self.name = name
        self.comment = comment
        self.creator = creator
        self.infoHashV1 = infoHashV1
        self.infoHashV2 = infoHashV2
        self.totalSize = totalSize
        self.creationDate = creationDate
        self.pieceLength = pieceLength
        self.pieceCount = pieceCount
        self.fileCount = fileCount
        self.isPrivate = isPrivate
        self.hasMetadata = hasMetadata
    }
}

public struct TorrentDetails: Sendable {
    public var info: TorrentInfo?
    public var files: [FileEntry]
    public var peers: [PeerEntry]
    public var trackers: [TrackerEntry]

    public init(info: TorrentInfo?, files: [FileEntry], peers: [PeerEntry], trackers: [TrackerEntry]) {
        self.info = info
        self.files = files
        self.peers = peers
        self.trackers = trackers
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var dhtNodes: Int
    public var listenPort: Int
    public var isListening: Bool
    /// Payload bytes received since the engine started.
    public var totalDownload: Int64 = 0
    /// Payload bytes sent since the engine started.
    public var totalUpload: Int64 = 0
    /// Peers that connected to us since the engine started.
    public var incomingConnections: Int64 = 0
    public var portMapped = false
    public var externalPort = 0
    public var isPaused = false

    public init(dhtNodes: Int = 0, listenPort: Int = 0, isListening: Bool = false) {
        self.dhtNodes = dhtNodes
        self.listenPort = listenPort
        self.isListening = isListening
    }
}

public enum LogLevel: Int, Sendable, Comparable {
    case info = 0
    case warning = 1
    case error = 2

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct LogEntry: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date: Date
    public var torrentID: TorrentID?
    public var level: LogLevel
    public var message: String

    public init(date: Date = Date(), torrentID: TorrentID?, level: LogLevel, message: String) {
        self.date = date
        self.torrentID = torrentID
        self.level = level
        self.message = message
    }
}

public enum AddSource: Hashable, Sendable {
    case file(URL)
    case data(Data, suggestedName: String?)
    case magnet(String)
}

public struct AddRequest: Sendable {
    public var source: AddSource
    public var savePath: String
    public var start: Bool
    public var skipHashCheck: Bool
    /// One libtorrent priority per file index; nil downloads everything.
    public var filePriorities: [Int]?
    /// Allocate full files up front instead of sparse files.
    public var preallocate: Bool

    public init(source: AddSource, savePath: String, start: Bool = true, skipHashCheck: Bool = false, filePriorities: [Int]? = nil,
                preallocate: Bool = false) {
        self.source = source
        self.savePath = savePath
        self.start = start
        self.skipHashCheck = skipHashCheck
        self.filePriorities = filePriorities
        self.preallocate = preallocate
    }
}

public enum AddResult: Equatable, Sendable {
    case added(TorrentID)
    case duplicate(TorrentID)
}

/// What a torrent contains, read before adding it.
public struct TorrentPreview: Hashable, Sendable {
    public var name: String
    public var infoHashV1: String
    public var infoHashV2: String
    public var totalSize: Int64
    public var files: [FileEntry]
    public var comment: String
    public var isPrivate: Bool
    public var isMagnet: Bool

    public init(name: String, infoHashV1: String, infoHashV2: String, totalSize: Int64, files: [FileEntry],
                comment: String, isPrivate: Bool, isMagnet: Bool) {
        self.name = name
        self.infoHashV1 = infoHashV1
        self.infoHashV2 = infoHashV2
        self.totalSize = totalSize
        self.files = files
        self.comment = comment
        self.isPrivate = isPrivate
        self.isMagnet = isMagnet
    }

    /// Same id the engine will use: the v1 info-hash, else the v2 hash truncated to 20 bytes.
    public var torrentID: TorrentID { infoHashV1.isEmpty ? String(infoHashV2.prefix(40)) : infoHashV1 }
}

public enum TorrentAction: Sendable {
    case start
    case pause
    case forceStart
    case recheck
    case reannounce
    case queueUp
    case queueDown
    case queueTop
    case queueBottom
}

public enum EngineEvent: Sendable {
    /// Torrents whose state changed since the previous batch.
    case statuses([TorrentSnapshot])
    case removed(TorrentID)
    case finished(TorrentID)
    case metadataReceived(TorrentID)
    case log(LogEntry)
    case session(SessionSnapshot)
    /// Number of torrents restored from the previous session.
    case loaded(Int)
    /// A storage move finished; error is nil on success.
    case moved(TorrentID, path: String, error: String?)
}

public struct EngineSettings: Equatable, Codable, Sendable {
    public var listenPort: Int
    /// Bytes per second, 0 = unlimited.
    public var downloadLimit: Int
    /// Bytes per second, 0 = unlimited.
    public var uploadLimit: Int
    public var enableDHT: Bool
    public var enableLSD: Bool
    public var enableUPnP: Bool
    public var enableNATPMP: Bool
    public var maxConnections: Int
    public var maxActiveTorrents: Int
    public var maxActiveDownloads: Int
    /// Interface name or IP to listen on, empty = all.
    public var listenInterface: String = ""
    /// Added to files until they complete, empty = off.
    public var incompleteSuffix: String = ""
    /// Pause every torrent at once (scheduler "off", transfer cap reached).
    public var sessionPaused = false
    /// Further libtorrent settings by settings_pack name, applied after the fields above.
    public var named: [String: String] = [:]

    public init(listenPort: Int = 6881, downloadLimit: Int = 0, uploadLimit: Int = 0, enableDHT: Bool = true,
                enableLSD: Bool = true, enableUPnP: Bool = true, enableNATPMP: Bool = true, maxConnections: Int = 500,
                maxActiveTorrents: Int = 8, maxActiveDownloads: Int = 5) {
        self.listenPort = listenPort
        self.downloadLimit = downloadLimit
        self.uploadLimit = uploadLimit
        self.enableDHT = enableDHT
        self.enableLSD = enableLSD
        self.enableUPnP = enableUPnP
        self.enableNATPMP = enableNATPMP
        self.maxConnections = maxConnections
        self.maxActiveTorrents = maxActiveTorrents
        self.maxActiveDownloads = maxActiveDownloads
    }
}

public enum EngineError: Error, LocalizedError, Sendable {
    case sessionFailed
    case notRunning
    case addFailed(String)
    case invalidTorrent(String)
    case downloadFailed(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sessionFailed: return "The torrent engine could not start."
        case .notRunning: return "The torrent engine is not running."
        case .addFailed(let message): return message
        case .invalidTorrent(let message): return message
        case .downloadFailed(let message): return message
        case .operationFailed(let message): return message
        }
    }
}
