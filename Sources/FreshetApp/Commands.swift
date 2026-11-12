import AppKit
import FreshetCore
import SwiftUI

struct FreshetCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(TorrentListStyle.storageKey) private var listStyle: TorrentListStyle = .cards
    @AppStorage("sidebarHidden") private var sidebarHidden = false
    /// The sidebar of whichever window is in front.
    @FocusedBinding(\.sidebarHidden) private var focusedSidebarHidden: Bool?

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: settingsWindowID) }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Add Torrent…") { model.openTorrentFiles() }
                .keyboardShortcut("o")
            Button("Add from URL or Magnet Link…") { model.showAddURL = true }
                .keyboardShortcut("u")
            Button("Search the Web for Torrents…") {
                openWindow(id: mainWindowID)
                model.showWebSearch = true
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("New Torrent…") { openWindow(id: "create") }
                .keyboardShortcut("n")
            Button("RSS Downloader") { openWindow(id: "rss") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandMenu("Torrent") {
            Button("Start") { model.perform(.start) }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Pause") { model.perform(.pause) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Force Start") { model.perform(.forceStart) }
            Divider()
            Button("Properties…") { model.showProperties() }
                .keyboardShortcut("i")
            Divider()
            Button("Force Re-check") { model.perform(.recheck) }
            Button("Update Tracker") { model.perform(.reannounce) }
            Divider()
            Button("Move Up in Queue") { model.perform(.queueUp) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Move Down in Queue") { model.perform(.queueDown) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Show in Finder") { if let id = model.focusedID { model.reveal(id) } }
                .keyboardShortcut("r")
            Button("Copy Magnet Link") { model.copyMagnetLinks() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Save .torrent File…") { model.saveTorrentFile() }
            Button("Set Download Location…") { model.chooseDownloadLocation() }
            Menu("Bandwidth Allocation") {
                ForEach(BandwidthPriority.allCases.reversed(), id: \.self) { priority in
                    Button(priority.title) { model.setPriority(priority) }
                }
            }
            Divider()
            Button("Resume All") { model.resumeAll() }
            Button("Pause All") { model.pauseAll() }
            Picker("When Downloads Finish", selection: Binding(get: { model.settings.whenDone }, set: { model.settings.whenDone = $0 })) {
                ForEach(WhenDoneAction.allCases, id: \.self) { action in Text(action.title).tag(action) }
            }
            Divider()
            Button("Remove…") { model.requestRemove() }
                .keyboardShortcut(.delete, modifiers: [.command])
        }
        CommandGroup(replacing: .help) {
            Button("Freshet Help") { openWindow(id: "help") }
                .keyboardShortcut("?", modifiers: [.command])
            Divider()
            Button("Setup Guide…") {
                openWindow(id: mainWindowID)
                model.showSetupGuide = true
            }
            Divider()
            Button("Third-Party Notices") {
                if let url = AppPaths.thirdPartyNotices { NSWorkspace.shared.open(url) }
            }
        }
        CommandGroup(after: .sidebar) {
            let hidden = focusedSidebarHidden ?? sidebarHidden
            Button(hidden ? "Show Sidebar" : "Hide Sidebar") {
                if let current = focusedSidebarHidden {
                    focusedSidebarHidden = !current
                } else {
                    sidebarHidden.toggle()
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Button(model.showInspector ? "Hide Details" : "Show Details") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Picker("Show Torrents", selection: $listStyle) {
                Text("as Cards").tag(TorrentListStyle.cards)
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Text("as Table").tag(TorrentListStyle.table)
                    .keyboardShortcut("2", modifiers: [.command, .option])
            }
            .pickerStyle(.inline)
        }
        CommandGroup(after: .textEditing) {
            Button("Filter Torrents") {
                openWindow(id: mainWindowID)
                model.focusFilter = true
            }
            .keyboardShortcut("f")
        }
    }
}
