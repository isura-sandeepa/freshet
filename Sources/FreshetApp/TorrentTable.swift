import AppKit
import FreshetCore
import SwiftUI

struct TorrentListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TorrentTable(rows: model.visible,
                     labels: model.labels.assignments,
                     selection: $model.selection,
                     sortKey: $model.sortKey,
                     buildMenu: { menu, ids in TorrentMenu.populate(menu, ids: ids, model: model) },
                     onDoubleClick: { model.reveal($0) })
            .overlay {
                if model.torrents.isEmpty {
                    ContentUnavailableView("No Torrents",
                                           systemImage: "arrow.down.circle",
                                           description: Text("Drop .torrent files here, or use Add Torrent (⌘O) or Add from URL (⌘U)."))
                }
            }
    }
}

/// The torrent list as an AppKit table: cell reuse and per-row reloads keep it fast with
/// thousands of torrents updating every second. Column order, widths and visibility are
/// saved automatically.
struct TorrentTable: NSViewRepresentable {
    var rows: [TorrentSnapshot]
    var labels: [TorrentID: String]
    @Binding var selection: Set<TorrentID>
    @Binding var sortKey: TorrentSortKey
    var buildMenu: (NSMenu, Set<TorrentID>) -> Void
    var onDoubleClick: (TorrentID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.allowsColumnSelection = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 8, height: 2)
        for field in TorrentField.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(field.rawValue))
            column.title = field.title
            column.width = field.defaultWidth
            column.minWidth = 30
            column.isHidden = !field.visibleByDefault
            column.headerCell.alignment = field.alignment
            column.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: field.defaultAscending)
            table.addTableColumn(column)
        }
        table.autosaveTableColumns = true
        table.autosaveName = "FreshetTorrentTable"
        table.sortDescriptors = [NSSortDescriptor(key: sortKey.field.rawValue, ascending: sortKey.ascending)]
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        table.headerView?.menu = context.coordinator.makeHeaderMenu()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        context.coordinator.tableView = table
        context.coordinator.apply(rows: rows, labels: labels, selection: selection)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(rows: rows, labels: labels, selection: selection)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: TorrentTable
        weak var tableView: NSTableView?
        private var rows: [TorrentSnapshot] = []
        private var labels: [TorrentID: String] = [:]
        private var isSyncingSelection = false

        init(_ parent: TorrentTable) {
            self.parent = parent
        }

        /// Reloads only what changed: everything when rows were added, removed or reordered,
        /// otherwise just the rows whose values differ.
        func apply(rows newRows: [TorrentSnapshot], labels newLabels: [TorrentID: String], selection: Set<TorrentID>) {
            guard let table = tableView else { return }
            let old = rows
            let labelsChanged = newLabels != labels
            rows = newRows
            labels = newLabels
            if old.map(\.id) != newRows.map(\.id) {
                table.reloadData()
            } else {
                var changed = IndexSet()
                for (index, row) in newRows.enumerated() where labelsChanged || row != old[index] {
                    changed.insert(index)
                }
                if !changed.isEmpty {
                    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
                }
            }
            syncSelection(selection)
        }

        private func syncSelection(_ selection: Set<TorrentID>) {
            guard let table = tableView else { return }
            var indexes = IndexSet()
            for (index, row) in rows.enumerated() where selection.contains(row.id) { indexes.insert(index) }
            guard indexes != table.selectedRowIndexes else { return }
            isSyncingSelection = true
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            isSyncingSelection = false
        }

        // MARK: Data source and delegate

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < rows.count,
                  let field = TorrentField(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let torrent = rows[row]
            if field == .done {
                let cell = tableView.makeView(withIdentifier: ProgressCellView.identifier, owner: nil) as? ProgressCellView ?? ProgressCellView()
                cell.update(progress: torrent.progress, color: Self.color(for: torrent.activity), activity: torrent.activity, status: torrent.statusText)
                return cell
            }
            let cell = tableView.makeView(withIdentifier: TextCellView.identifier, owner: nil) as? TextCellView ?? TextCellView()
            let color: NSColor = field == .status && torrent.activity == .error ? .systemRed : .labelColor
            cell.update(text: field.text(for: torrent, label: labels[torrent.id]), alignment: field.alignment,
                        monospacedDigits: field.isNumeric, color: color)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table = tableView else { return }
            let ids = Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].id : nil })
            if ids != parent.selection { parent.selection = ids }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
                  let field = TorrentField(rawValue: key) else { return }
            let newKey = TorrentSortKey(field: field, ascending: descriptor.ascending)
            if newKey != parent.sortKey { parent.sortKey = newKey }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < rows.count else { return }
            parent.onDoubleClick(rows[row].id)
        }

        // MARK: Menus

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table = tableView else { return }
            let clicked = table.clickedRow
            var ids = parent.selection
            if clicked >= 0, clicked < rows.count, !table.selectedRowIndexes.contains(clicked) {
                table.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false)
                ids = [rows[clicked].id]
            }
            guard !ids.isEmpty else { return }
            parent.buildMenu(menu, ids)
        }

        func makeHeaderMenu() -> NSMenu {
            let menu = NSMenu(title: "Columns")
            for field in TorrentField.allCases {
                let item = ClosureMenuItem(field.title) { [weak self] in self?.toggleColumn(field) }
                menu.addItem(item)
            }
            menu.delegate = HeaderMenuDelegate.shared
            HeaderMenuDelegate.shared.coordinator = self
            return menu
        }

        func isColumnVisible(_ field: TorrentField) -> Bool {
            guard let column = tableView?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(field.rawValue)) else { return false }
            return !column.isHidden
        }

        private func toggleColumn(_ field: TorrentField) {
            guard field != .name,
                  let column = tableView?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(field.rawValue)) else { return }
            column.isHidden.toggle()
        }

        static func color(for activity: TorrentActivity) -> NSColor {
            switch activity {
            case .downloading, .downloadingMetadata: return .systemBlue
            case .seeding, .finished: return .systemGreen
            case .checking: return .systemOrange
            case .error: return .systemRed
            case .queued, .queuedSeed, .paused: return .systemGray
            }
        }
    }
}

