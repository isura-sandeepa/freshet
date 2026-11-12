import AppKit
import FreshetCore
import SwiftUI

// MARK: Header

/// The page header: the current view's title and a status line, with the actions on the
/// right. Labels turn into icons when the window is too narrow for them.
struct PageHeader: View {
    @Environment(AppModel.self) private var model
    var leadingInset: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .top, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(model.filter.title)
                    .font(Typography.pageTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Typography.metadata.numbers)
                    .monospacedDigit()
                    .foregroundStyle(Colors.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.medium)
            ViewThatFits(in: .horizontal) {
                actions(showsTitles: true)
                actions(showsTitles: false)
            }
        }
        .padding(.leading, PageLayout.horizontalInset + leadingInset)
        .padding(.trailing, PageLayout.horizontalInset)
        .padding(.top, PageLayout.topInset)
        .padding(.bottom, Spacing.small)
    }

    private func actions(showsTitles: Bool) -> some View {
        @Bindable var model = model
        return HStack(spacing: Spacing.xSmall) {
            if !model.selection.isEmpty {
                HStack(spacing: Spacing.xxSmall) {
                    Button { model.perform(.start) } label: { Label("Start", systemImage: "play.fill") }
                        .help("Start (⌥⌘S)")
                    Button { model.perform(.pause) } label: { Label("Pause", systemImage: "pause.fill") }
                        .help("Pause (⌥⌘P)")
                    Button { model.showProperties() } label: { Label("Properties", systemImage: "info") }
                        .help("Properties (⌘I)")
                    Button { model.requestRemove() } label: { Label("Remove", systemImage: "trash") }
                        .help("Remove (⌘⌫)")
                }
                .buttonStyle(.freshet(.quiet, width: .square))
            }
            SearchCapsule(text: $model.searchText, prompt: "Filter", width: showsTitles ? 200 : 150,
                          focusRequest: $model.focusFilter)
            WebSearchButton()
            Button { model.showAddURL = true } label: { Label("Add from URL", systemImage: "link") }
                .buttonStyle(.freshet(.secondary, width: showsTitles ? .fit : .square))
                .help("Add a magnet link or torrent URL (⌘U)")
            Button { model.openTorrentFiles() } label: { Label("Add Torrent", systemImage: "plus") }
                .buttonStyle(.freshet(.primary, width: showsTitles ? .fit : .square))
                .help("Add .torrent files (⌘O)")
        }
        .fixedSize()
    }

    private var subtitle: String {
        var parts: [String] = []
        if model.isSimulated { parts.append("Simulation") }
        let shown = model.visible.count
        parts.append(model.selection.isEmpty ? "\(shown) \(shown == 1 ? "torrent" : "torrents")"
                                             : "\(model.selection.count) of \(shown) selected")
        if !model.searchText.isEmpty { parts.append("matching “\(model.searchText)”") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Overview

/// Total speeds as the page's big figure, then a bar of what every torrent is doing with a
/// legend. Hovering a segment or a legend entry brings it forward and fades the rest.
struct OverviewSummary: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlighted: StateStyle?

    var body: some View {
        let counts = stateCounts
        let total = counts.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text("\(Format.rateOrZero(model.totalDownloadRate)) down")
                    .font(Typography.title.weight(.bold).numbers)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
                Text("\(Format.rateOrZero(model.totalUploadRate)) up")
                    .font(Typography.rowTitle.numbers)
                    .monospacedDigit()
                    .foregroundStyle(Colors.textSecondary)
                Spacer(minLength: Spacing.small)
                Text(limitsText)
                    .font(Typography.rowTitle.numbers)
                    .foregroundStyle(Colors.textSecondary)
                    .lineLimit(1)
            }
            .contentTransition(reduceMotion ? .identity : .numericText())
            .accessibilityElement(children: .combine)
            StateBar(counts: counts, total: total, highlighted: highlighted) { highlighted = $0 }
            if total > 0 {
                HStack(spacing: Spacing.medium) {
                    ForEach(counts.filter { $0.count > 0 }, id: \.style) { entry in
                        HStack(spacing: Spacing.xxSmallPlus) {
                            Circle().fill(entry.style.color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(entry.style.title).foregroundStyle(Colors.textSecondary)
                            Text("\(entry.count)").font(Typography.metadataEmphasis.numbers).monospacedDigit()
                        }
                        .font(Typography.metadata)
                        .opacity(highlighted == nil || highlighted == entry.style ? 1 : 0.4)
                        .onHover { highlighted = $0 ? entry.style : nil }
                        .accessibilityElement(children: .combine)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: highlighted)
            }
        }
        .padding(.horizontal, PageLayout.horizontalInset)
        .padding(.top, Spacing.xSmall)
        .padding(.bottom, Spacing.medium)
    }

    private var limitsText: String {
        let down = model.settings.downloadLimitKBps, up = model.settings.uploadLimitKBps
        if down == 0 && up == 0 { return "No speed limits" }
        var parts: [String] = []
        if down > 0 { parts.append("↓ \(Format.rate(down * 1_024))") }
        if up > 0 { parts.append("↑ \(Format.rate(up * 1_024))") }
        return "Limits " + parts.joined(separator: " · ")
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

/// The 14 pt capsule bar: one segment per state with 2 pt gaps, every state kept in the bar
/// (empty ones at zero width) so widths animate together as torrents change state.
struct StateBar: View {
    let counts: [StateCount]
    let total: Int
    var highlighted: StateStyle?
    var onHover: (StateStyle?) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = segments(width: proxy.size.width)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Colors.State.empty)
                ForEach(layout, id: \.style) { segment in
                    Rectangle()
                        .fill(segment.style.color)
                        .opacity(highlighted == nil || highlighted == segment.style ? 1 : 0.3)
                        .frame(width: segment.width)
                        .offset(x: segment.x)
                }
            }
            .frame(width: proxy.size.width, height: 14, alignment: .leading)
            .clipShape(Capsule(style: .continuous))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: layout.map(\.width))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    onHover(layout.first { location.x >= $0.x - 1 && location.x <= $0.x + $0.width + 1 && $0.width > 0 }?.style)
                case .ended:
                    onHover(nil)
                }
            }
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Torrents by state")
        .accessibilityValue(counts.filter { $0.count > 0 }.map { "\($0.style.title) \($0.count)" }.joined(separator: ", "))
    }

    private struct Segment {
        let style: StateStyle
        let x: CGFloat
        let width: CGFloat
    }

    private func segments(width: CGFloat) -> [Segment] {
        guard total > 0 else { return [] }
        let shown = counts.filter { $0.count > 0 }
        let gaps = CGFloat(max(0, shown.count - 1)) * Spacing.xxxSmall
        let usable = max(0, width - gaps)
        var x: CGFloat = 0
        var result: [Segment] = []
        for entry in counts {
            let w = entry.count > 0 ? max(4, usable * CGFloat(entry.count) / CGFloat(total)) : 0
            result.append(Segment(style: entry.style, x: x, width: w))
            if w > 0 { x += w + Spacing.xxxSmall }
        }
        return result
    }
}

