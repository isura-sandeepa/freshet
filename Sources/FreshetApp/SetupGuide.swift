import FreshetCore
import SwiftUI

/// The Setup Guide: where downloads go, how fast the upload line is, and whether peers
/// can reach this Mac. Reachability is judged from the router's port mapping and from peers
/// actually connecting in, since Freshet has no outside service to test the port from.
struct SetupGuideView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var uploadMbps = 0

    struct SpeedOption: Hashable {
        let title: String
        let mbps: Double
    }

    static let speeds: [SpeedOption] = [
        SpeedOption(title: "I don't know — leave unlimited", mbps: 0),
        SpeedOption(title: "1 Mbit/s", mbps: 1), SpeedOption(title: "2 Mbit/s", mbps: 2),
        SpeedOption(title: "5 Mbit/s", mbps: 5), SpeedOption(title: "10 Mbit/s", mbps: 10),
        SpeedOption(title: "20 Mbit/s", mbps: 20), SpeedOption(title: "50 Mbit/s", mbps: 50),
        SpeedOption(title: "100 Mbit/s", mbps: 100), SpeedOption(title: "500 Mbit/s or more", mbps: 500),
    ]

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 0) {
            Text("Setup Guide").font(.title2.bold()).padding([.top, .horizontal], 20)
            Form {
                Section("1. Downloads") {
                    FolderField(title: "Save new torrents to", path: $settings.downloadFolder)
                }
                Section("2. Your upload speed") {
                    Picker("Upload speed of your connection", selection: $uploadMbps) {
                        ForEach(Self.speeds.indices, id: \.self) { index in Text(Self.speeds[index].title).tag(index) }
                    }
                    Text(speedAdvice).font(.callout).foregroundStyle(.secondary)
                }
                Section("3. Can peers reach you?") {
                    HStack {
                        TextField("Listening port", value: $settings.listenPort, format: .number.grouping(.never))
                        Button("Random Port") { settings.listenPort = AppSettings.randomPort() }
                    }
                    Toggle("Ask the router to forward the port (UPnP and NAT-PMP)", isOn: Binding(
                        get: { settings.enableUPnP || settings.enableNATPMP },
                        set: { settings.enableUPnP = $0; settings.enableNATPMP = $0 }))
                    status("Listening on port \(String(model.session.listenPort))", ok: model.session.isListening,
                           pending: "Not listening yet")
                    status("Router forwarded external port \(String(model.session.externalPort))", ok: model.session.portMapped,
                           pending: "The router hasn't confirmed a port mapping (normal if UPnP is off or unsupported)")
                    status("\(model.session.incomingConnections) peers connected in", ok: model.session.incomingConnections > 0,
                           pending: "No peer has connected in yet — this only shows once a torrent is running")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Skip") { finish(apply: false) }
                Button("Done") { finish(apply: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 600)
    }

    private var speedAdvice: String {
        let mbps = Self.speeds[uploadMbps].mbps
        guard mbps > 0 else { return "Uploads stay unlimited. Set a limit later if browsing gets slow while seeding." }
        let plan = Self.plan(forMbps: mbps)
        return "Freshet will cap uploads at \(Format.rate(plan.uploadKBps * 1_024)) (80% of the line) with \(plan.slots) upload slots, so web browsing stays responsive."
    }

    /// Upload limit at 80% of the line, and upload slots that grow with the line's speed.
    static func plan(forMbps mbps: Double) -> (uploadKBps: Int, slots: Int, connections: Int) {
        let kbps = Int(mbps * 1_000_000 / 8 / 1_024 * 0.8)
        let slots: Int
        switch mbps {
        case ..<2: slots = 3
        case ..<6: slots = 4
        case ..<11: slots = 6
        case ..<21: slots = 8
        case ..<51: slots = 12
        case ..<101: slots = 16
        default: slots = 24
        }
        return (kbps, slots, mbps < 5 ? 200 : 500)
    }

    private func status(_ text: String, ok: Bool, pending: String) -> some View {
        Label(ok ? text : pending, systemImage: ok ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(ok ? Palette.success : .secondary)
    }

    private func finish(apply: Bool) {
        let settings = model.settings
        if apply {
            let mbps = Self.speeds[uploadMbps].mbps
            if mbps > 0 {
                let plan = Self.plan(forMbps: mbps)
                settings.uploadLimitKBps = plan.uploadKBps
                settings.uploadSlots = plan.slots
                settings.maxConnections = plan.connections
            }
        }
        settings.setupGuideShown = true
        dismiss()
    }
}
