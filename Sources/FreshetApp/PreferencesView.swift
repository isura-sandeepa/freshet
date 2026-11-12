import AppKit
import Charts
import FreshetCore
import SwiftUI

/// The Settings window: the panes in a sidebar like the main window's, and the selected pane's
/// groups on the right.
struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            SidebarColumn {
                BrandMark(title: "Settings")
            } rows: {
                ForEach(SettingsPane.allCases) { item in
                    NavRow(title: item.title, systemImage: item.systemImage, isSelected: pane == item, count: 0) {
                        pane = item
                    }
                }
            }
            SidebarDivider()
            VStack(spacing: 0) {
                WindowHeader(title: pane.title, subtitle: pane.subtitle) { EmptyView() }
                ScrollView {
                    content(for: pane)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PageLayout.horizontalInset)
                        .padding(.top, Spacing.xxSmall)
                        .padding(.bottom, Spacing.large)
                }
                .id(pane)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 820, minHeight: 480)
        .themedWindow()
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

/// One pane's groups, evenly spaced.
struct PaneStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) { content }
    }
}

struct GeneralPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PaneStack {
            FormGroup(title: "Adding torrents") {
                FolderRow(title: "Save new torrents to", path: $settings.downloadFolder)
                FormDivider()
                SwitchRow("Start torrents automatically", isOn: $settings.startTorrentsAutomatically)
                FormDivider()
                SwitchRow("Show options when adding a torrent", caption: "Choose the folder, label and files for each one.",
                          isOn: $settings.showAddDialog)
            }
            FormGroup(title: "While transferring") {
                SwitchRow("Keep the Mac awake while torrents are active", isOn: $settings.preventSleep)
                FormDivider()
                FormRow("When all downloads finish",
                        caption: "Runs once, then resets to Do Nothing. Shutting down or restarting asks to control System Events the first time.") {
                    ValuePicker("When all downloads finish", selection: $settings.whenDone, options: WhenDoneAction.allCases) { $0.title }
                }
            }
            FormGroup(title: "Notifications") {
                SwitchRow("Notify me when a download finishes", isOn: $settings.notifyOnCompletion)
                FormDivider()
                SwitchRow("Show the number of downloads on the Dock icon", isOn: $settings.showDockBadge)
                FormDivider()
                SwitchRow("Show transfer speeds in the menu bar", isOn: $settings.showSpeedInMenuBar)
            }
            FormGroup(title: "Default app") {
                FormRow("Magnet links and .torrent files", caption: "Open them in Freshet from your browser and from Finder.") {
                    Button("Open with Freshet") { model.makeDefaultHandler() }
                        .buttonStyle(.freshet(.secondary, size: .small))
                }
                FormDivider()
                FormRow("Setup Guide", caption: "Download folder, upload speed and a check that peers can reach you.") {
                    Button("Run Setup Guide…") {
                        openWindow(id: mainWindowID)
                        model.showSetupGuide = true
                    }
                    .buttonStyle(.freshet(.secondary, size: .small))
                }
            }
        }
    }
}

