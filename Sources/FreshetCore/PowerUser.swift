import Foundation

// Phase 2 building blocks: per-torrent properties, seeding goals, bandwidth priority, the
// scheduler, the transfer cap, search providers and the mapping from preferences to
// libtorrent settings. All pure values so they can be tested without an engine.

// MARK: Per-torrent properties

/// What the Properties sheet edits for one torrent.
public struct TorrentProperties: Equatable, Sendable, Codable {
    /// Bytes per second, 0 = unlimited.
    public var downloadLimit = 0
    /// Bytes per second, 0 = unlimited.
    public var uploadLimit = 0
    /// 0 = no limit of its own.
    public var maxConnections = 0
    /// Upload slots, 0 = no limit of its own.
    public var maxUploads = 0
    public var disableDHT = false
    public var disablePEX = false
    public var disableLSD = false
    /// Initial seeding (BEP 16 super-seeding).
    public var superSeeding = false
    public var sequential = false

    public init() {}
}

public struct TrackerEdit: Equatable, Sendable {
    public var url: String
    public var tier: Int

    public init(url: String, tier: Int) {
        self.url = url
        self.tier = tier
    }

    /// The tracker list as typed: one URL per line, a blank line starts the next tier.
    public static func parse(_ text: String) -> [TrackerEdit] {
        var result: [TrackerEdit] = []
        var tier = 0
        var tierHasURL = false
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if tierHasURL {
                    tier += 1
                    tierHasURL = false
                }
                continue
            }
            if result.contains(where: { $0.url == line }) { continue }
            result.append(TrackerEdit(url: line, tier: tier))
            tierHasURL = true
        }
        return result
    }

    public static func format(_ list: [TrackerEdit]) -> String {
        var lines: [String] = []
        var previous: Int?
        for entry in list.sorted(by: { $0.tier < $1.tier }) {
            if let previous, previous != entry.tier { lines.append("") }
            lines.append(entry.url)
            previous = entry.tier
        }
        return lines.joined(separator: "\n")
    }
}

/// A peer address typed into Add Peer: "1.2.3.4:6881" or "[2001:db8::1]:6881".
public struct PeerAddress: Equatable, Sendable {
    public var ip: String
    public var port: Int

    public init?(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespaces)
        let host: Substring
        let portText: Substring
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            host = value[value.index(after: value.startIndex)..<close]
            let rest = value[value.index(after: close)...]
            guard rest.hasPrefix(":") else { return nil }
            portText = rest.dropFirst()
        } else {
            guard let colon = value.lastIndex(of: ":"), value.filter({ $0 == ":" }).count == 1 else { return nil }
            host = value[..<colon]
            portText = value[value.index(after: colon)...]
        }
        guard let port = Int(portText), (1...65_535).contains(port), !host.isEmpty else { return nil }
        let ip = String(host)
        let isV4 = ip.split(separator: ".", omittingEmptySubsequences: false).count == 4
            && ip.split(separator: ".").allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        let isV6 = ip.contains(":") && ip.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        guard isV4 || isV6 else { return nil }
        self.ip = ip
        self.port = port
    }
}

/// One libtorrent setting as listed by the Advanced pane.
public struct AdvancedSetting: Identifiable, Equatable, Sendable {
    public enum Kind: Int, Sendable { case text = 0, number = 1, toggle = 2 }

    public var name: String
    public var kind: Kind
    public var value: String
    public var defaultValue: String

    public init(name: String, kind: Kind, value: String, defaultValue: String) {
        self.name = name
        self.kind = kind
        self.value = value
        self.defaultValue = defaultValue
    }

    public var id: String { name }
    public var isDefault: Bool { value == defaultValue }
}

// MARK: Seeding goals

public enum SeedingGoalAction: String, Codable, CaseIterable, Sendable {
    /// Stop the torrent (the default).
    case stop
    /// Keep seeding at a reduced upload rate.
    case limitUpload
}

/// Seed until the ratio or the seeding time is reached, whichever comes first.
public struct SeedingGoal: Codable, Equatable, Sendable {
    /// Upload as a percentage of the torrent's size or of what was downloaded, 0 = no ratio goal.
    public var ratioPercent: Int
    /// Minutes of seeding, 0 = no time goal.
    public var minutes: Int

    public init(ratioPercent: Int = 0, minutes: Int = 0) {
        self.ratioPercent = ratioPercent
        self.minutes = minutes
    }

    public var isEnabled: Bool { ratioPercent > 0 || minutes > 0 }

    public func isReached(by torrent: TorrentSnapshot) -> Bool {
        guard isEnabled, torrent.isComplete else { return false }
        if ratioPercent > 0 {
            // Like libtorrent's seed rank: a torrent added complete counts its size as downloaded.
            let base = max(torrent.allTimeDownload, torrent.totalWanted)
            if base > 0, torrent.allTimeUpload * 100 >= Int64(ratioPercent) * base { return true }
        }
        if minutes > 0, torrent.seedingSeconds >= Int64(minutes) * 60 { return true }
        return false
    }
}

// MARK: Bandwidth priority

