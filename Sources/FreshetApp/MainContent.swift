import AppKit
import FreshetCore
import SwiftUI

// MARK: Header

/// The top of the main window's content: the current view's name and a status line on the
/// left, the filter and the add buttons on the right. Replaces the toolbar; every action here
/// is also in the menu bar.
struct ContentHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.filter.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if !model.selection.isEmpty {
                selectionButtons
            }
            FilterField()
            WebSearchButton()
                .buttonStyle(CapsuleButtonStyle(iconOnly: true))
            Button { model.showAddURL = true } label: {
                Label("Add from URL", systemImage: "link")
            }
            .buttonStyle(CapsuleButtonStyle())
            .help("Add a magnet link or torrent URL (⌘U)")
            Button { model.openTorrentFiles() } label: {
                Label("Add Torrent", systemImage: "plus")
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .help("Add .torrent files (⌘O)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var selectionButtons: some View {
        HStack(spacing: 6) {
            Button { model.perform(.start) } label: { Label("Start", systemImage: "play.fill") }
                .help("Start (⌥⌘S)")
            Button { model.perform(.pause) } label: { Label("Pause", systemImage: "pause.fill") }
                .help("Pause (⌥⌘P)")
            Button { model.showProperties() } label: { Label("Properties", systemImage: "info") }
                .help("Properties (⌘I)")
            Button { model.requestRemove() } label: { Label("Remove", systemImage: "trash") }
                .help("Remove (⌘⌫)")
        }
        .buttonStyle(CapsuleButtonStyle(iconOnly: true))
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.isSimulated { parts.append("Simulation") }
        let shown = model.visible.count
        if !model.selection.isEmpty {
            parts.append("\(model.selection.count) selected of \(shown)")
        } else {
            parts.append("\(shown) \(shown == 1 ? "torrent" : "torrents")")
        }
        if !model.searchText.isEmpty { parts.append("matching “\(model.searchText)”") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Overview

/// Total speeds, a bar showing what every torrent is doing, and the connection state — the
/// window's at-a-glance summary (it replaces the old status bar).
struct OverviewStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = stateCounts
        let total = counts.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                speed(Format.rateOrZero(model.totalDownloadRate), "down", symbol: "arrow.down", limit: model.settings.downloadLimitKBps)
                speed(Format.rateOrZero(model.totalUploadRate), "up", symbol: "arrow.up", limit: model.settings.uploadLimitKBps)
                Spacer(minLength: 12)
                connection
            }
            StateBar(counts: counts, total: total)
            if total > 0 {
                HStack(spacing: 14) {
                    ForEach(counts.filter { $0.count > 0 }, id: \.style) { entry in
                        HStack(spacing: 5) {
                            Circle().fill(entry.style.color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text("\(entry.style.title) \(entry.count)")
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func speed(_ value: String, _ direction: String, symbol: String, limit: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(limit > 0 ? "\(direction), limit \(Format.rate(limit * 1_024))" : direction)
                .font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(direction == "down" ? "Downloading" : "Uploading") \(value)")
    }

    @ViewBuilder private var connection: some View {
        HStack(spacing: 12) {
            Label("DHT \(model.session.dhtNodes)", systemImage: "point.3.connected.trianglepath.dotted")
                .help("Peers found without a tracker: \(model.session.dhtNodes) DHT nodes")
            if model.session.isListening {
                if model.hasIncomingConnections {
                    Label("Port \(String(model.session.listenPort)) open", systemImage: "checkmark.circle.fill")
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
        .font(.callout)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var stateCounts: [StateCount] {
        var counts: [StateStyle: Int] = [:]
        for torrent in model.torrents.values { counts[StateStyle(torrent), default: 0] += 1 }
        return StateStyle.allCases.map { StateCount(style: $0, count: counts[$0] ?? 0) }
    }
}

struct StateCount {
    let style: StateStyle
    let count: Int
}

/// The rounded multicolor bar: one segment per state, sized by how many torrents are in it.
struct StateBar: View {
    let counts: [StateCount]
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if total == 0 {
                    Capsule().fill(Color.primary.opacity(0.08))
                } else {
                    let shown = counts.filter { $0.count > 0 }
                    let spacing = CGFloat(max(0, shown.count - 1)) * 2
                    ForEach(shown, id: \.style) { entry in
                        Rectangle()
                            .fill(entry.style.color)
                            .frame(width: max(3, (proxy.size.width - spacing) * CGFloat(entry.count) / CGFloat(total)))
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

// MARK: Card list

/// The torrent list as rows in a rounded panel: an icon tile for the state, the name with tags,
/// a one-line summary, a progress bar, and the size on the right. Selection, the context menu,
/// double-click and Delete work as in the table.
struct TorrentCardsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.visible) { torrent in
                TorrentCardRow(torrent: torrent, label: model.labels.assignments[torrent.id])
                    .tag(torrent.id)
                    .listRowSeparator(.visible)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: TorrentID.self) { ids in
            if !ids.isEmpty { TorrentContextMenu(ids: ids) }
        } primaryAction: { ids in
            if let id = ids.first { model.reveal(id) }
        }
        .onDeleteCommand { model.requestRemove() }
        .overlay {
            if model.torrents.isEmpty {
                ContentUnavailableView {
                    Label("No Torrents", systemImage: "arrow.down.circle")
                } description: {
                    Text("Drop .torrent files here, or add a torrent or a magnet link.")
                } actions: {
                    Button("Add Torrent…") { model.openTorrentFiles() }
                    Button("Add from URL…") { model.showAddURL = true }
                }
            } else if model.visible.isEmpty {
                ContentUnavailableView("Nothing Here", systemImage: model.filter.systemImage,
                                       description: Text(model.searchText.isEmpty ? "No torrents are \(model.filter.title.lowercased()) right now." : "No torrents match “\(model.searchText)”."))
            }
        }
    }
}

struct TorrentCardRow: View {
    let torrent: TorrentSnapshot
    let label: String?

    var body: some View {
        let style = StateStyle(torrent)
        HStack(spacing: 12) {
            IconTile(symbol: style.symbol, color: style.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(torrent.displayName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let tag = stateTag(style) {
                        TagPill(text: tag, color: style.color)
                    }
                    if let label {
                        TagPill(text: label, systemImage: "tag")
                    }
                }
                Text(summary(style))
                    .font(.callout)
                    .foregroundStyle(style == .error ? Palette.error : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !torrent.isComplete {
                    ThinProgressBar(value: torrent.progress, color: style.color)
                        .frame(maxWidth: 420)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : "—")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                Text(torrent.isComplete ? "ratio \(Format.ratio(torrent.ratio))" : Format.percent(torrent.progress))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(torrent.displayName)
        .accessibilityValue("\(torrent.statusText), \(Format.percent(torrent.progress)), \(summary(style))\(label.map { ", label \($0)" } ?? "")")
    }

    /// Only states worth calling out get a tag; downloading and seeding speak through the icon.
    private func stateTag(_ style: StateStyle) -> String? {
        switch style {
        case .error: return "Error"
        case .paused: return "Paused"
        case .queued: return "Queued"
        case .checking: return "Checking \(Format.percent(torrent.progress))"
        case .downloading, .seeding, .done: return nil
        }
    }

    private func summary(_ style: StateStyle) -> String {
        let sizes = "\(Format.bytes(torrent.totalWantedDone)) of \(Format.bytes(torrent.totalWanted))"
        switch torrent.activity {
        case .error:
            return torrent.errorMessage ?? "Something went wrong"
        case .downloadingMetadata:
            return "Getting the torrent's details from peers…"
        case .checking:
            return "Checking files on disk · \(sizes)"
        case .downloading:
            var parts = [sizes, "↓ \(Format.rateOrZero(torrent.downloadRate))"]
            if torrent.uploadRate > 0 { parts.append("↑ \(Format.rateOrZero(torrent.uploadRate))") }
            if let eta = torrent.eta { parts.append("\(Format.duration(eta)) left") }
            parts.append("\(torrent.connectedPeers) \(torrent.connectedPeers == 1 ? "peer" : "peers")")
            return parts.joined(separator: " · ")
        case .seeding:
            if torrent.uploadRate > 0 {
                let peers = torrent.connectedLeechers
                return "Uploading \(Format.rateOrZero(torrent.uploadRate)) to \(peers) \(peers == 1 ? "peer" : "peers")"
            }
            return "Seeding · waiting for peers"
        case .finished:
            return "Downloaded · not seeding"
        case .queued, .queuedSeed:
            let position = torrent.queuePosition >= 0 ? " · position \(torrent.queuePosition + 1)" : ""
            return torrent.isComplete ? "Waiting to seed\(position)" : "Waiting in the queue\(position) · \(sizes)"
        case .paused:
            return torrent.isComplete ? "Downloaded · stopped" : "Stopped at \(Format.percent(torrent.progress)) · \(sizes)"
        }
    }
}

/// A 4 pt progress bar under the summary line.
struct ThinProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// The right-click menu for card rows; the same commands as the table's menu.
struct TorrentContextMenu: View {
    @Environment(AppModel.self) private var model
    let ids: Set<TorrentID>

    var body: some View {
        Button("Start") { model.perform(.start, ids: ids) }
        Button("Pause") { model.perform(.pause, ids: ids) }
        Button("Force Start") { model.perform(.forceStart, ids: ids) }
        Divider()
        Button("Force Re-check") { model.perform(.recheck, ids: ids) }
        Button("Update Tracker") { model.perform(.reannounce, ids: ids) }
        Divider()
        if ids.count == 1, let id = ids.first {
            Button("Show in Finder") { model.reveal(id) }
        }
        Button("Copy Magnet Link") { model.copyMagnetLinks(ids) }
        Divider()
        Menu("Label") {
            Button("New Label…") { model.promptNewLabel(for: ids) }
            Button("Remove Label") { model.setLabel(nil, for: ids) }
            if !model.labels.names.isEmpty { Divider() }
            ForEach(model.labels.names, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { ids.allSatisfy { model.labels.assignments[$0] == name } },
                    set: { _ in model.setLabel(name, for: ids) }))
            }
        }
        Menu("Queue") {
            Button("Move to Top") { model.perform(.queueTop, ids: ids) }
            Button("Move Up") { model.perform(.queueUp, ids: ids) }
            Button("Move Down") { model.perform(.queueDown, ids: ids) }
            Button("Move to Bottom") { model.perform(.queueBottom, ids: ids) }
        }
        Menu("Bandwidth Allocation") {
            ForEach(BandwidthPriority.allCases.reversed(), id: \.self) { priority in
                Toggle(priority.title, isOn: Binding(
                    get: { ids.allSatisfy { model.automation.meta(for: $0).priority == priority } },
                    set: { _ in model.setPriority(priority, for: ids) }))
            }
        }
        Menu("Advanced") {
            Button("Set Download Location…") { model.chooseDownloadLocation(for: ids) }
            if ids.count == 1, let id = ids.first {
                Button("Save .torrent File…") { model.saveTorrentFile(id) }
                Button("Add Peer…") { model.promptAddPeer(to: id) }
                Button("Clear Peer List and Bans") { model.clearPeers(of: id) }
            }
        }
        Divider()
        if ids.count == 1, let id = ids.first {
            Button("Properties…") { model.showProperties(id) }
        }
        Button("Remove…") { model.requestRemove(ids) }
    }
}

/// Sort order for the card list (the table sorts by its column headers).
struct SortMenu: View {
    @Environment(AppModel.self) private var model
    private static let fields: [TorrentField] = [.name, .added, .done, .size, .downSpeed, .upSpeed, .eta, .ratio, .status, .queue]

    var body: some View {
        Menu {
            Picker("Sort By", selection: Binding(get: { model.sortKey.field },
                                                 set: { model.sortKey = TorrentSortKey(field: $0, ascending: model.sortKey.ascending) })) {
                ForEach(Self.fields, id: \.self) { field in
                    Text(field == .queue ? "Queue Order" : field.title).tag(field)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Order", selection: Binding(get: { model.sortKey.ascending },
                                               set: { model.sortKey = TorrentSortKey(field: model.sortKey.field, ascending: $0) })) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort: \(model.sortKey.field == .queue ? "Queue Order" : model.sortKey.field.title)", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.callout)
        .foregroundStyle(.secondary)
        .help("Change the sort order")
    }
}