struct FoldersPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        PaneStack {
            FormGroup(title: "Files") {
                SwitchRow("Reserve disk space for all files when adding a torrent", isOn: $settings.preallocateFiles)
                FormDivider()
                SwitchRow("Add .!ut to the names of unfinished files", isOn: $settings.useIncompleteSuffix)
            }
            FormGroup(title: "Completed downloads") {
                SwitchRow("Move completed downloads", isOn: $settings.moveCompleted)
                FormDivider()
                Group {
                    FolderRow(title: "Move to", path: $settings.completedFolder)
                    FormDivider()
                    SwitchRow("Append the torrent's label to the folder", isOn: $settings.appendLabelToPath)
                    FormDivider()
                    SwitchRow("Only move from the default download folder", isOn: $settings.moveOnlyFromDefaultFolder)
                }
                .disabled(!settings.moveCompleted)
            }
            FormGroup(title: "Watch folder") {
                SwitchRow("Automatically add .torrent files from a folder", isOn: $settings.watchFolderEnabled)
                FormDivider()
                Group {
                    FolderRow(title: "Folder", path: $settings.watchFolder)
                    FormDivider()
                    SwitchRow("Move added .torrent files to the Trash", caption: "Otherwise they're renamed to end in .loaded.",
                              isOn: $settings.watchTrashLoaded)
                }
                .disabled(!settings.watchFolderEnabled)
            }
            FormGroup(title: ".torrent files") {
                SwitchRow("Keep a copy of every .torrent", isOn: $settings.keepTorrentCopies)
                FormDivider()
                Group {
                    FolderRow(title: "Store them in", path: $settings.torrentCopiesFolder)
                    FormDivider()
                    SwitchRow("Move them when the download finishes", isOn: $settings.moveTorrentCopiesWhenFinished)
                    FormDivider()
                    FolderRow(title: "Move them to", path: $settings.finishedTorrentsFolder)
                        .disabled(!settings.moveTorrentCopiesWhenFinished)
                }
                .disabled(!settings.keepTorrentCopies)
            }
        }
    }
}

