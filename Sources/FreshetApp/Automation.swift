import AppKit
import FreshetCore
import Observation

/// What the app remembers about each torrent beyond what libtorrent stores.
struct TorrentMeta: Codable, Equatable {
    var priority: BandwidthPriority = .normal
    /// nil = the default goal from Settings → Queueing.
    var goal: SeedingGoal?
    var goalHandled = false
    /// The user's own per-torrent limits in bytes per second, 0 = none.
    var downloadLimit = 0
    var uploadLimit = 0
    /// Where the copy of the .torrent file was saved.
    var torrentCopy: String?
}

/// Everything that runs on a timer or on torrent events rather than on a click: the scheduler,
/// the transfer cap and its usage ledger, the alternate upload rate, seeding goals, bandwidth
/// priority, moving completed downloads and keeping .torrent copies.
@Observable
@MainActor
final class Automation {
    @ObservationIgnored unowned let model: AppModel
    private(set) var meta: [TorrentID: TorrentMeta]
    private(set) var ledger: UsageLedger
    private(set) var scheduleMode: ScheduleMode = .full
    private(set) var capReached = false

    @ObservationIgnored private let metaURL: URL
    @ObservationIgnored private let ledgerURL: URL
    @ObservationIgnored private var lastTotals: (download: Int64, upload: Int64)?
    @ObservationIgnored private var schedulerPaused: Set<TorrentID> = []
    @ObservationIgnored private var appliedLimits: [TorrentID: [Int]] = [:]
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var ledgerDirty = false

    init(model: AppModel, simulated: Bool) {
        self.model = model
        metaURL = AppPaths.support.appendingPathComponent(simulated ? "torrents-simulated.json" : "torrents.json")
        ledgerURL = AppPaths.support.appendingPathComponent(simulated ? "usage-simulated.json" : "usage.json")
        meta = Self.load([TorrentID: TorrentMeta].self, from: metaURL) ?? [:]
        ledger = Self.load(UsageLedger.self, from: ledgerURL) ?? UsageLedger()
    }

    private var settings: AppSettings { model.settings }

    // MARK: Per-torrent data

    func meta(for id: TorrentID) -> TorrentMeta { meta[id] ?? TorrentMeta() }

    func update(_ ids: [TorrentID], _ change: (inout TorrentMeta) -> Void) {
        for id in ids {
            var value = meta[id] ?? TorrentMeta()
            change(&value)
            meta[id] = value
        }
        saveMeta()
        applyTorrentLimits(force: Set(ids))
    }

    func forget(_ ids: [TorrentID]) {
        for id in ids {
            meta.removeValue(forKey: id)
            appliedLimits.removeValue(forKey: id)
            schedulerPaused.remove(id)
        }
        saveMeta()
    }

    // MARK: Engine settings

    /// The preferences' engine settings adjusted for the scheduler, the cap and the alternate rate.
    func effective(_ base: EngineSettings) -> EngineSettings {
        var s = base
        let schedule = settings.schedule
        switch scheduleMode {
        case .full, .seedingOnly:
            break
        case .limited:
            s.downloadLimit = max(0, schedule.limitedDownloadKBps) * 1_024
            s.uploadLimit = max(0, schedule.limitedUploadKBps) * 1_024
        case .off:
            s.sessionPaused = true
            if schedule.disableDHTWhenOff { s.enableDHT = false }
        }
        if capReached { s.sessionPaused = true }
        if settings.alternateUploadEnabled, scheduleMode != .limited, !anyDownloading {
            s.uploadLimit = max(0, settings.alternateUploadKBps) * 1_024
        }
        return s
    }

    var anyDownloading: Bool {
        model.torrents.values.contains { !$0.isPaused && !$0.isComplete && $0.errorMessage == nil }
    }

    func settingsChanged() {
        evaluate(now: Date())
        model.applyEngineSettings()
        applyTorrentLimits(force: Set(model.torrents.keys))
    }

    // MARK: Timer

    func tick(now: Date) {
        ticks += 1
        recordUsage(now: now)
        if ticks % 5 == 1 {
            let before = (scheduleMode, capReached, anyDownloading)
            evaluate(now: now)
            if before != (scheduleMode, capReached, anyDownloading) { model.applyEngineSettings() }
            checkSeedingGoals()
            applyTorrentLimits(force: [])
        }
        if ticks % 60 == 0 { saveLedger() }
    }

    func shutdown() {
        saveLedger(force: true)
        saveMeta()
    }

