import Foundation
import FreshetCore
import FreshetEngine

// freshet-smoke: end-to-end check of the libtorrent engine without the UI.
//
//   freshet-smoke [--root DIR] [--seconds N] [--kill] [--expect-resume] [magnet | URL | .torrent path]
//
// --kill           ends the run with SIGKILL instead of a clean shutdown (simulates a crash)
// --expect-resume  requires torrents to come back from resume data with progress intact

setvbuf(stdout, nil, _IOLBF, 0)

struct Options {
    var root = "/tmp/freshet-smoke"
    var seconds = 45
    var kill = false
    var expectResume = false
    var source = "https://webtorrent.io/torrents/sintel.torrent"
}

var options = Options()
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--root": options.root = arguments.popFirst() ?? options.root
    case "--seconds": options.seconds = Int(arguments.popFirst() ?? "") ?? options.seconds
    case "--kill": options.kill = true
    case "--expect-resume": options.expectResume = true
    default: options.source = argument
    }
}

let sintelMagnet = "magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10&dn=Sintel"
    + "&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=udp%3A%2F%2Fexplodie.org%3A6969"
    + "&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F"

/// Collects engine events from the event task so the main flow can read them.
actor Observed {
    var restored = -1
    var latest: [TorrentID: TorrentSnapshot] = [:]
    /// First status per torrent once libtorrent has finished loading it (past checking resume data).
    var settled: [TorrentID: TorrentSnapshot] = [:]
    var sawFullRecheck = false
    var dhtNodes = 0
    var listenPort = 0
    var finished = false
    var metadata = false

    func record(_ event: EngineEvent) {
        switch event {
        case .loaded(let count): restored = count
        case .statuses(let list):
            for snapshot in list {
                latest[snapshot.id] = snapshot
                let state = snapshot.libtorrentState
                if state == TorrentSnapshot.stateCheckingFiles { sawFullRecheck = true }
                let loading = state == 0 || state == TorrentSnapshot.stateCheckingResume || state == TorrentSnapshot.stateCheckingFiles
                if settled[snapshot.id] == nil, !loading { settled[snapshot.id] = snapshot }
            }
        case .session(let session):
            dhtNodes = session.dhtNodes
            listenPort = session.listenPort
        case .finished: finished = true
        case .metadataReceived: metadata = true
        case .log(let entry):
            if entry.level >= .warning { print("  log: \(entry.message)") }
        case .removed, .moved: break
        }
    }

    func summary() -> (restored: Int, latest: [TorrentSnapshot], settled: [TorrentSnapshot], recheck: Bool, dht: Int, port: Int, metadata: Bool) {
        (restored, Array(latest.values), Array(settled.values), sawFullRecheck, dhtNodes, listenPort, metadata)
    }
}

let root = URL(fileURLWithPath: options.root)
let stateDirectory = root.appendingPathComponent("state")
// Run 1 (--kill) logs its progress every 5 s here; run 2 (--expect-resume) checks against it.
let progressLog = root.appendingPathComponent("progress.log")
let resumeSaveInterval = 10
let downloads = root.appendingPathComponent("downloads")
try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

print("libtorrent \(LibtorrentEngine.libtorrentVersion)")
let engine = LibtorrentEngine(stateDirectory: stateDirectory, settings: EngineSettings(listenPort: 6_891),
                              pollInterval: 0.5, resumeSaveInterval: TimeInterval(resumeSaveInterval))
let observed = Observed()
let eventTask = Task {
    for await event in engine.events { await observed.record(event) }
}

do {
    try await engine.start()
} catch {
    print("FAIL: engine did not start: \(error.localizedDescription)")
    exit(1)
}
try? await Task.sleep(nanoseconds: 1_500_000_000)
let restored = await observed.summary().restored
print("restored \(restored) torrent(s) from resume data")

if options.expectResume {
    guard restored > 0 else {
        print("FAIL: expected torrents restored from resume data")
        exit(1)
    }
} else if restored == 0 {
    let source: AddSource
    if options.source.hasPrefix("magnet:") {
        source = .magnet(options.source)
    } else if options.source.hasPrefix("http://") || options.source.hasPrefix("https://"), let url = URL(string: options.source) {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw EngineError.downloadFailed("HTTP \(http.statusCode)")
            }
            source = .data(data, suggestedName: url.lastPathComponent)
            print("fetched \(url.absoluteString) (\(data.count) bytes)")
        } catch {
            print("couldn't fetch \(url.absoluteString) (\(error.localizedDescription)); using the magnet link instead")
            source = .magnet(sintelMagnet)
        }
    } else {
        source = .file(URL(fileURLWithPath: options.source))
    }
    do {
        let preview = try await engine.preview(source)
        print("adding \"\(preview.name)\": \(preview.files.count) file(s), \(Format.bytes(preview.totalSize))")
        let result = try await engine.add(AddRequest(source: source, savePath: downloads.path))
        print("add result: \(result)")
    } catch {
        print("FAIL: couldn't add the torrent: \(error.localizedDescription)")
        exit(1)
    }
}

var elapsed = 0
var samples = ""
while elapsed < options.seconds {
    try? await Task.sleep(nanoseconds: 5_000_000_000)
    elapsed += 5
    let state = await observed.summary()
    if options.kill {
        samples += "\(elapsed) \(state.latest.map(\.progress).max() ?? 0)\n"
        try? samples.write(to: progressLog, atomically: true, encoding: .utf8)
    }
    for t in state.latest.sorted(by: { $0.id < $1.id }) {
        print(String(format: "[%3lds] %@ | %@ | %@ | down %@ up %@ | peers %ld seeds %ld | dht %ld | port %ld",
                     elapsed, String(t.displayName.prefix(28)), t.statusText, Format.percent(t.progress),
                     Format.rateOrZero(t.downloadRate), Format.rateOrZero(t.uploadRate), t.connectedPeers,
                     t.connectedSeeds, state.dht, state.port))
    }
}

let final = await observed.summary()
let bestProgress = final.latest.map(\.progress).max() ?? 0
var passed = bestProgress > 0 || final.metadata
if options.expectResume {
    // Resume data is saved every 10 s, so everything downloaded up to two intervals before the crash must be back.
    let logged = ((try? String(contentsOf: progressLog, encoding: .utf8)) ?? "")
        .split(separator: "\n")
        .compactMap { line -> (Int, Double)? in
            let parts = line.split(separator: " ")
            guard parts.count == 2, let seconds = Int(parts[0]), let progress = Double(parts[1]) else { return nil }
            return (seconds, progress)
        }
    let crashedAt = logged.last?.0 ?? 0
    let required = logged.last { $0.0 <= crashedAt - 2 * resumeSaveInterval }?.1 ?? 0
    let resumed = final.settled.map(\.progress).max() ?? 0
    print("progress \(2 * resumeSaveInterval) s before the crash: \(Format.percent(required)); "
        + "right after restart: \(Format.percent(resumed)); full recheck: \(final.recheck ? "yes" : "no")")
    passed = resumed > 0 && resumed + 0.0001 >= required && !final.recheck
}

if options.kill {
    print("progress before SIGKILL: \(Format.percent(bestProgress)); killing the process to simulate a crash")
    kill(getpid(), SIGKILL)
}

await engine.shutdown()
eventTask.cancel()
print(passed ? "PASS" : "FAIL: no progress")
exit(passed ? 0 : 1)
