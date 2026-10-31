import AppKit
import FreshetCore
import SwiftUI

/// The Add Torrent sheet: save location, label, start, skip hash check, files.
struct AddTorrentSheet: View {
    @Environment(AppModel.self) private var model
    @State private var draft: PendingAdd

    init(pending: PendingAdd) {
        _draft = State(initialValue: pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.preview.name)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                LabeledContent("Save to") {
                    HStack {
                        Text(abbreviated(draft.savePath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(draft.savePath)
                        Spacer()
                        Menu("Choose") {
                            Button("Other Folder…") { chooseFolder() }
                            if !model.settings.recentSaveFolders.isEmpty {
                                Divider()
                                ForEach(model.settings.recentSaveFolders, id: \.self) { folder in
                                    Button(abbreviated(folder)) { draft.savePath = folder }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
                LabeledContent("Label") {
                    HStack {
                        TextField("None", text: $draft.label)
                            .textFieldStyle(.roundedBorder)
                        if !model.labels.names.isEmpty {
                            Menu("Existing") {
                                ForEach(model.labels.names, id: \.self) { name in
                                    Button(name) { draft.label = name }
                                }
                            }
                            .fixedSize()
                        }
                    }
                }
                Toggle("Start torrent", isOn: $draft.start)
                Toggle("Skip hash check", isOn: $draft.skipHashCheck)
                    .help("Only for files that are already complete on disk.")
            }
            .formStyle(.columns)

            if draft.preview.isMagnet {
                Label("Files appear once peers send the torrent's metadata. You can choose them later in the Files tab.",
                      systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !draft.preview.files.isEmpty {
                fileList
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelAdd(draft) }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { model.confirmAdd(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.preview.isMagnet && !draft.preview.files.isEmpty && draft.selectedFiles.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(draft.preview.files) { file in
                Toggle(isOn: binding(for: file.index)) {
                    HStack {
                        Text(file.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(file.size))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 120, idealHeight: 200, maxHeight: 260)
            HStack {
                Button("Select All") { draft.selectedFiles = Set(draft.preview.files.map(\.index)) }
                Button("Select None") { draft.selectedFiles = [] }
                Spacer()
                Text("\(Format.bytes(selectedSize)) of \(Format.bytes(draft.preview.totalSize)) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if draft.preview.isMagnet {
            parts.append("Magnet link")
        } else {
            parts.append(Format.bytes(draft.preview.totalSize))
            parts.append("\(draft.preview.files.count) file\(draft.preview.files.count == 1 ? "" : "s")")
        }
        if draft.preview.isPrivate { parts.append("private torrent") }
        if !draft.preview.comment.isEmpty { parts.append(draft.preview.comment) }
        return parts.joined(separator: " · ")
    }

    private var selectedSize: Int64 {
        draft.preview.files.filter { draft.selectedFiles.contains($0.index) }.reduce(0) { $0 + $1.size }
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(get: { draft.selectedFiles.contains(index) },
                set: { selected in
                    if selected { draft.selectedFiles.insert(index) } else { draft.selectedFiles.remove(index) }
                })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: draft.savePath, isDirectory: true)
        panel.prompt = "Save Here"
        if panel.runModal() == .OK, let url = panel.url { draft.savePath = url.path }
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

/// The Add from URL sheet; also takes magnet links and info-hashes.
struct AddURLSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add from URL or Magnet Link")
                .font(.headline)
            Text("Paste magnet links, info-hashes, or links to .torrent files, one per line.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    model.addFromText(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            // Start with a link already on the clipboard.
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               clip.lowercased().hasPrefix("magnet:") || clip.lowercased().hasPrefix("http") {
                text = clip
            }
        }
    }
}
