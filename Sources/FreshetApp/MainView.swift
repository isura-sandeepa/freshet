import AppKit
import FreshetCore
import SwiftUI

/// The main window: a fixed sidebar (brand, filters, labels, connection) beside the page —
/// a header, notices, the transfer overview, the torrent list and the details panel.
struct MainView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TorrentListStyle.storageKey) private var listStyle: TorrentListStyle = .cards
    @AppStorage("sidebarHidden") private var sidebarHidden = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if !sidebarHidden {
                SidebarView()
                SidebarDivider()
            }
            page
        }
        .themedWindow()
        .navigationTitle(model.windowTitle)
        .focusedSceneValue(\.sidebarHidden, $sidebarHidden)
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

    private var page: some View {
        VStack(spacing: 0) {
            PageHeader(leadingInset: sidebarHidden ? PageLayout.windowButtonsWidth : 0)
            NoticeArea()
            OverviewSummary()
            VSplitView {
                VStack(spacing: Spacing.xSmall) {
                    ListControls()
                    switch listStyle {
                    case .cards:
                        TorrentCardList()
                    case .table:
                        TorrentListView()
                            .card()
                            .padding(.horizontal, PageLayout.horizontalInset)
                    }
                }
                .padding(.bottom, model.showInspector ? Spacing.xSmall : Spacing.large)
                .frame(minHeight: 200, idealHeight: 440, maxHeight: .infinity)
                if model.showInspector {
                    DetailTabsView()
                        .card()
                        .padding(.horizontal, PageLayout.horizontalInset)
                        .padding(.top, Spacing.xSmall)
                        .padding(.bottom, Spacing.large)
                        .frame(minHeight: 200, idealHeight: 280, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .background(Colors.surfaceBase)
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
        .buttonStyle(.freshet(.secondary, width: .square))
        .help("Search the web for torrents (⌥⌘F)")
        .popover(isPresented: $model.showWebSearch, arrowEdge: .bottom) { WebSearchPopover() }
    }
}

struct WebSearchPopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsPane.storageKey) private var pane: SettingsPane = .general
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let settings = model.settings
        let providers = settings.searchProviders
        let current = providers.first { $0.id == settings.selectedSearchProvider } ?? providers.first
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Search the Web for Torrents").font(Typography.sectionTitle)
            if let current {
                if providers.count > 1 {
                    ValuePicker("Site", selection: Binding(get: { current.id }, set: { settings.selectedSearchProvider = $0 }),
                                options: providers.map(\.id)) { id in
                        providers.first { $0.id == id }?.name ?? ""
                    }
                }
                HStack(spacing: Spacing.xSmall) {
                    TextInput("Search \(current.name)", text: $query, prompt: "Search \(current.name)", width: nil, focus: $focused)
                        .onSubmit(search)
                    Button("Search", action: search)
                        .buttonStyle(.freshet(.primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Results open in your browser.").font(Typography.callout).foregroundStyle(Colors.textSecondary)
            } else {
                Text("Add the search sites you use, then search them from here.")
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add a Search Site…") {
                    model.showWebSearch = false
                    pane = .search
                    openWindow(id: settingsWindowID)
                }
                .buttonStyle(.freshet(.secondary, size: .small))
            }
        }
        .padding(Spacing.medium)
        .frame(width: 340)
        .font(Typography.body)
        .foregroundStyle(Colors.textPrimary)
        .tint(Colors.textPrimary)
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

/// The sidebar: the brand under the window buttons, the filters and labels as rows that fill
/// their icon when selected, and a connection card at the bottom.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandMark()
                .padding(.top, PageLayout.sidebarTopInset)
                .padding(.bottom, Spacing.large)
                .padding(.horizontal, Spacing.small + Spacing.xSmall)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                    ForEach(SidebarFilter.standard, id: \.self) { filter in
                        row(filter, title: filter.title, systemImage: filter.systemImage)
                    }
                    SidebarSectionLabel(title: "Labels")
                    row(.noLabel, title: SidebarFilter.noLabel.title, systemImage: SidebarFilter.noLabel.systemImage)
                    ForEach(model.labels.names, id: \.self) { name in
                        row(.label(name), title: name, systemImage: "tag")
                            .contextMenu {
                                Button("Delete Label") { model.deleteLabel(name) }
                            }
                    }
                }
                .padding(.horizontal, Spacing.small)
            }
            .scrollIndicators(.never)
            Spacer(minLength: Spacing.medium)
            ConnectionCard()
                .padding(.horizontal, Spacing.small)
                .padding(.bottom, Spacing.small)
        }
        .frame(width: PageLayout.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Colors.surfaceCard)
        .ignoresSafeArea(.container, edges: .top)
    }

    private func row(_ filter: SidebarFilter, title: String, systemImage: String) -> some View {
        NavRow(title: title, systemImage: systemImage, isSelected: model.filter == filter,
               count: model.count(for: filter)) {
            model.filter = filter
        }
    }

}

/// The app's icon beside a name: Freshet in the main window, the window's job elsewhere.
struct BrandMark: View {
    var title = "Freshet"

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(title).font(Typography.sectionTitle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A sidebar row: outline icon that fills when selected, the title, and a quiet count.
struct NavRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: isSelected ? Self.filled(systemImage) : systemImage)
                    .font(Typography.rowTitle)
                    .frame(width: 16)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .foregroundStyle(isSelected ? Colors.textPrimary : Colors.textSecondary)
                Text(title)
                    .font(Typography.body.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                if count > 0 {
                    Text("\(count)")
                        .font(Typography.metadataEmphasis.numbers)
                        .monospacedDigit()
                        .foregroundStyle(Colors.textTertiary)
                }
            }
            .foregroundStyle(isSelected ? Colors.textPrimary : Colors.textSecondary)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmallPlus)
            .background(isSelected ? Colors.fillSecondary : (hovering ? Colors.surfaceCardHover : .clear),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// The filled variant of a symbol when SF Symbols has one.
    static func filled(_ name: String) -> String {
        let candidate = name + ".fill"
        return NSImage(systemSymbolName: candidate, accessibilityDescription: nil) == nil ? name : candidate
    }
}

/// The sidebar's bottom card: whether peers can reach this Mac, and the DHT size.
struct ConnectionCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmallPlus) {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(statusText).font(Typography.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Colors.textSecondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text("\(model.session.dhtNodes) DHT nodes")
                    .font(Typography.callout.numbers)
                    .monospacedDigit()
                    .foregroundStyle(Colors.textSecondary)
                    .help("Peers found without a tracker")
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Colors.fillSecondary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if model.isSimulated { return "Simulated session" }
        guard model.session.isListening else { return "Not listening" }
        let port = String(model.session.listenPort)
        return model.hasIncomingConnections ? "Port \(port) is open" : "Listening on port \(port)"
    }

    private var statusSymbol: String {
        if !model.session.isListening { return "exclamationmark.triangle.fill" }
        return model.hasIncomingConnections ? "checkmark.circle.fill" : "network"
    }

    private var statusColor: Color {
        if !model.session.isListening { return Colors.statusDangerText }
        return model.hasIncomingConnections ? Colors.statusSafeText : Colors.textSecondary
    }
}
