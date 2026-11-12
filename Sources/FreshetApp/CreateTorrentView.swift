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
            WindowHeader(title: "New Torrent", subtitle: "Make a .torrent from a file or folder to share it",
                         clearsWindowButtons: true) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    FormGroup(title: "Source") {
                        HStack(spacing: Spacing.medium) {
                            VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                                Text("Files")
                                Text(source.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Nothing chosen yet")
                                    .font(Typography.callout)
                                    .foregroundStyle(source == nil ? Colors.textTertiary : Colors.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            Button("Choose File…") { choose(directories: false) }
                                .buttonStyle(.freshet(.secondary, size: .small))
                            Button("Choose Folder…") { choose(directories: true) }
                                .buttonStyle(.freshet(.secondary, size: .small))
                        }
                        .formRowPadding()
                        FormDivider()
                        FormRow("Skip files", caption: "Separate patterns with semicolons.") {
                            TextInput("Skip files", text: $skipPatterns, prompt: "e.g. *.nfo;Thumbs.db", width: 220, monospaced: true)
                        }
                    }
                    FormGroup(title: "Trackers and web seeds") {
                        FormStackRow("Trackers", note: "One per line; a blank line starts the next tier.") {
                            TextEditor(text: $trackers)
                                .modifier(EditorChrome(height: 84))
                                .accessibilityLabel("Trackers")
                        }
                        FormDivider()
                        FormStackRow("Web seeds", note: "Optional. HTTP addresses that also serve the files.") {
                            TextEditor(text: $webSeeds)
                                .modifier(EditorChrome(height: 52))
                                .accessibilityLabel("Web seeds")
                        }
                        FormDivider()
                        FormRow("Comment") {
                            TextInput("Comment", text: $comment, prompt: "Optional", width: 260)
                        }
                    }
                    FormGroup(title: "Options") {
                        FormRow("Piece size", caption: "Automatic picks a size that suits the files.") {
                            ValuePicker("Piece size", selection: $pieceSize, options: Self.pieceSizes, minWidth: 100) { size in
                                size == 0 ? "Automatic" : Format.bytes(Int64(size))
                            }
                        }
                        FormDivider()
                        FormRow("Format") {
                            ValuePicker("Format", selection: $format, options: TorrentFormat.allCases, minWidth: 100) { $0.title }
                        }
                        FormDivider()
                        SwitchRow("Private torrent", caption: "Peers come only from its trackers: no DHT or peer exchange.",
                                  isOn: $isPrivate)
                        FormDivider()
                        SwitchRow("Start seeding", caption: "Add it to Freshet and share it right away.", isOn: $startSeeding)
                    }
                }
                .padding(.horizontal, PageLayout.horizontalInset)
                .padding(.top, Spacing.xxSmall)
                .padding(.bottom, Spacing.large)
            }
            .disabled(progress != nil)
            CardDivider(inset: 0)
            HStack(spacing: Spacing.small) {
                if progress != nil {
                    ProgressTrack(value: fraction, color: Colors.State.downloading, height: 6)
                        .frame(width: 200)
                    Text("Hashing \(Format.percent(fraction))")
                        .font(Typography.callout.numbers)
                        .monospacedDigit()
                        .foregroundStyle(Colors.textSecondary)
                } else if let message {
                    Text(message)
                        .font(Typography.callout)
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                if let progress {
                    Button("Cancel") { progress.cancel() }
                        .buttonStyle(.freshet(.secondary))
                } else {
                    Button("Create and Save As…") { create() }
                        .buttonStyle(.freshet(.primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(source == nil)
                }
            }
            .padding(.horizontal, PageLayout.horizontalInset)
            .padding(.vertical, Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 560, minHeight: 520)
        .themedWindow()
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
