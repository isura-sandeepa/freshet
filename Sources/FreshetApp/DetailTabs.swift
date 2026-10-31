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
            Picker("Details", selection: $tab) {
                ForEach(DetailTab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 6)
            Divider()
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
                ContentUnavailableView("No Torrent Selected", systemImage: "info.circle",
                                       description: Text("Select a torrent to see its details."))
            }
        }
    }
}

struct GeneralTab: View {
    let torrent: TorrentSnapshot
    let info: TorrentInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Downloaded:").foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    ProgressView(value: min(max(torrent.progress, 0), 1))
                    Text(Format.percent(torrent.progress)).monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                HStack {
                    Text("Availability:").foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    ProgressView(value: min(max(torrent.availability, 0), 1))
                    Text(Format.availability(torrent.availability)).monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                GroupBox("Transfer") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            key("Time Elapsed:"); value(Format.duration(TimeInterval(torrent.activeSeconds)))
                            key("Remaining:"); value(torrent.isComplete ? "Done" : Format.duration(torrent.eta))
                            key("Share Ratio:"); value(Format.ratio(torrent.ratio))
                        }
                        GridRow {
                            key("Downloaded:"); value(Format.bytes(torrent.allTimeDownload))
                            key("Download Speed:"); value(Format.rateOrZero(torrent.downloadRate))
                            key("Seeds:"); value(Format.count(torrent.connectedSeeds, of: torrent.swarmSeeds))
                        }
                        GridRow {
                            key("Uploaded:"); value(Format.bytes(torrent.allTimeUpload))
                            key("Upload Speed:"); value(Format.rateOrZero(torrent.uploadRate))
                            key("Peers:"); value(Format.count(torrent.connectedLeechers, of: torrent.swarmPeers))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("General") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow { key("Save As:"); value((torrent.savePath as NSString).appendingPathComponent(torrent.name)) }
                        GridRow { key("Total Size:"); value(info.map { Format.bytes($0.totalSize) } ?? "Waiting for metadata") }
                        GridRow { key("Pieces:"); value(piecesText) }
                        GridRow { key("Created On:"); value(Format.date(info?.creationDate)) }
                        GridRow { key("Created By:"); value(info?.creator ?? "") }
                        GridRow { key("Added On:"); value(Format.date(torrent.addedDate)) }
                        GridRow { key("Completed On:"); value(Format.date(torrent.completedDate)) }
                        GridRow { key("Hash:"); value(hashText) }
                        GridRow { key("Tracker:"); value(torrent.currentTracker) }
                        GridRow { key("Comment:"); value(info?.comment ?? "") }
                        if let error = torrent.errorMessage {
                            GridRow {
                                key("Error:")
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Palette.error)
                                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
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

    private func key(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func value(_ text: String) -> some View {
        Text(text).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
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
            ContentUnavailableView(torrent.hasMetadata ? "Loading Files" : "Waiting for Metadata", systemImage: "doc.on.doc",
                                   description: Text(torrent.hasMetadata ? "" : "The file list appears once peers send the torrent's metadata."))
        } else {
            Table(files.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.path) { file in
                    Text(file.path).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(file.priority == .skip ? .secondary : .primary)
                }
                TableColumn("Size", value: \.size) { file in
                    Text(Format.bytes(file.size)).monospacedDigit()
                }
                .width(min: 60, ideal: 80, max: 120)
                TableColumn("Done", value: \.progress) { file in
                    HStack(spacing: 6) {
                        ProgressView(value: file.progress)
                        Text(Format.percent(file.progress)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .width(min: 100, ideal: 150, max: 220)
                TableColumn("Priority", value: \.priorityRank) { file in
                    Text(file.priority.title)
                }
                .width(min: 80, ideal: 100, max: 130)
            }
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
                ContentUnavailableView("No Peers Connected", systemImage: "person.2")
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Country", value: \.country) { row in
                        let name = Locale.current.localizedString(forRegionCode: row.country) ?? row.country
                        HStack(spacing: 4) {
                            Text(CountryDatabase.flag(for: row.country))
                            Text(row.country.uppercased()).foregroundStyle(.secondary)
                        }
                        .help(name)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(row.country.isEmpty ? "Unknown" : name)
                    }
                    .width(min: 50, ideal: 64, max: 90)
                    TableColumn("IP", value: \.peer.ip) { row in Text(row.peer.address).monospacedDigit() }
                        .width(min: 120, ideal: 170)
                    TableColumn("Client", value: \.peer.client) { row in Text(row.peer.client) }
                        .width(min: 100, ideal: 150)
                    TableColumn("Flags", value: \.peer.flags) { row in Text(row.peer.flags) }
                        .width(min: 40, ideal: 60)
                    TableColumn("%", value: \.peer.progress) { row in Text(Format.percent(row.peer.progress)).monospacedDigit() }
                        .width(min: 50, ideal: 60)
                    TableColumn("Down Speed", value: \.peer.downloadRate) { row in Text(Format.rate(row.peer.downloadRate)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("Up Speed", value: \.peer.uploadRate) { row in Text(Format.rate(row.peer.uploadRate)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("Downloaded", value: \.peer.totalDownload) { row in Text(Format.bytes(row.peer.totalDownload)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("Uploaded", value: \.peer.totalUpload) { row in Text(Format.bytes(row.peer.totalUpload)).monospacedDigit() }
                        .width(min: 70, ideal: 90)
                }
            }
            HStack {
                Button("Add Peer…") { model.promptAddPeer(to: torrentID) }
                Button("Clear Peer List and Bans") { model.clearPeers(of: torrentID) }
                Spacer()
                if countries != nil {
                    Link("IP Geolocation by DB-IP", destination: URL(string: "https://db-ip.com")!)
                        .font(.callout)
                }
            }
            .padding(6)
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
                TableColumn("URL") { tracker in Text(tracker.url).lineLimit(1).truncationMode(.middle) }
                    .width(min: 160, ideal: 300)
                TableColumn("Status") { tracker in
                    if tracker.status == .error {
                        Label(tracker.statusTitle, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.error)
                    } else {
                        Text(tracker.statusTitle)
                    }
                }
                .width(min: 100, ideal: 200)
                TableColumn("Seeds") { tracker in Text(tracker.seeds >= 0 ? "\(tracker.seeds)" : "").monospacedDigit() }
                    .width(min: 40, ideal: 60)
                TableColumn("Peers") { tracker in Text(tracker.peers >= 0 ? "\(tracker.peers)" : "").monospacedDigit() }
                    .width(min: 40, ideal: 60)
                TableColumn("Downloaded") { tracker in Text(tracker.downloaded >= 0 ? "\(tracker.downloaded)" : "").monospacedDigit() }
                    .width(min: 60, ideal: 80)
                TableColumn("Update In") { tracker in
                    Text(tracker.nextAnnounce >= 0 ? Format.duration(TimeInterval(tracker.nextAnnounce)) : "").monospacedDigit()
                }
                .width(min: 60, ideal: 80)
            }
            HStack {
                Spacer()
                Button("Update Tracker") { model.perform(.reannounce, ids: [torrentID]) }
            }
            .padding(6)
        }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { scope in Text(scope.rawValue).tag(scope) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
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
                    AxisGridLine()
                    AxisValueLabel {
                        if let speed = value.as(Int.self) { Text(Format.rateOrZero(speed)) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour().minute().second())
                }
            }
        }
        .padding(10)
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
                TableColumn("Time") { entry in Text(entry.date, format: .dateTime.hour().minute().second()).monospacedDigit() }
                    .width(min: 70, ideal: 80, max: 100)
                TableColumn("Torrent") { entry in
                    Text(entry.torrentID.flatMap { model.torrents[$0]?.displayName } ?? "")
                        .lineLimit(1).truncationMode(.middle)
                }
                .width(min: 100, ideal: 180)
                TableColumn("Message") { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        switch entry.level {
                        case .error:
                            Image(systemName: "xmark.octagon.fill").foregroundStyle(Palette.error).accessibilityLabel("Error")
                        case .warning:
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning).accessibilityLabel("Warning")
                        default:
                            EmptyView()
                        }
                        Text(entry.message)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            HStack {
                Toggle("Selected torrent only", isOn: $onlySelected)
                Spacer()
                Button("Clear") { model.clearLogs() }
            }
            .padding(6)
        }
    }
}

/// Download and upload differ by line pattern and shade as well as color, so the charts read
/// without telling blue from green.
enum TransferStyle {
    static let download = Color.blue
    static let upload = Color.green
    static let downloadStroke = StrokeStyle(lineWidth: 2)
    static let uploadStroke = StrokeStyle(lineWidth: 2, dash: [5, 3])
}

/// A legend that shows the line pattern (or bar shade) next to each name.
struct TransferLegend: View {
    enum Kind { case line, bar }
    let kind: Kind

    var body: some View {
        HStack(spacing: 14) {
            entry("Download", color: TransferStyle.download, stroke: TransferStyle.downloadStroke, opacity: 1)
            entry("Upload", color: kind == .bar ? TransferStyle.download : TransferStyle.upload,
                  stroke: TransferStyle.uploadStroke, opacity: kind == .bar ? 0.4 : 1)
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .line ? "Download is a solid line, upload is dashed" : "Download is the dark bar, upload the light bar")
    }

    private func entry(_ title: String, color: Color, stroke: StrokeStyle, opacity: Double) -> some View {
        HStack(spacing: 5) {
            switch kind {
            case .line:
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 5))
                    path.addLine(to: CGPoint(x: 22, y: 5))
                }
                .stroke(color, style: stroke)
                .frame(width: 22, height: 10)
            case .bar:
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(opacity)).frame(width: 12, height: 12)
            }
            Text(title)
        }
    }
}