/// Ticks the visible columns each time the header menu opens.
@MainActor
final class HeaderMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = HeaderMenuDelegate()
    weak var coordinator: TorrentTable.Coordinator?

    func menuNeedsUpdate(_ menu: NSMenu) {
        for (index, field) in TorrentField.allCases.enumerated() where index < menu.items.count {
            menu.items[index].state = (coordinator?.isColumnVisible(field) ?? false) ? .on : .off
            menu.items[index].isEnabled = field != .name
        }
    }
}

final class TextCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FreshetTextCell")
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String, alignment: NSTextAlignment, monospacedDigits: Bool, color: NSColor) {
        label.stringValue = text
        label.alignment = alignment
        label.textColor = color
        label.font = monospacedDigits ? .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                                      : .systemFont(ofSize: NSFont.systemFontSize)
        label.toolTip = text.count > 30 ? text : nil
    }
}

final class ProgressCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FreshetProgressCell")
    private let bar = ProgressBarView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 15),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(progress: Double, color: NSColor, activity: TorrentActivity, status: String) {
        bar.progress = progress
        bar.color = color
        bar.activity = activity
        bar.status = status
    }
}

/// A rounded bar with the percentage drawn on top, for the Done column.
/// Errors and checking also change the text on the bar, so the state doesn't rest on color.
final class ProgressBarView: NSView {
    var progress: Double = 0 { didSet { if progress != oldValue { needsDisplay = true } } }
    var color: NSColor = .systemBlue { didSet { if color != oldValue { needsDisplay = true } } }
    var activity: TorrentActivity = .paused { didSet { if activity != oldValue { needsDisplay = true } } }
    var status = ""

    private var caption: String {
        switch activity {
        case .error: return "Error"
        case .checking: return "Checking \(Format.percent(progress))"
        default: return Format.percent(progress)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .progressIndicator }
    override func accessibilityLabel() -> String? { "Done" }
    override func accessibilityValue() -> Any? { NSNumber(value: min(max(progress, 0), 1) * 100) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 100) }
    override func accessibilityValueDescription() -> String? { "\(Format.percent(progress)), \(status)" }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let track = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.quaternaryLabelColor.setFill()
        track.fill()
        let fraction = CGFloat(min(max(progress, 0), 1))
        if fraction > 0 {
            var fill = rect
            fill.size.width = max(rect.height, rect.width * fraction)
            let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            color.withAlphaComponent(highContrast ? 1 : 0.85).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()
            if highContrast {
                NSColor.labelColor.withAlphaComponent(0.6).setStroke()
                track.lineWidth = 1
                track.stroke()
            }
        }
        let text = caption as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func fire() {
        handler()
    }
}

