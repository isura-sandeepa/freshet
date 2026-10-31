import FreshetCore
import SwiftUI

/// The main window: categories on the left, the torrent list on top, detail tabs below,
/// and a status bar along the bottom.
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } detail: {
            VSplitView {
                TorrentListView()
                    .frame(minHeight: 150, idealHeight: 400, maxHeight: .infinity)
                if model.showInspector {
                    DetailTabsView()
                        .frame(minHeight: 170, idealHeight: 270, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { NoticeArea() }
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBarView() }
        }
        .navigationTitle(model.windowTitle)
        .toolbar { MainToolbar(model: model) }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter torrents")
        .sheet(isPresented: $model.isAddSheetPresented) {
            if let pending = model.pendingAdds.first {
                AddTorrentSheet(pending: pending).id(pending.id)
            }
        }
        .sheet(isPresented: $model.showAddURL) { AddURLSheet() }
        .sheet(item: propertiesBinding) { target in PropertiesSheet(id: target.id) }
        .sheet(isPresented: $model.showSetupGuide) { SetupGuideView() }
        .sheet(item: $model.textPrompt) { prompt in TextPromptSheet(prompt: prompt) }
        .confirmationDialog(removeTitle, isPresented: removeBinding, titleVisibility: .visible) {
            Button("Remove") {
                if let ids = model.removeRequest { model.remove(ids, moveDataToTrash: false) }
            }
            Button("Remove and Move Data to Trash", role: .destructive) {
                if let ids = model.removeRequest { model.remove(ids, moveDataToTrash: true) }
            }
            Button("Cancel", role: .cancel) { model.removeRequest = nil }
        } message: {
            Text("Downloaded files stay on disk unless you move them to the Trash.")
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleOpen(urls)
            return true
        }
    }

    private var removeTitle: String {
        let ids = model.removeRequest ?? []
        if ids.count == 1, let id = ids.first, let torrent = model.torrents[id] {
            return "Remove “\(torrent.displayName)”?"
        }
        return "Remove \(ids.count) torrents?"
    }

    private var propertiesBinding: Binding<PropertiesTarget?> {
        Binding(get: { model.propertiesTarget.map(PropertiesTarget.init) }, set: { model.propertiesTarget = $0?.id })
    }

    private var removeBinding: Binding<Bool> {
        Binding(get: { model.removeRequest != nil }, set: { if !$0 { model.removeRequest = nil } })
    }
}

struct PropertiesTarget: Identifiable {
    let id: TorrentID
}

/// Web search for torrents, as a toolbar button with a popover so the toolbar has one
/// search field (the torrent filter). Also opened from File > Search the Web for Torrents.
struct WebSearchButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Button { model.showWebSearch.toggle() } label: {
            Label("Search the Web", systemImage: "globe")
        }
        .help("Search the web for torrents (⌥⌘F)")
        .popover(isPresented: $model.showWebSearch, arrowEdge: .bottom) { WebSearchPopover() }
    }
}