    private func evaluate(now: Date) {
        let mode = settings.schedule.mode(at: now)
        if mode != scheduleMode {
            scheduleMode = mode
            if settings.schedule.isEnabled {
                model.log(LogEntry(torrentID: nil, level: .info, message: "Scheduler: \(mode.title)"))
            }
        }
        // Seeding only: stop downloads for the slot, restart them afterwards.
        if mode == .seedingOnly {
            let downloads = model.torrents.values.filter { !$0.isPaused && !$0.isComplete }.map(\.id)
            if !downloads.isEmpty {
                schedulerPaused.formUnion(downloads)
                Task { await model.engine.perform(.pause, on: downloads) }
            }
        } else if !schedulerPaused.isEmpty {
            let resume = schedulerPaused.filter { model.torrents[$0]?.isStopped == true }
            schedulerPaused.removeAll()
            if !resume.isEmpty { Task { await model.engine.perform(.start, on: Array(resume)) } }
        }
        let cap = settings.transferCap
        let used = ledger.total(cap.kind, days: cap.periodDays, endingOn: now)
        let reached = cap.isEnabled && used >= cap.bytes
        if reached != capReached {
            capReached = reached
            let message = reached
                ? "Transfer cap reached (\(Format.bytes(used)) of \(Format.bytes(cap.bytes))); transfers stopped."
                : "Below the transfer cap again; transfers resumed."
            model.log(LogEntry(torrentID: nil, level: reached ? .warning : .info, message: message))
            if reached { Notifier.post(title: "Transfer cap reached", body: "Freshet stopped all transfers.") }
        }
    }

    var capUsage: Int64 {
        let cap = settings.transferCap
        return ledger.total(cap.kind, days: cap.periodDays, endingOn: Date())
    }

    func resetUsage() {
        ledger = UsageLedger()
        saveLedger(force: true)
        settingsChanged()
    }

    private func recordUsage(now: Date) {
        let session = model.session
        let totals = (download: session.totalDownload, upload: session.totalUpload)
        defer { lastTotals = totals }
        guard let last = lastTotals else { return }
        // The counters restart from zero when the engine restarts.
        let down = totals.download >= last.download ? totals.download - last.download : totals.download
        let up = totals.upload >= last.upload ? totals.upload - last.upload : totals.upload
        guard down > 0 || up > 0 else { return }
        ledger.record(download: down, upload: up, on: now)
        ledgerDirty = true
    }

    // MARK: Seeding goals and per-torrent limits

    private func checkSeedingGoals() {
        var stop: [TorrentID] = []
        var changed = false
        for torrent in model.torrents.values where torrent.isComplete && !torrent.isPaused {
            var value = meta[torrent.id] ?? TorrentMeta()
            guard !value.goalHandled else { continue }
            let goal = value.goal ?? settings.seedingGoal
            guard goal.isReached(by: torrent) else { continue }
            value.goalHandled = true
            meta[torrent.id] = value
            changed = true
            if settings.seedingGoalAction == .stop {
                stop.append(torrent.id)
                model.log(LogEntry(torrentID: torrent.id, level: .info, message: "Seeding goal reached; stopped"))
            } else {
                model.log(LogEntry(torrentID: torrent.id, level: .info, message: "Seeding goal reached; upload limited"))
            }
        }
        if changed { saveMeta() }
        if !stop.isEmpty { Task { await model.engine.perform(.pause, on: stop) } }
    }

    /// Sets each torrent's engine limits to the strictest of: its own limits, its bandwidth
    /// priority share of the global limit, and the post-goal upload rate.
    func applyTorrentLimits(force: Set<TorrentID>) {
        let s = effective(settings.engineSettings)
        let torrents = Array(model.torrents.values)
        let downShares = torrents.map {
            BandwidthAllocator.Share(id: $0.id, priority: meta(for: $0.id).priority, isActive: !$0.isPaused && !$0.isComplete)
        }
        let upShares = torrents.map {
            BandwidthAllocator.Share(id: $0.id, priority: meta(for: $0.id).priority, isActive: !$0.isPaused && ($0.uploadRate > 0 || $0.isComplete))
        }
        let downSplit = BandwidthAllocator.split(limit: s.downloadLimit, among: downShares)
        let upSplit = BandwidthAllocator.split(limit: s.uploadLimit, among: upShares)
        let goalLimit = settings.seedingGoalAction == .limitUpload ? max(0, settings.seedingGoalUploadKBps) * 1_024 : 0
        for torrent in torrents {
            let m = meta(for: torrent.id)
            let down = Self.strictest([m.downloadLimit, downSplit[torrent.id] ?? 0])
            let up = Self.strictest([m.uploadLimit, upSplit[torrent.id] ?? 0, m.goalHandled ? goalLimit : 0])
            let wanted = [down, up]
            guard appliedLimits[torrent.id] != wanted || force.contains(torrent.id) else { continue }
            appliedLimits[torrent.id] = wanted
            let id = torrent.id
            Task {
                guard var properties = await model.engine.properties(for: id) else { return }
                guard properties.downloadLimit != down || properties.uploadLimit != up else { return }
                properties.downloadLimit = down
                properties.uploadLimit = up
                await model.engine.setProperties(properties, for: id)
            }
        }
    }

