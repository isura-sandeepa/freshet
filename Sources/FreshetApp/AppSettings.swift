import Foundation
import FreshetCore
import Observation
import Security

/// User preferences, persisted in UserDefaults (the proxy password lives in the Keychain).
/// Engine-related changes are pushed to the engine immediately through `onEngineSettingsChange`.
@Observable
@MainActor
final class AppSettings {
    private let defaults = UserDefaults.standard
    @ObservationIgnored var onEngineSettingsChange: (() -> Void)?
    /// Called when a setting that the automation (scheduler, cap, goals, folders) reads changes.
    @ObservationIgnored var onAutomationChange: (() -> Void)?
    @ObservationIgnored var onIPFilterChange: (() -> Void)?

    // General
    var downloadFolder: String { didSet { defaults.set(downloadFolder, forKey: Keys.downloadFolder) } }
    var startTorrentsAutomatically: Bool { didSet { defaults.set(startTorrentsAutomatically, forKey: Keys.autoStart) } }
    var showAddDialog: Bool { didSet { defaults.set(showAddDialog, forKey: Keys.showAddDialog) } }
    var notifyOnCompletion: Bool { didSet { defaults.set(notifyOnCompletion, forKey: Keys.notify) } }
    var showDockBadge: Bool { didSet { defaults.set(showDockBadge, forKey: Keys.dockBadge) } }
    var showSpeedInMenuBar: Bool { didSet { defaults.set(showSpeedInMenuBar, forKey: Keys.menuBarSpeed) } }
    var recentSaveFolders: [String] { didSet { defaults.set(recentSaveFolders, forKey: Keys.recentFolders) } }
    var setupGuideShown: Bool { didSet { defaults.set(setupGuideShown, forKey: Keys.setupGuideShown) } }

    // Directories
    var preallocateFiles: Bool { didSet { defaults.set(preallocateFiles, forKey: Keys.preallocate) } }
    var useIncompleteSuffix: Bool { didSet { defaults.set(useIncompleteSuffix, forKey: Keys.incompleteSuffix); engineChanged() } }
    var moveCompleted: Bool { didSet { defaults.set(moveCompleted, forKey: Keys.moveCompleted) } }
    var completedFolder: String { didSet { defaults.set(completedFolder, forKey: Keys.completedFolder) } }
    var appendLabelToPath: Bool { didSet { defaults.set(appendLabelToPath, forKey: Keys.appendLabel) } }
    var moveOnlyFromDefaultFolder: Bool { didSet { defaults.set(moveOnlyFromDefaultFolder, forKey: Keys.moveOnlyFromDefault) } }
    var keepTorrentCopies: Bool { didSet { defaults.set(keepTorrentCopies, forKey: Keys.keepTorrents) } }
    var torrentCopiesFolder: String { didSet { defaults.set(torrentCopiesFolder, forKey: Keys.torrentsFolder) } }
    var moveTorrentCopiesWhenFinished: Bool { didSet { defaults.set(moveTorrentCopiesWhenFinished, forKey: Keys.moveTorrents) } }
    var finishedTorrentsFolder: String { didSet { defaults.set(finishedTorrentsFolder, forKey: Keys.finishedTorrentsFolder) } }

    // Automation
    var watchFolderEnabled: Bool { didSet { defaults.set(watchFolderEnabled, forKey: Keys.watchEnabled) } }
    var watchFolder: String { didSet { defaults.set(watchFolder, forKey: Keys.watchFolder) } }
    /// Move loaded .torrent files to the Trash instead of renaming them to .torrent.loaded.
    var watchTrashLoaded: Bool { didSet { defaults.set(watchTrashLoaded, forKey: Keys.watchTrash) } }
    var runWhenFinished: String { didSet { defaults.set(runWhenFinished, forKey: Keys.runFinished) } }
    var runWhenStateChanges: String { didSet { defaults.set(runWhenStateChanges, forKey: Keys.runState) } }
    var preventSleep: Bool { didSet { defaults.set(preventSleep, forKey: Keys.preventSleep) } }
    /// One-shot: resets after it runs and isn't kept across launches.
    var whenDone: WhenDoneAction = .nothing