struct ConnectionPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        PaneStack {
            FormGroup(title: "Listening port") {
                FormRow("Port for incoming connections") {
                    HStack(spacing: Spacing.xSmall) {
                        NumberInput("Port for incoming connections", value: $settings.listenPort, range: 1...65_535, width: 80)
                        Button("Random Port") { settings.listenPort = AppSettings.randomPort() }
                            .buttonStyle(.freshet(.secondary, size: .small))
                    }
                }
                FormDivider()
                SwitchRow("Pick a new random port each time Freshet starts", isOn: $settings.randomPortEachStart)
                FormDivider()
                SwitchRow("Map the port with UPnP", isOn: $settings.enableUPnP)
                FormDivider()
                SwitchRow("Map the port with NAT-PMP", isOn: $settings.enableNATPMP)
            }
            FormGroup(title: "Interfaces") {
                FormRow("Listen on", caption: "An interface name or IP address.") {
                    TextInput("Listen on", text: $settings.listenInterface, prompt: "All", width: 220)
                }
                FormDivider()
                FormRow("Outgoing connections from") {
                    TextInput("Outgoing connections from", text: $settings.outgoingInterface, prompt: "Any", width: 220)
                }
                FormDivider()
                FormRow("Address reported to trackers", caption: "An IP address or host name.") {
                    TextInput("Address reported to trackers", text: $settings.announceIP, prompt: "Automatic", width: 220)
                }
            }
            FormGroup(title: "Proxy server") {
                FormRow("Type") {
                    ValuePicker("Proxy type", selection: $settings.proxy.kind, options: ProxyKind.allCases) { $0.title }
                }
                if settings.proxy.kind != .none {
                    FormDivider()
                    FormRow("Server") {
                        TextInput("Proxy server", text: $settings.proxy.host, prompt: "Host name or IP", width: 220)
                    }
                    FormDivider()
                    FormRow("Port") {
                        NumberInput("Proxy port", value: $settings.proxy.port, range: 0...65_535, width: 80)
                    }
                    if settings.proxy.kind != .socks4 {
                        FormDivider()
                        SwitchRow("Authentication", isOn: $settings.proxy.useAuthentication)
                        if settings.proxy.useAuthentication {
                            FormDivider()
                            FormRow("User name") {
                                TextInput("User name", text: $settings.proxy.username, width: 220)
                            }
                            FormDivider()
                            FormRow("Password", caption: "Kept in your keychain.") {
                                TextInput("Password", text: $settings.proxyPassword, width: 220, secure: true)
                            }
                        }
                    }
                    FormDivider()
                    SwitchRow("Resolve host names through the proxy", isOn: $settings.proxy.resolveHostnames)
                    FormDivider()
                    SwitchRow("Use the proxy for peer connections", isOn: $settings.proxy.proxyPeers)
                    FormDivider()
                    SwitchRow("Use the proxy for trackers", isOn: $settings.proxy.proxyTrackers)
                    FormDivider()
                    SwitchRow("Turn off features that reveal your address", caption: "DHT, local discovery, UPnP and NAT-PMP.",
                              isOn: $settings.proxy.disableLeakyFeatures)
                }
            }
            FormGroup(title: "IP filter") {
                SwitchRow("Block addresses listed in a filter file", isOn: $settings.ipFilterEnabled)
                FormDivider()
                PathRow(title: "Filter file", path: settings.ipFilterPath, placeholder: "ipfilter.dat or a P2P list") {
                    chooseFilter()
                }
                if settings.ipFilterEnabled && !settings.ipFilterPath.isEmpty {
                    FormDivider()
                    FormRow("Blocked ranges", caption: "\(model.ipFilterRanges) loaded from the file.") {
                        Button("Reload Filter") { model.reloadIPFilter() }
                            .buttonStyle(.freshet(.secondary, size: .small))
                    }
                }
            }
        }
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
        PaneStack {
            FormGroup(title: "Global rate limits", footer: "0 means unlimited.") {
                FormRow("Maximum download rate") {
                    NumberInput("Maximum download rate", value: $settings.downloadLimitKBps, unit: "KB/s")
                }
                FormDivider()
                FormRow("Maximum upload rate") {
                    NumberInput("Maximum upload rate", value: $settings.uploadLimitKBps, unit: "KB/s")
                }
                FormDivider()
                SwitchRow("Use a different upload rate when nothing is downloading", isOn: $settings.alternateUploadEnabled)
                FormDivider()
                FormRow("Upload rate when not downloading") {
                    NumberInput("Upload rate when not downloading", value: $settings.alternateUploadKBps, unit: "KB/s")
                }
                .disabled(!settings.alternateUploadEnabled)
            }
            FormGroup(title: "Connections",
                      footer: "Per-torrent peers and slots apply to torrents added from now on; change existing ones in Properties (⌘I). Bandwidth priority shares the global limits between torrents.") {
                FormRow("Global maximum number of connections") {
                    NumberInput("Global maximum number of connections", value: $settings.maxConnections)
                }
                FormDivider()
                FormRow("Maximum connected peers per torrent") {
                    NumberInput("Maximum connected peers per torrent", value: $settings.maxConnectionsPerTorrent)
                }
                FormDivider()
                FormRow("Global upload slots", caption: "0 means unlimited.") {
                    NumberInput("Global upload slots", value: $settings.uploadSlots)
                }
                FormDivider()
                FormRow("Upload slots per torrent") {
                    NumberInput("Upload slots per torrent", value: $settings.uploadSlotsPerTorrent)
                }
                FormDivider()
                SwitchRow("Use additional upload slots if upload speed is under 90%", isOn: $settings.extraSlotsWhenSlow)
            }
        }
    }
}

struct BitTorrentPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        PaneStack {
            FormGroup(title: "Finding peers",
                      footer: "DHT is a shared directory of peers that works without trackers. Connected peers also tell Freshet about other peers (peer exchange). Private torrents use only their trackers. You can change these per torrent in Properties.") {
                SwitchRow("Find peers without a tracker (DHT)", isOn: $settings.enableDHT)
                FormDivider()
                SwitchRow("Find peers on your local network", isOn: $settings.enableLSD)
            }
            FormGroup(title: "Protocol encryption") {
                FormRow("Outgoing connections") {
                    ValuePicker("Outgoing encryption", selection: $settings.encryption, options: EncryptionMode.allCases) { $0.title }
                }
                FormDivider()
                SwitchRow("Allow incoming legacy (unencrypted) connections", isOn: $settings.allowLegacyIncoming)
                    .disabled(settings.encryption != .enabled)
            }
            QueueingGroups(settings: settings)
        }
    }
}

/// The queue and seeding goal, shown in the BitTorrent pane.
struct QueueingGroups: View {
    @Bindable var settings: AppSettings

