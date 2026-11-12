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
        SheetLayout(title: draft.preview.name, message: summary, width: 600) {
            FormGroup {
                saveRow
                FormDivider()
                FormRow("Label") {
                    HStack(spacing: Spacing.xSmall) {
                        TextInput("Label", text: $draft.label, prompt: "None", width: 180)
                        if !model.labels.names.isEmpty {
                            Menu {
                                ForEach(model.labels.names, id: \.self) { name in
                                    Button(name) { draft.label = name }
                                }
                            } label: { menuLabel("Existing") }
                            .menuStyle(.button)
                            .menuIndicator(.hidden)
                            .buttonStyle(.freshet(.secondary, size: .small))
                            .fixedSize()
                            .accessibilityLabel("Existing labels")
                        }
                    }
                }
                FormDivider()
                SwitchRow("Start torrent", isOn: $draft.start)
                FormDivider()
                SwitchRow("Skip hash check", caption: "Only for files that are already complete on disk.", isOn: $draft.skipHashCheck)
            }
            if draft.preview.isMagnet {
                NoticeBanner(kind: .info, title: "Files appear once peers send the torrent's details",
                             detail: "You can choose them later in the Files tab.")
            } else if !draft.preview.files.isEmpty {
                fileList
            }
        } actions: {
            Button("Cancel") { model.cancelAdd(draft) }
                .buttonStyle(.freshet(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Add") { model.confirmAdd(draft) }
                .buttonStyle(.freshet(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.preview.isMagnet && !draft.preview.files.isEmpty && draft.selectedFiles.isEmpty)
        }
    }

    private var saveRow: some View {
        HStack(spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                Text("Save to")
                Text(abbreviated(draft.savePath))
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(draft.savePath)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Menu {
                Button("Other Folder…") { chooseFolder() }
                if !model.settings.recentSaveFolders.isEmpty {
                    Divider()
                    ForEach(model.settings.recentSaveFolders, id: \.self) { folder in
                        Button(abbreviated(folder)) { draft.savePath = folder }
                    }
                }
            } label: { menuLabel("Choose") }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.freshet(.secondary, size: .small))
            .fixedSize()
            .accessibilityLabel("Choose where to save")
        }
        .formRowPadding()
    }

    private func menuLabel(_ title: String) -> some View {
        HStack(spacing: Spacing.xxSmall) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
    }

    private var fileList: some View {
        let allSelected = draft.selectedFiles.count == draft.preview.files.count
        return VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text("Files")
                    .font(Typography.metadataEmphasis)
                    .foregroundStyle(Colors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(Format.bytes(selectedSize)) of \(Format.bytes(draft.preview.totalSize)) selected")
                    .font(Typography.metadata.numbers)
                    .foregroundStyle(Colors.textSecondary)
            }
            .padding(.horizontal, Spacing.xxSmall)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(draft.preview.files) { file in
                        Toggle(isOn: binding(for: file.index)) {
                            HStack(spacing: Spacing.xSmall) {
                                Text(file.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: Spacing.xSmall)
                                Text(Format.bytes(file.size))
                                    .font(Typography.callout.numbers)
                                    .monospacedDigit()
                                    .foregroundStyle(Colors.textSecondary)
                            }
                        }
                        .toggleStyle(CheckboxStyle())
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.xxSmallPlus)
                    }
                }
                .padding(.vertical, Spacing.xxSmall)
            }
            .frame(height: min(240, max(120, CGFloat(draft.preview.files.count) * 28 + 8)))
            .insetCard()
            HStack(spacing: Spacing.xxSmall) {
                Button(allSelected ? "Select None" : "Select All") {
                    draft.selectedFiles = allSelected ? [] : Set(draft.preview.files.map(\.index))
                }
                .buttonStyle(.freshet(.quiet, size: .small))
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
        SheetLayout(title: "Add from URL or Magnet Link",
                    message: "Paste magnet links, info-hashes, or links to .torrent files, one per line.", width: 560) {
            TextEditor(text: $text)
                .modifier(EditorChrome(height: 120))
                .accessibilityLabel("Links")
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.freshet(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Add") {
                model.addFromText(text)
                dismiss()
            }
            .buttonStyle(.freshet(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear {
            // Start with a link already on the clipboard.
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               clip.lowercased().hasPrefix("magnet:") || clip.lowercased().hasPrefix("http") {
                text = clip
            }
        }
    }
}
