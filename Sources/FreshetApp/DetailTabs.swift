import Charts
import FreshetCore
import SwiftUI

enum DetailTab: String, CaseIterable, Identifiable {
    case general, files, peers, trackers, speed, logger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .files: return "Files"
        case .peers: return "Peers"
        case .trackers: return "Trackers"
        case .speed: return "Speed"
        case .logger: return "Logger"
        }
    }
}

/// The tabs under the torrent list, showing the first selected torrent.
struct DetailTabsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("detailTab") private var tab: DetailTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ChipTabs(tabs: DetailTab.allCases, selection: $tab) { $0.title }
                Spacer()
                if let torrent = model.focusedTorrent, tab != .speed, tab != .logger {
                    Text(torrent.displayName)
                        .font(Typography.metadata)
                        .foregroundStyle(Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall)
            CardDivider(inset: 0)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .speed:
            SpeedTab()
        case .logger:
            LoggerTab()
        default:
            if let torrent = model.focusedTorrent {
                switch tab {
                case .general:
                    GeneralTab(torrent: torrent, info: model.details?.info)
                case .files:
                    FilesTab(torrent: torrent, files: model.details?.files ?? [])
                case .peers:
                    PeersTab(torrentID: torrent.id, peers: model.details?.peers ?? [])
                default:
                    TrackersTab(torrentID: torrent.id, trackers: model.details?.trackers ?? [])
                }
            } else {
                EmptyStateView(symbol: "info.circle", title: "No torrent selected",
                               message: "Select a torrent to see its details.") { EmptyView() }
            }
        }
    }
}

/// A tab's bottom bar: quiet actions on a hairline.
struct TabFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            CardDivider(inset: 0)
            HStack(spacing: Spacing.xSmall) { content }
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.xSmall)
        }
    }
}

extension View {
    /// Tables inside cards: no stripes, the card's own surface behind them.
    func cardTable() -> some View {
        alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
    }
}

