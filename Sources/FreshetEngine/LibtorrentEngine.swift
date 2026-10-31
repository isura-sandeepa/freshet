import Foundation
import FreshetCore
import LTShim

/// Drives libtorrent through the C shim. Every call into the shim happens on this actor,
/// so the shim never sees concurrent access. A poll loop pumps libtorrent's alerts into
/// `events`, and resume data is saved every `resumeSaveInterval` seconds so a crash
/// loses at most that much progress.
public actor LibtorrentEngine: EngineService {
    public nonisolated let events: AsyncStream<EngineEvent>
    private let continuation: AsyncStream<EngineEvent>.Continuation
    private let stateDirectory: URL
    private let pollInterval: TimeInterval
    private let resumeSaveInterval: TimeInterval
    private var settings: EngineSettings
    private var session: OpaquePointer?
    private var pollTask: Task<Void, Never>?
    private var lastResumeSave = Date()

    public static var libtorrentVersion: String { String(cString: lt_version()) }

    public init(stateDirectory: URL, settings: EngineSettings, pollInterval: TimeInterval = 0.5,
                resumeSaveInterval: TimeInterval = 30) {
        var captured: AsyncStream<EngineEvent>.Continuation?
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(10_000)) { captured = $0 }
        self.continuation = captured!
        self.stateDirectory = stateDirectory
        self.settings = settings
        self.pollInterval = pollInterval
        self.resumeSaveInterval = resumeSaveInterval
    }

    // MARK: Lifecycle

    public func start() async throws {
        guard session == nil else { return }
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let path = stateDirectory.path
        let created: OpaquePointer? = Self.withCSettings(settings) { lt_session_create($0, path) }
        guard let created else { throw EngineError.sessionFailed }
        session = created
        applyExtras(settings, to: created)
        let restored = Int(lt_session_load_resume(created))
        continuation.yield(.loaded(restored))
        lastResumeSave = Date()
        let nanoseconds = UInt64(max(0.05, pollInterval) * 1_000_000_000)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    public func shutdown() async {
        pollTask?.cancel()
        pollTask = nil
        if let session {
            self.session = nil
            lt_session_destroy(session, 8_000)
        }
        continuation.finish()
    }

    public func apply(settings newSettings: EngineSettings) async {
        settings = newSettings
        guard let session else { return }
        Self.withCSettings(newSettings) { lt_session_apply_settings(session, $0) }
        applyExtras(newSettings, to: session)
    }

    /// Named libtorrent settings, the incomplete-file suffix and the session pause.
    private func applyExtras(_ s: EngineSettings, to session: OpaquePointer) {
        lt_session_set_incomplete_suffix(session, s.incompleteSuffix)
        lt_session_set_paused(session, s.sessionPaused)
        guard !s.named.isEmpty else { return }
        let entries = s.named.sorted { $0.key < $1.key }
        let names = entries.map { strdup($0.key) }
        let values = entries.map { strdup($0.value) }
        defer {
            names.forEach { free($0) }
            values.forEach { free($0) }
        }
        var pairs = zip(names, values).map { lt_setting_pair(name: UnsafePointer($0), value: UnsafePointer($1)) }
        var error = [CChar](repeating: 0, count: 1_024)
        let errorLength = error.count
        _ = lt_session_apply_named(session, &pairs, Int32(pairs.count), &error, errorLength)
        let message = Self.string(from: error, fallback: "")
        if !message.isEmpty {
            continuation.yield(.log(LogEntry(torrentID: nil, level: .warning, message: "Settings: \(message)")))
        }
    }

    // MARK: Adding

    public func preview(_ source: AddSource) async throws -> TorrentPreview {
        let sink = PreviewSink()
        let context = Unmanaged.passUnretained(sink).toOpaque()
        let infoCallback: lt_info_cb = { context, info in
            guard let context, let info else { return }
            PreviewSink.from(context).info = TorrentInfo(info.pointee)
        }
        let fileCallback: lt_file_cb = { context, file in
            guard let context, let file else { return }
            PreviewSink.from(context).files.append(FileEntry(file.pointee))
        }
        var error = [CChar](repeating: 0, count: 512)
        let errorLength = error.count
        let ok: Bool = withExtendedLifetime(sink) {
            switch source {
            case .file(let url):
                return lt_inspect_torrent(url.path, nil, 0, infoCallback, fileCallback, context, &error, errorLength)
            case .data(let data, _):
                return data.withUnsafeBytes { raw in
                    lt_inspect_torrent(nil, raw.baseAddress?.assumingMemoryBound(to: CChar.self), raw.count,
                                       infoCallback, fileCallback, context, &error, errorLength)
                }
            case .magnet(let uri):
                return lt_inspect_magnet(uri, infoCallback, context, &error, errorLength)
            }
        }
        guard ok, let info = sink.info else {
            throw EngineError.invalidTorrent(Self.string(from: error, fallback: "This isn't a valid torrent or magnet link."))
        }
        var isMagnet = false
        if case .magnet = source { isMagnet = true }
        var name = info.name
        if name.isEmpty, case .data(_, let suggested) = source, let suggested {
            name = (suggested as NSString).deletingPathExtension
        }
        if name.isEmpty { name = info.infoHashV1.isEmpty ? info.infoHashV2 : info.infoHashV1 }
        let total = info.hasMetadata ? info.totalSize : sink.files.reduce(Int64(0)) { $0 + $1.size }
        return TorrentPreview(name: name, infoHashV1: info.infoHashV1, infoHashV2: info.infoHashV2, totalSize: total,
                              files: sink.files, comment: info.comment, isPrivate: info.isPrivate, isMagnet: isMagnet)
    }

    public func add(_ request: AddRequest) async throws -> AddResult {
        guard let session else { throw EngineError.notRunning }
        var idBuffer = [CChar](repeating: 0, count: 128)
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let idLength = idBuffer.count
        let errorLength = errorBuffer.count
        let priorities = (request.filePriorities ?? []).map { Int32(clamping: $0) }
        let code: Int32 = request.savePath.withCString { savePath in
            priorities.withUnsafeBufferPointer { priorityBuffer in
                var params = lt_add_params()
                params.save_path = savePath
                params.start = request.start
                params.skip_hash_check = request.skipHashCheck
                params.file_priorities = priorities.isEmpty ? nil : priorityBuffer.baseAddress
                params.file_priority_count = Int32(priorities.count)
                params.preallocate = request.preallocate
                switch request.source {
                case .file(let url):
                    return lt_add_torrent_file(session, url.path, &params, &idBuffer, idLength, &errorBuffer, errorLength)
                case .data(let data, _):
                    return data.withUnsafeBytes { raw in
                        lt_add_torrent_data(session, raw.baseAddress?.assumingMemoryBound(to: CChar.self), raw.count,
                                            &params, &idBuffer, idLength, &errorBuffer, errorLength)
                    }
                case .magnet(let uri):
                    return lt_add_magnet(session, uri, &params, &idBuffer, idLength, &errorBuffer, errorLength)
                }
            }
        }
        let id = Self.string(from: idBuffer, fallback: "")
        switch code {
        case LT_ADD_OK: return .added(id)
        case LT_ADD_DUPLICATE: return .duplicate(id)
        default: throw EngineError.addFailed(Self.string(from: errorBuffer, fallback: "libtorrent couldn't add this torrent."))
        }
    }

    // MARK: Commands

    public func perform(_ action: TorrentAction, on ids: [TorrentID]) async {
        guard let session else { return }
        let code: Int32
        switch action {
        case .start: code = LT_ACTION_START
        case .pause: code = LT_ACTION_PAUSE
        case .forceStart: code = LT_ACTION_FORCE_START
        case .recheck: code = LT_ACTION_RECHECK
        case .reannounce: code = LT_ACTION_REANNOUNCE
        case .queueUp: code = LT_ACTION_QUEUE_UP
        case .queueDown: code = LT_ACTION_QUEUE_DOWN
        case .queueTop: code = LT_ACTION_QUEUE_TOP
        case .queueBottom: code = LT_ACTION_QUEUE_BOTTOM
        }
        for id in ids { _ = lt_torrent_action(session, id, code) }
    }

    public func remove(_ ids: [TorrentID]) async {
        guard let session else { return }
        for id in ids where lt_torrent_remove(session, id) {
            continuation.yield(.removed(id))
        }
    }

    public func setFilePriority(_ priority: FilePriority, files: [Int], in id: TorrentID) async {
        guard let session, !files.isEmpty else { return }
        let indexes = files.map { Int32(clamping: $0) }
        indexes.withUnsafeBufferPointer { buffer in
            _ = lt_torrent_set_file_priority(session, id, buffer.baseAddress, Int32(buffer.count), Int32(priority.rawValue))
        }
    }

    // MARK: Queries

    public func details(for id: TorrentID) async -> TorrentDetails? {
        guard let session else { return nil }
        let sink = DetailSink()
        let context = Unmanaged.passUnretained(sink).toOpaque()
        let found: Bool = withExtendedLifetime(sink) {
            let ok = lt_torrent_info_query(session, id, { context, info in
                guard let context, let info else { return }
                DetailSink.from(context).info = TorrentInfo(info.pointee)
            }, context)
            _ = lt_torrent_files(session, id, { context, file in
                guard let context, let file else { return }
                DetailSink.from(context).files.append(FileEntry(file.pointee))
            }, context)
            _ = lt_torrent_peers(session, id, { context, peer in
                guard let context, let peer else { return }
                DetailSink.from(context).peers.append(PeerEntry(peer.pointee))
            }, context)
            _ = lt_torrent_trackers(session, id, { context, tracker in
                guard let context, let tracker else { return }
                DetailSink.from(context).trackers.append(TrackerEntry(tracker.pointee))
            }, context)
            return ok
        }
        guard found else { return nil }
        return TorrentDetails(info: sink.info, files: sink.files, peers: sink.peers, trackers: sink.trackers)
    }

    public func magnetLink(for id: TorrentID) async -> String? {
        guard let session, let pointer = lt_torrent_magnet(session, id) else { return nil }
        defer { lt_free(pointer) }
        return String(cString: pointer)
    }

    // MARK: Phase 2

    public func properties(for id: TorrentID) async -> TorrentProperties? {
        guard let session else { return nil }
        var c = lt_torrent_props()
        guard lt_torrent_get_props(session, id, &c) else { return nil }
        var p = TorrentProperties()
        p.downloadLimit = Int(c.download_limit)
        p.uploadLimit = Int(c.upload_limit)
        p.maxConnections = Int(c.max_connections)
        p.maxUploads = Int(c.max_uploads)
        p.disableDHT = c.disable_dht
        p.disablePEX = c.disable_pex
        p.disableLSD = c.disable_lsd
        p.superSeeding = c.super_seeding
        p.sequential = c.sequential
        return p
    }

    public func setProperties(_ p: TorrentProperties, for id: TorrentID) async {
        guard let session else { return }
        var c = lt_torrent_props()
        c.download_limit = Int32(clamping: p.downloadLimit)
        c.upload_limit = Int32(clamping: p.uploadLimit)
        c.max_connections = Int32(clamping: p.maxConnections)
        c.max_uploads = Int32(clamping: p.maxUploads)
        c.disable_dht = p.disableDHT
        c.disable_pex = p.disablePEX
        c.disable_lsd = p.disableLSD
        c.super_seeding = p.superSeeding
        c.sequential = p.sequential
        _ = lt_torrent_set_props(session, id, &c)
    }

    public func setTrackers(_ trackers: [TrackerEdit], for id: TorrentID) async {
        guard let session else { return }
        let urls = trackers.map { strdup($0.url) }
        defer { urls.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = urls.map { UnsafePointer($0) }
        let tiers = trackers.map { Int32(clamping: $0.tier) }
        pointers.withUnsafeBufferPointer { urlBuffer in
            tiers.withUnsafeBufferPointer { tierBuffer in
                _ = lt_torrent_set_trackers(session, id, urlBuffer.baseAddress, tierBuffer.baseAddress, Int32(trackers.count))
            }
        }
    }

    public func addPeer(_ address: PeerAddress, to id: TorrentID) async -> Bool {
        guard let session else { return false }
        return lt_torrent_add_peer(session, id, address.ip, Int32(address.port))
    }

    public func clearPeers(of id: TorrentID) async {
        guard let session else { return }
        _ = lt_torrent_clear_peers(session, id)
    }

    public func moveStorage(of id: TorrentID, to path: String) async {
        guard let session else { return }
        if !lt_torrent_move_storage(session, id, path) {
            continuation.yield(.moved(id, path: path, error: "The torrent isn't in the list any more."))
        }
    }

    public func exportTorrent(_ id: TorrentID, to url: URL) async throws {
        guard let session else { throw EngineError.notRunning }
        var error = [CChar](repeating: 0, count: 512)
        let errorLength = error.count
        guard lt_torrent_export(session, id, url.path, &error, errorLength) else {
            throw EngineError.operationFailed(Self.string(from: error, fallback: "Couldn't save the .torrent file."))
        }
    }

    public func advancedSettings() async -> [AdvancedSetting] {
        guard let session else { return [] }
        let sink = SettingsSink()
        withExtendedLifetime(sink) {
            lt_session_list_settings(session, { context, info in
                guard let context, let info else { return }
                let i = info.pointee
                SettingsSink.from(context).items.append(
                    AdvancedSetting(name: String(cString: i.name), kind: AdvancedSetting.Kind(rawValue: Int(i.type)) ?? .text,
                                    value: String(cString: i.value), defaultValue: String(cString: i.default_value)))
            }, Unmanaged.passUnretained(sink).toOpaque())
        }
        return sink.items.sorted { $0.name < $1.name }
    }

    public func loadIPFilter(path: String?) async throws -> Int {
        guard let session else { throw EngineError.notRunning }
        var error = [CChar](repeating: 0, count: 512)
        let errorLength = error.count
        let count = Int(lt_session_load_ip_filter(session, path, &error, errorLength))
        if count < 0 { throw EngineError.operationFailed(Self.string(from: error, fallback: "Couldn't load the IP filter.")) }
        return count
    }

    // MARK: Polling

    private func tick() {
        guard let session else { return }
        let sink = PollSink()
        var callbacks = lt_callbacks()
        callbacks.on_status = { context, status in
            guard let context, let status else { return }
            PollSink.from(context).statuses.append(TorrentSnapshot(status.pointee))
        }
        callbacks.on_removed = { context, id in
            guard let context, let id else { return }
            PollSink.from(context).removed.append(String(cString: id))
        }
        callbacks.on_finished = { context, id in
            guard let context, let id else { return }
            PollSink.from(context).finished.append(String(cString: id))
        }
        callbacks.on_metadata = { context, id in
            guard let context, let id else { return }
            PollSink.from(context).metadata.append(String(cString: id))
        }
        callbacks.on_log = { context, id, level, message in
            guard let context, let message else { return }
            let torrent = id.map { String(cString: $0) }
            PollSink.from(context).logs.append(LogEntry(torrentID: (torrent?.isEmpty ?? true) ? nil : torrent,
                                                        level: LogLevel(rawValue: Int(level)) ?? .info,
                                                        message: String(cString: message)))
        }
        callbacks.on_session = { context, stats in
            guard let context, let stats else { return }
            let c = stats.pointee
            var snapshot = SessionSnapshot(dhtNodes: Int(c.dht_nodes), listenPort: Int(c.listen_port), isListening: c.listening)
            snapshot.totalDownload = c.total_download
            snapshot.totalUpload = c.total_upload
            snapshot.incomingConnections = c.incoming_connections
            snapshot.portMapped = c.port_mapped
            snapshot.externalPort = Int(c.external_port)
            snapshot.isPaused = c.paused
            PollSink.from(context).session = snapshot
        }
        callbacks.on_moved = { context, id, path, error in
            guard let context, let id else { return }
            let message = error.map { String(cString: $0) } ?? ""
            PollSink.from(context).moved.append((String(cString: id), path.map { String(cString: $0) } ?? "",
                                                  message.isEmpty ? nil : message))
        }
        withExtendedLifetime(sink) {
            lt_session_poll(session, &callbacks, Unmanaged.passUnretained(sink).toOpaque())
        }
        sink.flush(into: continuation)
        if Date().timeIntervalSince(lastResumeSave) >= resumeSaveInterval {
            lastResumeSave = Date()
            lt_session_save_resume(session, true)
        }
    }

    // MARK: Helpers

    private static func withCSettings<Result>(_ s: EngineSettings, _ body: (UnsafePointer<lt_settings>) -> Result) -> Result {
        let interface = s.listenInterface.trimmingCharacters(in: .whitespaces)
        let listenSpec: String
        if interface.isEmpty {
            listenSpec = "0.0.0.0:\(s.listenPort),[::]:\(s.listenPort)"
        } else if interface.contains(":") && !interface.hasPrefix("[") {
            listenSpec = "[\(interface)]:\(s.listenPort)"
        } else {
            listenSpec = "\(interface):\(s.listenPort)"
        }
        let listen = strdup(listenSpec)
        let agent = strdup("Freshet/0.1 libtorrent/\(String(cString: lt_version()))")
        let fingerprint = strdup("-FR0010-")
        defer {
            free(listen)
            free(agent)
            free(fingerprint)
        }
        var c = lt_settings()
        c.listen_interfaces = UnsafePointer(listen)
        c.user_agent = UnsafePointer(agent)
        c.peer_fingerprint = UnsafePointer(fingerprint)
        c.download_rate_limit = Int32(clamping: s.downloadLimit)
        c.upload_rate_limit = Int32(clamping: s.uploadLimit)
        c.connections_limit = Int32(clamping: s.maxConnections)
        c.active_downloads = Int32(clamping: s.maxActiveDownloads)
        c.active_seeds = Int32(clamping: s.maxActiveTorrents)
        c.active_limit = Int32(clamping: s.maxActiveTorrents)
        c.enable_dht = s.enableDHT
        c.enable_lsd = s.enableLSD
        c.enable_upnp = s.enableUPnP
        c.enable_natpmp = s.enableNATPMP
        return withUnsafePointer(to: &c) { body($0) }
    }

    private static func string(from buffer: [CChar], fallback: String) -> String {
        let text = buffer.withUnsafeBufferPointer { pointer -> String in
            guard let base = pointer.baseAddress else { return "" }
            return String(cString: base)
        }
        return text.isEmpty ? fallback : text
    }
}

/// Collects one poll's worth of callbacks, then turns them into events.
private final class PollSink {
    var statuses: [TorrentSnapshot] = []
    var removed: [TorrentID] = []
    var finished: [TorrentID] = []
    var metadata: [TorrentID] = []
    var logs: [LogEntry] = []
    var moved: [(TorrentID, String, String?)] = []
    var session: SessionSnapshot?

    static func from(_ pointer: UnsafeMutableRawPointer) -> PollSink {
        Unmanaged<PollSink>.fromOpaque(pointer).takeUnretainedValue()
    }

    func flush(into continuation: AsyncStream<EngineEvent>.Continuation) {
        if !statuses.isEmpty { continuation.yield(.statuses(statuses)) }
        for id in metadata { continuation.yield(.metadataReceived(id)) }
        for id in finished { continuation.yield(.finished(id)) }
        for id in removed { continuation.yield(.removed(id)) }
        for entry in logs { continuation.yield(.log(entry)) }
        for (id, path, error) in moved { continuation.yield(.moved(id, path: path, error: error)) }
        if let session { continuation.yield(.session(session)) }
    }
}

private final class DetailSink {
    var info: TorrentInfo?
    var files: [FileEntry] = []
    var peers: [PeerEntry] = []
    var trackers: [TrackerEntry] = []

    static func from(_ pointer: UnsafeMutableRawPointer) -> DetailSink {
        Unmanaged<DetailSink>.fromOpaque(pointer).takeUnretainedValue()
    }
}

private final class SettingsSink {
    var items: [AdvancedSetting] = []

    static func from(_ pointer: UnsafeMutableRawPointer) -> SettingsSink {
        Unmanaged<SettingsSink>.fromOpaque(pointer).takeUnretainedValue()
    }
}

private final class PreviewSink {
    var info: TorrentInfo?
    var files: [FileEntry] = []

    static func from(_ pointer: UnsafeMutableRawPointer) -> PreviewSink {
        Unmanaged<PreviewSink>.fromOpaque(pointer).takeUnretainedValue()
    }
}
