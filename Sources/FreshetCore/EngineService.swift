import Foundation

/// Everything the app needs from a torrent engine. Implemented by the libtorrent-backed
/// engine and by the simulated engine used for UI work and tests.
public protocol EngineService: AnyObject, Sendable {
    /// Batched state changes, removals, completions, log lines and session stats.
    var events: AsyncStream<EngineEvent> { get }

    func start() async throws
    /// Saves resume data for every torrent, then stops the engine.
    func shutdown() async
    func apply(settings: EngineSettings) async

    /// Reads a .torrent or magnet link without adding it.
    func preview(_ source: AddSource) async throws -> TorrentPreview
    func add(_ request: AddRequest) async throws -> AddResult
    func perform(_ action: TorrentAction, on ids: [TorrentID]) async
    /// Removes torrents from the session. Files on disk are left alone.
    func remove(_ ids: [TorrentID]) async
    func setFilePriority(_ priority: FilePriority, files: [Int], in id: TorrentID) async
    func details(for id: TorrentID) async -> TorrentDetails?
    func magnetLink(for id: TorrentID) async -> String?

    // Phase 2
    func properties(for id: TorrentID) async -> TorrentProperties?
    func setProperties(_ properties: TorrentProperties, for id: TorrentID) async
    func setTrackers(_ trackers: [TrackerEdit], for id: TorrentID) async
    func addPeer(_ address: PeerAddress, to id: TorrentID) async -> Bool
    func clearPeers(of id: TorrentID) async
    /// Moves the torrent's files; the outcome arrives as `.moved`.
    func moveStorage(of id: TorrentID, to path: String) async
    /// Writes a .torrent file for the torrent (needs metadata).
    func exportTorrent(_ id: TorrentID, to url: URL) async throws
    /// Every libtorrent setting with its current and default value.
    func advancedSettings() async -> [AdvancedSetting]
    /// Loads a DAT or P2P range file into the IP filter; nil clears it. Returns the number of ranges.
    func loadIPFilter(path: String?) async throws -> Int
}
