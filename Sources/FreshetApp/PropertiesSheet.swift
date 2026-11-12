import FreshetCore
import SwiftUI

/// A torrent's Properties sheet: trackers, limits, seeding goal and switches.
struct PropertiesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: TorrentID

    @State private var loaded = false
    @State private var trackersText = ""
    @State private var originalTrackers = ""
    @State private var properties = TorrentProperties()
    @State private var downloadKBps = 0
    @State private var uploadKBps = 0
    @State private var priority = BandwidthPriority.normal
    @State private var overrideGoal = false
    @State private var goal = SeedingGoal()

    var body: some View {
        SheetLayout(title: model.torrents[id]?.displayName ?? "Properties",
                    message: "Trackers, limits and options for this torrent.", width: 580) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    FormGroup(title: "Trackers", footer: "One URL per line. Leave a blank line between tiers.") {
                        TextEditor(text: $trackersText)
                            .modifier(EditorChrome(height: 110))
                            .accessibilityLabel("Trackers")
                            .padding(Spacing.small)
                    }
                    FormGroup(title: "Bandwidth", footer: "0 means unlimited, or the global default for peers and slots.") {
                        FormRow("Maximum download rate") {
                            NumberInput("Maximum download rate", value: $downloadKBps, unit: "KB/s")
                        }
                        FormDivider()
                        FormRow("Maximum upload rate") {
                            NumberInput("Maximum upload rate", value: $uploadKBps, unit: "KB/s")
                        }
                        FormDivider()
                        FormRow("Maximum connected peers") {
                            NumberInput("Maximum connected peers", value: $properties.maxConnections)
                        }
                        FormDivider()
                        FormRow("Upload slots") {
                            NumberInput("Upload slots", value: $properties.maxUploads)
                        }
                        FormDivider()
                        FormRow("Bandwidth allocation", caption: "How this torrent shares the global limits with the others.") {
                            ValuePicker("Bandwidth allocation", selection: $priority,
                                        options: Array(BandwidthPriority.allCases.reversed()), minWidth: 100) { $0.title }
                        }
                    }
                    FormGroup(title: "Seeding goal") {
                        SwitchRow("Use its own seeding goal", caption: "Otherwise it follows the goal in Settings › BitTorrent.",
                                  isOn: $overrideGoal)
                        if overrideGoal {
                            FormDivider()
                            FormRow("Seed while the ratio is under") {
                                NumberInput("Seed while the ratio is under", value: $goal.ratioPercent, unit: "%")
                            }
                            FormDivider()
                            FormRow("Seed for at least") {
                                NumberInput("Seed for at least", value: $goal.minutes, unit: "minutes")
                            }
                        }
                    }
                    FormGroup(title: "Options") {
                        SwitchRow("DHT", caption: "Find peers without a tracker.", isOn: inverted(\.disableDHT))
                        FormDivider()
                        SwitchRow("Peer exchange", caption: "Learn about peers from connected peers.", isOn: inverted(\.disablePEX))
                        FormDivider()
                        SwitchRow("Find peers on the local network", isOn: inverted(\.disableLSD))
                        FormDivider()
                        SwitchRow("Initial seeding (super-seeding)", caption: "Helps a new torrent spread when you're its only seed.",
                                  isOn: $properties.superSeeding)
                        FormDivider()
                        SwitchRow("Download pieces in order", caption: "Useful for previewing; usually slower.", isOn: $properties.sequential)
                    }
                }
            }
            .frame(height: 440)
            .disabled(!loaded)
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.freshet(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .buttonStyle(.freshet(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!loaded)
        }
        .task { await load() }
    }

    private func inverted(_ key: WritableKeyPath<TorrentProperties, Bool>) -> Binding<Bool> {
        Binding(get: { !properties[keyPath: key] }, set: { properties[keyPath: key] = !$0 })
    }

    private func load() async {
        let meta = model.automation.meta(for: id)
        if let current = await model.engine.properties(for: id) { properties = current }
        let trackers = await model.engine.details(for: id)?.trackers ?? []
        trackersText = TrackerEdit.format(trackers.map { TrackerEdit(url: $0.url, tier: $0.tier) })
        originalTrackers = trackersText
        downloadKBps = meta.downloadLimit / 1_024
        uploadKBps = meta.uploadLimit / 1_024
        priority = meta.priority
        overrideGoal = meta.goal != nil
        goal = meta.goal ?? model.settings.seedingGoal
        loaded = true
    }

    private func save() {
        let edits = TrackerEdit.parse(trackersText)
        let trackersChanged = trackersText != originalTrackers
        var values = properties
        values.maxConnections = max(0, values.maxConnections)
        values.maxUploads = max(0, values.maxUploads)
        let down = max(0, downloadKBps) * 1_024
        let up = max(0, uploadKBps) * 1_024
        let newGoal: SeedingGoal? = overrideGoal ? goal : nil
        let newPriority = priority
        let target = id
        Task {
            await model.engine.setProperties(values, for: target)
            if trackersChanged { await model.engine.setTrackers(edits, for: target) }
            model.automation.update([target]) { meta in
                if meta.goal != newGoal { meta.goalHandled = false }
                meta.goal = newGoal
                meta.priority = newPriority
                meta.downloadLimit = down
                meta.uploadLimit = up
            }
            await model.refreshDetails()
        }
        dismiss()
    }
}