    // Connection
    var listenPort: Int { didSet { defaults.set(listenPort, forKey: Keys.listenPort); engineChanged() } }
    var randomPortEachStart: Bool { didSet { defaults.set(randomPortEachStart, forKey: Keys.randomPortEachStart) } }
    var listenInterface: String { didSet { defaults.set(listenInterface, forKey: Keys.listenInterface); engineChanged() } }
    var outgoingInterface: String { didSet { defaults.set(outgoingInterface, forKey: Keys.outgoingInterface); engineChanged() } }
    var announceIP: String { didSet { defaults.set(announceIP, forKey: Keys.announceIP); engineChanged() } }
    var enableUPnP: Bool { didSet { defaults.set(enableUPnP, forKey: Keys.upnp); engineChanged() } }
    var enableNATPMP: Bool { didSet { defaults.set(enableNATPMP, forKey: Keys.natpmp); engineChanged() } }
    var proxy: ProxyOptions { didSet { store(proxy, Keys.proxy); engineChanged() } }
    var proxyPassword: String {
        didSet {
            if proxyPassword != oldValue { Keychain.set(proxyPassword, account: Keys.proxyPasswordAccount) }
            engineChanged()
        }
    }
    var ipFilterEnabled: Bool { didSet { defaults.set(ipFilterEnabled, forKey: Keys.ipFilterEnabled); onIPFilterChange?() } }
    var ipFilterPath: String { didSet { defaults.set(ipFilterPath, forKey: Keys.ipFilterPath); onIPFilterChange?() } }

    // BitTorrent
    var enableDHT: Bool { didSet { defaults.set(enableDHT, forKey: Keys.dht); engineChanged() } }
    var enableLSD: Bool { didSet { defaults.set(enableLSD, forKey: Keys.lsd); engineChanged() } }
    var encryption: EncryptionMode { didSet { defaults.set(encryption.rawValue, forKey: Keys.encryption); engineChanged() } }
    var allowLegacyIncoming: Bool { didSet { defaults.set(allowLegacyIncoming, forKey: Keys.allowLegacy); engineChanged() } }

    // Bandwidth
    /// KB/s, 0 = unlimited.
    var downloadLimitKBps: Int { didSet { defaults.set(downloadLimitKBps, forKey: Keys.downLimit); engineChanged() } }
    /// KB/s, 0 = unlimited.
    var uploadLimitKBps: Int { didSet { defaults.set(uploadLimitKBps, forKey: Keys.upLimit); engineChanged() } }
    var alternateUploadEnabled: Bool { didSet { defaults.set(alternateUploadEnabled, forKey: Keys.altUpEnabled); automationChanged() } }
    /// KB/s used instead of the upload limit while nothing is downloading.
    var alternateUploadKBps: Int { didSet { defaults.set(alternateUploadKBps, forKey: Keys.altUp); automationChanged() } }
    var maxConnections: Int { didSet { defaults.set(maxConnections, forKey: Keys.maxConnections); engineChanged() } }
    var maxConnectionsPerTorrent: Int { didSet { defaults.set(maxConnectionsPerTorrent, forKey: Keys.maxPerTorrent) } }
    var uploadSlots: Int { didSet { defaults.set(uploadSlots, forKey: Keys.uploadSlots); engineChanged() } }
    var uploadSlotsPerTorrent: Int { didSet { defaults.set(uploadSlotsPerTorrent, forKey: Keys.uploadSlotsPerTorrent) } }
    var extraSlotsWhenSlow: Bool { didSet { defaults.set(extraSlotsWhenSlow, forKey: Keys.extraSlots); engineChanged() } }

    // Queueing
    var maxActiveTorrents: Int { didSet { defaults.set(maxActiveTorrents, forKey: Keys.maxActive); engineChanged() } }
    var maxActiveDownloads: Int { didSet { defaults.set(maxActiveDownloads, forKey: Keys.maxDownloads); engineChanged() } }
    var seedingGoal: SeedingGoal { didSet { store(seedingGoal, Keys.seedingGoal); automationChanged() } }
    var seedingGoalAction: SeedingGoalAction { didSet { defaults.set(seedingGoalAction.rawValue, forKey: Keys.goalAction); automationChanged() } }
    /// KB/s applied once the goal is met when the action is `.limitUpload`.
    var seedingGoalUploadKBps: Int { didSet { defaults.set(seedingGoalUploadKBps, forKey: Keys.goalUpload); automationChanged() } }
    var preferSeeds: Bool { didSet { defaults.set(preferSeeds, forKey: Keys.preferSeeds); engineChanged() } }

    // Scheduler, transfer cap, search
    var schedule: Schedule { didSet { store(schedule, Keys.schedule); automationChanged() } }
    var transferCap: TransferCap { didSet { store(transferCap, Keys.transferCap); automationChanged() } }
    var searchProviders: [SearchProvider] { didSet { store(searchProviders, Keys.searchProviders) } }
    var selectedSearchProvider: UUID? {
        didSet { defaults.set(selectedSearchProvider?.uuidString, forKey: Keys.selectedSearchProvider) }
    }