    var body: some View {
        FormGroup(title: "Queue") {
            FormRow("Maximum active torrents") {
                NumberInput("Maximum active torrents", value: $settings.maxActiveTorrents, range: 1...200, step: 1, width: 56)
            }
            FormDivider()
            FormRow("Maximum active downloads") {
                NumberInput("Maximum active downloads", value: $settings.maxActiveDownloads, range: 1...200, step: 1, width: 56)
            }
            FormDivider()
            SwitchRow("Seeding torrents have priority over downloads", isOn: $settings.preferSeeds)
        }
        FormGroup(title: "Seeding goal",
                  footer: "A torrent stops at whichever goal it reaches first; 0 means no goal. Torrents can override the goal in Properties.") {
            FormRow("Seed while the ratio is under") {
                NumberInput("Seed while the ratio is under", value: $settings.seedingGoal.ratioPercent, unit: "%")
            }
            FormDivider()
            FormRow("Seed for at least") {
                NumberInput("Seed for at least", value: $settings.seedingGoal.minutes, unit: "minutes")
            }
            FormDivider()
            FormRow("When the goal is reached") {
                ValuePicker("When the goal is reached", selection: $settings.seedingGoalAction, options: SeedingGoalAction.allCases) {
                    $0 == .stop ? "Stop the torrent" : "Limit its upload rate"
                }
            }
            FormDivider()
            FormRow("Upload rate after the goal") {
                NumberInput("Upload rate after the goal", value: $settings.seedingGoalUploadKBps, unit: "KB/s")
            }
            .disabled(settings.seedingGoalAction != .limitUpload)
        }
    }
}