// MARK: List controls

/// Above the list: the sort order and the card / table switch.
struct ListControls: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TorrentListStyle.storageKey) private var listStyle: TorrentListStyle = .cards
    private static let fields: [TorrentField] = [.queue, .name, .added, .done, .size, .downSpeed, .upSpeed, .eta, .ratio, .status]

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            if listStyle == .cards {
                Menu {
                    Picker("Sort By", selection: Binding(get: { model.sortKey.field },
                                                         set: { model.sortKey = TorrentSortKey(field: $0, ascending: model.sortKey.ascending) })) {
                        ForEach(Self.fields, id: \.self) { field in Text(title(field)).tag(field) }
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
                    Label(title(model.sortKey.field), systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.freshet(.secondary, size: .small))
                .fixedSize()
                .accessibilityLabel("Sort by \(title(model.sortKey.field))")
            }
            Spacer()
            HStack(spacing: Spacing.xxSmall) {
                Button { listStyle = .cards } label: { Label("Show as Cards", systemImage: "rectangle.grid.1x2") }
                    .buttonStyle(.freshet(listStyle == .cards ? .soft : .quiet, size: .small, width: .square))
                    .accessibilityAddTraits(listStyle == .cards ? .isSelected : [])
                    .help("Show as cards (⌥⌘1)")
                Button { listStyle = .table } label: { Label("Show as Table", systemImage: "tablecells") }
                    .buttonStyle(.freshet(listStyle == .table ? .soft : .quiet, size: .small, width: .square))
                    .accessibilityAddTraits(listStyle == .table ? .isSelected : [])
                    .help("Show as table (⌥⌘2)")
            }
        }
        .padding(.horizontal, PageLayout.horizontalInset)
    }

    private func title(_ field: TorrentField) -> String {
        field == .queue ? "Queue Order" : field.title
    }
}