    // Advanced
    var diskThreads: Int { didSet { defaults.set(diskThreads, forKey: Keys.diskThreads); engineChanged() } }
    var hashingThreads: Int { didSet { defaults.set(hashingThreads, forKey: Keys.hashingThreads); engineChanged() } }
    var maxQueuedDiskMB: Int { didSet { defaults.set(maxQueuedDiskMB, forKey: Keys.queuedDisk); engineChanged() } }
    var filePoolSize: Int { didSet { defaults.set(filePoolSize, forKey: Keys.filePool); engineChanged() } }
    /// libtorrent settings set by hand in the Advanced pane, by settings_pack name. Applied last.
    var advancedOverrides: [String: String] { didSet { store(advancedOverrides, Keys.advanced); engineChanged() } }

    /// A port for incoming connections away from 6881–6889, which ISPs often throttle or block, and
    /// below the range macOS uses for outgoing connections (49152 and up).
    static func randomPort() -> Int { Int.random(in: 20_000...48_999) }

    init() {
        let d = UserDefaults.standard
        // Pick a random listening port on first launch and keep it.
        if d.object(forKey: Keys.listenPort) == nil {
            d.set(Self.randomPort(), forKey: Keys.listenPort)
        }
        d.register(defaults: [
            Keys.autoStart: true,
            Keys.showAddDialog: true,
            Keys.notify: true,
            Keys.dockBadge: true,
            Keys.menuBarSpeed: true,
            Keys.upnp: true,
            Keys.natpmp: true,
            Keys.dht: true,
            Keys.lsd: true,
            Keys.downLimit: 0,
            Keys.upLimit: 0,
            Keys.maxActive: 8,
            Keys.maxDownloads: 5,
            Keys.moveOnlyFromDefault: true,
            Keys.encryption: EncryptionMode.enabled.rawValue,
            Keys.allowLegacy: true,
            Keys.altUp: 0,
            Keys.maxConnections: 500,
            Keys.maxPerTorrent: 50,
            Keys.uploadSlots: 8,
            Keys.uploadSlotsPerTorrent: 4,
            Keys.extraSlots: true,
            Keys.goalAction: SeedingGoalAction.stop.rawValue,
            Keys.goalUpload: 5,
            Keys.diskThreads: 10,
            Keys.hashingThreads: 1,
            Keys.queuedDisk: 1,
            Keys.filePool: 40,
            Keys.preventSleep: true,
        ])
        downloadFolder = d.string(forKey: Keys.downloadFolder) ?? AppPaths.defaultDownloads
        startTorrentsAutomatically = d.bool(forKey: Keys.autoStart)
        showAddDialog = d.bool(forKey: Keys.showAddDialog)
        notifyOnCompletion = d.bool(forKey: Keys.notify)
        showDockBadge = d.bool(forKey: Keys.dockBadge)
        showSpeedInMenuBar = d.bool(forKey: Keys.menuBarSpeed)
        recentSaveFolders = d.stringArray(forKey: Keys.recentFolders) ?? []
        setupGuideShown = d.bool(forKey: Keys.setupGuideShown)

        preallocateFiles = d.bool(forKey: Keys.preallocate)
        useIncompleteSuffix = d.bool(forKey: Keys.incompleteSuffix)
        moveCompleted = d.bool(forKey: Keys.moveCompleted)
        completedFolder = d.string(forKey: Keys.completedFolder) ?? ""
        appendLabelToPath = d.bool(forKey: Keys.appendLabel)
        moveOnlyFromDefaultFolder = d.bool(forKey: Keys.moveOnlyFromDefault)
        keepTorrentCopies = d.bool(forKey: Keys.keepTorrents)
        torrentCopiesFolder = d.string(forKey: Keys.torrentsFolder) ?? ""
        moveTorrentCopiesWhenFinished = d.bool(forKey: Keys.moveTorrents)
        finishedTorrentsFolder = d.string(forKey: Keys.finishedTorrentsFolder) ?? ""

        watchFolderEnabled = d.bool(forKey: Keys.watchEnabled)
        watchFolder = d.string(forKey: Keys.watchFolder) ?? ""
        watchTrashLoaded = d.bool(forKey: Keys.watchTrash)
        runWhenFinished = d.string(forKey: Keys.runFinished) ?? ""
        runWhenStateChanges = d.string(forKey: Keys.runState) ?? ""
        preventSleep = d.bool(forKey: Keys.preventSleep)

        listenPort = d.integer(forKey: Keys.listenPort)
        randomPortEachStart = d.bool(forKey: Keys.randomPortEachStart)
        listenInterface = d.string(forKey: Keys.listenInterface) ?? ""
        outgoingInterface = d.string(forKey: Keys.outgoingInterface) ?? ""
        announceIP = d.string(forKey: Keys.announceIP) ?? ""
        enableUPnP = d.bool(forKey: Keys.upnp)
        enableNATPMP = d.bool(forKey: Keys.natpmp)
        proxy = Self.load(ProxyOptions.self, Keys.proxy) ?? ProxyOptions()
        proxyPassword = Keychain.get(account: Keys.proxyPasswordAccount) ?? ""
        ipFilterEnabled = d.bool(forKey: Keys.ipFilterEnabled)
        ipFilterPath = d.string(forKey: Keys.ipFilterPath) ?? ""

        enableDHT = d.bool(forKey: Keys.dht)
        enableLSD = d.bool(forKey: Keys.lsd)
        encryption = EncryptionMode(rawValue: d.string(forKey: Keys.encryption) ?? "") ?? .enabled
        allowLegacyIncoming = d.bool(forKey: Keys.allowLegacy)

        downloadLimitKBps = d.integer(forKey: Keys.downLimit)
        uploadLimitKBps = d.integer(forKey: Keys.upLimit)
        alternateUploadEnabled = d.bool(forKey: Keys.altUpEnabled)
        alternateUploadKBps = d.integer(forKey: Keys.altUp)
        maxConnections = d.integer(forKey: Keys.maxConnections)
        maxConnectionsPerTorrent = d.integer(forKey: Keys.maxPerTorrent)
        uploadSlots = d.integer(forKey: Keys.uploadSlots)
        uploadSlotsPerTorrent = d.integer(forKey: Keys.uploadSlotsPerTorrent)
        extraSlotsWhenSlow = d.bool(forKey: Keys.extraSlots)

        maxActiveTorrents = d.integer(forKey: Keys.maxActive)
        maxActiveDownloads = d.integer(forKey: Keys.maxDownloads)
        seedingGoal = Self.load(SeedingGoal.self, Keys.seedingGoal) ?? SeedingGoal(ratioPercent: 150, minutes: 0)
        seedingGoalAction = SeedingGoalAction(rawValue: d.string(forKey: Keys.goalAction) ?? "") ?? .stop
        seedingGoalUploadKBps = d.integer(forKey: Keys.goalUpload)
        preferSeeds = d.bool(forKey: Keys.preferSeeds)

        schedule = Self.load(Schedule.self, Keys.schedule) ?? Schedule()
        transferCap = Self.load(TransferCap.self, Keys.transferCap) ?? TransferCap()
        searchProviders = Self.load([SearchProvider].self, Keys.searchProviders) ?? []
        selectedSearchProvider = d.string(forKey: Keys.selectedSearchProvider).flatMap(UUID.init(uuidString:))

        diskThreads = d.integer(forKey: Keys.diskThreads)
        hashingThreads = d.integer(forKey: Keys.hashingThreads)
        maxQueuedDiskMB = d.integer(forKey: Keys.queuedDisk)
        filePoolSize = d.integer(forKey: Keys.filePool)
        advancedOverrides = Self.load([String: String].self, Keys.advanced) ?? [:]
    }