struct GeneralTab: View {
    let torrent: TorrentSnapshot
    let info: TorrentInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                VStack(spacing: Spacing.xSmall) {
                    meter("Downloaded", value: torrent.progress, text: Format.percent(torrent.progress),
                          color: StateStyle(torrent).color)
                    meter("Availability", value: torrent.availability, text: Format.availability(torrent.availability),
                          color: Colors.Chart.neutral)
                }
                section("Transfer") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.small, verticalSpacing: Spacing.xxSmallPlus) {
                        GridRow {
                            key("Time elapsed"); value(Format.duration(TimeInterval(torrent.activeSeconds)))
                            key("Remaining"); value(torrent.isComplete ? "Done" : Format.duration(torrent.eta))
                            key("Share ratio"); value(Format.ratio(torrent.ratio))
                        }
                        GridRow {
                            key("Downloaded"); value(Format.bytes(torrent.allTimeDownload))
                            key("Download speed"); value(Format.rateOrZero(torrent.downloadRate))
                            key("Seeds"); value(Format.count(torrent.connectedSeeds, of: torrent.swarmSeeds))
                        }
                        GridRow {
                            key("Uploaded"); value(Format.bytes(torrent.allTimeUpload))
                            key("Upload speed"); value(Format.rateOrZero(torrent.uploadRate))
                            key("Peers"); value(Format.count(torrent.connectedLeechers, of: torrent.swarmPeers))
                        }
                    }
                }
                section("General") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.small, verticalSpacing: Spacing.xxSmallPlus) {
                        GridRow { key("Save as"); value((torrent.savePath as NSString).appendingPathComponent(torrent.name)) }
                        GridRow { key("Total size"); value(info.map { Format.bytes($0.totalSize) } ?? "Waiting for metadata") }
                        GridRow { key("Pieces"); value(piecesText) }
                        GridRow { key("Created on"); value(Format.date(info?.creationDate)) }
                        GridRow { key("Created by"); value(info?.creator ?? "") }
                        GridRow { key("Added on"); value(Format.date(torrent.addedDate)) }
                        GridRow { key("Completed on"); value(Format.date(torrent.completedDate)) }
                        GridRow { key("Hash"); value(hashText, monospaced: true) }
                        GridRow { key("Tracker"); value(torrent.currentTracker) }
                        GridRow { key("Comment"); value(info?.comment ?? "") }
                        if let error = torrent.errorMessage {
                            GridRow {
                                key("Error")
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(Typography.callout)
                                    .foregroundStyle(Colors.statusDangerText)
                                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.medium)
        }
    }

    private var piecesText: String {
        guard let info, info.hasMetadata else { return "" }
        let size = Format.bytes(Int64(info.pieceLength))
        return "\(info.pieceCount) × \(size) (have \(torrent.piecesHave))\(info.isPrivate ? " · private torrent" : "")"
    }

    private var hashText: String {
        guard let info else { return torrent.id }
        if !info.infoHashV1.isEmpty && !info.infoHashV2.isEmpty { return "v1 \(info.infoHashV1) · v2 \(info.infoHashV2)" }
        return info.infoHashV1.isEmpty ? info.infoHashV2 : info.infoHashV1
    }

    private func meter(_ title: String, value: Double, text: String, color: Color) -> some View {
        HStack(spacing: Spacing.small) {
            Text(title)
                .font(Typography.callout)
                .foregroundStyle(Colors.textSecondary)
                .frame(width: 84, alignment: .leading)
            ProgressTrack(value: value, color: color, height: 6)
            Text(text)
                .font(Typography.callout.numbers)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Typography.metadataEmphasis)
                .foregroundStyle(Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.small)
                .insetCard()
        }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(Typography.callout)
            .foregroundStyle(Colors.textSecondary)
            .gridColumnAlignment(.leading)
    }

    private func value(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? Typography.callout.monospaced() : Typography.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct FilesTab: View {
    @Environment(AppModel.self) private var model
    let torrent: TorrentSnapshot
    let files: [FileEntry]
    @State private var selection = Set<FileEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\FileEntry.path)]

    var body: some View {
        if files.isEmpty {
            EmptyStateView(symbol: "doc.on.doc", title: torrent.hasMetadata ? "Loading files" : "Waiting for metadata",
                           message: torrent.hasMetadata ? "The file list appears in a moment."
                                                        : "The file list appears once peers send the torrent's details.") { EmptyView() }
        } else {
            Table(files.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.path) { file in
                    Text(file.path).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(file.priority == .skip ? Colors.textTertiary : Colors.textPrimary)
                }
                TableColumn("Size", value: \.size) { file in
                    Text(Format.bytes(file.size)).font(Typography.body.numbers).monospacedDigit()
                }
                .width(min: 60, ideal: 80, max: 120)
                TableColumn("Done", value: \.progress) { file in
                    HStack(spacing: Spacing.xxSmallPlus) {
                        ProgressTrack(value: file.progress, color: file.progress >= 1 ? Colors.State.done : Colors.State.downloading)
                        Text(Format.percent(file.progress)).font(Typography.callout.numbers).monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                .width(min: 100, ideal: 150, max: 220)
                TableColumn("Priority", value: \.priorityRank) { file in
                    Text(file.priority.title)
                        .foregroundStyle(file.priority == .skip ? Colors.textTertiary : Colors.textSecondary)
                }
                .width(min: 80, ideal: 100, max: 130)
            }
            .cardTable()
            .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
                if !ids.isEmpty {
                    ForEach(FilePriority.allCases.reversed(), id: \.self) { priority in
                        Button(priority.title) { model.setFilePriority(priority, files: ids, torrent: torrent.id) }
                    }
                }
            }
        }
    }
}

struct PeersTab: View {
    @Environment(AppModel.self) private var model
    let torrentID: TorrentID
    let peers: [PeerEntry]
    @State private var sortOrder = [KeyPathComparator(\Row.peer.downloadRate, order: .reverse)]

    struct Row: Identifiable {
        let peer: PeerEntry
        let country: String
        var id: String { peer.id }
    }

