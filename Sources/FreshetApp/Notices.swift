import FreshetCore
import SwiftUI

// MARK: Banners

/// A strip across the top of the main window for things that need attention: errors, the
/// transfer cap, a closed port, the scheduler and the when-downloads-finish countdown. It
/// replaces alerts for anything that doesn't have to stop people mid-task.
struct NoticeBanner<Actions: View>: View {
    enum Kind {
        case error, warning, info

        var symbol: String {
            switch self {
            case .error: return "xmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: return Palette.error
            case .warning: return Palette.warning
            case .info: return Palette.info
            }
        }

        var spokenName: String {
            switch self {
            case .error: return "Error"
            case .warning: return "Warning"
            case .info: return "Information"
            }
        }
    }

    let kind: Kind
    let title: String
    var detail: String?
    var onClose: (() -> Void)?
    @ViewBuilder var actions: () -> Actions
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(kind.tint)
                .accessibilityLabel(kind.spokenName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                if let detail { Text(detail).foregroundStyle(.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions()
            if let onClose {
                Button(action: onClose) {
                    Label("Dismiss", systemImage: "xmark").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(kind.tint.opacity(Palette.fillOpacity(contrast, standard: 0.12)))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

extension NoticeBanner where Actions == EmptyView {
    init(kind: Kind, title: String, detail: String? = nil, onClose: (() -> Void)? = nil) {
        self.init(kind: kind, title: title, detail: detail, onClose: onClose) { EmptyView() }
    }
}

/// Every banner the main window can show, most urgent first.
struct NoticeArea: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general

    var body: some View {
        VStack(spacing: 0) {
            if let countdown = model.whenDoneCountdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NoticeBanner(kind: .warning, title: "All downloads have finished",
                                 detail: countdown.message(at: context.date)) {
                        Button("Cancel") { model.cancelWhenDone() }
                        Button("\(countdown.action.title) Now") { model.performWhenDoneNow() }
                    }
                }
            }
            if let message = model.errorMessage {
                NoticeBanner(kind: .error, title: message, onClose: { model.errorMessage = nil })
            }
            if model.automation.capReached {
                let cap = model.settings.transferCap
                NoticeBanner(kind: .warning, title: "Transfer cap reached — all transfers are stopped",
                             detail: "\(Format.bytes(model.automation.capUsage)) used of \(Format.bytes(cap.bytes)) in the last \(cap.periodDays) days.") {
                    Button("Transfer Cap Settings…") { open(.transferCap) }
                }
            }
            if model.listenFailed {
                NoticeBanner(kind: .error, title: "Peers can't connect to this Mac",
                             detail: "Freshet couldn't open port \(String(model.settings.listenPort)) for incoming connections, so downloads may be slow.") {
                    Button("Connection Settings…") { open(.connection) }
                }
            }
            if let schedulerNotice {
                NoticeBanner(kind: .info, title: schedulerNotice) {
                    Button("Scheduler Settings…") { open(.scheduler) }
                }
            }
            if model.showSetupNotice {
                NoticeBanner(kind: .info, title: "Finish setting up Freshet",
                             detail: "Choose where downloads go, set your upload speed and check that peers can reach you.",
                             onClose: { model.settings.setupGuideShown = true }) {
                    Button("Open Setup Guide…") { model.showSetupGuide = true }
                }
            }
        }
    }

    private var schedulerNotice: String? {
        guard model.settings.schedule.isEnabled else { return nil }
        switch model.automation.scheduleMode {
        case .off: return "The scheduler has turned transfers off for this hour"
        case .seedingOnly: return "The scheduler is only seeding this hour — downloads are paused"
        case .full, .limited: return nil
        }
    }

    private func open(_ target: SettingsPane) {
        pane = target
        openSettings()
    }
}

// MARK: Text entry

/// A short question that needs a typed answer, such as a label name or a peer address. Shown as
/// a sheet on the main window instead of an alert, and checked as people type.
struct TextPrompt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var placeholder: String
    var actionTitle: String
    /// Returns why the text can't be used yet, or nil when it's fine. An empty string disables
    /// the action without showing a message.
    var validate: @MainActor (String) -> String? = { _ in nil }
    var commit: @MainActor (String) -> Void
}

struct TextPromptSheet: View {
    let prompt: TextPrompt
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let problem = value.isEmpty ? "" : prompt.validate(value)
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.title).font(.headline)
            Text(prompt.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(prompt.title, text: $text, prompt: Text(prompt.placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if problem == nil { finish(value) } }
            if let problem, !problem.isEmpty {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(prompt.actionTitle) { finish(value) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { focused = true }
    }

    private func finish(_ value: String) {
        prompt.commit(value)
        dismiss()
    }
}

// MARK: When downloads finish

struct WhenDoneCountdown {
    static let delay: TimeInterval = 60
    let action: WhenDoneAction
    let deadline: Date

    func secondsLeft(at date: Date) -> Int { max(0, Int(deadline.timeIntervalSince(date).rounded(.up))) }

    func message(at date: Date) -> String {
        "Freshet will \(action.phrase) in \(secondsLeft(at: date)) seconds."
    }
}

extension WhenDoneAction {
    /// How the action reads in a sentence: "Freshet will shut down the Mac in 30 seconds."
    var phrase: String {
        switch self {
        case .nothing: return "do nothing"
        case .quit: return "quit"
        case .sleep: return "put the Mac to sleep"
        case .shutDown: return "shut down the Mac"
        case .restart: return "restart the Mac"
        }
    }
}

// MARK: Settings panes

/// The Settings window's panes. The selection is stored so a banner can open a specific one.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, folders, connection, bandwidth, bittorrent, scheduler, transferCap, search, advanced

    static let storageKey = "settingsPane"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .folders: return "Folders"
        case .connection: return "Connection"
        case .bandwidth: return "Bandwidth"
        case .bittorrent: return "BitTorrent"
        case .scheduler: return "Scheduler"
        case .transferCap: return "Transfer Cap"
        case .search: return "Search"
        case .advanced: return "Advanced"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .folders: return "folder"
        case .connection: return "network"
        case .bandwidth: return "speedometer"
        case .bittorrent: return "point.3.connected.trianglepath.dotted"
        case .scheduler: return "calendar"
        case .transferCap: return "gauge.with.needle"
        case .search: return "magnifyingglass"
        case .advanced: return "slider.horizontal.3"
        }
    }
}
