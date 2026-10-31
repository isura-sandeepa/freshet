import Foundation
import FreshetCore
import LTShim

/// Makes .torrent files with libtorrent's creator. Hashing runs on a background thread; it
/// doesn't need a running session.
public enum TorrentCreator {
    public final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var _done = 0
        private var _total = 0
        private var _cancelled = false

        public init() {}

        public var fraction: Double {
            lock.lock(); defer { lock.unlock() }
            return _total > 0 ? Double(_done) / Double(_total) : 0
        }

        public func cancel() {
            lock.lock(); _cancelled = true; lock.unlock()
        }

        fileprivate func update(done: Int, total: Int) -> Bool {
            lock.lock(); defer { lock.unlock() }
            _done = done
            _total = total
            return !_cancelled
        }
    }

    /// Writes the torrent to `output` and returns the id the engine will give it.
    public static func create(_ request: CreateTorrentRequest, output: URL, progress: Progress) async throws -> TorrentID {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try run(request, output: output, progress: progress) })
            }
        }
    }

    private static func run(_ r: CreateTorrentRequest, output: URL, progress: Progress) throws -> TorrentID {
        var id = [CChar](repeating: 0, count: 96)
        var error = [CChar](repeating: 0, count: 512)
        let idLength = id.count
        let errorLength = error.count
        let context = Unmanaged.passUnretained(progress).toOpaque()
        let code: Int32 = withExtendedLifetime(progress) {
            r.source.path.withCString { source in
                r.trackers.withCString { trackers in
                    r.webSeeds.withCString { seeds in
                        r.comment.withCString { comment in
                            r.skipPatterns.withCString { skip in
                                var p = lt_create_params()
                                p.source_path = source
                                p.trackers = trackers
                                p.web_seeds = seeds
                                p.comment = comment
                                p.creator = nil
                                p.skip_patterns = skip
                                p.piece_size = Int32(clamping: r.pieceSize)
                                p.format = Int32(r.format.rawValue)
                                p.is_private = r.isPrivate
                                return lt_create_torrent(&p, output.path, { context, done, total in
                                    guard let context else { return true }
                                    return Unmanaged<Progress>.fromOpaque(context).takeUnretainedValue()
                                        .update(done: Int(done), total: Int(total))
                                }, context, &id, idLength, &error, errorLength)
                            }
                        }
                    }
                }
            }
        }
        let message = error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        switch code {
        case 0: return id.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        case -2: throw CancellationError()
        default: throw EngineError.operationFailed(message.isEmpty ? "Couldn't create the torrent." : message)
        }
    }
}
