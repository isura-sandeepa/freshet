import AppKit
import FreshetCore
import FreshetEngine
import FreshetSim
import Observation
import UniformTypeIdentifiers

/// A torrent waiting in the Add dialog.
struct PendingAdd: Identifiable {
    let id = UUID()
    var source: AddSource
    var preview: TorrentPreview
    var savePath: String
    var label: String
    var start: Bool
    var skipHashCheck: Bool
    var selectedFiles: Set<Int>
}

/// The app's single source of truth. Engine events arrive here, and every view and menu
/// sends its commands through here; nothing else talks to the engine.
@Observable
@MainActor
final class AppModel {
    let settings: AppSettings
    let engine: any EngineService
    let isSimulated: Bool
    private let labelsURL: URL

    private(set) var torrents: [TorrentID: TorrentSnapshot] = [:]
    private(set) var visible: [TorrentSnapshot] = []
    var selection: Set<TorrentID> = [] {
        didSet { if selection != oldValue { selectionChanged() } }
    }
    var filter: SidebarFilter = .all { didSet { recomputeVisible() } }
    var searchText = "" { didSet { recomputeVisible() } }
    var sortKey: TorrentSortKey { didSet { recomputeVisible(); saveSortKey() } }
    private(set) var labels: LabelBook
    private(set) var session = SessionSnapshot()
    private(set) var totalDownloadRate = 0
    private(set) var totalUploadRate = 0
    private(set) var hasIncomingConnections = false
    private(set) var globalHistory = SpeedHistory()
    private(set) var focusedHistory = SpeedHistory()
    private(set) var logs: [LogEntry] = []
    private(set) var details: TorrentDetails?
    var pendingAdds: [PendingAdd] = []
    var showAddURL = false
    var showInspector = true
    var removeRequest: Set<TorrentID>?
    var errorMessage: String?
    private(set) var isShuttingDown = false
    /// The torrent whose Properties sheet is open.
    var propertiesTarget: TorrentID?
    var showSetupGuide = false
    var showWebSearch = false
    /// Set by Edit › Filter Torrents (⌘F); the header's filter field takes focus and clears it.
    var focusFilter = false
    /// A typed answer the main window is asking for (label name, peer address).
    var textPrompt: TextPrompt?
    /// Counting down to the when-downloads-finish action; the main window shows a banner.
    var whenDoneCountdown: WhenDoneCountdown?
    private(set) var engineStartDate: Date?
    private(set) var countries: CountryDatabase?
    private(set) var ipFilterRanges = 0
    @ObservationIgnored private(set) var automation: Automation!
    @ObservationIgnored private(set) var hooks: SystemHooks!
    @ObservationIgnored private(set) var rss: RSSManager!

    @ObservationIgnored private var started = false
    @ObservationIgnored private var engineRunning = false
    @ObservationIgnored private var queuedOpens: [URL] = []
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var napActivity: NSObjectProtocol?
    @ObservationIgnored private var seenIncomplete: Set<TorrentID> = []

    init(simulate: Bool) {
        let settings = AppSettings()
        if settings.randomPortEachStart { settings.listenPort = AppSettings.randomPort() }
        self.settings = settings
        isSimulated = simulate
        if simulate {
            engine = SimulatedEngine()
        } else {
            engine = LibtorrentEngine(stateDirectory: AppPaths.engineState, settings: settings.engineSettings)
        }
        labelsURL = AppPaths.labelsFile(simulated: simulate)
        labels = Self.loadLabels(from: labelsURL)
        sortKey = Self.loadSortKey()
        automation = Automation(model: self, simulated: simulate)
        hooks = SystemHooks(model: self)
        rss = RSSManager(model: self, simulated: simulate)
        settings.onEngineSettingsChange = { [weak self] in
            self?.applyEngineSettings()
            self?.automation.applyTorrentLimits(force: [])
        }
        settings.onAutomationChange = { [weak self] in self?.automation.settingsChanged() }
        settings.onIPFilterChange = { [weak self] in self?.reloadIPFilter() }
    }

    // MARK: Derived state

    var focusedID: TorrentID? {
        if let first = visible.first(where: { selection.contains($0.id) }) { return first.id }
        return selection.first
    }

    var focusedTorrent: TorrentSnapshot? { focusedID.flatMap { torrents[$0] } }

