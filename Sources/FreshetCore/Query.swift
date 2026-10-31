import Foundation

/// The sidebar's categories.
public enum SidebarFilter: Hashable, Sendable {
    case all
    case downloading
    case seeding
    case completed
    case active
    case inactive
    case label(String)
    case noLabel

    public static let standard: [SidebarFilter] = [.all, .downloading, .seeding, .completed, .active, .inactive]

    public var title: String {
        switch self {
        case .all: return "All"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .completed: return "Completed"
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .label(let name): return name
        case .noLabel: return "No Label"
        }
    }

    public var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .downloading: return "arrow.down.circle"
        case .seeding: return "arrow.up.circle"
        case .completed: return "checkmark.circle"
        case .active: return "bolt.horizontal.circle"
        case .inactive: return "moon.zzz"
        case .label: return "tag"
        case .noLabel: return "tag.slash"
        }
    }

    public func matches(_ torrent: TorrentSnapshot, label: String?) -> Bool {
        switch self {
        case .all: return true
        case .downloading: return !torrent.isComplete
        case .seeding: return torrent.isComplete && !torrent.isStopped
        case .completed: return torrent.isComplete
        case .active: return torrent.isActive
        case .inactive: return !torrent.isActive
        case .label(let name): return label == name
        case .noLabel: return label == nil || label?.isEmpty == true
        }
    }
}

/// The torrent list's columns: titles, display text and sort order.
public enum TorrentField: String, CaseIterable, Codable, Sendable {
    case queue, name, size, done, status, seeds, peers, downSpeed, upSpeed, eta, ratio, availability
    case label, added, completed, remaining, downloaded, uploaded, tracker, savePath

    public var title: String {
        switch self {
        case .queue: return "#"
        case .name: return "Name"
        case .size: return "Size"
        case .done: return "Done"
        case .status: return "Status"
        case .seeds: return "Seeds"
        case .peers: return "Peers"
        case .downSpeed: return "Down Speed"
        case .upSpeed: return "Up Speed"
        case .eta: return "ETA"
        case .ratio: return "Ratio"
        case .availability: return "Availability"
        case .label: return "Label"
        case .added: return "Added On"
        case .completed: return "Completed On"
        case .remaining: return "Remaining"
        case .downloaded: return "Downloaded"
        case .uploaded: return "Uploaded"
        case .tracker: return "Tracker"
        case .savePath: return "Save Path"
        }
    }

    public var isNumeric: Bool {
        switch self {
        case .name, .status, .label, .tracker, .savePath, .added, .completed: return false
        default: return true
        }
    }

    public func text(for torrent: TorrentSnapshot, label: String?) -> String {
        switch self {
        case .queue: return torrent.queuePosition >= 0 ? "\(torrent.queuePosition + 1)" : "*"
        case .name: return torrent.displayName
        case .size: return torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : ""
        case .done: return Format.percent(torrent.progress)
        case .status: return torrent.statusText
        case .seeds: return Format.count(torrent.connectedSeeds, of: torrent.swarmSeeds)
        case .peers: return Format.count(torrent.connectedLeechers, of: torrent.swarmPeers)
        case .downSpeed: return Format.rate(torrent.downloadRate)
        case .upSpeed: return Format.rate(torrent.uploadRate)
        case .eta:
            if torrent.isComplete || torrent.isPaused { return "" }
            return Format.duration(torrent.eta)
        case .ratio: return Format.ratio(torrent.ratio)
        case .availability: return Format.availability(torrent.availability)
        case .label: return label ?? ""
        case .added: return Format.date(torrent.addedDate)
        case .completed: return Format.date(torrent.completedDate)
        case .remaining: return torrent.hasMetadata ? Format.bytes(torrent.remaining) : ""
        case .downloaded: return Format.bytes(torrent.allTimeDownload)
        case .uploaded: return Format.bytes(torrent.allTimeUpload)
        case .tracker: return Self.host(of: torrent.currentTracker)
        case .savePath: return torrent.savePath
        }
    }

    public func compare(_ a: TorrentSnapshot, _ b: TorrentSnapshot, labelA: String?, labelB: String?) -> ComparisonResult {
        switch self {
        case .queue:
            // Torrents outside the queue (seeds) sort after queued ones.
            let qa = a.queuePosition < 0 ? Int.max : a.queuePosition
            let qb = b.queuePosition < 0 ? Int.max : b.queuePosition
            return Self.order(qa, qb)
        case .name: return a.displayName.localizedStandardCompare(b.displayName)
        case .size: return Self.order(a.totalWanted, b.totalWanted)
        case .done: return Self.order(a.progress, b.progress)
        case .status: return a.statusText.localizedStandardCompare(b.statusText)
        case .seeds: return Self.order(a.connectedSeeds, b.connectedSeeds)
        case .peers: return Self.order(a.connectedLeechers, b.connectedLeechers)
        case .downSpeed: return Self.order(a.downloadRate, b.downloadRate)
        case .upSpeed: return Self.order(a.uploadRate, b.uploadRate)
        case .eta: return Self.order(a.eta ?? .infinity, b.eta ?? .infinity)
        case .ratio: return Self.order(a.ratio, b.ratio)
        case .availability: return Self.order(a.availability, b.availability)
        case .label: return (labelA ?? "").localizedStandardCompare(labelB ?? "")
        case .added: return Self.order(a.addedDate ?? .distantPast, b.addedDate ?? .distantPast)
        case .completed: return Self.order(a.completedDate ?? .distantPast, b.completedDate ?? .distantPast)
        case .remaining: return Self.order(a.remaining, b.remaining)
        case .downloaded: return Self.order(a.allTimeDownload, b.allTimeDownload)
        case .uploaded: return Self.order(a.allTimeUpload, b.allTimeUpload)
        case .tracker: return Self.host(of: a.currentTracker).localizedStandardCompare(Self.host(of: b.currentTracker))
        case .savePath: return a.savePath.localizedStandardCompare(b.savePath)
        }
    }

    static func host(of url: String) -> String {
        URL(string: url)?.host ?? url
    }

    static func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}

public struct TorrentSortKey: Hashable, Codable, Sendable {
    public var field: TorrentField
    public var ascending: Bool

    public init(field: TorrentField, ascending: Bool) {
        self.field = field
        self.ascending = ascending
    }
}

public enum TorrentQuery {
    /// Torrents that pass the sidebar filter and search text, in the requested order.
    public static func visible(_ torrents: [TorrentSnapshot], filter: SidebarFilter, search: String,
                               labels: [TorrentID: String], sort: TorrentSortKey) -> [TorrentSnapshot] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = torrents.filter { torrent in
            filter.matches(torrent, label: labels[torrent.id])
                && (needle.isEmpty || torrent.displayName.localizedCaseInsensitiveContains(needle))
        }
        list.sort { a, b in
            var result = sort.field.compare(a, b, labelA: labels[a.id], labelB: labels[b.id])
            if result == .orderedSame { result = TorrentField.order(a.id, b.id) }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return list
    }
}