public enum BandwidthPriority: Int, Codable, CaseIterable, Sendable {
    case low = 1
    case normal = 2
    case high = 4

    public var title: String {
        switch self {
        case .low: return "Low"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

public enum BandwidthAllocator {
    public struct Share: Equatable, Sendable {
        public var id: TorrentID
        public var priority: BandwidthPriority
        public var isActive: Bool

        public init(id: TorrentID, priority: BandwidthPriority, isActive: Bool) {
            self.id = id
            self.priority = priority
            self.isActive = isActive
        }
    }

    /// Splits a global limit (bytes per second) between active torrents by priority weight.
    /// Returns no limits when there is no global limit or every active torrent is Normal,
    /// since the global limit alone already shares evenly then.
    public static func split(limit: Int, among torrents: [Share]) -> [TorrentID: Int] {
        let active = torrents.filter(\.isActive)
        guard limit > 0, active.contains(where: { $0.priority != .normal }) else { return [:] }
        let total = active.reduce(0) { $0 + $1.priority.rawValue }
        var result: [TorrentID: Int] = [:]
        for torrent in active {
            result[torrent.id] = max(1_024, limit * torrent.priority.rawValue / total)
        }
        return result
    }
}

// MARK: Scheduler

public enum ScheduleMode: Int, Codable, CaseIterable, Sendable {
    case full = 0
    case limited = 1
    case seedingOnly = 2
    case off = 3

    public var title: String {
        switch self {
        case .full: return "Full speed"
        case .limited: return "Limited"
        case .seedingOnly: return "Seeding only"
        case .off: return "Turn off"
        }
    }

    public var next: ScheduleMode { ScheduleMode(rawValue: (rawValue + 1) % 4) ?? .full }
}

/// The 7 × 24 weekly scheduler grid. Day 0 is Monday.
public struct Schedule: Codable, Equatable, Sendable {
    public static let days = 7
    public static let hours = 24

    public var isEnabled = false
    public var slots: [ScheduleMode] = Array(repeating: .full, count: days * hours)
    public var limitedDownloadKBps = 0
    public var limitedUploadKBps = 0
    public var disableDHTWhenOff = true

    public init() {}

    public subscript(day: Int, hour: Int) -> ScheduleMode {
        get { slots[day * Self.hours + hour] }
        set { slots[day * Self.hours + hour] = newValue }
    }

    /// The slot in force at `date`, or full speed when the scheduler is off.
    public func mode(at date: Date, calendar: Calendar = .current) -> ScheduleMode {
        guard isEnabled, slots.count == Self.days * Self.hours else { return .full }
        let weekday = calendar.component(.weekday, from: date)  // 1 = Sunday
        let day = (weekday + 5) % 7                              // 0 = Monday
        let hour = calendar.component(.hour, from: date)
        return self[day, hour]
    }
}

// MARK: Transfer cap

public enum CapKind: String, Codable, CaseIterable, Sendable {
    case upload, download, both

    public var title: String {
        switch self {
        case .upload: return "Uploads"
        case .download: return "Downloads"
        case .both: return "Uploads + downloads"
        }
    }
}

public struct TransferCap: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var kind: CapKind = .both
    /// The cap in megabytes.
    public var megabytes = 10_240
    /// Length of the rolling window, ending today.
    public var periodDays = 31

    public init() {}

    public var bytes: Int64 { Int64(megabytes) * 1_048_576 }
}

/// Bytes transferred per calendar day, kept for the transfer cap and its usage graph.
public struct UsageLedger: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public var download: Int64 = 0
        public var upload: Int64 = 0
    }

    public var days: [String: Day] = [:]

    public init() {}

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public mutating func record(download: Int64, upload: Int64, on date: Date, calendar: Calendar = .current) {
        guard download > 0 || upload > 0 else { return }
        let key = Self.key(for: date, calendar: calendar)
        var day = days[key] ?? Day()
        day.download += max(0, download)
        day.upload += max(0, upload)
        days[key] = day
    }

    /// Daily totals for the `count` days ending on `date`, oldest first.
    public func series(days count: Int, endingOn date: Date, calendar: Calendar = .current) -> [(date: Date, usage: Day)] {
        let today = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, days[Self.key(for: day, calendar: calendar)] ?? Day())
        }
    }

    public func total(_ kind: CapKind, days count: Int, endingOn date: Date, calendar: Calendar = .current) -> Int64 {
        series(days: count, endingOn: date, calendar: calendar).reduce(Int64(0)) { sum, entry in
            switch kind {
            case .upload: return sum + entry.usage.upload
            case .download: return sum + entry.usage.download
            case .both: return sum + entry.usage.upload + entry.usage.download
            }
        }
    }

    /// Drops days older than `keepDays`.
    public mutating func prune(keepDays: Int, now: Date, calendar: Calendar = .current) {
        let kept = Set(series(days: keepDays, endingOn: now, calendar: calendar).map { Self.key(for: $0.date, calendar: calendar) })
        days = days.filter { kept.contains($0.key) }
    }
}

// MARK: Search providers