    var networkOptions: NetworkOptions {
        var o = NetworkOptions()
        o.encryption = encryption
        o.allowLegacyIncoming = allowLegacyIncoming
        o.proxy = proxy
        o.proxyPassword = proxyPassword
        o.outgoingInterface = outgoingInterface
        o.announceIP = announceIP
        o.uploadSlots = max(0, uploadSlots)
        o.extraSlotsWhenSlow = extraSlotsWhenSlow
        o.preferSeeds = preferSeeds
        o.diskThreads = diskThreads
        o.hashingThreads = hashingThreads
        o.maxQueuedDiskMB = maxQueuedDiskMB
        o.filePoolSize = filePoolSize
        return o
    }

    /// The engine settings the preferences ask for, before the scheduler, the transfer cap and
    /// the alternate upload rate adjust them (see `Automation`).
    var engineSettings: EngineSettings {
        let privacy = proxy.isActive && proxy.disableLeakyFeatures
        var s = EngineSettings(listenPort: min(max(listenPort, 0), 65_535),
                               downloadLimit: max(0, downloadLimitKBps) * 1_024,
                               uploadLimit: max(0, uploadLimitKBps) * 1_024,
                               enableDHT: enableDHT && !privacy, enableLSD: enableLSD && !privacy,
                               enableUPnP: enableUPnP && !privacy, enableNATPMP: enableNATPMP && !privacy,
                               maxConnections: max(1, maxConnections),
                               maxActiveTorrents: max(1, maxActiveTorrents),
                               maxActiveDownloads: max(1, maxActiveDownloads))
        s.listenInterface = listenInterface
        s.incompleteSuffix = useIncompleteSuffix ? ".!ut" : ""
        s.named = LibtorrentSettingsMapper.named(networkOptions).merging(advancedOverrides) { _, manual in manual }
        return s
    }

