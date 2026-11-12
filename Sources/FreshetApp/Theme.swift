import AppKit
import FreshetCore
import SwiftUI

// MARK: Buttons

/// Capsule buttons for the main window's header: a filled one for the main action and a quiet
/// one for the rest. Built on system colors, so they work in Light and Dark Mode.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration, prominent: prominent, iconOnly: iconOnly)
    }
}

private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    var body: some View {
        label
            .font(.body.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(prominent ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, iconOnly ? 0 : 14)
            .frame(width: iconOnly ? 30 : nil, height: 30)
            .background {
                Capsule().fill(prominent ? Color.primary.opacity(hovering ? 0.85 : 1)
                                         : Color.primary.opacity(hovering ? 0.12 : 0.07))
            }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : (contrast == .increased ? 0.45 : 0.14)))
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .onHover { hovering = $0 && isEnabled }
    }

    @ViewBuilder private var label: some View {
        if iconOnly {
            configuration.label.labelStyle(.iconOnly)
        } else {
            configuration.label.labelStyle(.titleAndIcon)
        }
    }
}

// MARK: Panels and tags

extension View {
    /// The rounded panel the torrent list and other content sit in.
    func panel(cornerRadius: CGFloat = 12) -> some View {
        modifier(PanelModifier(cornerRadius: cornerRadius))
    }
}

private struct PanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.4 : 0.1))
            }
    }
}

/// A small outlined tag next to a name, like "Paused" or a label.
struct TagPill: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().strokeBorder(color.opacity(0.45)))
        .fixedSize()
    }
}

// MARK: Torrent states

/// How each torrent state looks: one color and one symbol, used by the overview bar, the card
/// rows and the icon tiles, so a state always looks the same.
enum StateStyle: CaseIterable {
    case downloading, seeding, done, checking, queued, paused, error

    init(_ torrent: TorrentSnapshot) {
        switch torrent.activity {
        case .downloading, .downloadingMetadata: self = .downloading
        case .seeding: self = .seeding
        case .finished: self = .done
        case .checking: self = .checking
        case .queued, .queuedSeed: self = .queued
        case .paused: self = torrent.isComplete ? .done : .paused
        case .error: self = .error
        }
    }

    var title: String {
        switch self {
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .done: return "Done"
        case .checking: return "Checking"
        case .queued: return "Queued"
        case .paused: return "Paused"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .downloading: return Color(nsColor: .systemBlue)
        case .seeding: return Palette.success
        case .done: return Color(nsColor: .systemTeal)
        case .checking: return Palette.warning
        case .queued: return Color(nsColor: .systemIndigo)
        case .paused: return Color(nsColor: .systemGray)
        case .error: return Palette.error
        }
    }

    var symbol: String {
        switch self {
        case .downloading: return "arrow.down"
        case .seeding: return "arrow.up"
        case .done: return "checkmark"
        case .checking: return "arrow.triangle.2.circlepath"
        case .queued: return "clock"
        case .paused: return "pause.fill"
        case .error: return "exclamationmark"
        }
    }
}

/// A rounded, tinted square with a white symbol, like the category icons in the sidebar of
/// many Mac utilities.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: Filter field

/// The torrent filter as a rounded field in the header (the toolbar is gone). ⌘F focuses it.
struct FilterField: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Filter torrents", text: $model.searchText, prompt: Text("Filter"))
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { model.searchText = ""; focused = false }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Label("Clear Filter", systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 190, height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .overlay(Capsule().strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: focused ? 2 : 1))
        .onChange(of: model.focusFilter) {
            if model.focusFilter {
                focused = true
                model.focusFilter = false
            }
        }
    }
}

// MARK: List style

enum TorrentListStyle: String, CaseIterable, Identifiable {
    case cards, table
    static let storageKey = "torrentListStyle"
    var id: String { rawValue }
    var title: String { self == .cards ? "as Cards" : "as Table" }
}