    var isAddSheetPresented: Bool {
        get { !pendingAdds.isEmpty }
        set { if !newValue, !pendingAdds.isEmpty { pendingAdds.removeFirst() } }
    }

    var windowTitle: String {
        guard totalDownloadRate > 0 || totalUploadRate > 0 else { return "Freshet" }
        return "Freshet — ↓ \(Format.rateOrZero(totalDownloadRate))  ↑ \(Format.rateOrZero(totalUploadRate))"
    }

    var activeTorrents: [TorrentSnapshot] {
        torrents.values
            .filter { $0.isActive || $0.activity == .downloading }
            .sorted { ($0.downloadRate + $0.uploadRate) > ($1.downloadRate + $1.uploadRate) }
    }

    /// True once the engine has had a few seconds to open its port and still isn't listening.
    var listenFailed: Bool {
        guard let engineStartDate, !session.isListening else { return false }
        return Date().timeIntervalSince(engineStartDate) > 5
    }

    /// The first-run setup suggestion, shown as a banner until it's run or dismissed.
    var showSetupNotice: Bool { !settings.setupGuideShown && !isSimulated }

    func cancelWhenDone() {
        guard let countdown = whenDoneCountdown else { return }
        whenDoneCountdown = nil
        appendLog(LogEntry(torrentID: nil, level: .info, message: "Cancelled “\(countdown.action.title)” after downloads finished"))
    }

    func performWhenDoneNow() {
        guard let countdown = whenDoneCountdown else { return }
        whenDoneCountdown = nil
        hooks.perform(countdown.action)
    }