    var body: some View {
        let countries = model.countries
        let rows = peers.map { Row(peer: $0, country: countries?.country(for: $0.ip) ?? "") }.sorted(using: sortOrder)
        VStack(spacing: 0) {
            if peers.isEmpty {
                EmptyStateView(symbol: "person.2", title: "No peers connected",
                               message: "Peers appear here as Freshet finds them.") { EmptyView() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Country", value: \.country) { row in
                        let name = Locale.current.localizedString(forRegionCode: row.country) ?? row.country
                        HStack(spacing: Spacing.xxSmall) {
                            Text(CountryDatabase.flag(for: row.country))
                            Text(row.country.uppercased()).foregroundStyle(Colors.textSecondary)
                        }
                        .help(name)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.country.isEmpty ? "Unknown" : name)
                    }
                    .width(min: 50, ideal: 64, max: 90)
                    TableColumn("IP", value: \.peer.ip) { row in Text(row.peer.address).font(Typography.body.numbers).monospacedDigit() }
                        .width(min: 120, ideal: 170)
                    TableColumn("Client", value: \.peer.client) { row in Text(row.peer.client) }
                        .width(min: 100, ideal: 150)
                    TableColumn("Flags", value: \.peer.flags) { row in Text(row.peer.flags).font(Typography.callout.monospaced()) }
                        .width(min: 40, ideal: 60)
                    TableColumn("%", value: \.peer.progress) { row in
                        Text(Format.percent(row.peer.progress)).font(Typography.body.numbers).monospacedDigit()
                    }
                    .width(min: 50, ideal: 60)
                    TableColumn("Down Speed", value: \.peer.downloadRate) { row in
                        Text(Format.rate(row.peer.downloadRate)).font(Typography.body.numbers).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Up Speed", value: \.peer.uploadRate) { row in
                        Text(Format.rate(row.peer.uploadRate)).font(Typography.body.numbers).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Downloaded", value: \.peer.totalDownload) { row in
                        Text(Format.bytes(row.peer.totalDownload)).font(Typography.body.numbers).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Uploaded", value: \.peer.totalUpload) { row in
                        Text(Format.bytes(row.peer.totalUpload)).font(Typography.body.numbers).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                }
                .cardTable()
            }
            TabFooter {
                Button("Add Peer…") { model.promptAddPeer(to: torrentID) }
                    .buttonStyle(.freshet(.secondary, size: .small))
                Button("Clear Peer List and Bans") { model.clearPeers(of: torrentID) }
                    .buttonStyle(.freshet(.quiet, size: .small))
                Spacer()
                if countries != nil {
                    Link("IP Geolocation by DB-IP", destination: URL(string: "https://db-ip.com")!)
                        .font(Typography.metadata)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
        }
    }
}

struct TrackersTab: View {
    @Environment(AppModel.self) private var model
    let torrentID: TorrentID
    let trackers: [TrackerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(trackers) {
                TableColumn("URL") { tracker in
                    Text(tracker.url).font(Typography.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                }
                .width(min: 160, ideal: 300)
                TableColumn("Status") { tracker in
                    if tracker.status == .error {
                        Label(tracker.statusTitle, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Colors.statusDangerText)
                    } else {
                        Text(tracker.statusTitle).foregroundStyle(Colors.textSecondary)
                    }
                }
                .width(min: 100, ideal: 200)
                TableColumn("Seeds") { tracker in number(tracker.seeds >= 0 ? "\(tracker.seeds)" : "") }
                    .width(min: 40, ideal: 60)
                TableColumn("Peers") { tracker in number(tracker.peers >= 0 ? "\(tracker.peers)" : "") }
                    .width(min: 40, ideal: 60)
                TableColumn("Downloaded") { tracker in number(tracker.downloaded >= 0 ? "\(tracker.downloaded)" : "") }
                    .width(min: 60, ideal: 80)
                TableColumn("Update In") { tracker in
                    number(tracker.nextAnnounce >= 0 ? Format.duration(TimeInterval(tracker.nextAnnounce)) : "")
                }
                .width(min: 60, ideal: 80)
            }
            .cardTable()
            TabFooter {
                Spacer()
                Button("Update Tracker") { model.perform(.reannounce, ids: [torrentID]) }
                    .buttonStyle(.freshet(.secondary, size: .small))
            }
        }
    }

    private func number(_ text: String) -> some View {
        Text(text).font(Typography.body.numbers).monospacedDigit()
    }
}

struct SpeedTab: View {
    @Environment(AppModel.self) private var model
    @State private var scope = Scope.all

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All Torrents"
        case selected = "Selected Torrent"
        var id: String { rawValue }
    }