extension ScheduleMode {
    var color: Color {
        switch self {
        case .full: return Colors.Chart.green
        case .limited: return Colors.Chart.orange
        case .seedingOnly: return Colors.Chart.skyBlue
        case .off: return Colors.Chart.neutral
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
        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            .fill(mode.color.opacity(contrast == .increased ? 1 : 0.85))
            .overlay {
                if let symbol = mode.symbol {
                    Image(systemName: symbol).font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(.black.opacity(0.7))
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A scheduler mode to paint with: a capsule chip with the mode's swatch.
struct ScheduleModeChip: View {
    let mode: ScheduleMode
    let shortcut: Int
    @Binding var paint: ScheduleMode

    var body: some View {
        let selected = paint == mode
        Button { paint = mode } label: {
            HStack(spacing: Spacing.xxSmallPlus) {
                ScheduleSwatch(mode: mode)
                Text(mode.title)
                    .font(selected ? Typography.headline : Typography.body)
                    .foregroundStyle(selected ? Colors.textPrimary : Colors.textSecondary)
            }
            .padding(.horizontal, Spacing.small - 2)
            .frame(height: 28)
            .background(Capsule(style: .continuous).fill(selected ? Colors.surfaceRaised : Color.clear))
            .overlay {
                Capsule(style: .continuous).strokeBorder(selected ? Colors.actionPrimary : Colors.borderStrong, lineWidth: 1)
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(mode.title) (press \(shortcut) in the grid)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SchedulerPreferences: View {
    @Bindable var settings: AppSettings
    @State private var paint = ScheduleMode.off

    var body: some View {
        PaneStack {
            FormGroup {
                SwitchRow("Turn on the scheduler", caption: "Change speeds hour by hour through the week.",
                          isOn: $settings.schedule.isEnabled)
            }
            FormGroup(title: "Weekly plan",
                      footer: "Pick a mode, then click or drag over the hours. From the keyboard: arrow keys move, Space sets the hour, Shift-arrow sets hours as you move, and 1–4 pick a mode.") {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    HStack(spacing: Spacing.xxSmallPlus) {
                        ForEach(Array(ScheduleMode.allCases.enumerated()), id: \.element) { index, mode in
                            ScheduleModeChip(mode: mode, shortcut: index + 1, paint: $paint)
                        }
                    }
                    ScheduleGrid(schedule: $settings.schedule, paint: $paint)
                        .frame(height: ScheduleGrid.height)
                        .disabled(!settings.schedule.isEnabled)
                        .opacity(settings.schedule.isEnabled ? 1 : 0.5)
                }
                .padding(Spacing.medium)
            }
            FormGroup(title: "Limited hours", footer: "0 means unlimited.") {
                FormRow("Download rate") {
                    NumberInput("Limited download rate", value: $settings.schedule.limitedDownloadKBps, unit: "KB/s")
                }
                FormDivider()
                FormRow("Upload rate") {
                    NumberInput("Limited upload rate", value: $settings.schedule.limitedUploadKBps, unit: "KB/s")
                }
                FormDivider()
                SwitchRow("Also turn off DHT during “Turn off” hours", isOn: $settings.schedule.disableDHTWhenOff)
            }
        }
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
                    Text(Self.dayNames[day])
                        .font(Typography.metadata)
                        .foregroundStyle(Colors.textSecondary)
                        .frame(width: Self.labelWidth, height: Self.cellHeight, alignment: .leading)
                        .offset(y: CGFloat(day) * Self.cellHeight)
                        .accessibilityHidden(true)
                    ForEach(0..<Schedule.hours, id: \.self) { hour in
                        cell(day: day, hour: hour, mode: shown[day, hour], width: cellWidth)
                            .offset(x: Self.labelWidth + CGFloat(hour) * cellWidth, y: CGFloat(day) * Self.cellHeight)
                    }
                }
                if focused {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Colors.actionPrimary, lineWidth: 2.5)
                        .frame(width: cellWidth, height: Self.cellHeight)
                        .offset(x: Self.labelWidth + CGFloat(cursorHour) * cellWidth, y: CGFloat(cursorDay) * Self.cellHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text("\(hour):00")
                        .font(Typography.metadata.numbers)
                        .foregroundStyle(Colors.textTertiary)
                        .offset(x: Self.labelWidth + CGFloat(hour) * cellWidth, y: CGFloat(Schedule.days) * Self.cellHeight + 4)
                        .accessibilityHidden(true)
                }
            }
            // The cells are placed with offsets, which don't size the stack, so give it the
            // whole grid's frame; otherwise only the top-left corner receives clicks.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
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
            .fill(mode.color.opacity(contrast == .increased ? 1 : 0.8))
            .overlay {
                if let symbol = mode.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.65))
                }
            }
            // Gaps in the group's own fill, so the cells read as separate hours.
            .overlay(Rectangle().stroke(Colors.fillSecondary, lineWidth: 1))
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
        let cap = settings.transferCap
        PaneStack {
            FormGroup {
                SwitchRow("Stop transfers when the cap is reached", isOn: $settings.transferCap.isEnabled)
                FormDivider()
                FormRow("Count") {
                    ValuePicker("Count", selection: $settings.transferCap.kind, options: CapKind.allCases) { $0.title }
                }
                FormDivider()
                FormRow("Cap") {
                    NumberInput("Cap", value: $settings.transferCap.megabytes, unit: "MB", width: 88)
                }
                FormDivider()
                FormRow("Period", caption: "Usage is counted over this many recent days.") {
                    NumberInput("Period", value: $settings.transferCap.periodDays, range: 1...31, step: 1, unit: "days", width: 48)
                }
            }
            FormGroup(title: "Usage") {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                        Text("\(Format.bytes(automation.capUsage)) used")
                            .font(Typography.pageTitle.weight(.bold).numbers)
                            .monospacedDigit()
                        Text("of \(Format.bytes(cap.bytes)) in the last \(cap.periodDays) days")
                            .font(Typography.rowTitle.numbers)
                            .foregroundStyle(Colors.textSecondary)
                        Spacer(minLength: Spacing.small)
                        if automation.capReached {
                            Badge(text: "Cap reached", tone: .warning, systemImage: "exclamationmark.triangle.fill")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    ProgressTrack(value: cap.bytes > 0 ? Double(automation.capUsage) / Double(cap.bytes) : 0,
                                  color: automation.capReached ? Colors.statusCheckText : Colors.Chart.blue, height: 6)
                    let days = automation.ledger.series(days: max(7, cap.periodDays), endingOn: Date())
                    Chart {
                        ForEach(days, id: \.date) { entry in
                            BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Bytes", entry.usage.download))
                                .foregroundStyle(TransferStyle.download)
                                .position(by: .value("Direction", "Download"))
                                .accessibilityLabel("Downloaded on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue(Format.bytes(entry.usage.download))
                            BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Bytes", entry.usage.upload))
                                .foregroundStyle(TransferStyle.upload)
                                .position(by: .value("Direction", "Upload"))
                                .accessibilityLabel("Uploaded on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                                .accessibilityValue(Format.bytes(entry.usage.upload))
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Colors.borderStrong)
                            AxisValueLabel {
                                if let bytes = value.as(Int64.self) { Text(Format.bytes(bytes)).font(Typography.metadata.numbers) }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                                .font(Typography.metadata.font)
                        }
                    }
                    .frame(height: 160)
                    HStack {
                        TransferLegend(kind: .bar)
                        Spacer()
                        Button("Reset Usage History") { automation.resetUsage() }
                            .buttonStyle(.freshet(.secondary, size: .small))
                    }
                }
                .padding(Spacing.medium)
            }
        }
    }
}

struct SearchPreferences: View {
    @Bindable var settings: AppSettings

    var body: some View {
        PaneStack { SearchSitesGroups(settings: settings) }
    }
}

/// The sites the web search button sends queries to.
struct SearchSitesGroups: View {
    @Bindable var settings: AppSettings
    @State private var name = ""
    @State private var template = ""

    var body: some View {
        FormGroup(title: "Search sites") {
            if settings.searchProviders.isEmpty {
                Text("None yet. Freshet doesn't come with any; add the sites you use.")
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .formRowPadding()
            }
            ForEach(Array(settings.searchProviders.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { FormDivider() }
                HStack(spacing: Spacing.medium) {
                    VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                        Text(provider.name)
                        Text(provider.template)
                            .font(Typography.callout.monospaced())
                            .foregroundStyle(Colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        settings.searchProviders.removeAll { $0.id == provider.id }
                    } label: { Label("Remove \(provider.name)", systemImage: "trash") }
                    .buttonStyle(.freshet(.quiet, size: .small, width: .square))
                    .help("Remove \(provider.name)")
                }
                .formRowPadding()
            }
        }
        let candidate = SearchProvider(name: name.trimmingCharacters(in: .whitespaces), template: template.trimmingCharacters(in: .whitespaces))
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            FormGroup(title: "Add a search site") {
                FormRow("Name") {
                    TextInput("Site name", text: $name, prompt: "Example", width: 300)
                }
                FormDivider()
                FormRow("Search URL") {
                    TextInput("Search URL", text: $template, prompt: "https://example.com/search?q=%s", width: 300, monospaced: true)
                }
            }
            HStack {
                Text("%s is replaced by what you type.")
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                Spacer()
                Button {
                    settings.searchProviders.append(candidate)
                    if settings.selectedSearchProvider == nil { settings.selectedSearchProvider = candidate.id }
                    name = ""
                    template = ""
                } label: { Label("Add Site", systemImage: "plus") }
                .buttonStyle(.freshet(.secondary, size: .small))
                .disabled(candidate.name.isEmpty || !candidate.isValid)
            }
            .padding(.horizontal, Spacing.xxSmall)
        }
    }
}

struct AdvancedPreferences: View {
    @Bindable var settings: AppSettings
    let model: AppModel
    @State private var showExpert = false

    var body: some View {
        PaneStack {
            FormGroup(title: "Run a program",
                      footer: "Commands run with zsh. Placeholders: %F file, %D folder, %N name, %L label, %T tracker, %I info-hash, %S state, %P previous state, %M status message, %K single or multi-file.") {
                FormStackRow("When a torrent finishes") {
                    TextInput("When a torrent finishes", text: $settings.runWhenFinished, prompt: "e.g. open -a Infuse %D",
                              width: nil, monospaced: true)
                }
                FormDivider()
                FormStackRow("When a torrent changes state") {
                    TextInput("When a torrent changes state", text: $settings.runWhenStateChanges, prompt: "Optional",
                              width: nil, monospaced: true)
                }
            }
            FormGroup(title: "Disk") {
                FormRow("Disk I/O threads") {
                    NumberInput("Disk I/O threads", value: $settings.diskThreads, range: 1...64, step: 1, width: 56)
                }
                FormDivider()
                FormRow("Hashing threads") {
                    NumberInput("Hashing threads", value: $settings.hashingThreads, range: 1...32, step: 1, width: 56)
                }
                FormDivider()
                FormRow("Write queue") {
                    NumberInput("Write queue", value: $settings.maxQueuedDiskMB, range: 1...1_024, unit: "MB")
                }
                FormDivider()
                FormRow("Open files") {
                    NumberInput("Open files", value: $settings.filePoolSize, range: 4...2_000, step: 4, width: 56)
                }
            }
            FormGroup(title: "Expert settings",
                      footer: "The torrent engine's own settings. Changes apply right away and take priority over the other panes.") {
                FormRow("Changed settings", caption: settings.advancedOverrides.isEmpty ? "None" : "\(settings.advancedOverrides.count) changed") {
                    Button("Edit Expert Settings…") { showExpert = true }
                        .buttonStyle(.freshet(.secondary, size: .small))
                }
            }
        }
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
    @State private var focusFilter = false
    @State private var selection: AdvancedSetting.ID?
    @State private var editValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(alignment: .top, spacing: Spacing.medium) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("Expert Settings")
                        .font(Typography.pageTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Changed settings are shown in bold. Changes apply right away and take priority over the other panes.")
                        .font(Typography.callout)
                        .foregroundStyle(Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.medium)
                SearchCapsule(text: $filter, prompt: "Filter by name", width: 200, focusRequest: $focusFilter)
            }
            Table(shown, selection: $selection) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .font(settings.advancedOverrides[item.name] != nil ? Typography.headline : Typography.body)
                }
                TableColumn("Value") { item in
                    Text(item.value).font(Typography.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                .width(min: 80, ideal: 160)
                TableColumn("Default") { item in
                    Text(item.defaultValue).font(Typography.callout.monospaced()).foregroundStyle(Colors.textSecondary).lineLimit(1)
                }
                .width(min: 60, ideal: 120)
            }
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .card()
            .frame(minHeight: 240)
            HStack(spacing: Spacing.xSmall) {
                if let item = items.first(where: { $0.id == selection }) {
                    Text(item.name)
                        .font(Typography.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if item.kind == .toggle {
                        ValuePicker(item.name, selection: $editValue, options: ["true", "false"], minWidth: 80) { $0 }
                    } else {
                        TextInput(item.name, text: $editValue, prompt: "Value", width: 200, monospaced: true)
                    }
                    Button("Set") {
                        settings.advancedOverrides[item.name] = editValue
                        reloadSoon()
                    }
                    .buttonStyle(.freshet(.secondary, size: .small))
                    Button("Reset") {
                        settings.advancedOverrides.removeValue(forKey: item.name)
                        reloadSoon()
                    }
                    .buttonStyle(.freshet(.quiet, size: .small))
                    .disabled(settings.advancedOverrides[item.name] == nil)
                } else {
                    Text("Select a setting to change it.")
                        .font(Typography.callout)
                        .foregroundStyle(Colors.textSecondary)
                    Spacer()
                }
                Rectangle().fill(Colors.borderSubtle).frame(width: 1, height: 20)
                Button("Done") { dismiss() }
                    .buttonStyle(.freshet(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.large)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .themedWindow()
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
