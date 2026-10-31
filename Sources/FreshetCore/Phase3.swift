import Foundation

// MARK: Run a program

/// "Run a program" placeholders, the same set other BitTorrent clients use, so existing scripts keep working:
/// %F file (single-file torrents), %D save folder, %N torrent name, %P previous state, %L label,
/// %T tracker, %M status message, %I info-hash, %S state, %K "single" or "multi".
public enum RunCommand {
    /// Numeric state codes for %S and %P.
    public static func stateCode(_ torrent: TorrentSnapshot) -> Int {
        let forced = !torrent.isAutoManaged && !torrent.isPaused
        switch torrent.activity {
        case .error: return 1
        case .checking: return 2
        case .paused: return torrent.isComplete ? 11 : 13
        case .seeding: return forced ? 8 : 5
        case .downloading, .downloadingMetadata: return forced ? 9 : 6
        case .queuedSeed: return 10
        case .finished: return 11
        case .queued: return 12
        }
    }

    /// Expands the placeholders; every substituted value is single-quoted for the shell.
    public static func expand(_ template: String, torrent: TorrentSnapshot, label: String?, isMultiFile: Bool,
                              previousState: Int?) -> String {
        let values: [Character: String] = [
            "F": isMultiFile ? "" : (torrent.savePath as NSString).appendingPathComponent(torrent.name),
            "D": isMultiFile ? (torrent.savePath as NSString).appendingPathComponent(torrent.name) : torrent.savePath,
            "N": torrent.displayName,
            "P": previousState.map(String.init) ?? "",
            "L": label ?? "",
            "T": torrent.currentTracker,
            "M": torrent.statusText,
            "I": torrent.id.uppercased(),
            "S": String(stateCode(torrent)),
            "K": isMultiFile ? "multi" : "single",
        ]
        var out = ""
        var iterator = template.makeIterator()
        while let c = iterator.next() {
            guard c == "%" else { out.append(c); continue }
            guard let next = iterator.next() else { out.append(c); break }
            if next == "%" { out.append("%") } else if let value = values[next] { out += shellQuote(value) } else { out.append(c); out.append(next) }
        }
        return out
    }

    public static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// What to do once every download has finished.
public enum WhenDoneAction: String, Codable, CaseIterable, Sendable {
    case nothing, quit, sleep, shutDown, restart

    public var title: String {
        switch self {
        case .nothing: return "Do Nothing"
        case .quit: return "Quit Freshet"
        case .sleep: return "Sleep"
        case .shutDown: return "Shut Down"
        case .restart: return "Restart"
        }
    }
}

// MARK: RSS feeds

public struct RSSItem: Hashable, Sendable, Codable, Identifiable {
    public var title: String
    /// What to add: a .torrent URL or a magnet link.
    public var link: String
    public var guid: String
    public var published: Date?

    public init(title: String, link: String, guid: String, published: Date?) {
        self.title = title
        self.link = link
        self.guid = guid
        self.published = published
    }

    public var id: String { guid.isEmpty ? link : guid }
}

/// Reads RSS 2.0 and Atom feeds, preferring a torrent enclosure, then a magnet link, then the link.
public final class RSSFeedParser: NSObject, XMLParserDelegate {
    private var items: [RSSItem] = []
    private var current: [String: String]?
    private var enclosure: String?
    private var text = ""

    public static func parse(_ data: Data) -> [RSSItem]? {
        let delegate = RSSFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return delegate.items.isEmpty ? nil : delegate.items }
        return delegate.items
    }

    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                       attributes: [String: String] = [:]) {
        let tag = name.lowercased()
        if tag == "item" || tag == "entry" {
            current = [:]
            enclosure = nil
        } else if current != nil {
            if tag == "enclosure", let url = attributes["url"] {
                let type = attributes["type"]?.lowercased() ?? ""
                if enclosure == nil || type.contains("bittorrent") { enclosure = url }
            } else if tag == "link", let href = attributes["href"] {  // Atom
                let rel = attributes["rel"] ?? "alternate"
                if rel == "enclosure" || attributes["type"]?.contains("bittorrent") == true { enclosure = href }
                else if current?["link"] == nil { current?["link"] = href }
            }
        }
        text = ""
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let tag = name.lowercased()
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag == "item" || tag == "entry" {
            if let fields = current {
                let magnet = fields["torrent:magneturi"] ?? fields["magneturi"]
                let link = enclosure ?? magnet ?? fields["link"] ?? ""
                if !link.isEmpty {
                    let date = (fields["pubdate"] ?? fields["published"] ?? fields["updated"] ?? fields["dc:date"]).flatMap(Self.date)
                    items.append(RSSItem(title: fields["title"] ?? link, link: link, guid: fields["guid"] ?? fields["id"] ?? link,
                                         published: date))
                }
            }
            current = nil
        } else if current != nil, !value.isEmpty, current?[tag] == nil {
            current?[tag] = value
        }
        text = ""
    }

    static func date(_ text: String) -> Date? {
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z"] {
            rfc822.dateFormat = format
            if let date = rfc822.date(from: text) { return date }
        }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }
}