/// The torrent list's context menu.
@MainActor
enum TorrentMenu {
    static func populate(_ menu: NSMenu, ids: Set<TorrentID>, model: AppModel) {
        menu.addItem(ClosureMenuItem("Start") { model.perform(.start, ids: ids) })
        menu.addItem(ClosureMenuItem("Pause") { model.perform(.pause, ids: ids) })
        menu.addItem(ClosureMenuItem("Force Start") { model.perform(.forceStart, ids: ids) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Force Re-check") { model.perform(.recheck, ids: ids) })
        menu.addItem(ClosureMenuItem("Update Tracker") { model.perform(.reannounce, ids: ids) })
        menu.addItem(.separator())
        if ids.count == 1, let id = ids.first {
            menu.addItem(ClosureMenuItem("Show in Finder") { model.reveal(id) })
        }
        menu.addItem(ClosureMenuItem("Copy Magnet Link") { model.copyMagnetLinks(ids) })
        menu.addItem(.separator())

        let labelMenu = NSMenu(title: "Label")
        labelMenu.addItem(ClosureMenuItem("New Label…") { model.promptNewLabel(for: ids) })
        labelMenu.addItem(ClosureMenuItem("Remove Label") { model.setLabel(nil, for: ids) })
        let names = model.labels.names
        if !names.isEmpty { labelMenu.addItem(.separator()) }
        for name in names {
            let item = ClosureMenuItem(name) { model.setLabel(name, for: ids) }
            item.state = ids.allSatisfy { model.labels.assignments[$0] == name } ? .on : .off
            labelMenu.addItem(item)
        }
        let labelItem = NSMenuItem(title: "Label", action: nil, keyEquivalent: "")
        labelItem.submenu = labelMenu
        menu.addItem(labelItem)

        let queueMenu = NSMenu(title: "Queue")
        queueMenu.addItem(ClosureMenuItem("Move to Top") { model.perform(.queueTop, ids: ids) })
        queueMenu.addItem(ClosureMenuItem("Move Up") { model.perform(.queueUp, ids: ids) })
        queueMenu.addItem(ClosureMenuItem("Move Down") { model.perform(.queueDown, ids: ids) })
        queueMenu.addItem(ClosureMenuItem("Move to Bottom") { model.perform(.queueBottom, ids: ids) })
        let queueItem = NSMenuItem(title: "Queue", action: nil, keyEquivalent: "")
        queueItem.submenu = queueMenu
        menu.addItem(queueItem)

        let bandwidthMenu = NSMenu(title: "Bandwidth Allocation")
        for priority in BandwidthPriority.allCases.reversed() {
            let item = ClosureMenuItem(priority.title) { model.setPriority(priority, for: ids) }
            item.state = ids.allSatisfy { model.automation.meta(for: $0).priority == priority } ? .on : .off
            bandwidthMenu.addItem(item)
        }
        let bandwidthItem = NSMenuItem(title: "Bandwidth Allocation", action: nil, keyEquivalent: "")
        bandwidthItem.submenu = bandwidthMenu
        menu.addItem(bandwidthItem)

        let advancedMenu = NSMenu(title: "Advanced")
        advancedMenu.addItem(ClosureMenuItem("Set Download Location…") { model.chooseDownloadLocation(for: ids) })
        if ids.count == 1, let id = ids.first {
            advancedMenu.addItem(ClosureMenuItem("Save .torrent File…") { model.saveTorrentFile(id) })
            advancedMenu.addItem(ClosureMenuItem("Add Peer…") { model.promptAddPeer(to: id) })
            advancedMenu.addItem(ClosureMenuItem("Clear Peer List and Bans") { model.clearPeers(of: id) })
        }
        let advancedItem = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        advancedItem.submenu = advancedMenu
        menu.addItem(advancedItem)

        menu.addItem(.separator())
        if ids.count == 1, let id = ids.first {
            menu.addItem(ClosureMenuItem("Properties…") { model.showProperties(id) })
        }
        menu.addItem(ClosureMenuItem("Remove…") { model.requestRemove(ids) })
    }
}

extension TorrentField {
    var defaultWidth: CGFloat {
        switch self {
        case .queue: return 34
        case .name: return 300
        case .size: return 80
        case .done: return 110
        case .status: return 130
        case .seeds, .peers: return 80
        case .downSpeed, .upSpeed: return 90
        case .eta: return 70
        case .ratio: return 60
        case .availability: return 80
        case .label: return 90
        case .added, .completed: return 135
        case .remaining, .downloaded, .uploaded: return 85
        case .tracker: return 150
        case .savePath: return 220
        }
    }

    var alignment: NSTextAlignment {
        switch self {
        case .name, .status, .label, .tracker, .savePath, .added, .completed: return .left
        case .queue: return .center
        default: return .right
        }
    }

    var visibleByDefault: Bool {
        switch self {
        case .queue, .name, .size, .done, .status, .seeds, .peers, .downSpeed, .upSpeed, .eta, .ratio, .label, .added:
            return true
        default:
            return false
        }
    }

    var defaultAscending: Bool {
        switch self {
        case .queue, .name, .status, .label, .tracker, .savePath, .eta: return true
        default: return false
        }
    }
}