struct WebSearchPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let settings = model.settings
        let providers = settings.searchProviders
        let current = providers.first { $0.id == settings.selectedSearchProvider } ?? providers.first
        VStack(alignment: .leading, spacing: 10) {
            Text("Search the Web for Torrents").font(.headline)
            if let current {
                if providers.count > 1 {
                    Picker("Site", selection: Binding(get: { current.id }, set: { settings.selectedSearchProvider = $0 })) {
                        ForEach(providers) { provider in Text(provider.name).tag(provider.id) }
                    }
                }
                HStack {
                    TextField("Search \(current.name)", text: $query, prompt: Text("Search \(current.name)"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onSubmit(search)
                    Button("Search", action: search)
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Results open in your browser.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Add the search sites you use, then search them from here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add a Search Site…") {
                    model.showWebSearch = false
                    pane = .search
                    openSettings()
                }
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func search() {
        let settings = model.settings
        guard let current = settings.searchProviders.first(where: { $0.id == settings.selectedSearchProvider }) ?? settings.searchProviders.first,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.webSearch(query, provider: current)
        model.showWebSearch = false
    }
}

struct MainToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.openTorrentFiles() } label: {
                Label("Add Torrent", systemImage: "plus")
            }
            .help("Add .torrent files (⌘O)")
            Button { model.showAddURL = true } label: {
                Label("Add from URL", systemImage: "link.badge.plus")
            }
            .help("Add a magnet link or torrent URL (⌘U)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.perform(.start) } label: {
                Label("Start", systemImage: "play.fill")
            }
            .help("Start")
            .disabled(model.selection.isEmpty)
            Button { model.perform(.pause) } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .help("Pause")
            .disabled(model.selection.isEmpty)
            Button { model.requestRemove() } label: {
                Label("Remove", systemImage: "trash")
            }
            .help("Remove (⌘⌫)")
            .disabled(model.selection.isEmpty)
            Button { model.perform(.queueUp) } label: {
                Label("Move Up in Queue", systemImage: "arrow.up")
            }
            .help("Move up in queue")
            .disabled(model.selection.isEmpty)
            Button { model.perform(.queueDown) } label: {
                Label("Move Down in Queue", systemImage: "arrow.down")
            }
            .help("Move down in queue")
            .disabled(model.selection.isEmpty)
            Button { model.showProperties() } label: {
                Label("Properties", systemImage: "slider.horizontal.3")
            }
            .help("Properties (⌘I)")
            .disabled(model.selection.isEmpty)
            Button { model.showInspector.toggle() } label: {
                Label("Details", systemImage: "rectangle.split.1x2")
            }
            .help(model.showInspector ? "Hide details" : "Show details")
        }
        ToolbarItem(placement: .automatic) {
            WebSearchButton()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selectionBinding) {
            Section("Torrents") {
                ForEach(SidebarFilter.standard, id: \.self) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .badge(model.count(for: filter))
                        .tag(Optional(filter))
                }
            }
            Section("Labels") {
                Label(SidebarFilter.noLabel.title, systemImage: SidebarFilter.noLabel.systemImage)
                    .badge(model.count(for: .noLabel))
                    .tag(Optional(SidebarFilter.noLabel))
                ForEach(model.labels.names, id: \.self) { name in
                    Label(name, systemImage: "tag")
                        .badge(model.count(for: .label(name)))
                        .tag(Optional(SidebarFilter.label(name)))
                        .contextMenu {
                            Button("Delete Label") { model.deleteLabel(name) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 210)
    }

    private var selectionBinding: Binding<SidebarFilter?> {
        Binding(get: { model.filter }, set: { if let value = $0 { model.filter = value } })
    }
}

struct StatusBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            if model.isSimulated {
                Text("Simulation")
                    .font(.callout.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Palette.warning.opacity(0.25)))
                    .help("Freshet is running with simulated torrents (--simulate)")
            }
            Label("DHT: \(model.session.dhtNodes) \(model.session.dhtNodes == 1 ? "node" : "nodes")",
                  systemImage: "point.3.connected.trianglepath.dotted")
            Label("Down \(Format.rateOrZero(model.totalDownloadRate))\(limitText(model.settings.downloadLimitKBps))", systemImage: "arrow.down")
            Label("Up \(Format.rateOrZero(model.totalUploadRate))\(limitText(model.settings.uploadLimitKBps))", systemImage: "arrow.up")
            if model.automation.capReached {
                Label("Transfer cap reached", systemImage: "gauge.with.needle.fill").foregroundStyle(Palette.warning)
            }
            if model.settings.schedule.isEnabled {
                Label("Scheduler: \(model.automation.scheduleMode.title)", systemImage: "calendar")
                    .foregroundStyle(model.automation.scheduleMode == .full ? Color.secondary : model.automation.scheduleMode.color)
            }
            if model.session.isPaused && !model.automation.capReached && model.automation.scheduleMode != .off {
                Label("Paused", systemImage: "pause.circle")
            }
            Spacer()
            portStatus
            Text("\(model.torrents.count) \(model.torrents.count == 1 ? "torrent" : "torrents")")
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func limitText(_ kilobytesPerSecond: Int) -> String {
        kilobytesPerSecond > 0 ? " (limit \(Format.rate(kilobytesPerSecond * 1_024)))" : ""
    }

    @ViewBuilder private var portStatus: some View {
        if model.session.isListening {
            if model.hasIncomingConnections {
                Label("Port \(String(model.session.listenPort)) reachable", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
            } else {
                Label("Port \(String(model.session.listenPort))", systemImage: "network")
                    .help("No incoming connections yet. If downloads are slow, check port forwarding.")
            }
        } else {
            Label("Not listening", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.error)
        }
    }
}