    var body: some View {
        let samples = scope == .all ? model.globalHistory.samples : model.focusedHistory.samples
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                ChipTabs(tabs: Scope.allCases, selection: $scope) { $0.rawValue }
                Spacer()
                TransferLegend(kind: .line)
            }
            Chart {
                ForEach(samples) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("Speed", sample.download),
                             series: .value("Direction", "Download"))
                        .foregroundStyle(TransferStyle.download)
                        .lineStyle(TransferStyle.downloadStroke)
                        .accessibilityLabel("Download at \(sample.date.formatted(date: .omitted, time: .standard))")
                        .accessibilityValue(Format.rateOrZero(sample.download))
                    LineMark(x: .value("Time", sample.date), y: .value("Speed", sample.upload),
                             series: .value("Direction", "Upload"))
                        .foregroundStyle(TransferStyle.upload)
                        .lineStyle(TransferStyle.uploadStroke)
                        .accessibilityLabel("Upload at \(sample.date.formatted(date: .omitted, time: .standard))")
                        .accessibilityValue(Format.rateOrZero(sample.upload))
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Colors.borderStrong)
                    AxisValueLabel {
                        if let speed = value.as(Int.self) { Text(Format.rateOrZero(speed)).font(Typography.metadata.numbers) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Colors.borderSubtle)
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                        .font(Typography.metadata.numbers.font)
                }
            }
        }
        .padding(Spacing.small)
    }
}

struct LoggerTab: View {
    @Environment(AppModel.self) private var model
    @State private var onlySelected = false

    var body: some View {
        let focused = model.focusedID
        let entries = model.logs.reversed().filter { !onlySelected || $0.torrentID == focused }
        VStack(spacing: 0) {
            Table(entries) {
                TableColumn("Time") { entry in
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(Typography.callout.numbers)
                        .monospacedDigit()
                        .foregroundStyle(Colors.textSecondary)
                }
                .width(min: 70, ideal: 80, max: 100)
                TableColumn("Torrent") { entry in
                    Text(entry.torrentID.flatMap { model.torrents[$0]?.displayName } ?? "")
                        .lineLimit(1).truncationMode(.middle)
                }
                .width(min: 100, ideal: 180)
                TableColumn("Message") { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxSmallPlus) {
                        switch entry.level {
                        case .error:
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(Colors.statusDangerText).accessibilityLabel("Error")
                        case .warning:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Colors.statusCheckText).accessibilityLabel("Warning")
                        default:
                            EmptyView()
                        }
                        Text(entry.message)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            .cardTable()
            TabFooter {
                Toggle("Selected torrent only", isOn: $onlySelected)
                    .toggleStyle(CheckboxStyle())
                    .font(Typography.callout)
                Spacer()
                Button("Clear") { model.clearLogs() }
                    .buttonStyle(.freshet(.secondary, size: .small))
            }
        }
    }
}

/// Download and upload differ by line pattern as well as color — blue for what arrives,
/// green for what's sent — so the charts read without telling the colors apart.
enum TransferStyle {
    static let download = Colors.Chart.blue
    static let upload = Colors.Chart.green
    static let downloadStroke = StrokeStyle(lineWidth: 2)
    static let uploadStroke = StrokeStyle(lineWidth: 2, dash: [5, 3])
}

/// A legend that shows the line pattern (or bar color) next to each name.
struct TransferLegend: View {
    enum Kind { case line, bar }
    let kind: Kind

    var body: some View {
        HStack(spacing: Spacing.small) {
            entry("Download", color: TransferStyle.download, stroke: TransferStyle.downloadStroke)
            entry("Upload", color: TransferStyle.upload, stroke: TransferStyle.uploadStroke)
        }
        .font(Typography.metadata)
        .foregroundStyle(Colors.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .line ? "Download is a solid blue line, upload a dashed green line"
                                          : "Download bars are blue, upload bars green")
    }

    private func entry(_ title: String, color: Color, stroke: StrokeStyle) -> some View {
        HStack(spacing: Spacing.xxSmallPlus) {
            switch kind {
            case .line:
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5))
                    path.addLine(to: CGPoint(x: 22, y: 5))
                }
                .stroke(color, style: stroke)
                .frame(width: 22, height: 10)
            case .bar:
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 10, height: 10)
            }
            Text(title)
        }
    }
}
