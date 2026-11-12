import AppKit
import FreshetCore
import SwiftUI

/// The main window: categories in the sidebar; a header, an overview of transfers, the
/// torrent list and the detail tabs on the right.
struct MainView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(TorrentListStyle.storageKey) private var listStyle: TorrentListStyle = .cards

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                NoticeArea()
                ContentHeader()
                OverviewStrip()
                VSplitView {
                    VStack(spacing: 6) {
                        HStack {
                            Spacer()
                            if listStyle == .cards { SortMenu() }
                        }
                        .padding(.horizontal, 4)
                        Group {
                            switch listStyle {
                            case .cards: TorrentCardsView()
                            case .table: TorrentListView()
                            }
                        }
                        .panel()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, model.showInspector ? 8 : 16)
                    .frame(minHeight: 180, idealHeight: 420, maxHeight: .infinity)
                    if model.showInspector {
                        DetailTabsView()
                            .panel()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                            .frame(minHeight: 190, idealHeight: 280, maxHeight: .infinity)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(model.windowTitle)
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

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selectionBinding) {
            Section("Torrents") {
                ForEach(SidebarFilter.standard, id: \.self) { filter in
                    SidebarRow(title: filter.title, systemImage: filter.systemImage, count: model.count(for: filter))
                        .tag(Optional(filter))
                }
            }
            Section("Labels") {
                SidebarRow(title: SidebarFilter.noLabel.title, systemImage: SidebarFilter.noLabel.systemImage,
                           count: model.count(for: .noLabel))
                    .tag(Optional(SidebarFilter.noLabel))
                ForEach(model.labels.names, id: \.self) { name in
                    SidebarRow(title: name, systemImage: "tag", count: model.count(for: .label(name)))
                        .tag(Optional(SidebarFilter.label(name)))
                        .contextMenu {
                            Button("Delete Label") { model.deleteLabel(name) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { SidebarHeader() }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }

    private var selectionBinding: Binding<SidebarFilter?> {
        Binding(get: { model.filter }, set: { if let value = $0 { model.filter = value } })
    }
}

/// The app's icon and name at the top of the sidebar.
struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text("Freshet").font(.headline)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A sidebar item with its count as quiet right-aligned text rather than a badge.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 6)
            if count > 0 {
                Text("\(count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
