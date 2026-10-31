import AppKit
import FreshetCore
import FreshetEngine
import SwiftUI
import UniformTypeIdentifiers

/// The New Torrent window: makes a .torrent from a file or folder.
struct CreateTorrentView: View {
    @Environment(AppModel.self) private var model
    @State private var source: URL?
    @State private var trackers = ""
    @State private var webSeeds = ""
    @State private var comment = ""
    @State private var skipPatterns = ""
    @State private var pieceSize = 0
    @State private var format = TorrentFormat.hybrid
    @State private var isPrivate = false
    @State private var startSeeding = true
    @State private var progress: TorrentCreator.Progress?
    @State private var fraction = 0.0
    @State private var message: String?

    private static let pieceSizes = [0] + (14...24).map { 1 << $0 }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Source") {
                    LabeledContent("Files") {
                        HStack {
                            Text(source.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Nothing chosen")
                                .foregroundStyle(source == nil ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Add File…") { choose(directories: false) }
                            Button("Add Folder…") { choose(directories: true) }
                        }
                    }
                    TextField("Skip files", text: $skipPatterns, prompt: Text("e.g. *.nfo;Thumbs.db"))
                }
                Section("Properties") {
                    VStack(alignment: .leading) {
                        Text("Trackers")
                        TextEditor(text: $trackers).font(.system(.body, design: .monospaced)).frame(height: 70)
                        Text("One per line; a blank line starts the next tier.").font(.callout).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("Web seeds")
                        TextEditor(text: $webSeeds).font(.system(.body, design: .monospaced)).frame(height: 40)
                    }
                    TextField("Comment", text: $comment)
                    Picker("Piece size", selection: $pieceSize) {
                        ForEach(Self.pieceSizes, id: \.self) { size in
                            Text(size == 0 ? "Automatic" : Format.bytes(Int64(size))).tag(size)
                        }
                    }
                    Picker("Format", selection: $format) {
                        ForEach(TorrentFormat.allCases, id: \.self) { format in Text(format.title).tag(format) }
                    }
                    Toggle("Private torrent (no DHT or peer exchange)", isOn: $isPrivate)
                    Toggle("Start seeding", isOn: $startSeeding)
                }
            }
            .formStyle(.grouped)
            .disabled(progress != nil)
            HStack {
                if progress != nil {
                    ProgressView(value: fraction).frame(width: 220)
                    Text(Format.percent(fraction)).monospacedDigit()
                } else if let message {
                    Text(message).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if let progress {
                    Button("Cancel") { progress.cancel() }
                } else {
                    Button("Create and Save As…") { create() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(source == nil)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520, idealHeight: 640)
    }

    private func choose(directories: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { source = url }
    }

    private func create() {
        guard let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.nameFieldStringValue = source.lastPathComponent + ".torrent"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        let request = CreateTorrentRequest(source: source, trackers: trackers, webSeeds: webSeeds, comment: comment,
                                           skipPatterns: skipPatterns, pieceSize: pieceSize, format: format, isPrivate: isPrivate)
        let tracker = TorrentCreator.Progress()
        progress = tracker
        fraction = 0
        message = nil
        let seed = startSeeding
        Task {
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    fraction = tracker.fraction
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            defer {
                poll.cancel()
                progress = nil
            }
            do {
                _ = try await TorrentCreator.create(request, output: output, progress: tracker)
                message = "Saved \(output.lastPathComponent)."
                if seed {
                    let folder = source.deletingLastPathComponent().path
                    if await model.addAutomatically(.file(output), savePath: folder, start: true, skipHashCheck: true) != nil {
                        message = "Saved \(output.lastPathComponent) and started seeding."
                    }
                }
            } catch is CancellationError {
                message = "Cancelled."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
