import AppKit
import FreshetCore
import SwiftUI

/// The menu bar icon. Shows live speeds when transferring.
struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.settings.showSpeedInMenuBar && (model.totalDownloadRate > 0 || model.totalUploadRate > 0) {
                Text("↓\(Format.compactRate(model.totalDownloadRate)) ↑\(Format.compactRate(model.totalUploadRate))")
                    .monospacedDigit()
            } else {
                Image(systemName: "arrow.down.circle")
            }
        }
        .accessibilityLabel("Freshet")
        .accessibilityValue("Downloading \(Format.rateOrZero(model.totalDownloadRate)), uploading \(Format.rateOrZero(model.totalUploadRate))")
        .onReceive(NotificationCenter.default.publisher(for: .freshetOpenMainWindow)) { _ in
            openWindow(id: mainWindowID)
            NSApp.activate()
        }
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let countdown = model.whenDoneCountdown {
            Text(countdown.message(at: Date()))
            Button("Cancel \(countdown.action.title)") { model.cancelWhenDone() }
            Divider()
        }
        Text("Down \(Format.rateOrZero(model.totalDownloadRate)) · Up \(Format.rateOrZero(model.totalUploadRate))")
        let active = Array(model.activeTorrents.prefix(8))
        if !active.isEmpty {
            Divider()
            ForEach(active) { torrent in
                Text("\(torrent.displayName.prefix(40)) — \(Format.percent(torrent.progress))")
            }
        }
        Divider()
        Button("Resume All") { model.resumeAll() }
        Button("Pause All") { model.pauseAll() }
        Divider()
        Menu("Download Limit") {
            ForEach(SpeedPresets.values(around: model.settings.downloadLimitKBps), id: \.self) { value in
                Toggle(SpeedPresets.title(value), isOn: Binding(
                    get: { model.settings.downloadLimitKBps == value },
                    set: { if $0 { model.setGlobalLimits(downloadKBps: value) } }))
            }
        }
        Menu("Upload Limit") {
            ForEach(SpeedPresets.values(around: model.settings.uploadLimitKBps), id: \.self) { value in
                Toggle(SpeedPresets.title(value), isOn: Binding(
                    get: { model.settings.uploadLimitKBps == value },
                    set: { if $0 { model.setGlobalLimits(uploadKBps: value) } }))
            }
        }
        Divider()
        Button("Open Freshet") {
            openWindow(id: mainWindowID)
            NSApp.activate()
        }
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit Freshet") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Speed limit presets: unlimited plus steps around the current limit.
enum SpeedPresets {
    static let standard = [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]

    static func values(around current: Int) -> [Int] {
        var values = Set(standard)
        if current > 0 { values.insert(current) }
        return [0] + values.sorted()
    }

    static func title(_ kilobytesPerSecond: Int) -> String {
        kilobytesPerSecond == 0 ? "Unlimited" : Format.rate(kilobytesPerSecond * 1_024)
    }

    /// The same presets as an AppKit menu, for the Dock.
    @MainActor
    static func menu(title: String, current: Int, apply: @escaping (Int) -> Void) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        for value in values(around: current) {
            let item = ClosureMenuItem(self.title(value)) { apply(value) }
            item.state = value == current ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