    private static func strictest(_ limits: [Int]) -> Int {
        limits.filter { $0 > 0 }.min() ?? 0
    }

    // MARK: Torrent events

    /// After a torrent is added: per-torrent defaults and the .torrent copy.
    func onAdded(_ id: TorrentID, name: String) {
        let connections = max(0, settings.maxConnectionsPerTorrent)
        let slots = max(0, settings.uploadSlotsPerTorrent)
        if connections > 0 || slots > 0 {
            Task {
                guard var properties = await model.engine.properties(for: id) else { return }
                properties.maxConnections = connections
                properties.maxUploads = slots
                await model.engine.setProperties(properties, for: id)
            }
        }
        saveTorrentCopy(id, name: name)
    }

    func onMetadata(_ id: TorrentID) {
        saveTorrentCopy(id, name: nil)
    }

    func onFinished(_ id: TorrentID) {
        guard let torrent = model.torrents[id] else { return }
        if settings.moveCompleted, !settings.completedFolder.isEmpty {
            let from = Self.standardized(torrent.savePath)
            if !settings.moveOnlyFromDefaultFolder || from == Self.standardized(settings.downloadFolder) {
                var target = URL(fileURLWithPath: settings.completedFolder, isDirectory: true)
                if settings.appendLabelToPath, let label = model.labels.assignments[id], !label.isEmpty {
                    target.appendPathComponent(Self.safeName(label), isDirectory: true)
                }
                if Self.standardized(target.path) != from {
                    do {
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                        let path = target.path
                        Task { await model.engine.moveStorage(of: id, to: path) }
                    } catch {
                        model.log(LogEntry(torrentID: id, level: .error, message: "Couldn't create \(target.path): \(error.localizedDescription)"))
                    }
                }
            }
        }
        if settings.moveTorrentCopiesWhenFinished, !settings.finishedTorrentsFolder.isEmpty,
           let copy = meta(for: id).torrentCopy, FileManager.default.fileExists(atPath: copy) {
            let folder = URL(fileURLWithPath: settings.finishedTorrentsFolder, isDirectory: true)
            let destination = Self.unique(folder.appendingPathComponent((copy as NSString).lastPathComponent))
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(atPath: copy, toPath: destination.path)
                update([id]) { $0.torrentCopy = destination.path }
            } catch {
                model.log(LogEntry(torrentID: id, level: .error, message: "Couldn't move the .torrent copy: \(error.localizedDescription)"))
            }
        }
    }

    private func saveTorrentCopy(_ id: TorrentID, name fallbackName: String?) {
        guard settings.keepTorrentCopies, !settings.torrentCopiesFolder.isEmpty, meta(for: id).torrentCopy == nil else { return }
        let folder = URL(fileURLWithPath: settings.torrentCopiesFolder, isDirectory: true)
        let name = Self.safeName(model.torrents[id]?.name.isEmpty == false ? model.torrents[id]!.name : (fallbackName ?? id))
        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = Self.unique(folder.appendingPathComponent(name + ".torrent"))
                try await model.engine.exportTorrent(id, to: destination)
                update([id]) { $0.torrentCopy = destination.path }
            } catch {
                // Magnets have no metadata yet; the copy is made when it arrives.
                if fallbackName == nil || model.torrents[id]?.hasMetadata == true {
                    model.log(LogEntry(torrentID: id, level: .warning, message: "Couldn't keep a copy of the .torrent: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: Files

    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "torrent" : String(cleaned.prefix(200))
    }

    static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func unique(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for n in 2...999 {
            let candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private func saveMeta() {
        Self.save(meta, to: metaURL)
    }

    private func saveLedger(force: Bool = false) {
        guard ledgerDirty || force else { return }
        ledger.prune(keepDays: 400, now: Date())
        Self.save(ledger, to: ledgerURL)
        ledgerDirty = false
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {}
    }
}