    func count(for filter: SidebarFilter) -> Int {
        torrents.values.reduce(0) { $0 + (filter.matches($1, label: labels.assignments[$1.id]) ? 1 : 0) }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        Notifier.requestAuthorizationIfPossible()
        eventTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.start()
            } catch {
                self.errorMessage = "The torrent engine couldn't start: \(error.localizedDescription)"
                return
            }
            self.engineRunning = true
            self.engineStartDate = Date()
            self.applyEngineSettings()
            self.reloadIPFilter()
            self.loadCountries()
            self.flushQueuedOpens()
            for await event in self.engine.events {
                self.handle(event)
            }
        }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.everySecond()
            }
        }
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        timerTask?.cancel()
        saveLabels()
        automation.shutdown()
        hooks.shutdown()
        await engine.shutdown()
        eventTask?.cancel()
        endAppNap()
    }

    // MARK: Torrent commands

    func perform(_ action: TorrentAction, ids: Set<TorrentID>? = nil) {
        let targets = orderedForQueue(Array(ids ?? selection), action: action)
        guard !targets.isEmpty else { return }
        Task { await engine.perform(action, on: targets) }
    }

    func pauseAll() {
        let ids = Array(torrents.keys)
        Task { await engine.perform(.pause, on: ids) }
    }

    func resumeAll() {
        let ids = Array(torrents.keys)
        Task { await engine.perform(.start, on: ids) }
    }

    func requestRemove(_ ids: Set<TorrentID>? = nil) {
        let targets = ids ?? selection
        guard !targets.isEmpty else { return }
        removeRequest = targets
    }

    func remove(_ ids: Set<TorrentID>, moveDataToTrash: Bool) {
        removeRequest = nil
        let snapshots = ids.compactMap { torrents[$0] }
        Task {
            await engine.remove(Array(ids))
            labels.forget(Array(ids))
            automation.forget(Array(ids))
            hooks.forget(Array(ids))
            saveLabels()
            if moveDataToTrash {
                for snapshot in snapshots { trashContent(of: snapshot) }
            }
        }
    }

    func reveal(_ id: TorrentID) {
        guard let torrent = torrents[id] else { return }
        if let url = contentURL(of: torrent), FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if !torrent.savePath.isEmpty {
            NSWorkspace.shared.open(URL(fileURLWithPath: torrent.savePath, isDirectory: true))
        }
    }

    func copyMagnetLinks(_ ids: Set<TorrentID>? = nil) {
        let targets = Array(ids ?? selection)
        guard !targets.isEmpty else { return }
        Task {
            var links: [String] = []
            for id in targets {
                if let link = await engine.magnetLink(for: id) { links.append(link) }
            }
            guard !links.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(links.joined(separator: "\n"), forType: .string)
        }
    }

    func setFilePriority(_ priority: FilePriority, files: Set<Int>, torrent id: TorrentID) {
        guard !files.isEmpty else { return }
        Task {
            await engine.setFilePriority(priority, files: Array(files), in: id)
            await refreshDetails()
        }
    }

    // MARK: Labels

    func setLabel(_ label: String?, for ids: Set<TorrentID>? = nil) {
        let targets = Array(ids ?? selection)
        guard !targets.isEmpty else { return }
        labels.assign(label, to: targets)
        saveLabels()
        recomputeVisible()
    }

    func promptNewLabel(for ids: Set<TorrentID>? = nil) {
        let targets = ids ?? selection
        guard !targets.isEmpty else { return }
        let count = targets.count
        textPrompt = TextPrompt(
            title: "New Label",
            message: count == 1 ? "Name the label for the selected torrent." : "Name the label for the \(count) selected torrents.",
            placeholder: "Label name",
            actionTitle: "Add Label",
            commit: { [weak self] name in self?.setLabel(name, for: targets) })
    }

    func deleteLabel(_ name: String) {
        labels.removeLabel(name)
        if filter == .label(name) { filter = .all }
        saveLabels()
        recomputeVisible()
    }

    // MARK: Adding torrents

    func openTorrentFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.message = "Choose .torrent files to add"
        guard panel.runModal() == .OK else { return }
        handleOpen(panel.urls)
    }

    /// Files dropped on the window or the Dock icon, double-clicked .torrent files, and magnet links.
    func handleOpen(_ urls: [URL]) {
        guard engineRunning else {
            queuedOpens.append(contentsOf: urls)
            return
        }
        for url in urls { open(url) }
    }

    /// Text from the Add from URL sheet: magnet links, info-hashes or .torrent URLs, one per line.
    func addFromText(_ text: String) {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.lowercased().hasPrefix("magnet:") {
                enqueue(.magnet(line))
            } else if let url = URL(string: line), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                download(url)
            } else if line.count == 40, line.allSatisfy(\.isHexDigit) {
                enqueue(.magnet("magnet:?xt=urn:btih:\(line)"))
            } else {
                errorMessage = "“\(line)” isn't a magnet link, an info-hash or a torrent URL."
            }
        }
    }

    func confirmAdd(_ pending: PendingAdd) {
        pendingAdds.removeAll { $0.id == pending.id }
        var priorities: [Int]? = nil
        if !pending.preview.files.isEmpty, pending.selectedFiles.count < pending.preview.files.count {
            let highestIndex = pending.preview.files.map(\.index).max() ?? -1
            var values = Array(repeating: FilePriority.normal.rawValue, count: highestIndex + 1)
            for file in pending.preview.files where !pending.selectedFiles.contains(file.index) {
                values[file.index] = FilePriority.skip.rawValue
            }
            priorities = values
        }
        let request = AddRequest(source: pending.source, savePath: pending.savePath, start: pending.start,
                                 skipHashCheck: pending.skipHashCheck, filePriorities: priorities,
                                 preallocate: settings.preallocateFiles)
        Task {
            do {
                switch try await engine.add(request) {
                case .added(let id):
                    let label = pending.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty { setLabel(label, for: [id]) }
                    settings.rememberSaveFolder(pending.savePath)
                    automation.onAdded(id, name: pending.preview.name)
                case .duplicate:
                    errorMessage = "“\(pending.preview.name)” is already in the list."
                }
            } catch {
                errorMessage = "Couldn't add “\(pending.preview.name)”: \(error.localizedDescription)"
            }
        }
    }

    func cancelAdd(_ pending: PendingAdd) {
        pendingAdds.removeAll { $0.id == pending.id }
    }

    /// Registers this app bundle for magnet links and .torrent files.
    func makeDefaultHandler() {
        guard AppPaths.isBundled else {
            errorMessage = "Run the app bundle built by Scripts/make-app.sh to register Freshet for magnet links."
            return
        }
        let appURL = Bundle.main.bundleURL
        Task {
            do {
                try await Self.registerAsDefaultHandler(appURL)
            } catch {
                errorMessage = "Couldn't make Freshet the default: \(error.localizedDescription)"
            }
        }
    }

    private nonisolated static func registerAsDefaultHandler(_ appURL: URL) async throws {
        let workspace = NSWorkspace.shared
        try await workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "magnet")
        if let type = UTType(filenameExtension: "torrent") {
            try await workspace.setDefaultApplication(at: appURL, toOpen: type)
        }
    }

    // MARK: Adding without the dialog (watch folder, RSS, created torrents)

    /// Adds a torrent with the defaults from Settings, overridden where given. Problems go to the log.
    @discardableResult
    func addAutomatically(_ source: AddSource, savePath: String? = nil, label: String? = nil, start: Bool? = nil,
                          skipHashCheck: Bool = false) async -> TorrentID? {
        do {
            let preview = try await engine.preview(source)
            if torrents[preview.torrentID] != nil { return nil }
            let folder = savePath ?? settings.downloadFolder
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            let request = AddRequest(source: source, savePath: folder, start: start ?? settings.startTorrentsAutomatically,
                                     skipHashCheck: skipHashCheck, preallocate: settings.preallocateFiles)
            guard case .added(let id) = try await engine.add(request) else { return nil }
            if let label, !label.isEmpty { setLabel(label, for: [id]) }
            automation.onAdded(id, name: preview.name)
            return id
        } catch {
            appendLog(LogEntry(torrentID: nil, level: .error, message: "Couldn't add a torrent: \(error.localizedDescription)"))
            return nil
        }
    }

    // MARK: Phase 2 commands

    func showProperties(_ id: TorrentID? = nil) {
        guard let target = id ?? focusedID else { return }
        propertiesTarget = target
    }

    func setPriority(_ priority: BandwidthPriority, for ids: Set<TorrentID>? = nil) {
        let targets = Array(ids ?? selection)
        guard !targets.isEmpty else { return }
        automation.update(targets) { $0.priority = priority }
    }

    /// Global limits from the menu bar and Dock presets, KB/s (0 = unlimited).
    func setGlobalLimits(downloadKBps: Int? = nil, uploadKBps: Int? = nil) {
        if let downloadKBps { settings.downloadLimitKBps = downloadKBps }
        if let uploadKBps { settings.uploadLimitKBps = uploadKBps }
    }

    func chooseDownloadLocation(for ids: Set<TorrentID>? = nil) {
        let targets = Array(ids ?? selection)
        guard !targets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = "Choose where the downloaded files should live. They are moved there."
        if let first = targets.first.flatMap({ torrents[$0] }) {
            panel.directoryURL = URL(fileURLWithPath: first.savePath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        Task { for id in targets { await engine.moveStorage(of: id, to: path) } }
    }

    func saveTorrentFile(_ id: TorrentID? = nil) {
        guard let target = id ?? focusedID else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = Automation.safeName(torrents[target]?.displayName ?? target) + ".torrent"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await engine.exportTorrent(target, to: url)
            } catch {
                errorMessage = "Couldn't save the .torrent file: \(error.localizedDescription)"
            }
        }
    }

    func promptAddPeer(to id: TorrentID) {
        textPrompt = TextPrompt(
            title: "Add Peer",
            message: "Enter the peer's address and port, such as 203.0.113.5:51413 or [2001:db8::5]:51413.",
            placeholder: "IP address:port",
            actionTitle: "Add Peer",
            validate: { PeerAddress($0) == nil ? "Enter an IP address followed by a colon and a port number." : nil },
            commit: { [weak self] text in
                guard let self, let address = PeerAddress(text) else { return }
                Task {
                    if await self.engine.addPeer(address, to: id) {
                        self.appendLog(LogEntry(torrentID: id, level: .info, message: "Connecting to \(address.ip) port \(address.port)"))
                    }
                }
            })
    }

    func clearPeers(of id: TorrentID) {
        Task {
            await engine.clearPeers(of: id)
            appendLog(LogEntry(torrentID: id, level: .info, message: "Cleared the peer list and bans"))
            await refreshDetails()
        }
    }

    func webSearch(_ query: String, provider: SearchProvider) {
        guard let url = provider.url(for: query) else { return }
        NSWorkspace.shared.open(url)
    }

    func reloadIPFilter() {
        guard engineRunning else { return }
        let path: String? = settings.ipFilterEnabled && !settings.ipFilterPath.isEmpty ? settings.ipFilterPath : nil
        Task {
            do {
                let count = try await engine.loadIPFilter(path: path)
                ipFilterRanges = count
                if path != nil {
                    appendLog(LogEntry(torrentID: nil, level: .info, message: "IP filter: \(count) blocked ranges loaded"))
                }
            } catch {
                ipFilterRanges = 0
                appendLog(LogEntry(torrentID: nil, level: .error, message: "IP filter: \(error.localizedDescription)"))
            }
        }
    }

    private func loadCountries() {
        guard countries == nil, let url = AppPaths.countryDatabase else { return }
        Task.detached(priority: .utility) {
            let database = CountryDatabase(contentsOf: url)
            await MainActor.run { self.countries = database }
        }
    }

    // MARK: Logs

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: Private

    private func open(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "magnet" {
            enqueue(.magnet(url.absoluteString))
        } else if url.isFileURL {
            if url.pathExtension.lowercased() == "torrent" { enqueue(.file(url)) }
        } else if scheme == "http" || scheme == "https" {
            download(url)
        }
    }

    private func flushQueuedOpens() {
        let urls = queuedOpens
        queuedOpens.removeAll()
        for url in urls { open(url) }
    }

    private func download(_ url: URL) {
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw EngineError.downloadFailed("The server answered HTTP \(http.statusCode).")
                }
                enqueue(.data(data, suggestedName: url.lastPathComponent))
            } catch {
                errorMessage = "Couldn't download \(url.absoluteString): \(error.localizedDescription)"
            }
        }
    }

    private func enqueue(_ source: AddSource) {
        Task {
            do {
                let preview = try await engine.preview(source)
                if torrents[preview.torrentID] != nil {
                    errorMessage = "“\(preview.name)” is already in the list."
                    return
                }
                var label = ""
                if case .label(let name) = filter { label = name }
                let pending = PendingAdd(source: source, preview: preview, savePath: settings.downloadFolder, label: label,
                                         start: settings.startTorrentsAutomatically, skipHashCheck: false,
                                         selectedFiles: Set(preview.files.map(\.index)))
                if settings.showAddDialog {
                    pendingAdds.append(pending)
                } else {
                    confirmAdd(pending)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .statuses(let list):
            for snapshot in list {
                torrents[snapshot.id] = snapshot
                if !snapshot.isComplete { seenIncomplete.insert(snapshot.id) }
            }
            recomputeVisible()
            recomputeTotals()
            hooks.statusesChanged(list)
        case .removed(let id):
            guard torrents.removeValue(forKey: id) != nil else { return }
            seenIncomplete.remove(id)
            if selection.contains(id) { selection.remove(id) }
            recomputeVisible()
            recomputeTotals()
        case .finished(let id):
            // Only announce torrents we watched download, not seeds restored at launch.
            guard seenIncomplete.remove(id) != nil, let torrent = torrents[id] else { return }
            appendLog(LogEntry(torrentID: id, level: .info, message: "Finished downloading"))
            if settings.notifyOnCompletion { Notifier.postCompletion(name: torrent.displayName) }
            automation.onFinished(id)
            hooks.finished(id)
        case .metadataReceived(let id):
            appendLog(LogEntry(torrentID: id, level: .info, message: "Received metadata from peers"))
            automation.onMetadata(id)
        case .log(let entry):
            appendLog(entry)
        case .session(let snapshot):
            if snapshot != session { session = snapshot }
        case .loaded(let count):
            if count > 0 {
                appendLog(LogEntry(torrentID: nil, level: .info, message: "Restored \(count) torrent(s) from the last session"))
            }
        case .moved(let id, let path, let error):
            if let error {
                appendLog(LogEntry(torrentID: id, level: .error, message: "Couldn't move the files to \(path): \(error)"))
            } else {
                appendLog(LogEntry(torrentID: id, level: .info, message: "Moved the files to \(path)"))
            }
        }
    }

    private func everySecond() async {
        let now = Date()
        globalHistory.append(SpeedSample(date: now, download: totalDownloadRate, upload: totalUploadRate))
        if let torrent = focusedTorrent {
            focusedHistory.append(SpeedSample(date: now, download: torrent.downloadRate, upload: torrent.uploadRate))
        }
        automation.tick(now: now)
        hooks.tick()
        rss.tick(now: now)
        await refreshDetails()
    }

    func refreshDetails() async {
        guard showInspector, let id = focusedID else {
            if details != nil { details = nil }
            return
        }
        let fresh = await engine.details(for: id)
        if focusedID == id { details = fresh }
    }

    private func selectionChanged() {
        focusedHistory.reset()
        details = nil
        Task { await refreshDetails() }
    }

    private func recomputeVisible() {
        visible = TorrentQuery.visible(Array(torrents.values), filter: filter, search: searchText,
                                       labels: labels.assignments, sort: sortKey)
    }

    private func recomputeTotals() {
        var down = 0
        var up = 0
        var downloading = 0
        var busy = false
        var incoming = false
        for torrent in torrents.values {
            down += torrent.downloadRate
            up += torrent.uploadRate
            let running = !torrent.isPaused && torrent.errorMessage == nil
            if running && !torrent.isComplete { downloading += 1 }
            if torrent.isActive || (running && !torrent.isComplete) { busy = true }
            if torrent.hasIncoming { incoming = true }
        }
        if down != totalDownloadRate { totalDownloadRate = down }
        if up != totalUploadRate { totalUploadRate = up }
        if incoming != hasIncomingConnections { hasIncomingConnections = incoming }
        let badge = settings.showDockBadge && downloading > 0 ? "\(downloading)" : nil
        if NSApp.dockTile.badgeLabel != badge { NSApp.dockTile.badgeLabel = badge }
        // Keep App Nap from throttling transfers while the window is hidden.
        if busy, napActivity == nil {
            napActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                                reason: "Transferring torrents")
        } else if !busy {
            endAppNap()
        }
    }

    private func endAppNap() {
        if let activity = napActivity {
            ProcessInfo.processInfo.endActivity(activity)
            napActivity = nil
        }
    }

    /// Queue moves are applied one torrent at a time, so order them to keep the selection's relative order.
    private func orderedForQueue(_ ids: [TorrentID], action: TorrentAction) -> [TorrentID] {
        let position: (TorrentID) -> Int = { self.torrents[$0]?.queuePosition ?? Int.max }
        switch action {
        case .queueUp, .queueBottom: return ids.sorted { position($0) < position($1) }
        case .queueDown, .queueTop: return ids.sorted { position($0) > position($1) }
        default: return ids
        }
    }

    private func contentURL(of torrent: TorrentSnapshot) -> URL? {
        let name = torrent.name
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..", !torrent.savePath.isEmpty else { return nil }
        return URL(fileURLWithPath: torrent.savePath, isDirectory: true).appendingPathComponent(name)
    }

    private func trashContent(of torrent: TorrentSnapshot) {
        guard let url = contentURL(of: torrent), FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            appendLog(LogEntry(torrentID: torrent.id, level: .error,
                               message: "Couldn't move \(url.lastPathComponent) to the Trash: \(error.localizedDescription)"))
        }
    }

    private func appendLog(_ entry: LogEntry) {
        logs.append(entry)
        if logs.count > 2_000 { logs.removeFirst(logs.count - 2_000) }
    }

    func applyEngineSettings() {
        let snapshot = automation.effective(settings.engineSettings)
        Task { await engine.apply(settings: snapshot) }
    }

    func log(_ entry: LogEntry) {
        appendLog(entry)
    }

    private func saveLabels() {
        do {
            try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(labels).write(to: labelsURL, options: .atomic)
        } catch {
            appendLog(LogEntry(torrentID: nil, level: .warning, message: "Couldn't save labels: \(error.localizedDescription)"))
        }
    }

    private static func loadLabels(from url: URL) -> LabelBook {
        guard let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(LabelBook.self, from: data) else { return LabelBook() }
        return book
    }

    private static func loadSortKey() -> TorrentSortKey {
        if let data = UserDefaults.standard.data(forKey: "sortKey"),
           let key = try? JSONDecoder().decode(TorrentSortKey.self, from: data) {
            return key
        }
        return TorrentSortKey(field: .queue, ascending: true)
    }

    private func saveSortKey() {
        if let data = try? JSONEncoder().encode(sortKey) { UserDefaults.standard.set(data, forKey: "sortKey") }
    }
}
