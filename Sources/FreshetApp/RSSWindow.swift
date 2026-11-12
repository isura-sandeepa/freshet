import FreshetCore
import SwiftUI

enum RSSTab: String, CaseIterable, Identifiable {
    case feeds, filters

    static let storageKey = "rssTab"
    var id: String { rawValue }
    var title: String { self == .feeds ? "Feeds" : "Filters" }
}

/// The RSS Downloader window: feeds or filters in a sidebar like the main window's, and the
/// selected feed's items or the selected filter's settings on the right.
struct RSSWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("rssSidebarHidden") private var sidebarHidden = false
    @AppStorage(RSSTab.storageKey) private var tab: RSSTab = .feeds
    @State private var selectedFeed: UUID?
    @State private var selectedFilter: UUID?
    @State private var showAddFeed = false

    var body: some View {
        let rss: RSSManager = model.rss
        HStack(spacing: 0) {
            if !sidebarHidden {
                RSSSidebar(rss: rss, tab: $tab, selectedFeed: $selectedFeed, selectedFilter: $selectedFilter,
                           showAddFeed: $showAddFeed, sidebarHidden: $sidebarHidden)
                SidebarDivider()
            }
            Group {
                switch tab {
                case .feeds:
                    RSSFeedPage(rss: rss, feedID: selectedFeed, sidebarHidden: $sidebarHidden, showAddFeed: $showAddFeed)
                case .filters:
                    RSSFilterPage(rss: rss, selection: $selectedFilter, sidebarHidden: $sidebarHidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 780, minHeight: 480)
        .themedWindow()
        .focusedSceneValue(\.sidebarHidden, $sidebarHidden)
        .sheet(isPresented: $showAddFeed) { AddFeedSheet(rss: rss) }
        .onAppear {
            if selectedFeed == nil { selectedFeed = rss.feeds.first?.id }
            if selectedFilter == nil { selectedFilter = rss.filters.first?.id }
        }
    }
}

struct RSSSidebar: View {
    @Bindable var rss: RSSManager
    @Binding var tab: RSSTab
    @Binding var selectedFeed: UUID?
    @Binding var selectedFilter: UUID?
    @Binding var showAddFeed: Bool
    @Binding var sidebarHidden: Bool

    var body: some View {
        SidebarColumn(hidden: $sidebarHidden) {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack(spacing: Spacing.xSmall) {
                    IconTile(symbol: "dot.radiowaves.up.forward", color: Colors.Tile.orange, size: 22)
                    Text("RSS Downloader").font(Typography.sectionTitle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ChipTabs(tabs: RSSTab.allCases, selection: $tab) { $0.title }
            }
        } rows: {
            switch tab {
            case .feeds: feedRows
            case .filters: filterRows
            }
        } footer: {
            footer
                .padding(.horizontal, Spacing.small)
                .padding(.bottom, Spacing.small)
        }
    }

    @ViewBuilder private var feedRows: some View {
        if rss.feeds.isEmpty {
            Text("No feeds yet.")
                .font(Typography.callout)
                .foregroundStyle(Colors.textSecondary)
                .padding(.horizontal, Spacing.xSmall)
        }
        ForEach(rss.feeds) { feed in
            let problem = rss.errors[feed.id] != nil
            SidebarItemRow(title: feed.displayName, subtitle: status(of: feed),
                           subtitleColor: problem ? Colors.statusCheckText : Colors.textTertiary,
                           systemImage: problem ? "exclamationmark.triangle.fill" : "dot.radiowaves.up.forward",
                           symbolColor: problem ? Colors.statusCheckText : nil,
                           isDimmed: !feed.isEnabled, isSelected: selectedFeed == feed.id) {
                selectedFeed = feed.id
            }
            .accessibilityValue(feed.isEnabled ? "" : "Turned off")
            .contextMenu {
                Button(feed.isEnabled ? "Turn Off" : "Turn On") {
                    var copy = feed
                    copy.isEnabled.toggle()
                    rss.updateFeed(copy)
                }
                Button("Refresh") { Task { await rss.refresh(feed) } }
                Divider()
                Button("Remove Feed") {
                    rss.removeFeed(feed.id)
                    if selectedFeed == feed.id { selectedFeed = rss.feeds.first?.id }
                }
            }
        }
    }

    @ViewBuilder private var filterRows: some View {
        if rss.filters.isEmpty {
            Text("No filters yet.")
                .font(Typography.callout)
                .foregroundStyle(Colors.textSecondary)
                .padding(.horizontal, Spacing.xSmall)
        }
        ForEach(rss.filters) { filter in
            SidebarItemRow(title: filter.name.isEmpty ? "Untitled Filter" : filter.name,
                           subtitle: filter.isEnabled ? nil : "Off",
                           systemImage: "line.3.horizontal.decrease.circle",
                           isDimmed: !filter.isEnabled, isSelected: selectedFilter == filter.id) {
                selectedFilter = filter.id
            }
            .contextMenu {
                Button("Remove Filter") {
                    rss.removeFilter(filter.id)
                    if selectedFilter == filter.id { selectedFilter = rss.filters.first?.id }
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch tab {
        case .feeds:
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.xSmall) {
                    Button { showAddFeed = true } label: { Label("Add Feed…", systemImage: "plus") }
                        .buttonStyle(.freshet(.secondary, size: .small))
                    Spacer()
                    Button { rss.refreshAll() } label: { Label("Refresh All Feeds", systemImage: "arrow.clockwise") }
                        .buttonStyle(.freshet(.quiet, size: .small, width: .square))
                        .help("Refresh all feeds")
                }
                VStack(alignment: .leading, spacing: Spacing.xxSmallPlus) {
                    Text("Check feeds every").font(Typography.callout.weight(.medium))
                    NumberInput("Minutes between checks", value: $rss.refreshMinutes, range: 5...240, step: 5, unit: "min", width: 48)
                }
                .padding(Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Colors.fillSecondary, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        case .filters:
            HStack {
                Button {
                    selectedFilter = rss.newFilter().id
                } label: { Label("Add Filter", systemImage: "plus") }
                .buttonStyle(.freshet(.secondary, size: .small))
                Spacer()
            }
        }
    }

    private func status(of feed: RSSFeed) -> String {
        if let error = rss.errors[feed.id] { return error }
        if rss.refreshing.contains(feed.id) { return "Refreshing…" }
        if let date = rss.lastRefresh[feed.id] {
            return "\(rss.items[feed.id]?.count ?? 0) items · \(date.formatted(date: .omitted, time: .shortened))"
        }
        return feed.url
    }
}

/// The selected feed's items, newest first.
struct RSSFeedPage: View {
    @Bindable var rss: RSSManager
    let feedID: UUID?
    @Binding var sidebarHidden: Bool
    @Binding var showAddFeed: Bool
    @State private var selectedItems = Set<RSSItem.ID>()

    var body: some View {
        VStack(spacing: 0) {
            if let id = feedID, let feed = rss.feeds.first(where: { $0.id == id }) {
                let items = (rss.items[id] ?? []).sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
                WindowHeader(title: feed.displayName, subtitle: subtitle(feed, count: items.count), figures: true,
                             sidebarHidden: $sidebarHidden) {
                    Button { Task { await rss.refresh(feed) } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(.freshet(.quiet, width: .square))
                        .help("Refresh this feed")
                    Button { rss.removeFeed(id) } label: { Label("Remove Feed", systemImage: "trash") }
                        .buttonStyle(.freshet(.quiet, width: .square))
                        .help("Remove this feed")
                    Button { download(selectedItems, feed: feed, items: items) } label: {
                        Label("Download", systemImage: "arrow.down")
                    }
                    .buttonStyle(.freshet(.primary))
                    .disabled(selectedItems.isEmpty)
                    .help("Download the selected items (or double-click one)")
                }
                if let error = rss.errors[id] {
                    NoticeBanner(kind: .warning, title: "This feed couldn't be read", detail: error)
                        .padding(.horizontal, PageLayout.horizontalInset)
                        .padding(.bottom, Spacing.small)
                }
                Table(items, selection: $selectedItems) {
                    TableColumn("Name") { item in Text(item.title).lineLimit(1).truncationMode(.middle) }
                        .width(min: 200, ideal: 380)
                    TableColumn("Published") { item in
                        Text(item.published.map { Format.date($0) } ?? "")
                            .font(Typography.callout.numbers)
                            .foregroundStyle(Colors.textSecondary)
                    }
                    .width(min: 100, ideal: 140)
                    TableColumn("Episode") { item in
                        Text(EpisodeInfo.parse(item.title).map { String(format: "S%02dE%02d", $0.season, $0.episode) } ?? "")
                            .font(Typography.callout.numbers)
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Status") { item in
                        if let filter = rss.matchedFilter(for: item) {
                            Badge(text: filter, tone: .safe)
                        }
                    }
                    .width(min: 80, ideal: 140)
                }
                .cardTable()
                .contextMenu(forSelectionType: RSSItem.ID.self) { ids in
                    Button("Download") { download(ids, feed: feed, items: items) }
                } primaryAction: { ids in
                    download(ids, feed: feed, items: items)
                }
                .overlay {
                    if items.isEmpty {
                        EmptyStateView(symbol: "tray", title: rss.refreshing.contains(id) ? "Refreshing…" : "No items",
                                       message: "Items appear here when the feed lists them.") { EmptyView() }
                    }
                }
                .card()
                .padding(.horizontal, PageLayout.horizontalInset)
                .padding(.bottom, Spacing.large)
            } else {
                // The empty state carries the action, so the header stays quiet.
                WindowHeader(title: "Feeds", subtitle: rss.feeds.isEmpty ? "No feeds yet" : "\(rss.feeds.count) feeds",
                             sidebarHidden: $sidebarHidden) { EmptyView() }
                Spacer()
                EmptyStateView(symbol: "dot.radiowaves.up.forward",
                               title: rss.feeds.isEmpty ? "No feeds yet" : "Select a feed",
                               message: rss.feeds.isEmpty ? "Add a feed's address. Filters then download matching items automatically."
                                                          : "Choose a feed in the sidebar to see its items.") {
                    if rss.feeds.isEmpty {
                        Button("Add Feed…") { showAddFeed = true }
                            .buttonStyle(.freshet(.primary))
                    }
                }
                Spacer()
            }
        }
        .onChange(of: feedID) { selectedItems = [] }
    }

    private func subtitle(_ feed: RSSFeed, count: Int) -> String {
        var parts = ["\(count) \(count == 1 ? "item" : "items")"]
        if rss.refreshing.contains(feed.id) {
            parts.append("refreshing…")
        } else if let date = rss.lastRefresh[feed.id] {
            parts.append("updated \(date.formatted(date: .omitted, time: .shortened))")
        }
        parts.append("checked every \(rss.refreshMinutes) min")
        if !feed.isEnabled { parts.append("turned off") }
        return parts.joined(separator: " · ")
    }

    private func download(_ ids: Set<RSSItem.ID>, feed: RSSFeed, items: [RSSItem]) {
        for item in items where ids.contains(item.id) { rss.downloadManually(item, from: feed) }
    }
}

/// The selected filter's settings.
struct RSSFilterPage: View {
    @Bindable var rss: RSSManager
    @Binding var selection: UUID?
    @Binding var sidebarHidden: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let id = selection, let filter = binding(for: id) {
                WindowHeader(title: filter.wrappedValue.name.isEmpty ? "Untitled Filter" : filter.wrappedValue.name,
                             subtitle: filter.wrappedValue.isEnabled ? "On — downloads matching items as they appear" : "Off",
                             sidebarHidden: $sidebarHidden) {
                    Button {
                        rss.removeFilter(id)
                        selection = rss.filters.first?.id
                    } label: { Label("Remove Filter", systemImage: "trash") }
                    .buttonStyle(.freshet(.quiet, width: .square))
                    .help("Remove this filter")
                }
                ScrollView {
                    FilterEditor(filter: filter, rss: rss)
                        .padding(.horizontal, PageLayout.horizontalInset)
                        .padding(.top, Spacing.xxSmall)
                        .padding(.bottom, Spacing.large)
                }
                .id(id)
            } else {
                WindowHeader(title: "Filters", subtitle: rss.filters.isEmpty ? "No filters yet" : "\(rss.filters.count) filters",
                             sidebarHidden: $sidebarHidden) { EmptyView() }
                Spacer()
                EmptyStateView(symbol: "line.3.horizontal.decrease.circle", title: "No filter selected",
                               message: "Filters download matching items from your feeds as they appear.") {
                    Button("Add Filter") { selection = rss.newFilter().id }
                        .buttonStyle(.freshet(.primary))
                }
                Spacer()
            }
        }
    }

    /// Looks the filter up by ID on every read and write, so removing one never leaves the
    /// editor holding a stale index.
    private func binding(for id: UUID) -> Binding<RSSFilter>? {
        guard let current = rss.filters.first(where: { $0.id == id }) else { return nil }
        return Binding(get: { rss.filters.first(where: { $0.id == id }) ?? current },
                       set: { newValue in
                           if let index = rss.filters.firstIndex(where: { $0.id == id }) { rss.filters[index] = newValue }
                       })
    }
}

struct AddFeedSheet: View {
    let rss: RSSManager
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var alias = ""
    @State private var cookies = ""
    @FocusState private var focused: Bool

    var body: some View {
        SheetLayout(title: "Add Feed", message: "Freshet checks the feed regularly and lists its items. Filters then download the ones you want.",
                    width: 540) {
            FormGroup(footer: "Cookies are sent with the feed and its .torrent links, for sites that need a login.") {
                FormRow("Feed URL") {
                    TextInput("Feed URL", text: $url, prompt: "https://example.com/rss", width: 300, focus: $focused)
                }
                FormDivider()
                FormRow("Name") {
                    TextInput("Name", text: $alias, prompt: "Optional", width: 300)
                }
                FormDivider()
                FormRow("Cookies") {
                    TextInput("Cookies", text: $cookies, prompt: "Optional, e.g. uid=123; pass=abc", width: 300, monospaced: true)
                }
            }
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.freshet(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Add Feed") {
                rss.addFeed(url: url, alias: alias, cookies: cookies)
                dismiss()
            }
            .buttonStyle(.freshet(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") != true)
        }
        .onAppear { focused = true }
    }
}

struct FilterEditor: View {
    @Binding var filter: RSSFilter
    let rss: RSSManager

    private static let intervals: [(hours: Int, title: String)] = [
        (0, "Every time"), (12, "12 hours"), (24, "1 day"), (48, "2 days"), (168, "1 week"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            FormGroup(title: "Match", footer: "* matches any text, ? one character, | separates alternatives. Case doesn't matter.") {
                FormRow("Name") {
                    TextInput("Filter name", text: $filter.name, prompt: "Untitled Filter", width: 280)
                }
                FormDivider()
                SwitchRow("Turned on", isOn: $filter.isEnabled)
                FormDivider()
                FormRow("Download items matching") {
                    TextInput("Download items matching", text: $filter.include, prompt: "*Show Name*1080p*", width: 280, monospaced: true)
                }
                FormDivider()
                FormRow("Except items matching") {
                    TextInput("Except items matching", text: $filter.exclude, prompt: "Optional, e.g. *x265*|*HDR*", width: 280, monospaced: true)
                }
                FormDivider()
                FormRow("From feed") {
                    ValuePicker("From feed", selection: $filter.feedID, options: [nil] + rss.feeds.map { Optional($0.id) }) { id in
                        id.flatMap { id in rss.feeds.first { $0.id == id }?.displayName } ?? "All feeds"
                    }
                }
            }
            FormGroup(title: "When it matches") {
                FolderRow(title: "Save in", path: $filter.saveFolder)
                FormDivider()
                FormRow("Label") {
                    TextInput("Label", text: $filter.label, prompt: "Optional", width: 200)
                }
                FormDivider()
                SwitchRow("Add stopped", caption: "Add the torrent without starting it.", isOn: $filter.addStopped)
            }
            FormGroup(title: "Episodes and quality") {
                FormRow("Episode numbers", caption: "For example 1x1-10;2x3-;3") {
                    TextInput("Episode numbers", text: $filter.episodes, prompt: "All episodes", width: 200, monospaced: true)
                }
                FormDivider()
                SwitchRow("Smart episode filter", caption: "Download each episode only once.", isOn: $filter.smartEpisodeFilter)
                FormDivider()
                FormRow("Quality") {
                    HStack(spacing: Spacing.small) {
                        ForEach(VideoQuality.allCases, id: \.self) { quality in
                            Toggle(quality.rawValue, isOn: Binding(
                                get: { filter.qualities.contains(quality) },
                                set: { if $0 { filter.qualities.insert(quality) } else { filter.qualities.remove(quality) } }))
                                .toggleStyle(CheckboxStyle())
                        }
                    }
                }
                FormDivider()
                FormRow("Minimum interval", caption: "Time to wait before taking the same match again.") {
                    ValuePicker("Minimum interval", selection: $filter.minimumIntervalHours, options: Self.intervals.map { $0.hours }) { hours in
                        Self.intervals.first { $0.hours == hours }?.title ?? "\(hours) hours"
                    }
                }
            }
            FormGroup(title: "Would download now") {
                let matches = rss.preview(filter)
                if matches.isEmpty {
                    Text("Nothing in the current feeds.")
                        .font(Typography.callout)
                        .foregroundStyle(Colors.textSecondary)
                        .formRowPadding()
                } else {
                    ForEach(Array(matches.prefix(20).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { FormDivider() }
                        HStack(spacing: Spacing.xSmall) {
                            Image(systemName: "arrow.down.circle")
                                .foregroundStyle(Colors.textTertiary)
                                .accessibilityHidden(true)
                            Text(item.title).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.xSmall + 2)
                    }
                }
            }
        }
    }
}