public struct RSSFeed: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var url: String
    public var alias: String
    /// Sent as the Cookie header, e.g. "uid=123; pass=abc".
    public var cookies: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), url: String, alias: String = "", cookies: String = "", isEnabled: Bool = true) {
        self.id = id
        self.url = url
        self.alias = alias
        self.cookies = cookies
        self.isEnabled = isEnabled
    }

    public var displayName: String {
        if !alias.isEmpty { return alias }
        return URL(string: url)?.host ?? url
    }
}

/// Season and episode read from a title: S01E02, 1x02, or a date episode (2026.10.29).
public struct EpisodeInfo: Hashable, Codable, Sendable {
    public var season: Int
    public var episode: Int

    public init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }

    public static func parse(_ title: String) -> EpisodeInfo? {
        let patterns = [#"(?i)\bS(\d{1,3})[ ._-]?E(\d{1,4})"#, #"(?i)\b(\d{1,2})x(\d{1,4})\b"#,
                        #"\b(20\d\d)[.\- ](\d\d)[.\- ](\d\d)\b"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) else { continue }
            func group(_ i: Int) -> Int? {
                Range(match.range(at: i), in: title).flatMap { Int(title[$0]) }
            }
            if index == 2, let year = group(1), let month = group(2), let day = group(3) {
                return EpisodeInfo(season: year, episode: month * 100 + day)
            }
            if let season = group(1), let episode = group(2) { return EpisodeInfo(season: season, episode: episode) }
        }
        return nil
    }
}

/// Episode filter: "1x1-10;2x3-;3" — seasons with optional episode ranges, open-ended allowed.
public struct EpisodeFilter: Equatable, Sendable {
    struct Rule: Equatable {
        var season: Int
        var from: Int?
        var to: Int?
    }

    var rules: [Rule]

    public init?(_ text: String) {
        var rules: [Rule] = []
        for part in text.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
            let pieces = part.lowercased().split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard let head = pieces.first, let season = Int(head.trimmingCharacters(in: .whitespaces)) else { return nil }
            if pieces.count == 1 {
                rules.append(Rule(season: season, from: nil, to: nil))
                continue
            }
            let range = pieces[1].split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = range.first, let from = Int(first) else { return nil }
            if range.count == 1 { rules.append(Rule(season: season, from: from, to: from)); continue }
            let to = range[1].isEmpty ? nil : Int(range[1])
            if !range[1].isEmpty && to == nil { return nil }
            rules.append(Rule(season: season, from: from, to: to))
        }
        guard !rules.isEmpty else { return nil }
        self.rules = rules
    }

    public func contains(_ e: EpisodeInfo) -> Bool {
        rules.contains { rule in
            guard rule.season == e.season else { return false }
            if let from = rule.from, e.episode < from { return false }
            if let to = rule.to, e.episode > to { return false }
            return true
        }
    }
}

public enum VideoQuality: String, Codable, CaseIterable, Sendable {
    case sd = "SD", hd720 = "720p", hd1080 = "1080p", uhd = "2160p"

    public static func detect(_ title: String) -> VideoQuality {
        let t = title.lowercased()
        if t.contains("2160p") || t.contains("4k") || t.contains("uhd") { return .uhd }
        if t.contains("1080") { return .hd1080 }
        if t.contains("720p") { return .hd720 }
        return .sd
    }
}

