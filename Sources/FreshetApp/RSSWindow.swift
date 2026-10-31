import FreshetCore
import SwiftUI

/// The RSS Downloader window: feeds and their items on one tab, filters on the other.
struct RSSWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("rssSidebarHidden") private var sidebarHidden = false

    var body: some View {
        TabView {
            RSSFeedsView(rss: model.rss)
                .tabItem { Text("Feeds") }
            RSSFiltersView(rss: model.rss)
                .tabItem { Text("Filters") }
        }
        .padding(10)
        .frame(minWidth: 700, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { sidebarHidden.toggle() } label: {
                    Label(sidebarHidden ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left")
                }
                .help(sidebarHidden ? "Show the feed and filter lists" : "Hide the feed and filter lists")
            }
        }
    }
}

/// The add and remove buttons under a list, with a comfortable click target.
struct ListEditButtons: View {
    let addTitle: String
    let removeTitle: String
    let canRemove: Bool
    let add: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: add) {
                Label(addTitle, systemImage: "plus").labelStyle(.iconOnly)
                    .frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .help(addTitle)
            Button(action: remove) {
                Label(removeTitle, systemImage: "minus").labelStyle(.iconOnly)
                    .frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .help(removeTitle)
            .disabled(!canRemove)
        }
        .buttonStyle(.borderless)
    }
}

struct RSSFeedsView: View {
    @Bindable var rss: RSSManager
    @AppStorage("rssSidebarHidden") private var sidebarHidden = false
    @State private var selectedFeed: UUID?
    @State private var showAdd = false
    @State private var selectedItems = Set<RSSItem.ID>()

    var body: some View {
        SidebarSplit(storageKey: "rssFeedsWidth", defaultWidth: 260, range: 200...420, isCollapsed: sidebarHidden) {
            VStack(spacing: 0) {
                List(selection: $selectedFeed) {
                    ForEach(rss.feeds) { feed in
                        HStack {
                            Image(systemName: rss.errors[feed.id] != nil ? "exclamationmark.triangle.fill" : "dot.radiowaves.up.forward")
                                .foregroundStyle(rss.errors[feed.id] != nil ? Palette.warning : .secondary)
                                .accessibilityLabel(rss.errors[feed.id] != nil ? "Problem" : "Feed")
                            VStack(alignment: .leading) {
                                Text(feed.displayName).lineLimit(1)
                                Text(status(of: feed)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tag(feed.id)
                        .opacity(feed.isEnabled ? 1 : 0.5)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(feed.isEnabled ? "" : "Disabled")
                        .contextMenu {
                            Button(feed.isEnabled ? "Disable" : "Enable") {
                                var copy = feed
                                copy.isEnabled.toggle()
                                rss.updateFeed(copy)
                            }
                            Button("Refresh") { Task { await rss.refresh(feed) } }
                            Button("Remove Feed", role: .destructive) { rss.removeFeed(feed.id) }
                        }
                    }
                }
                HStack {
                    ListEditButtons(addTitle: "Add Feed", removeTitle: "Remove Feed", canRemove: selectedFeed != nil,
                                    add: { showAdd = true },
                                    remove: { if let id = selectedFeed { rss.removeFeed(id) } })
                    Spacer()
                    Button("Refresh All") { rss.refreshAll() }
                        .buttonStyle(.borderless)
                }
                .padding(6)
                HStack {
                    Stepper("Check every \(rss.refreshMinutes) min", value: $rss.refreshMinutes, in: 5...240, step: 5)
                        .font(.callout)
                }
                .padding([.horizontal, .bottom], 6)
            }
        } detail: {
            itemsPane
        }
        .sheet(isPresented: $showAdd) { AddFeedSheet(rss: rss) }
    }

    @ViewBuilder private var itemsPane: some View {
        if let id = selectedFeed, let feed = rss.feeds.first(where: { $0.id == id }) {
            let items = (rss.items[id] ?? []).sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
            VStack(spacing: 0) {
                if let error = rss.errors[id] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                Table(items, selection: $selectedItems) {
                    TableColumn("Name") { item in Text(item.title).lineLimit(1).truncationMode(.middle) }
                        .width(min: 200, ideal: 380)
                    TableColumn("Published") { item in
                        Text(item.published.map { Format.date($0) } ?? "").foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 140)
                    TableColumn("Episode") { item in
                        Text(EpisodeInfo.parse(item.title).map { String(format: "S%02dE%02d", $0.season, $0.episode) } ?? "")
                            .monospacedDigit()
                    }
                    .width(min: 60, ideal: 70)
                    TableColumn("Status") { item in
                        Text(rss.matchedFilter(for: item) ?? "").foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 120)
                }
                .contextMenu(forSelectionType: RSSItem.ID.self) { ids in
                    Button("Download") { download(ids, feed: feed, items: items) }
                } primaryAction: { ids in
                    download(ids, feed: feed, items: items)
                }
                HStack {
                    Text(rss.refreshing.contains(id) ? "Refreshing…" : "\(items.count) items").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Download") { download(selectedItems, feed: feed, items: items) }
                        .disabled(selectedItems.isEmpty)
                }
                .padding(6)
            }
        } else {
            ContentUnavailableView(rss.feeds.isEmpty ? "No Feeds" : "Select a Feed", systemImage: "dot.radiowaves.up.forward",
                                   description: Text(rss.feeds.isEmpty ? "Add a feed with +. Filters then add matching torrents automatically." : ""))
        }
    }

    private func download(_ ids: Set<RSSItem.ID>, feed: RSSFeed, items: [RSSItem]) {
        for item in items where ids.contains(item.id) { rss.downloadManually(item, from: feed) }
    }

    private func status(of feed: RSSFeed) -> String {
        if let error = rss.errors[feed.id] { return error }
        if rss.refreshing.contains(feed.id) { return "Refreshing…" }
        if let date = rss.lastRefresh[feed.id] { return "\(rss.items[feed.id]?.count ?? 0) items · \(date.formatted(date: .omitted, time: .shortened))" }
        return feed.url
    }
}

struct AddFeedSheet: View {
    let rss: RSSManager
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var alias = ""
    @State private var cookies = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Feed URL", text: $url, prompt: Text("https://example.com/rss"))
                TextField("Name", text: $alias, prompt: Text("Optional"))
                TextField("Cookies", text: $cookies, prompt: Text("Optional, e.g. uid=123; pass=abc"))
                Text("Cookies are sent with the feed and its .torrent links, for sites that need a login.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Feed") {
                    rss.addFeed(url: url, alias: alias, cookies: cookies)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") != true)
            }
            .padding(14)
        }
        .frame(width: 480)
    }
}

struct RSSFiltersView: View {
    @Bindable var rss: RSSManager
    @AppStorage("rssSidebarHidden") private var sidebarHidden = false
    @State private var selected: UUID?

