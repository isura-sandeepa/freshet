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
        VStack(spacing: 0) {
            Form {
                Section("Trackers") {
                    TextEditor(text: $trackersText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 110)
                    Text("One URL per line. Leave a blank line between tiers.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Bandwidth (0 = unlimited or the global default)") {
                    NumberField(title: "Maximum download rate", value: $downloadKBps, unit: "KB/s")
                    NumberField(title: "Maximum upload rate", value: $uploadKBps, unit: "KB/s")
                    NumberField(title: "Maximum connected peers", value: $properties.maxConnections)
                    NumberField(title: "Upload slots", value: $properties.maxUploads)
                    Picker("Bandwidth allocation", selection: $priority) {
                        ForEach(BandwidthPriority.allCases.reversed(), id: \.self) { p in Text(p.title).tag(p) }
                    }
                }
                Section("Seeding goal") {
                    Toggle("Use its own seeding goal", isOn: $overrideGoal)
                    if overrideGoal {
                        NumberField(title: "Seed while the ratio is under", value: $goal.ratioPercent, unit: "%")
                        NumberField(title: "Seed for at least", value: $goal.minutes, unit: "minutes")
                    }
                }
                Section("Options") {
                    Toggle("DHT", isOn: inverted(\.disableDHT))
                    Toggle("Peer exchange", isOn: inverted(\.disablePEX))
                    Toggle("Find peers on the local network", isOn: inverted(\.disableLSD))
                    Toggle("Initial seeding (super-seeding)", isOn: $properties.superSeeding)
                    Toggle("Download pieces in order", isOn: $properties.sequential)
                }
            }
            .formStyle(.grouped)
            .disabled(!loaded)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!loaded)
            }
            .padding(14)
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 480, idealHeight: 640)
        .navigationTitle(model.torrents[id]?.displayName ?? "Properties")
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
