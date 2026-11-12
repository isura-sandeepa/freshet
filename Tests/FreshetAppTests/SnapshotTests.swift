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
        func file(_ name: String) -> URL { out.appendingPathComponent("\(name).png") }

        // Windows, at their default sizes, in both appearances.
        let windows: [(String, () -> AnyView, CGSize)] = [
            ("main", { AnyView(MainView()) }, CGSize(width: 1_200, height: 780)),
            ("help", { AnyView(HelpView()) }, CGSize(width: 880, height: 620)),
            ("create-torrent", { AnyView(CreateTorrentView()) }, CGSize(width: 620, height: 760)),
        ]
        for (name, view, size) in windows {
            try await render(view().environment(model), size: size, to: file(name))
            try await render(view().environment(model), size: size, to: file("\(name)-light"), appearance: .aqua)
        }
        UserDefaults.standard.set(TorrentListStyle.table.rawValue, forKey: TorrentListStyle.storageKey)
        try await render(MainView().environment(model), size: CGSize(width: 1_200, height: 780), to: file("main-table"))
        UserDefaults.standard.set(TorrentListStyle.cards.rawValue, forKey: TorrentListStyle.storageKey)

        // RSS, both tabs.
        for tab in RSSTab.allCases {
            UserDefaults.standard.set(tab.rawValue, forKey: RSSTab.storageKey)
            try await render(RSSWindow().environment(model), size: CGSize(width: 1_000, height: 640), to: file("rss-\(tab.rawValue)"))
            try await render(RSSWindow().environment(model), size: CGSize(width: 1_000, height: 640), to: file("rss-\(tab.rawValue)-light"),
                             appearance: .aqua)
        }

        // Settings: the window on each pane, plus each pane's whole content.
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
        for (pane, content) in panes {
            UserDefaults.standard.set(pane.rawValue, forKey: SettingsPane.storageKey)
            try await render(PreferencesView().environment(model), size: CGSize(width: 900, height: 660), to: file("settings-\(pane.rawValue)"))
            if pane == .general || pane == .scheduler {
                try await render(PreferencesView().environment(model), size: CGSize(width: 900, height: 660),
                                 to: file("settings-\(pane.rawValue)-light"), appearance: .aqua)
            }
            try await renderFitting(content.padding(24).frame(width: 659).themedWindow().environment(model),
                                    to: file("pane-\(pane.rawValue)"))
        }
        UserDefaults.standard.set(SettingsPane.general.rawValue, forKey: SettingsPane.storageKey)

        // Sheets and popovers at their natural height.
        let sheets: [(String, () -> AnyView)] = [
            ("setup-guide", { AnyView(SetupGuideView()) }),
            ("add-url", { AnyView(AddURLSheet()) }),
            ("add-feed", { AnyView(AddFeedSheet(rss: model.rss)) }),
            ("text-prompt", {
                AnyView(TextPromptSheet(prompt: TextPrompt(title: "Add Peer", message: "Enter the peer's address and port, such as 203.0.113.5:51413.",
                                                           placeholder: "IP address:port", actionTitle: "Add Peer", commit: { _ in })))
            }),
            ("web-search", { AnyView(WebSearchPopover()) }),
        ]
        for (name, view) in sheets {
            try await renderFitting(view().environment(model), to: file(name))
            try await renderFitting(view().environment(model), to: file("\(name)-light"), appearance: .aqua)
        }
        try await render(ExpertSettingsSheet(settings: s, model: model).environment(model), size: CGSize(width: 760, height: 560),
                         to: file("expert-settings"))
        try await render(FilterEditor(filter: .constant(model.rss.filters[0]), rss: model.rss).padding(24).frame(width: 640).themedWindow()
                            .environment(model), size: CGSize(width: 640, height: 900), to: file("rss-filter-editor"))

        model.errorMessage = "“Example.torrent” is already in the list."
        model.whenDoneCountdown = WhenDoneCountdown(action: .sleep, deadline: Date().addingTimeInterval(42))
        try await render(NoticeArea().environment(model), size: CGSize(width: 1_000, height: 120), to: file("notices"))
        model.errorMessage = nil
        model.whenDoneCountdown = nil
        if let id = model.focusedID {
            try await renderFitting(PropertiesSheet(id: id).environment(model), to: file("properties"))
            try await renderFitting(PropertiesSheet(id: id).environment(model), to: file("properties-light"), appearance: .aqua)
            for tab in ["general", "files", "peers", "trackers", "speed", "logger"] {
                UserDefaults.standard.set(tab, forKey: "detailTab")
                try await render(DetailTabsView().card().padding(12).themedWindow().environment(model), size: CGSize(width: 1_000, height: 320),
                                 to: file("tab-\(tab)"))
            }
            UserDefaults.standard.set("general", forKey: "detailTab")
            try await render(DetailTabsView().card().padding(12).themedWindow().environment(model), size: CGSize(width: 1_000, height: 320),
                             to: file("tab-general-light"), appearance: .aqua)
        }

        // Outlined capsules through SwiftUI's own renderer as well, to tell artifacts of the
        // bitmap capture above from real drawing problems.
        let probe = HStack(spacing: 12) {
            Button("Choose…") {}.buttonStyle(.freshet(.secondary, size: .small))
            Button {} label: { Label("Search the Web", systemImage: "globe") }.buttonStyle(.freshet(.secondary, width: .square))
            Button {} label: { Label("Add from URL", systemImage: "link") }.buttonStyle(.freshet(.secondary))
            Button {} label: { Label("Add Torrent", systemImage: "plus") }.buttonStyle(.freshet(.primary))
        }
        .padding(20)
        .background(Colors.surfaceBase)
        let renderer = ImageRenderer(content: probe)
        renderer.scale = 2
        if let image = renderer.cgImage {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file("probe-renderer"))
        }
        try await render(probe, size: CGSize(width: 520, height: 70), to: file("probe-capture"), appearance: .aqua)
    }

    private func render(_ view: some View, size: CGSize, to url: URL, appearance: NSAppearance.Name = .darkAqua) async throws {
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

    /// Renders at the view's own fitting size, for sheets and panes whose height depends on content.
    private func renderFitting(_ view: some View, to url: URL, appearance: NSAppearance.Name = .darkAqua) async throws {
        let probe = NSHostingView(rootView: view)
        probe.appearance = NSAppearance(named: appearance)
        let fitting = probe.fittingSize
        try await render(view, size: CGSize(width: max(fitting.width, 100), height: min(max(fitting.height, 100), 2_400)), to: url,
                         appearance: appearance)
    }
}