// MARK: Card list

/// The torrent list as separate cards. Selection is handled here rather than by List, so no
/// system highlight paints behind the cards: click selects, ⌘-click toggles, Shift-click
/// extends, arrow keys move (Shift extends), Delete removes, double-click shows in Finder.
struct TorrentCardList: View {
    @Environment(AppModel.self) private var model
    /// Where a Shift-extended selection starts.
    @State private var anchor: TorrentID?
    /// The card the keyboard last moved to.
    @State private var cursor: TorrentID?
    @FocusState private var focused: Bool

    var body: some View {
        let rows = model.visible
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.xSmall) {
                    ForEach(rows) { torrent in
                        TorrentCardRow(torrent: torrent, label: model.labels.assignments[torrent.id],
                                       isSelected: model.selection.contains(torrent.id))
                            .id(torrent.id)
                            .gesture(TapGesture().onEnded { click(torrent.id, in: rows) })
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.reveal(torrent.id) })
                            .contextMenu { TorrentContextMenu(ids: menuTargets(torrent.id)) }
                            .accessibilityAction { click(torrent.id, in: rows) }
                            .accessibilityAction(named: "Show in Finder") { model.reveal(torrent.id) }
                    }
                }
                .padding(.horizontal, PageLayout.horizontalInset)
                .padding(.vertical, Spacing.xxSmall)
                .frame(maxWidth: .infinity)
                .background {
                    // A click on empty space clears the selection.
                    Color.clear.contentShape(Rectangle()).onTapGesture {
                        model.selection = []
                        focused = true
                    }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                move(press.key == .downArrow ? 1 : -1, extending: press.modifiers.contains(.shift), in: rows, proxy: proxy)
                return .handled
            }
            .onDeleteCommand { model.requestRemove() }
            .overlay { emptyState }
        }
    }

    private func click(_ id: TorrentID, in rows: [TorrentSnapshot]) {
        focused = true
        let flags = NSEvent.modifierFlags
        cursor = id
        if flags.contains(.command) {
            if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchor, let from = rows.firstIndex(where: { $0.id == anchor }),
                  let to = rows.firstIndex(where: { $0.id == id }) {
            model.selection = Set(rows[min(from, to)...max(from, to)].map(\.id))
        } else {
            model.selection = [id]
            anchor = id
        }
    }

    private func move(_ step: Int, extending: Bool, in rows: [TorrentSnapshot], proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let current = cursor.flatMap { id in rows.firstIndex { $0.id == id } }
            ?? rows.lastIndex { model.selection.contains($0.id) }
        let index = min(max((current ?? (step > 0 ? -1 : rows.count)) + step, 0), rows.count - 1)
        let id = rows[index].id
        cursor = id
        if extending, let anchor, let from = rows.firstIndex(where: { $0.id == anchor }) {
            model.selection = Set(rows[min(from, index)...max(from, index)].map(\.id))
        } else {
            model.selection = [id]
            anchor = id
        }
        proxy.scrollTo(id)
    }

    /// A right-click acts on the selection when the clicked card is part of it, otherwise on
    /// that card alone.
    private func menuTargets(_ id: TorrentID) -> Set<TorrentID> {
        model.selection.contains(id) ? model.selection : [id]
    }

    @ViewBuilder private var emptyState: some View {
        if model.torrents.isEmpty {
            EmptyStateView(symbol: "arrow.down.circle", title: "No torrents yet",
                           message: "Drop .torrent files here, or add a torrent or a magnet link.") {
                Button("Add from URL…") { model.showAddURL = true }
                    .buttonStyle(.freshet(.secondary))
                Button("Add Torrent…") { model.openTorrentFiles() }
                    .buttonStyle(.freshet(.primary))
            }
        } else if model.visible.isEmpty {
            EmptyStateView(symbol: model.filter.systemImage, title: "Nothing here",
                           message: model.searchText.isEmpty ? "No torrents are \(model.filter.title.lowercased()) right now."
                                                             : "No torrents match “\(model.searchText)”.") { EmptyView() }
        }
    }
}

