import AppKit
import Charts
import FreshetCore
import SwiftUI

/// The Settings window's panes.
struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        TabView(selection: $pane) {
            ForEach(SettingsPane.allCases) { pane in
                content(for: pane)
                    .settingsPane()
                    .tabItem { Label(pane.title, systemImage: pane.systemImage) }
                    .tag(pane)
            }
        }
    }

    @ViewBuilder private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPreferences(settings: model.settings, model: model)
        case .folders: FoldersPreferences(settings: model.settings)
        case .connection: ConnectionPreferences(settings: model.settings, model: model)
        case .bandwidth: BandwidthPreferences(settings: model.settings)
        case .bittorrent: BitTorrentPreferences(settings: model.settings)
        case .scheduler: SchedulerPreferences(settings: model.settings)
        case .transferCap: TransferCapPreferences(settings: model.settings, automation: model.automation)
        case .search: SearchPreferences(settings: model.settings)
        case .advanced: AdvancedPreferences(settings: model.settings, model: model)
        }
    }
}

extension View {
    /// Each pane is as tall as its content, so the window resizes as people switch panes, and
    /// scrolls only when a pane would be taller than most screens.
    func settingsPane() -> some View {
        frame(width: 680).frame(maxHeight: 760)
    }
}

/// A number field with a unit after it.
struct NumberField: View {
    let title: String
    @Binding var value: Int
    var unit: String = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A folder path with a Choose… button.
struct FolderField: View {
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? "Not set" : (path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") { choose() }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

struct GeneralPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        Form {
            Section("Adding torrents") {
                FolderField(title: "Save new torrents to", path: $settings.downloadFolder)
                Toggle("Start torrents automatically", isOn: $settings.startTorrentsAutomatically)
                Toggle("Show options when adding a torrent", isOn: $settings.showAddDialog)
            }
            Section("While transferring") {
                Toggle("Keep the Mac awake while torrents are active", isOn: $settings.preventSleep)
                Picker("When all downloads finish", selection: $settings.whenDone) {
                    ForEach(WhenDoneAction.allCases, id: \.self) { action in Text(action.title).tag(action) }
                }
                Text("This runs once, then resets to Do Nothing. Shutting down or restarting asks to control System Events the first time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Notify me when a download finishes", isOn: $settings.notifyOnCompletion)
                Toggle("Show the number of downloads on the Dock icon", isOn: $settings.showDockBadge)
                Toggle("Show transfer speeds in the menu bar", isOn: $settings.showSpeedInMenuBar)
            }
            Section("Default app") {
                LabeledContent("Magnet links and .torrent files") {
                    Button("Open with Freshet") { model.makeDefaultHandler() }
                }
                LabeledContent("Setup guide") {
                    Button("Run Setup Guide…") { model.showSetupGuide = true }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FoldersPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Files") {
                Toggle("Reserve disk space for all files when adding a torrent", isOn: $settings.preallocateFiles)
                Toggle("Add .!ut to the names of unfinished files", isOn: $settings.useIncompleteSuffix)
            }
            Section("Completed downloads") {
                Toggle("Move completed downloads", isOn: $settings.moveCompleted)
                FolderField(title: "Move to", path: $settings.completedFolder)
                    .disabled(!settings.moveCompleted)
                Toggle("Append the torrent's label to the folder", isOn: $settings.appendLabelToPath)
                    .disabled(!settings.moveCompleted)
                Toggle("Only move from the default download folder", isOn: $settings.moveOnlyFromDefaultFolder)
                    .disabled(!settings.moveCompleted)
            }
            Section("Watch folder") {
                Toggle("Automatically add .torrent files from a folder", isOn: $settings.watchFolderEnabled)
                FolderField(title: "Folder", path: $settings.watchFolder)
                    .disabled(!settings.watchFolderEnabled)
                Toggle("Move added .torrent files to the Trash (otherwise renamed to .loaded)", isOn: $settings.watchTrashLoaded)
                    .disabled(!settings.watchFolderEnabled)
            }
            Section(".torrent files") {
                Toggle("Keep a copy of every .torrent", isOn: $settings.keepTorrentCopies)
                FolderField(title: "Store them in", path: $settings.torrentCopiesFolder)
                    .disabled(!settings.keepTorrentCopies)
                Toggle("Move them when the download finishes", isOn: $settings.moveTorrentCopiesWhenFinished)
                    .disabled(!settings.keepTorrentCopies)
                FolderField(title: "Move them to", path: $settings.finishedTorrentsFolder)
                    .disabled(!settings.keepTorrentCopies || !settings.moveTorrentCopiesWhenFinished)
            }
        }
        .formStyle(.grouped)
    }
}

struct ConnectionPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        Form {
            Section("Listening port") {
                HStack {
                    TextField("Port for incoming connections", value: $settings.listenPort, format: .number.grouping(.never))
                    Button("Random Port") { settings.listenPort = AppSettings.randomPort() }
                }
                Toggle("Pick a new random port each time Freshet starts", isOn: $settings.randomPortEachStart)
                Toggle("Map the port with UPnP", isOn: $settings.enableUPnP)
                Toggle("Map the port with NAT-PMP", isOn: $settings.enableNATPMP)
            }
            Section("Interfaces") {
                TextField("Listen on (interface or IP)", text: $settings.listenInterface, prompt: Text("All"))
                TextField("Outgoing connections from", text: $settings.outgoingInterface, prompt: Text("Any"))
                TextField("IP or hostname reported to trackers", text: $settings.announceIP, prompt: Text("Automatic"))
            }
            Section("Proxy server") {
                Picker("Type", selection: $settings.proxy.kind) {
                    ForEach(ProxyKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                if settings.proxy.kind != .none {
                    TextField("Proxy", text: $settings.proxy.host, prompt: Text("host name or IP"))
                    TextField("Port", value: $settings.proxy.port, format: .number.grouping(.never))
                    if settings.proxy.kind != .socks4 {
                        Toggle("Authentication", isOn: $settings.proxy.useAuthentication)
                        if settings.proxy.useAuthentication {
                            TextField("Username", text: $settings.proxy.username)
                            SecureField("Password", text: $settings.proxyPassword)
                        }
                    }
                    Toggle("Resolve host names through the proxy", isOn: $settings.proxy.resolveHostnames)
                    Toggle("Use the proxy for peer connections", isOn: $settings.proxy.proxyPeers)
                    Toggle("Use the proxy for trackers", isOn: $settings.proxy.proxyTrackers)
                    Toggle("Turn off features that reveal your address (DHT, local discovery, UPnP, NAT-PMP)",
                           isOn: $settings.proxy.disableLeakyFeatures)
                }
            }
            Section("IP filter") {
                Toggle("Block addresses listed in a filter file", isOn: $settings.ipFilterEnabled)
                LabeledContent("Filter file") {
                    HStack {
                        Text(settings.ipFilterPath.isEmpty ? "ipfilter.dat or a P2P list" : (settings.ipFilterPath as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(settings.ipFilterPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFilter() }
                    }
                }
                if settings.ipFilterEnabled && !settings.ipFilterPath.isEmpty {
                    LabeledContent("Loaded") { Text("\(model.ipFilterRanges) blocked ranges") }
                    Button("Reload Filter") { model.reloadIPFilter() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFilter() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Choose an ipfilter.dat (DAT) or PeerGuardian (P2P) text file"
        if panel.runModal() == .OK, let url = panel.url { settings.ipFilterPath = url.path }
    }
}

struct BandwidthPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Global rate limits (0 = unlimited)") {
                NumberField(title: "Maximum download rate", value: $settings.downloadLimitKBps, unit: "KB/s")
                NumberField(title: "Maximum upload rate", value: $settings.uploadLimitKBps, unit: "KB/s")
                Toggle("Use a different upload rate when nothing is downloading", isOn: $settings.alternateUploadEnabled)
                NumberField(title: "Upload rate when not downloading", value: $settings.alternateUploadKBps, unit: "KB/s")
                    .disabled(!settings.alternateUploadEnabled)
            }
            Section("Connections") {
                NumberField(title: "Global maximum number of connections", value: $settings.maxConnections)
                NumberField(title: "Maximum connected peers per torrent", value: $settings.maxConnectionsPerTorrent)
                NumberField(title: "Global upload slots (0 = unlimited)", value: $settings.uploadSlots)
                NumberField(title: "Upload slots per torrent", value: $settings.uploadSlotsPerTorrent)
                Toggle("Use additional upload slots if upload speed is under 90%", isOn: $settings.extraSlotsWhenSlow)
            }
            Section {
                Text("Per-torrent peers and slots apply to torrents added from now on; change existing ones in Properties (⌘I). Bandwidth priority shares the global limits between torrents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct BitTorrentPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Finding peers") {
                Toggle("Find peers without a tracker (DHT)", isOn: $settings.enableDHT)
                Toggle("Find peers on your local network", isOn: $settings.enableLSD)
                Text("DHT is a shared directory of peers that works without trackers. Connected peers also tell Freshet about other peers (peer exchange). Private torrents use only their trackers. You can change these per torrent in Properties.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Protocol encryption") {
                Picker("Outgoing", selection: $settings.encryption) {
                    ForEach(EncryptionMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                }
                Toggle("Allow incoming legacy (unencrypted) connections", isOn: $settings.allowLegacyIncoming)
                    .disabled(settings.encryption != .enabled)
            }
            QueueingSections(settings: settings)
        }
        .formStyle(.grouped)
    }
}

/// The queue and seeding goal, shown in the BitTorrent pane.
struct QueueingSections: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Queue") {
            Stepper("Maximum active torrents: \(settings.maxActiveTorrents)", value: $settings.maxActiveTorrents, in: 1...200)
            Stepper("Maximum active downloads: \(settings.maxActiveDownloads)", value: $settings.maxActiveDownloads, in: 1...200)
            Toggle("Seeding torrents have priority over downloads", isOn: $settings.preferSeeds)
        }
        Section("Seeding goal (0 = no goal)") {
            NumberField(title: "Seed while the ratio is under", value: $settings.seedingGoal.ratioPercent, unit: "%")
            NumberField(title: "Seed for at least", value: $settings.seedingGoal.minutes, unit: "minutes")
            Picker("When the goal is reached", selection: $settings.seedingGoalAction) {
                Text("Stop the torrent").tag(SeedingGoalAction.stop)
                Text("Limit its upload rate").tag(SeedingGoalAction.limitUpload)
            }
            NumberField(title: "Upload rate after the goal", value: $settings.seedingGoalUploadKBps, unit: "KB/s")
                .disabled(settings.seedingGoalAction != .limitUpload)
            Text("A torrent stops at whichever goal it reaches first. Torrents can override the goal in Properties.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

extension ScheduleMode {
    var color: Color {
        switch self {
        case .full: return Palette.success
        case .limited: return Palette.warning
        case .seedingOnly: return Color(nsColor: .systemBlue)
        case .off: return Color(nsColor: .systemGray)
        }
    }

    /// A mark drawn in the scheduler grid so the modes differ by shape, not only by color.
    var symbol: String? {
        switch self {
        case .full: return nil
        case .limited: return "tortoise.fill"
        case .seedingOnly: return "arrow.up"
        case .off: return "xmark"
        }
    }
}

/// A color swatch with the mode's mark, used in the grid's palette.
struct ScheduleSwatch: View {
    let mode: ScheduleMode
    var size: CGFloat = 14
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(mode.color.opacity(contrast == .increased ? 1 : 0.8))
            .overlay {
                if let symbol = mode.symbol {
                    Image(systemName: symbol).font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct SchedulerPreferences: View {
    @Bindable var settings: AppSettings
    @State private var paint = ScheduleMode.off

    var body: some View {
        Form {
            Section {
                Toggle("Turn on the scheduler", isOn: $settings.schedule.isEnabled)
            }
            Section {
                HStack {
                    ForEach(Array(ScheduleMode.allCases.enumerated()), id: \.element) { index, mode in
                        Button {
                            paint = mode
                        } label: {
                            HStack(spacing: 5) {
                                ScheduleSwatch(mode: mode)
                                Text(mode.title)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(paint == mode ? .accentColor : nil)
                        .help("\(mode.title) (press \(index + 1) in the grid)")
                        .accessibilityAddTraits(paint == mode ? .isSelected : [])
                    }
                }
                ScheduleGrid(schedule: $settings.schedule, paint: $paint)
                    .frame(height: ScheduleGrid.height)
                    .disabled(!settings.schedule.isEnabled)
                    .opacity(settings.schedule.isEnabled ? 1 : 0.5)
            } header: {
                Text("Weekly plan")
            } footer: {
                Text("Pick a mode, then click or drag over the hours. From the keyboard: arrow keys move, Space sets the hour, Shift-arrow sets hours as you move, and 1–4 pick a mode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Limited hours (0 = unlimited)") {
                NumberField(title: "Download rate", value: $settings.schedule.limitedDownloadKBps, unit: "KB/s")
                NumberField(title: "Upload rate", value: $settings.schedule.limitedUploadKBps, unit: "KB/s")
                Toggle("Also turn off DHT during “Turn off” hours", isOn: $settings.schedule.disableDHTWhenOff)
            }
        }
        .formStyle(.grouped)
    }
}

/// The 7 × 24 hour grid. It can be painted with the pointer, driven from the keyboard, and
/// read and changed hour by hour with VoiceOver.
struct ScheduleGrid: View {
    @Binding var schedule: Schedule
    @Binding var paint: ScheduleMode
    @Environment(\.isEnabled) private var isEnabled
    @State private var draft: Schedule?
    @State private var cursorDay = 0
    @State private var cursorHour = 0
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    static let cellHeight: CGFloat = 20
    static let labelWidth: CGFloat = 38
    static let height = CGFloat(Schedule.days) * cellHeight + 20
    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let fullDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        let shown = draft ?? schedule
        GeometryReader { proxy in
            let cellWidth = (proxy.size.width - Self.labelWidth) / CGFloat(Schedule.hours)
            ZStack(alignment: .topLeading) {
                ForEach(0..<Schedule.days, id: \.self) { day in
                    Text(Self.dayNames[day]).font(.callout).foregroundStyle(.secondary)
                        .frame(width: Self.labelWidth, height: Self.cellHeight, alignment: .leading)
                        .offset(y: CGFloat(day) * Self.cellHeight)
                        .accessibilityHidden(true)
                    ForEach(0..<Schedule.hours, id: \.self) { hour in
                        cell(day: day, hour: hour, mode: shown[day, hour], width: cellWidth)
                            .offset(x: Self.labelWidth + CGFloat(hour) * cellWidth, y: CGFloat(day) * Self.cellHeight)
                    }
                }
                if focused {
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .frame(width: cellWidth, height: Self.cellHeight)
                        .offset(x: Self.labelWidth + CGFloat(cursorHour) * cellWidth, y: CGFloat(cursorDay) * Self.cellHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour):00").font(.caption).foregroundStyle(.secondary)
                        .offset(x: Self.labelWidth + CGFloat(hour) * cellWidth, y: CGFloat(Schedule.days) * Self.cellHeight + 3)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let hour = Int((value.location.x - Self.labelWidth) / cellWidth)
                    let day = Int(value.location.y / Self.cellHeight)
                    guard (0..<Schedule.days).contains(day), (0..<Schedule.hours).contains(hour) else { return }
                    focused = true
                    cursorDay = day
                    cursorHour = hour
                    var updated = draft ?? schedule
                    if updated[day, hour] != paint {
                        updated[day, hour] = paint
                        draft = updated
                    }
                }
                .onEnded { _ in
                    if let draft { schedule = draft }
                    draft = nil
                })
        }
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let wasDay = cursorDay, wasHour = cursorHour
            switch press.key {
            case .leftArrow: cursorHour = max(0, cursorHour - 1)
            case .rightArrow: cursorHour = min(Schedule.hours - 1, cursorHour + 1)
            case .upArrow: cursorDay = max(0, cursorDay - 1)
            default: cursorDay = min(Schedule.days - 1, cursorDay + 1)
            }
            if press.modifiers.contains(.shift) {
                set(day: wasDay, hour: wasHour)
                set(day: cursorDay, hour: cursorHour)
            }
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            set(day: cursorDay, hour: cursorHour)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "1234"), phases: .down) { press in
            guard let digit = Int(press.characters), (1...ScheduleMode.allCases.count).contains(digit) else { return .ignored }
            paint = ScheduleMode.allCases[digit - 1]
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weekly plan")
    }

    private func cell(day: Int, hour: Int, mode: ScheduleMode, width: CGFloat) -> some View {
        Rectangle()
            .fill(mode.color.opacity(contrast == .increased ? 1 : 0.75))
            .overlay {
                if let symbol = mode.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
            .overlay(Rectangle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
            .frame(width: width, height: Self.cellHeight)
            .help("\(Self.dayNames[day]) \(hour):00–\(hour + 1):00 · \(mode.title)")
            .accessibilityElement()
            .accessibilityLabel("\(Self.fullDayNames[day]), \(hour):00 to \(hour + 1):00")
            .accessibilityValue(mode.title)
            .accessibilityHint("Sets this hour to \(paint.title)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { set(day: day, hour: hour) }
    }

    private func set(day: Int, hour: Int) {
        guard isEnabled, schedule[day, hour] != paint else { return }
        schedule[day, hour] = paint
    }
}

struct TransferCapPreferences: View {
    @Bindable var settings: AppSettings
    let automation: Automation

    var body: some View {
        Form {
            Section {
                Toggle("Stop transfers when the cap is reached", isOn: $settings.transferCap.isEnabled)
                Picker("Count", selection: $settings.transferCap.kind) {
                    ForEach(CapKind.allCases, id: \.self) { kind in Text(kind.title).tag(kind) }
                }
                NumberField(title: "Cap", value: $settings.transferCap.megabytes, unit: "MB")
                Stepper("Period: last \(settings.transferCap.periodDays) days", value: $settings.transferCap.periodDays, in: 1...31)
            }
            Section("Usage") {
                let cap = settings.transferCap
                LabeledContent("Used in this period") {
                    if automation.capReached {
                        Label("\(Format.bytes(automation.capUsage)) of \(Format.bytes(cap.bytes)) — cap reached",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                    } else {
                        Text("\(Format.bytes(automation.capUsage)) of \(Format.bytes(cap.bytes))")
                    }
                }
                let days = automation.ledger.series(days: max(7, cap.periodDays), endingOn: Date())
                Chart {
                    ForEach(days, id: \.date) { entry in
                        BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Bytes", entry.usage.download))
                            .foregroundStyle(TransferStyle.download)
                            .position(by: .value("Direction", "Download"))
                            .accessibilityLabel("Downloaded on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                            .accessibilityValue(Format.bytes(entry.usage.download))
                        BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Bytes", entry.usage.upload))
                            .foregroundStyle(TransferStyle.download.opacity(0.4))
                            .position(by: .value("Direction", "Upload"))
                            .accessibilityLabel("Uploaded on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                            .accessibilityValue(Format.bytes(entry.usage.upload))
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel { if let bytes = value.as(Int64.self) { Text(Format.bytes(bytes)) } }
                    }
                }
                .frame(height: 160)
                HStack {
                    TransferLegend(kind: .bar)
                    Spacer()
                    Button("Reset Usage History") { automation.resetUsage() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SearchPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form { SearchSitesSections(settings: settings) }
            .formStyle(.grouped)
    }
}

/// The sites the toolbar search box sends queries to.
struct SearchSitesSections: View {
    @Bindable var settings: AppSettings
    @State private var name = ""
    @State private var template = ""

    var body: some View {
        Section("Search sites for the toolbar search box") {
            if settings.searchProviders.isEmpty {
                Text("None yet. Freshet doesn't come with any; add the sites you use.")
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.searchProviders) { provider in
                HStack {
                    VStack(alignment: .leading) {
                        Text(provider.name)
                        Text(provider.template).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        settings.searchProviders.removeAll { $0.id == provider.id }
                    } label: { Label("Remove \(provider.name)", systemImage: "minus.circle").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                    .help("Remove \(provider.name)")
                }
            }
        }
        Section("Add a search site") {
            TextField("Name", text: $name)
            TextField("Search URL", text: $template, prompt: Text("https://example.com/search?q=%s"))
            let candidate = SearchProvider(name: name.trimmingCharacters(in: .whitespaces), template: template.trimmingCharacters(in: .whitespaces))
            HStack {
                Text("%s is replaced by what you type.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Add") {
                    settings.searchProviders.append(candidate)
                    if settings.selectedSearchProvider == nil { settings.selectedSearchProvider = candidate.id }
                    name = ""
                    template = ""
                }
                .disabled(candidate.name.isEmpty || !candidate.isValid)
            }
        }
    }
}

struct AdvancedPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel
    @State private var showExpert = false

    var body: some View {
        Form {
            Section {
                TextField("When a torrent finishes", text: $settings.runWhenFinished, prompt: Text("e.g. open -a Infuse %D"))
                TextField("When a torrent changes state", text: $settings.runWhenStateChanges, prompt: Text("Optional"))
            } header: {
                Text("Run a program")
            } footer: {
                Text("Commands run with zsh. Placeholders: %F file, %D folder, %N name, %L label, %T tracker, %I info-hash, %S state, %P previous state, %M status message, %K single or multi-file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Disk") {
                Stepper("Disk I/O threads: \(settings.diskThreads)", value: $settings.diskThreads, in: 1...64)
                Stepper("Hashing threads: \(settings.hashingThreads)", value: $settings.hashingThreads, in: 1...32)
                Stepper("Write queue: \(settings.maxQueuedDiskMB) MB", value: $settings.maxQueuedDiskMB, in: 1...1_024)
                Stepper("Open files: \(settings.filePoolSize)", value: $settings.filePoolSize, in: 4...2_000, step: 4)
            }
            Section {
                LabeledContent("Changed settings") {
                    HStack {
                        Text(settings.advancedOverrides.isEmpty ? "None" : "\(settings.advancedOverrides.count)")
                            .foregroundStyle(.secondary)
                        Button("Edit Expert Settings…") { showExpert = true }
                    }
                }
            } header: {
                Text("Expert settings")
            } footer: {
                Text("The torrent engine's own settings. Changes apply right away and take priority over the other panes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showExpert) { ExpertSettingsSheet(settings: settings, model: model) }
    }
}

/// Every engine setting in a filterable table, edited one at a time.
struct ExpertSettingsSheet: View {
    @Bindable var settings: AppSettings
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AdvancedSetting] = []
    @State private var filter = ""
    @State private var selection: AdvancedSetting.ID?
    @State private var editValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Expert Settings").font(.headline)
            Text("Changed settings are shown in bold. Changes apply right away and take priority over the other panes.")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $filter, prompt: Text("Filter by name"))
                .textFieldStyle(.roundedBorder)
            Table(shown, selection: $selection) {
                TableColumn("Name") { item in
                    Text(item.name).fontWeight(settings.advancedOverrides[item.name] != nil ? .bold : .regular)
                }
                TableColumn("Value") { item in Text(item.value).lineLimit(1).truncationMode(.middle) }
                    .width(min: 80, ideal: 160)
                TableColumn("Default") { item in Text(item.defaultValue).foregroundStyle(.secondary).lineLimit(1) }
                    .width(min: 60, ideal: 120)
            }
            .frame(minHeight: 240)
            HStack {
                if let item = items.first(where: { $0.id == selection }) {
                    Text(item.name).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if item.kind == .toggle {
                        Picker(item.name, selection: $editValue) {
                            Text("true").tag("true")
                            Text("false").tag("false")
                        }
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        TextField(item.name, text: $editValue, prompt: Text("Value"))
                            .labelsHidden()
                            .frame(width: 200)
                    }
                    Button("Set") {
                        settings.advancedOverrides[item.name] = editValue
                        reloadSoon()
                    }
                    Button("Reset") {
                        settings.advancedOverrides.removeValue(forKey: item.name)
                        reloadSoon()
                    }
                    .disabled(settings.advancedOverrides[item.name] == nil)
                } else {
                    Text("Select a setting to change it.").foregroundStyle(.secondary)
                    Spacer()
                }
                Divider().frame(height: 20)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .task { await reload() }
        .onChange(of: selection) {
            editValue = items.first(where: { $0.id == selection })?.value ?? ""
        }
    }

    private var shown: [AdvancedSetting] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return query.isEmpty ? items : items.filter { $0.name.lowercased().contains(query) }
    }

    private func reload() async {
        items = await model.engine.advancedSettings()
    }

    private func reloadSoon() {
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await reload()
        }
    }
}