/// A search site the user added; `%s` in the template is replaced by the query.
public struct SearchProvider: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var template: String

    public init(id: UUID = UUID(), name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }

    public var isValid: Bool { url(for: "test") != nil }

    public func url(for query: String) -> URL? {
        guard template.contains("%s") else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/")
        guard let encoded = query.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.isEmpty else { return nil }
        guard let url = URL(string: template.replacingOccurrences(of: "%s", with: encoded)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

// MARK: Network preferences → libtorrent settings

public enum EncryptionMode: String, Codable, CaseIterable, Sendable {
    case disabled, enabled, forced

    public var title: String {
        switch self {
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        case .forced: return "Forced"
        }
    }
}

public enum ProxyKind: String, Codable, CaseIterable, Sendable {
    case none, socks4, socks5, http

    public var title: String {
        switch self {
        case .none: return "None"
        case .socks4: return "SOCKS4"
        case .socks5: return "SOCKS5"
        case .http: return "HTTP"
        }
    }
}

public struct ProxyOptions: Codable, Equatable, Sendable {
    public var kind: ProxyKind = .none
    public var host = ""
    public var port = 1_080
    public var useAuthentication = false
    public var username = ""
    public var resolveHostnames = true
    public var proxyPeers = true
    public var proxyTrackers = true
    /// Proxy privacy switches: no DHT, LSD, UPnP or NAT-PMP while a proxy is set.
    public var disableLeakyFeatures = true

    public init() {}

    public var isActive: Bool { kind != .none && !host.trimmingCharacters(in: .whitespaces).isEmpty }
}

public struct NetworkOptions: Equatable, Sendable {
    public var encryption: EncryptionMode = .enabled
    public var allowLegacyIncoming = true
    public var proxy = ProxyOptions()
    public var proxyPassword = ""
    /// Interface name or IP for outgoing connections, empty = any.
    public var outgoingInterface = ""
    /// IP or hostname reported to trackers, empty = let them see it.
    public var announceIP = ""
    /// Global upload slots, 0 = unlimited.
    public var uploadSlots = 8
    /// "Use additional upload slots if upload speed is under 90%": libtorrent's rate-based choker.
    public var extraSlotsWhenSlow = true
    public var preferSeeds = false
    public var diskThreads = 10
    public var hashingThreads = 1
    public var maxQueuedDiskMB = 1
    public var filePoolSize = 40

    public init() {}
}

public enum LibtorrentSettingsMapper {
    /// libtorrent settings_pack values for the given preferences (enum values from settings_pack.hpp).
    public static func named(_ o: NetworkOptions) -> [String: String] {
        var s: [String: String] = [:]
        switch o.encryption {
        case .disabled:
            s["out_enc_policy"] = "2"
            s["in_enc_policy"] = "2"
            s["allowed_enc_level"] = "3"
        case .enabled:
            s["out_enc_policy"] = "1"
            s["in_enc_policy"] = o.allowLegacyIncoming ? "1" : "0"
            s["allowed_enc_level"] = "3"
        case .forced:
            s["out_enc_policy"] = "0"
            s["in_enc_policy"] = "0"
            s["allowed_enc_level"] = "2"
        }
        let proxy = o.proxy
        if proxy.isActive {
            let auth = proxy.useAuthentication && !proxy.username.isEmpty
            switch proxy.kind {
            case .none: s["proxy_type"] = "0"
            case .socks4: s["proxy_type"] = "1"
            case .socks5: s["proxy_type"] = auth ? "3" : "2"
            case .http: s["proxy_type"] = auth ? "5" : "4"
            }
            s["proxy_hostname"] = proxy.host.trimmingCharacters(in: .whitespaces)
            s["proxy_port"] = String(min(max(proxy.port, 1), 65_535))
            s["proxy_username"] = auth ? proxy.username : ""
            s["proxy_password"] = auth ? o.proxyPassword : ""
            s["proxy_hostnames"] = proxy.resolveHostnames ? "true" : "false"
            s["proxy_peer_connections"] = proxy.proxyPeers ? "true" : "false"
            s["proxy_tracker_connections"] = proxy.proxyTrackers ? "true" : "false"
        } else {
            s["proxy_type"] = "0"
            s["proxy_hostname"] = ""
            s["proxy_username"] = ""
            s["proxy_password"] = ""
        }
        s["outgoing_interfaces"] = o.outgoingInterface.trimmingCharacters(in: .whitespaces)
        s["announce_ip"] = o.announceIP.trimmingCharacters(in: .whitespaces)
        s["choking_algorithm"] = o.extraSlotsWhenSlow ? "2" : "0"
        s["unchoke_slots_limit"] = o.uploadSlots > 0 ? String(o.uploadSlots) : "-1"
        s["auto_manage_prefer_seeds"] = o.preferSeeds ? "true" : "false"
        s["aio_threads"] = String(min(max(o.diskThreads, 1), 64))
        s["hashing_threads"] = String(min(max(o.hashingThreads, 1), 64))
        s["max_queued_disk_bytes"] = String(min(max(o.maxQueuedDiskMB, 1), 1_024) * 1_048_576)
        s["file_pool_size"] = String(min(max(o.filePoolSize, 4), 10_000))
        return s
    }
}