/// An empty page: a quiet symbol, a heading, one line, and what to do next.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Colors.textTertiary)
                .accessibilityHidden(true)
            Text(title).font(Typography.sectionTitle)
            Text(message)
                .font(Typography.callout)
                .foregroundStyle(Colors.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Spacing.xSmall) { actions() }
                .padding(.top, Spacing.xxSmall)
        }
        .padding(Spacing.large)
        .frame(maxWidth: 360)
    }
}

/// One torrent as a card: state tile, name with tags, a one-line summary and progress, and the
/// size with progress or ratio on the right.
struct TorrentCardRow: View {
    let torrent: TorrentSnapshot
    let label: String?
    let isSelected: Bool
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let style = StateStyle(torrent)
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        HStack(alignment: .center, spacing: Spacing.small) {
            IconTile(symbol: style.symbol, color: style.tileColor)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                HStack(spacing: Spacing.xxSmallPlus) {
                    Text(torrent.displayName)
                        .font(Typography.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let tag = stateTag(style) {
                        Badge(text: tag, tone: style.badgeTone)
                    }
                    if let label {
                        Badge(text: label, tone: .accent, systemImage: "tag")
                    }
                }
                Text(summary)
                    .font(Typography.metadata)
                    .foregroundStyle(style == .error ? Colors.statusDangerText : Colors.textSecondary)
                    .lineLimit(1)
                if !torrent.isComplete {
                    ProgressTrack(value: torrent.progress, color: style.color)
                        .frame(maxWidth: 440)
                        .padding(.top, Spacing.xxxSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Spacing.xxSmall) {
                Text(torrent.hasMetadata ? Format.bytes(torrent.totalWanted) : "—")
                    .font(Typography.rowTitle.weight(.semibold).numbers)
                    .monospacedDigit()
                Text(torrent.isComplete ? "ratio \(Format.ratio(torrent.ratio))" : Format.percent(torrent.progress))
                    .font(Typography.metadata.numbers)
                    .monospacedDigit()
                    .foregroundStyle(Colors.textTertiary)
            }
        }
        .padding(.horizontal, PageLayout.cardHorizontalPadding)
        .padding(.vertical, Spacing.small)
        .background(shape.fill(isSelected ? Colors.fillSecondaryPressed : (hovering ? Colors.fillSecondaryHover : Colors.fillSecondary)))
        .overlay {
            shape.strokeBorder(isSelected ? Colors.actionPrimary : (contrast == .increased ? Colors.borderStrong : Colors.borderSubtle),
                               lineWidth: isSelected ? 1.5 : 0.5)
        }
        .contentShape(shape)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(torrent.displayName)
        .accessibilityValue("\(torrent.statusText), \(Format.percent(torrent.progress)), \(summary)\(label.map { ", label \($0)" } ?? "")")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Only states worth calling out get a tag; downloading and done speak through the tile.
    private func stateTag(_ style: StateStyle) -> String? {
        switch style {
        case .error: return "Error"
        case .paused: return "Paused"
        case .queued: return "Queued"
        case .checking: return "Checking \(Format.percent(torrent.progress))"
        case .seeding: return "Seeding"
        case .downloading, .done: return nil
        }
    }

    private var summary: String {
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
            return "Waiting for peers who want it"
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

/// A thin progress track with rounded ends, 4 pt unless asked otherwise.
struct ProgressTrack: View {
    let value: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(Colors.textPrimary.opacity(0.12))
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(color)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
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