public struct RSSFilter: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Wildcards: * any text, ? one character; several alternatives separated by |. Case-insensitive.
    public var include: String
    /// Titles matching this are skipped.
    public var exclude: String
    /// nil = every feed.
    public var feedID: UUID?
    /// Empty = the default download folder.
    public var saveFolder: String
    public var label: String
    /// Empty = any quality.
    public var qualities: Set<VideoQuality>
    /// Episode number filter, e.g. "1x1-10;2", empty = any.
    public var episodes: String
    /// Download each episode only once, whatever release turns up.
    public var smartEpisodeFilter: Bool
    /// Hours to ignore further matches after a download, 0 = every time.
    public var minimumIntervalHours: Int
    public var addStopped: Bool

    public init(id: UUID = UUID(), name: String = "New Filter", isEnabled: Bool = true, include: String = "", exclude: String = "",
                feedID: UUID? = nil, saveFolder: String = "", label: String = "", qualities: Set<VideoQuality> = [],
                episodes: String = "", smartEpisodeFilter: Bool = false, minimumIntervalHours: Int = 0, addStopped: Bool = false) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.include = include
        self.exclude = exclude
        self.feedID = feedID
        self.saveFolder = saveFolder
        self.label = label
        self.qualities = qualities
        self.episodes = episodes
        self.smartEpisodeFilter = smartEpisodeFilter
        self.minimumIntervalHours = minimumIntervalHours
        self.addStopped = addStopped
    }

    public static func wildcard(_ pattern: String, matches text: String) -> Bool {
        let alternatives = pattern.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !alternatives.isEmpty else { return false }
        return alternatives.contains { alternative in
            var regex = "^"
            for c in alternative {
                switch c {
                case "*": regex += ".*"
                case "?": regex += "."
                default: regex += NSRegularExpression.escapedPattern(for: String(c))
                }
            }
            regex += "$"
            // A pattern without wildcards matches anywhere in the title.
            if !alternative.contains("*") && !alternative.contains("?") { regex = "^.*" + regex.dropFirst().dropLast() + ".*$" }
            return text.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

/// What has been downloaded already, so filters fire once per item or episode.
public struct RSSHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var title: String
        public var date: Date
        public var filterID: UUID?
    }

    public var items: [String: Entry] = [:]
    public var episodes: [UUID: Set<EpisodeInfo>] = [:]
    public var lastMatch: [UUID: Date] = [:]

    public init() {}

    public func contains(_ item: RSSItem) -> Bool { items[item.id] != nil }

    public mutating func record(_ item: RSSItem, filter: RSSFilter?, at date: Date) {
        items[item.id] = Entry(title: item.title, date: date, filterID: filter?.id)
        if let filter {
            lastMatch[filter.id] = date
            if let episode = EpisodeInfo.parse(item.title) { episodes[filter.id, default: []].insert(episode) }
        }
    }

    public mutating func prune(olderThan date: Date) {
        items = items.filter { $0.value.date >= date }
    }
}

public enum RSSMatcher {
    /// The first enabled filter that wants this item now, or nil.
    public static func filter(for item: RSSItem, feed: UUID, filters: [RSSFilter], history: RSSHistory, now: Date) -> RSSFilter? {
        guard !history.contains(item) else { return nil }
        return filters.first { matches($0, item: item, feed: feed, history: history, now: now) }
    }

    public static func matches(_ f: RSSFilter, item: RSSItem, feed: UUID, history: RSSHistory, now: Date) -> Bool {
        guard f.isEnabled, f.feedID == nil || f.feedID == feed else { return false }
        guard RSSFilter.wildcard(f.include, matches: item.title) else { return false }
        if !f.exclude.isEmpty, RSSFilter.wildcard(f.exclude, matches: item.title) { return false }
        if !f.qualities.isEmpty, !f.qualities.contains(VideoQuality.detect(item.title)) { return false }
        let episode = EpisodeInfo.parse(item.title)
        if !f.episodes.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let rule = EpisodeFilter(f.episodes), let episode, rule.contains(episode) else { return false }
        }
        if f.smartEpisodeFilter, let episode, history.episodes[f.id]?.contains(episode) == true { return false }
        if f.minimumIntervalHours > 0, let last = history.lastMatch[f.id],
           now.timeIntervalSince(last) < Double(f.minimumIntervalHours) * 3_600 { return false }
        return true
    }
}

// MARK: Creating torrents

public enum TorrentFormat: Int, Codable, CaseIterable, Sendable {
    case hybrid = 0, v1 = 1, v2 = 2

    public var title: String {
        switch self {
        case .hybrid: return "Hybrid (v1 + v2)"
        case .v1: return "v1 (widest compatibility)"
        case .v2: return "v2 only"
        }
    }
}

public struct CreateTorrentRequest: Sendable {
    public var source: URL
    public var trackers: String
    public var webSeeds: String
    public var comment: String
    public var skipPatterns: String
    /// Bytes, 0 = automatic.
    public var pieceSize: Int
    public var format: TorrentFormat
    public var isPrivate: Bool

    public init(source: URL, trackers: String = "", webSeeds: String = "", comment: String = "", skipPatterns: String = "",
                pieceSize: Int = 0, format: TorrentFormat = .hybrid, isPrivate: Bool = false) {
        self.source = source
        self.trackers = trackers
        self.webSeeds = webSeeds
        self.comment = comment
        self.skipPatterns = skipPatterns
        self.pieceSize = pieceSize
        self.format = format
        self.isPrivate = isPrivate
    }
}