    var body: some View {
        SidebarSplit(storageKey: "rssFiltersWidth", defaultWidth: 230, range: 180...400, isCollapsed: sidebarHidden) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(rss.filters) { filter in
                        Text(filter.name).tag(filter.id).opacity(filter.isEnabled ? 1 : 0.5)
                            .accessibilityValue(filter.isEnabled ? "" : "Disabled")
                    }
                }
                HStack {
                    ListEditButtons(addTitle: "Add Filter", removeTitle: "Remove Filter", canRemove: selected != nil,
                                    add: { selected = rss.newFilter().id },
                                    remove: { if let id = selected { rss.removeFilter(id); selected = nil } })
                    Spacer()
                }
                .padding(6)
            }
        } detail: {
            if let index = rss.filters.firstIndex(where: { $0.id == selected }) {
                FilterEditor(filter: $rss.filters[index], rss: rss)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Filter Selected", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Filters download matching items from your feeds as they appear."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct FilterEditor: View {
    @Binding var filter: RSSFilter
    let rss: RSSManager

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $filter.name)
                Toggle("Enabled", isOn: $filter.isEnabled)
                TextField("Filter", text: $filter.include, prompt: Text("*Show Name*1080p*"))
                TextField("Not", text: $filter.exclude, prompt: Text("Optional, e.g. *x265*|*HDR*"))
                Text("* matches any text, ? one character, | separates alternatives. Case doesn't matter.")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Feed", selection: $filter.feedID) {
                    Text("All feeds").tag(UUID?.none)
                    ForEach(rss.feeds) { feed in Text(feed.displayName).tag(Optional(feed.id)) }
                }
            }
            Section("When it matches") {
                FolderField(title: "Save in", path: $filter.saveFolder)
                TextField("Label", text: $filter.label, prompt: Text("Optional"))
                Toggle("Add stopped", isOn: $filter.addStopped)
            }
            Section("Episodes and quality") {
                TextField("Episode numbers", text: $filter.episodes, prompt: Text("e.g. 1x1-10;2x3-;3"))
                Toggle("Smart episode filter (each episode once)", isOn: $filter.smartEpisodeFilter)
                HStack {
                    Text("Quality")
                    Spacer()
                    ForEach(VideoQuality.allCases, id: \.self) { quality in
                        Toggle(quality.rawValue, isOn: Binding(
                            get: { filter.qualities.contains(quality) },
                            set: { if $0 { filter.qualities.insert(quality) } else { filter.qualities.remove(quality) } }))
                            .toggleStyle(.checkbox)
                    }
                }
                Picker("Minimum interval", selection: $filter.minimumIntervalHours) {
                    Text("Every time").tag(0)
                    Text("12 hours").tag(12)
                    Text("1 day").tag(24)
                    Text("2 days").tag(48)
                    Text("1 week").tag(168)
                }
            }
            Section("Would download now") {
                let matches = rss.preview(filter)
                if matches.isEmpty {
                    Text("Nothing in the current feeds.").foregroundStyle(.secondary)
                } else {
                    ForEach(matches.prefix(20)) { item in Text(item.title).lineLimit(1).truncationMode(.middle) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