    /// Remembers a save folder for the add dialog's menu (most recent first).
    func rememberSaveFolder(_ path: String) {
        var folders = recentSaveFolders.filter { $0 != path }
        folders.insert(path, at: 0)
        recentSaveFolders = Array(folders.prefix(6))
    }

    private func engineChanged() {
        onEngineSettingsChange?()
    }

    private func automationChanged() {
        onAutomationChange?()
    }

    private func store<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Keys {
        static let downloadFolder = "downloadFolder"
        static let autoStart = "startTorrentsAutomatically"
        static let showAddDialog = "showAddDialog"
        static let notify = "notifyOnCompletion"
        static let dockBadge = "showDockBadge"
        static let menuBarSpeed = "showSpeedInMenuBar"
        static let recentFolders = "recentSaveFolders"
        static let setupGuideShown = "setupGuideShown"
        static let preallocate = "preallocateFiles"
        static let incompleteSuffix = "useIncompleteSuffix"
        static let moveCompleted = "moveCompleted"
        static let completedFolder = "completedFolder"
        static let appendLabel = "appendLabelToPath"
        static let moveOnlyFromDefault = "moveOnlyFromDefaultFolder"
        static let keepTorrents = "keepTorrentCopies"
        static let torrentsFolder = "torrentCopiesFolder"
        static let moveTorrents = "moveTorrentCopiesWhenFinished"
        static let finishedTorrentsFolder = "finishedTorrentsFolder"
        static let watchEnabled = "watchFolderEnabled"
        static let watchFolder = "watchFolder"
        static let watchTrash = "watchTrashLoaded"
        static let runFinished = "runWhenFinished"
        static let runState = "runWhenStateChanges"
        static let preventSleep = "preventSleep"
        static let listenPort = "listenPort"
        static let randomPortEachStart = "randomPortEachStart"
        static let listenInterface = "listenInterface"
        static let outgoingInterface = "outgoingInterface"
        static let announceIP = "announceIP"
        static let upnp = "enableUPnP"
        static let natpmp = "enableNATPMP"
        static let proxy = "proxy"
        static let proxyPasswordAccount = "proxy-password"
        static let ipFilterEnabled = "ipFilterEnabled"
        static let ipFilterPath = "ipFilterPath"
        static let dht = "enableDHT"
        static let lsd = "enableLSD"
        static let encryption = "encryption"
        static let allowLegacy = "allowLegacyIncoming"
        static let downLimit = "downloadLimitKBps"
        static let upLimit = "uploadLimitKBps"
        static let altUpEnabled = "alternateUploadEnabled"
        static let altUp = "alternateUploadKBps"
        static let maxConnections = "maxConnections"
        static let maxPerTorrent = "maxConnectionsPerTorrent"
        static let uploadSlots = "uploadSlots"
        static let uploadSlotsPerTorrent = "uploadSlotsPerTorrent"
        static let extraSlots = "extraSlotsWhenSlow"
        static let maxActive = "maxActiveTorrents"
        static let maxDownloads = "maxActiveDownloads"
        static let seedingGoal = "seedingGoal"
        static let goalAction = "seedingGoalAction"
        static let goalUpload = "seedingGoalUploadKBps"
        static let preferSeeds = "preferSeeds"
        static let schedule = "schedule"
        static let transferCap = "transferCap"
        static let searchProviders = "searchProviders"
        static let selectedSearchProvider = "selectedSearchProvider"
        static let diskThreads = "diskThreads"
        static let hashingThreads = "hashingThreads"
        static let queuedDisk = "maxQueuedDiskMB"
        static let filePool = "filePoolSize"
        static let advanced = "advancedOverrides"
    }
}

/// Generic-password Keychain items for this app.
enum Keychain {
    private static let service = "app.freshet.Freshet"

    static func get(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
