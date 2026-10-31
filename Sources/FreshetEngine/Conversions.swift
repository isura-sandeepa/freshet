import Foundation
import FreshetCore
import LTShim

// Copies from the shim's C structs into Swift values. The C strings are only valid
// during the callback, so everything is copied here.

extension TorrentSnapshot {
    init(_ s: lt_torrent_status) {
        self.init(id: String(cString: s.id))
        name = String(cString: s.name)
        savePath = String(cString: s.save_path)
        currentTracker = String(cString: s.current_tracker)
        let error = String(cString: s.error)
        errorMessage = error.isEmpty ? nil : error
        libtorrentState = Int(s.state)
        isPaused = s.paused
        isAutoManaged = s.auto_managed
        hasMetadata = s.has_metadata
        isSeeding = s.is_seeding
        isFinished = s.is_finished
        hasIncoming = s.has_incoming
        isMovingStorage = s.moving_storage
        progress = Double(s.progress)
        totalWanted = s.total_wanted
        totalWantedDone = s.total_wanted_done
        allTimeDownload = s.all_time_download
        allTimeUpload = s.all_time_upload
        downloadRate = Int(s.download_rate)
        uploadRate = Int(s.upload_rate)
        connectedSeeds = Int(s.num_seeds)
        connectedPeers = Int(s.num_peers)
        swarmSeeds = Int(s.num_complete)
        swarmPeers = Int(s.num_incomplete)
        availability = Double(s.distributed_copies)
        queuePosition = Int(s.queue_position)
        addedDate = s.added_time > 0 ? Date(timeIntervalSince1970: TimeInterval(s.added_time)) : nil
        completedDate = s.completed_time > 0 ? Date(timeIntervalSince1970: TimeInterval(s.completed_time)) : nil
        activeSeconds = s.active_seconds
        seedingSeconds = s.seeding_seconds
        piecesHave = Int(s.num_pieces)
    }
}

extension TorrentInfo {
    init(_ i: lt_torrent_info) {
        self.init(name: String(cString: i.name),
                  comment: String(cString: i.comment),
                  creator: String(cString: i.creator),
                  infoHashV1: String(cString: i.info_hash_v1),
                  infoHashV2: String(cString: i.info_hash_v2),
                  totalSize: i.total_size,
                  creationDate: i.creation_date > 0 ? Date(timeIntervalSince1970: TimeInterval(i.creation_date)) : nil,
                  pieceLength: Int(i.piece_length),
                  pieceCount: Int(i.num_pieces),
                  fileCount: Int(i.num_files),
                  isPrivate: i.is_private,
                  hasMetadata: i.has_metadata)
    }
}

extension FileEntry {
    init(_ f: lt_file_entry) {
        self.init(index: Int(f.index), path: String(cString: f.path), size: f.size, downloaded: f.downloaded,
                  priority: FilePriority(libtorrentValue: Int(f.priority)))
    }
}

extension PeerEntry {
    init(_ p: lt_peer_entry) {
        self.init(ip: String(cString: p.ip), port: Int(p.port), client: String(cString: p.client),
                  flags: String(cString: p.flags), progress: Double(p.progress), downloadRate: Int(p.download_rate),
                  uploadRate: Int(p.upload_rate), totalDownload: p.total_download, totalUpload: p.total_upload,
                  isSeed: p.is_seed)
    }
}

extension TrackerEntry {
    init(_ t: lt_tracker_entry) {
        self.init(url: String(cString: t.url), message: String(cString: t.message), tier: Int(t.tier),
                  status: TrackerStatus(rawValue: Int(t.status)) ?? .idle, seeds: Int(t.seeds), peers: Int(t.peers),
                  downloaded: Int(t.downloaded), nextAnnounce: Int(t.next_announce_seconds))
    }
}
