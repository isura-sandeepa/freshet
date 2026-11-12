import AppKit
import FreshetCore
import SwiftUI
import Testing
@testable import FreshetApp

/// Renders screens against the simulated engine into .devloop/snapshots so they can be looked
/// at without clicking through the app. Runs only when .devloop/snapshots-on exists.
@MainActor
struct SnapshotTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func renderScreens() async throws {
        let marker = Self.root.appendingPathComponent(".devloop/snapshots-on")
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let out = Self.root.appendingPathComponent(".devloop/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = AppModel(simulate: true)
        model.start()
        try await Task.sleep(nanoseconds: 2_500_000_000)
        model.selection = Set(model.visible.prefix(1).map(\.id))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let s = model.settings
        if model.rss.filters.isEmpty {
            var sample = model.rss.newFilter()
            sample.name = "Sample show"
            sample.include = "*sample*1080p*"
            sample.qualities = [.hd1080]
            sample.smartEpisodeFilter = true
            model.rss.filters[0] = sample
        }
        let screens: [(String, AnyView, CGSize)] = [
            ("main", AnyView(MainView()), CGSize(width: 1_200, height: 780)),
            ("setup-guide", AnyView(SetupGuideView()), CGSize(width: 560, height: 600)),
            ("rss-feeds", AnyView(RSSFeedsView(rss: model.rss)), CGSize(width: 980, height: 560)),
            ("rss-filters", AnyView(RSSFiltersView(rss: model.rss)), CGSize(width: 980, height: 560)),
            ("create-torrent", AnyView(CreateTorrentView()), CGSize(width: 560, height: 640)),
            ("expert-settings", AnyView(ExpertSettingsSheet(settings: s, model: model)), CGSize(width: 760, height: 560)),
            ("help", AnyView(HelpView()), CGSize(width: 860, height: 600)),
            ("web-search", AnyView(WebSearchPopover()), CGSize(width: 340, height: 150)),
        ]
        // Settings panes render at the size the Settings window gives them.
        var sizes: [String] = []
        let panes: [(SettingsPane, AnyView)] = [
            (.general, AnyView(GeneralPreferences(settings: s, model: model))),
            (.folders, AnyView(FoldersPreferences(settings: s))),
            (.connection, AnyView(ConnectionPreferences(settings: s, model: model))),
            (.bandwidth, AnyView(BandwidthPreferences(settings: s))),
            (.bittorrent, AnyView(BitTorrentPreferences(settings: s))),
            (.scheduler, AnyView(SchedulerPreferences(settings: s))),
            (.transferCap, AnyView(TransferCapPreferences(settings: s, automation: model.automation))),
            (.search, AnyView(SearchPreferences(settings: s))),
            (.advanced, AnyView(AdvancedPreferences(settings: s, model: model))),
        ]
        for (pane, view) in panes {
            let sized = AnyView(view.settingsPane().environment(model))
            let fitting = NSHostingView(rootView: sized).fittingSize
            sizes.append("\(pane.rawValue) \(Int(fitting.width))x\(Int(fitting.height))")
            try await render(sized, size: CGSize(width: max(fitting.width, 100), height: max(fitting.height, 100)), to: out.appendingPathComponent("pref-\(pane.rawValue).png"))
        }
        try sizes.joined(separator: "\n").write(to: out.appendingPathComponent("pane-sizes.txt"), atomically: true, encoding: .utf8)
        try await render(AnyView(TextPromptSheet(prompt: TextPrompt(title: "Add Peer", message: "Enter the peer's address and port, such as 203.0.113.5:51413.",
                                                                     placeholder: "IP address:port", actionTitle: "Add Peer", commit: { _ in })).environment(model)),
                         size: CGSize(width: 400, height: 170), to: out.appendingPathComponent("text-prompt.png"))
        for (name, view, frame) in screens {
            try await render(AnyView(view.environment(model)), size: frame, to: out.appendingPathComponent("\(name).png"))
        }
        try await render(AnyView(FilterEditor(filter: .constant(model.rss.filters[0]), rss: model.rss).environment(model)),
                         size: CGSize(width: 560, height: 700), to: out.appendingPathComponent("rss-filter-editor.png"))
        try await render(AnyView(MainView().environment(model)), size: CGSize(width: 1_200, height: 780),
                         to: out.appendingPathComponent("main-light.png"), appearance: .aqua)
        UserDefaults.standard.set(TorrentListStyle.table.rawValue, forKey: TorrentListStyle.storageKey)
        try await render(AnyView(MainView().environment(model)), size: CGSize(width: 1_200, height: 780),
                         to: out.appendingPathComponent("main-table.png"))
        UserDefaults.standard.set(TorrentListStyle.cards.rawValue, forKey: TorrentListStyle.storageKey)
        model.errorMessage = "“Example.torrent” is already in the list."
        model.whenDoneCountdown = WhenDoneCountdown(action: .sleep, deadline: Date().addingTimeInterval(42))
        try await render(AnyView(NoticeArea().environment(model)), size: CGSize(width: 1_000, height: 120),
                         to: out.appendingPathComponent("notices.png"))
        model.errorMessage = nil
        model.whenDoneCountdown = nil
        if let id = model.focusedID {
            try await render(AnyView(PropertiesSheet(id: id).environment(model)), size: CGSize(width: 520, height: 640),
                             to: out.appendingPathComponent("properties.png"))
            for tab in ["peers", "general", "trackers"] {
                UserDefaults.standard.set(tab, forKey: "detailTab")
                try await render(AnyView(DetailTabsView().environment(model)), size: CGSize(width: 1_000, height: 300),
                                 to: out.appendingPathComponent("tab-\(tab).png"))
            }
        }
    }

    private func render(_ view: AnyView, size: CGSize, to url: URL, appearance: NSAppearance.Name = .darkAqua) async throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 800_000_000)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
