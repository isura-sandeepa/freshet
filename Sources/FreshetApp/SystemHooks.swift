import AppKit
import FreshetCore
import IOKit.pwr_mgt

/// The parts of automation that reach outside the app: the watch folder, running a program on
/// torrent events, the when-downloads-finish action and keeping the Mac awake while transferring.
@MainActor
final class SystemHooks {
    unowned let model: AppModel
    private var assertionID: IOPMAssertionID = 0
    private var holdingAssertion = false
    private var lastStates: [TorrentID: Int] = [:]
    private var sawDownloads = false
    private var ticks = 0

    init(model: AppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.settings }

    func tick() {
        ticks += 1
        updateSleepAssertion()
        if ticks % 5 == 0 { scanWatchFolder() }
        checkWhenDone()
        checkCountdown()
    }

    func shutdown() {
        releaseAssertion()
    }

    // MARK: Run a program

    func statusesChanged(_ list: [TorrentSnapshot]) {
        let command = settings.runWhenStateChanges.trimmingCharacters(in: .whitespacesAndNewlines)
        for torrent in list {
            let code = RunCommand.stateCode(torrent)
            let previous = lastStates[torrent.id]
            lastStates[torrent.id] = code
            if let previous, previous != code, !command.isEmpty { run(command, for: torrent, previousState: previous) }
        }
    }

    func finished(_ id: TorrentID) {
        let command = settings.runWhenFinished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, let torrent = model.torrents[id] else { return }
        run(command, for: torrent, previousState: nil)
    }

    func forget(_ ids: [TorrentID]) {
        for id in ids { lastStates.removeValue(forKey: id) }
    }

    private func run(_ template: String, for torrent: TorrentSnapshot, previousState: Int?) {
        let path = (torrent.savePath as NSString).appendingPathComponent(torrent.name)
        var isDirectory: ObjCBool = false
        let multi = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        let command = RunCommand.expand(template, torrent: torrent, label: model.labels.assignments[torrent.id],
                                        isMultiFile: multi, previousState: previousState)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let id = torrent.id
        process.terminationHandler = { [weak model = self.model] finished in
            let status = finished.terminationStatus
            guard status != 0 else { return }
            Task { @MainActor in
                model?.log(LogEntry(torrentID: id, level: .warning, message: "Run program exited with status \(status)"))
            }
        }
        do {
            try process.run()
            model.log(LogEntry(torrentID: id, level: .info, message: "Ran: \(command)"))
        } catch {
            model.log(LogEntry(torrentID: id, level: .error, message: "Couldn't run the program: \(error.localizedDescription)"))
        }
    }

    // MARK: Watch folder

    private func scanWatchFolder() {
        guard settings.watchFolderEnabled, !settings.watchFolder.isEmpty else { return }
        let folder = URL(fileURLWithPath: settings.watchFolder, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                         options: [.skipsHiddenFiles]) else { return }
        for url in entries where url.pathExtension.lowercased() == "torrent" {
            // Leave files that are still being written alone for a moment.
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard Date().timeIntervalSince(modified) > 2, let data = try? Data(contentsOf: url) else { continue }
            do {
                if settings.watchTrashLoaded {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try FileManager.default.moveItem(at: url, to: Automation.unique(url.appendingPathExtension("loaded")))
                }
            } catch {
                model.log(LogEntry(torrentID: nil, level: .error, message: "Watch folder: couldn't move \(url.lastPathComponent) aside: \(error.localizedDescription)"))
                continue
            }
            let name = url.lastPathComponent
            Task {
                if await model.addAutomatically(.data(data, suggestedName: name)) != nil {
                    model.log(LogEntry(torrentID: nil, level: .info, message: "Watch folder: added \(name)"))
                }
            }
        }
    }

    // MARK: When downloads finish

    private func checkWhenDone() {
        let downloading = model.torrents.values.contains { !$0.isPaused && !$0.isComplete && $0.errorMessage == nil }
        guard settings.whenDone != .nothing else {
            sawDownloads = downloading
            return
        }
        if downloading {
            sawDownloads = true
            return
        }
        guard sawDownloads, model.whenDoneCountdown == nil else { return }
        sawDownloads = false
        let action = settings.whenDone
        settings.whenDone = .nothing
        // A countdown people can cancel, shown as a banner in the main window
        // and the menu bar menu rather than an alert that blocks the app.
        let countdown = WhenDoneCountdown(action: action, deadline: Date().addingTimeInterval(WhenDoneCountdown.delay))
        model.whenDoneCountdown = countdown
        model.log(LogEntry(torrentID: nil, level: .info, message: "All downloads finished: \(countdown.message(at: Date()))"))
        Notifier.post(title: "All downloads have finished",
                      body: "Freshet will \(action.phrase) in one minute. Open Freshet to cancel.")
    }

    private func checkCountdown() {
        guard let countdown = model.whenDoneCountdown, Date() >= countdown.deadline else { return }
        model.whenDoneCountdown = nil
        perform(countdown.action)
    }

    func perform(_ action: WhenDoneAction) {
        model.log(LogEntry(torrentID: nil, level: .info, message: "All downloads finished: \(action.title)"))
        switch action {
        case .nothing:
            break
        case .quit:
            NSApp.terminate(nil)
        case .sleep:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["sleepnow"]
            try? process.run()
        case .shutDown, .restart:
            let verb = action == .shutDown ? "shut down" : "restart"
            var error: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to \(verb)")?.executeAndReturnError(&error)
            if let error {
                model.log(LogEntry(torrentID: nil, level: .error, message: "Couldn't \(verb): \(error[NSAppleScript.errorMessage] ?? error)"))
            }
        }
    }

    // MARK: Keep the Mac awake

    private func updateSleepAssertion() {
        let busy = settings.preventSleep && model.torrents.values.contains {
            !$0.isPaused && $0.errorMessage == nil && (!$0.isComplete || $0.uploadRate > 0)
        } && !model.session.isPaused
        if busy && !holdingAssertion {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Freshet is transferring torrents" as CFString, &assertionID)
            holdingAssertion = result == kIOReturnSuccess
        } else if !busy {
            releaseAssertion()
        }
    }

    private func releaseAssertion() {
        if holdingAssertion {
            IOPMAssertionRelease(assertionID)
            holdingAssertion = false
        }
    }
}
