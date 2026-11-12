import AppKit
import CoreText
import FreshetCore
import SwiftUI

// Freshet's design system. Every color, font, radius, gap and button in every window comes
// from this file and from Style.swift, so a change here changes the app consistently.

// MARK: - Colors

/// Colors named by job. The neutrals are a warm graphite (low-chroma greys leaning slightly
/// yellow), so light mode reads like paper and dark mode isn't blue-black. Each token has a
/// light and a dark value; text tokens keep 4.5:1 or better on cards.
enum Colors {
    // Text
    static let textPrimary = Color(light: 0x2E2D2B, dark: 0xECEAE6)
    static let textSecondary = Color(light: 0x64625E, dark: 0xA6A39D)
    /// Icons, placeholders and small figures — never a sentence someone has to read.
    static let textTertiary = Color(light: 0x85827C, dark: 0x807D78)

    // Surfaces
    static let surfaceBase = Color(light: 0xF6F5F3, dark: 0x171615)
    static let surfaceCard = Color(light: 0xFFFFFF, dark: 0x1E1D1C)
    static let surfaceRaised = Color(light: 0xFFFFFF, dark: 0x2B2A28)
    static let surfaceCardHover = Color(light: 0xF4F2EF, dark: 0x2A2927)

    // Fills
    static let fillSecondary = Color(light: 0xEFEDEA, dark: 0x282725)
    static let fillSecondaryHover = Color(light: 0xE8E6E2, dark: 0x2F2E2C)
    static let fillSecondaryPressed = Color(light: 0xDFDCD8, dark: 0x373533)

    // Borders
    static let borderSubtle = Color(light: 0xE6E3DF, dark: 0x302F2D)
    static let borderStrong = Color(light: 0xD5D2CD, dark: 0x3D3B38)

    // Actions
    static let actionPrimary = Color(light: 0x353431, dark: 0xECEAE6)
    static let actionPrimaryHover = Color(light: 0x42403D, dark: 0xF6F4F1)
    static let actionPrimaryPressed = Color(light: 0x2A2927, dark: 0xD8D5D0)
    static let onActionPrimary = Color(light: 0xFFFFFF, dark: 0x171615)
    static let actionDestructive = Color(light: 0xD1312A, dark: 0xD9372D)
    static let actionDestructiveHover = Color(light: 0xBC2B25, dark: 0xE2453B)
    static let actionDestructivePressed = Color(light: 0xA92620, dark: 0xC4302A)

    // Status: text on its own fill
    static let statusSafeText = Color(light: 0x1F7A35, dark: 0x5FD36B)
    static let statusSafeFill = Color(light: 0xE6F4EA, dark: 0x1B2E22)
    static let statusCheckText = Color(light: 0x8A5300, dark: 0xF2B84B)
    static let statusCheckFill = Color(light: 0xFAEEDA, dark: 0x332910)
    static let statusDangerText = Color(light: 0xB4302A, dark: 0xF47468)
    static let statusDangerFill = Color(light: 0xFBE8E5, dark: 0x321B19)
    static let statusNeutralText = Color(light: 0x5A5853, dark: 0xA9A6A0)
    static let statusNeutralFill = Color(light: 0xEFEDEA, dark: 0x282725)

    /// Data colors for bars, charts and the scheduler. Blue, sky blue, orange, vermillion and
    /// reddish purple come from the Okabe–Ito set, which stays distinct with any kind of color
    /// blindness. The greens are Freshet's own: a fresh green and a lighter one, which differ in
    /// lightness as well as tone. Dark mode lifts each a little so it holds up on dark cards.
    enum Chart {
        static let blue = Color(light: 0x0072B2, dark: 0x3A94D0)
        static let skyBlue = Color(light: 0x56B4E9, dark: 0x6CC3F0)
        static let green = Color(light: 0x2F9E57, dark: 0x43B86B)
        static let lightGreen = Color(light: 0x86CC9A, dark: 0x96D9A8)
        static let orange = Color(light: 0xE69F00, dark: 0xF0B020)
        static let vermillion = Color(light: 0xD55E00, dark: 0xE8772A)
        static let reddishPurple = Color(light: 0xCC79A7, dark: 0xDA93BA)
        static let neutral = Color(light: 0x8C8983, dark: 0xA8A49D)
        /// Free or unused space.
        static let empty = Color(light: 0xDAD7D2, dark: 0x4E4B47)
    }

    /// Deeper shades for icon tiles, which carry a white glyph.
    enum Tile {
        static let blue = Chart.blue
        static let green = Chart.green
        static let orange = Color(light: 0xC27F00, dark: 0xCF8E00)
        static let purple = Color(light: 0xB35A8D, dark: 0xBE6C9C)
        static let vermillion = Chart.vermillion
        static let graphite = Color(light: 0x7A7771, dark: 0x6E6B66)
    }

    /// Torrent states. Blue is still arriving; green means the data is here — seeding in
    /// the fresh green, done and resting in the lighter one.
    enum State {
        static let downloading = Chart.blue
        static let seeding = Chart.green
        static let done = Chart.lightGreen
        static let checking = Chart.orange
        static let queued = Chart.reddishPurple
        static let paused = Chart.neutral
        static let error = Chart.vermillion
        static let empty = Chart.empty
    }
}

/// Older call sites name colors by meaning; they map onto the tokens above.
enum Palette {
    static let error = Colors.statusDangerText
    static let warning = Colors.statusCheckText
    static let success = Colors.statusSafeText
    static let info = Colors.textSecondary

    static func fillOpacity(_ contrast: ColorSchemeContrast, standard: Double) -> Double {
        contrast == .increased ? min(1, standard * 2) : standard
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Metrics

enum Radius {
    /// Badges, progress bars.
    static let xs: CGFloat = 4
    /// Badges, small chips.
    static let sm: CGFloat = 6
    /// Fields, pickers, sidebar selection — anything that holds a value.
    static let md: CGFloat = 8
    /// Cards, list rows, notices, panels.
    static let lg: CGFloat = 14
}

enum Spacing {
    static let xxxSmall: CGFloat = 2
    static let xxSmall: CGFloat = 4
    static let xxSmallPlus: CGFloat = 6
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

enum PageLayout {
    /// Page content's left and right inset.
    static let horizontalInset = Spacing.large
    /// From the top of the window to the page title, level with the window buttons.
    static let topInset: CGFloat = 20
    static let sidebarWidth: CGFloat = 240
    /// Clears the window's close, minimize and zoom buttons above the sidebar's brand mark.
    static let sidebarTopInset: CGFloat = 42
    /// Room for the window buttons when the sidebar is hidden and the header moves left.
    static let windowButtonsWidth: CGFloat = 72
    static let cardHorizontalPadding: CGFloat = 14
    static let controlHeight: CGFloat = 28
}

// MARK: - Type

/// A text style: family, size, weight and its own letter spacing. Small sizes get a little
/// air; display sizes get none.
struct TextStyle: Hashable {
    enum Family: Hashable { case onest, rounded, monospaced }

    let family: Family
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat

    var font: Font {
        switch family {
        case .onest: return AppFont.onest(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    func weight(_ weight: Font.Weight) -> TextStyle {
        TextStyle(family: family, size: size, weight: weight, tracking: tracking)
    }

    /// Figures (sizes, speeds, percentages) are set in SF Rounded.
    var numbers: TextStyle { TextStyle(family: .rounded, size: size, weight: weight, tracking: 0) }

    /// Paths, commands and other text people type exactly.
    func monospaced() -> TextStyle { TextStyle(family: .monospaced, size: size, weight: weight, tracking: 0) }
}

enum Typography {
    static let displaySmall = TextStyle(family: .rounded, size: 30, weight: .bold, tracking: 0)
    static let title = onest(26, .semibold, 0)
    static let pageTitle = onest(20, .semibold, 0)
    static let sectionTitle = onest(15, .semibold, 0.1)
    static let headline = onest(13, .semibold, 0.15)
    static let body = onest(13, .regular, 0.15)
    static let rowTitle = onest(13, .medium, 0.15)
    static let callout = onest(12, .regular, 0.25)
    static let metadata = onest(11, .regular, 0.3)
    static let metadataEmphasis = onest(11, .medium, 0.3)
    static let micro = onest(10, .semibold, 0.4)

    private static func onest(_ size: CGFloat, _ weight: Font.Weight, _ tracking: CGFloat) -> TextStyle {
        TextStyle(family: .onest, size: size, weight: weight, tracking: tracking)
    }
}

extension View {
    /// Sets a text style's font and letter spacing together.
    func font(_ style: TextStyle) -> some View {
        font(style.font).tracking(style.tracking)
    }
}

extension Text {
    func font(_ style: TextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

/// The bundled Onest typeface (SIL Open Font License), registered for this process on first
/// use. Falls back to the system font if the file is missing.
enum AppFont {
    private static let registered: Bool = {
        guard let url = AppPaths.onestFont else { return false }
        var error: Unmanaged<CFError>?
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            || NSFont(name: "Onest", size: 13) != nil
    }()

    static func onest(size: CGFloat, weight: Font.Weight) -> Font {
        registered ? Font.custom("Onest", size: size).weight(weight) : .system(size: size, weight: weight)
    }

    /// The same face for AppKit views such as the torrent table.
    static func nsOnest(size: CGFloat) -> NSFont {
        (registered ? NSFont(name: "Onest", size: size) : nil) ?? .systemFont(ofSize: size)
    }

    static func register() { _ = registered }
}

// MARK: - Buttons

/// The one button style. Every action is a capsule; controls that hold a value (fields,
/// pickers) use a rounded rectangle instead, so shape tells an action from a setting.
struct FreshetButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive, quiet, soft }
    enum Size { case small, regular, large }
    enum Width { case fit, fill, square }

    var role: Role = .secondary
    var size: Size = .regular
    var width: Width = .fit

    func makeBody(configuration: Configuration) -> some View {
        FreshetButtonBody(configuration: configuration, role: role, size: size, width: width)
    }
}

extension ButtonStyle where Self == FreshetButtonStyle {
    static func freshet(_ role: FreshetButtonStyle.Role = .secondary, size: FreshetButtonStyle.Size = .regular,
                        width: FreshetButtonStyle.Width = .fit) -> FreshetButtonStyle {
        FreshetButtonStyle(role: role, size: size, width: width)
    }
}

private struct FreshetButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: FreshetButtonStyle.Role
    let size: FreshetButtonStyle.Size
    let width: FreshetButtonStyle.Width
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    var body: some View {
        label
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, width == .square ? 0 : horizontalPadding)
            .frame(height: height)
            .background(background, in: Capsule(style: .continuous))
            .overlay {
                if let border {
                    Capsule(style: .continuous).strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder private var label: some View {
        switch width {
        case .fit: configuration.label.labelStyle(.titleAndIcon)
        case .fill: configuration.label.labelStyle(.titleAndIcon).frame(maxWidth: .infinity)
        case .square: configuration.label.labelStyle(.iconOnly).frame(width: height)
        }
    }

    private var height: CGFloat {
        switch size {
        case .small: return 24
        case .regular: return 30
        case .large: return 38
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: return 10
        case .regular: return 14
        case .large: return 20
        }
    }

    private var font: TextStyle {
        switch size {
        case .small: return Typography.callout.weight(.semibold)
        case .regular: return Typography.headline
        case .large: return Typography.sectionTitle
        }
    }

    private var active: Bool { isEnabled && hovering }

    private var foreground: Color {
        switch role {
        case .primary: return Colors.onActionPrimary
        case .secondary: return Colors.textPrimary
        case .destructive: return .white
        case .quiet, .soft: return active ? Colors.textPrimary : Colors.textSecondary
        }
    }

    private var background: Color {
        let pressed = configuration.isPressed
        switch role {
        case .primary:
            return pressed ? Colors.actionPrimaryPressed : (active ? Colors.actionPrimaryHover : Colors.actionPrimary)
        case .secondary, .soft:
            return pressed ? Colors.fillSecondaryPressed : (active ? Colors.fillSecondaryHover : Colors.fillSecondary)
        case .destructive:
            return pressed ? Colors.actionDestructivePressed : (active ? Colors.actionDestructiveHover : Colors.actionDestructive)
        case .quiet:
            return pressed ? Colors.fillSecondaryPressed : (active ? Colors.fillSecondaryHover : .clear)
        }
    }

    private var border: Color? {
        switch role {
        case .secondary: return contrast == .increased ? Colors.textSecondary : Colors.borderStrong
        case .quiet, .soft: return contrast == .increased ? Colors.borderStrong : nil
        default: return nil
        }
    }
}

// MARK: - Badges

/// A small status tag: tinted text on its own fill, with a hairline in the same tint.
struct Badge: View {
    enum Tone { case neutral, accent, safe, warning, danger }

    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: Spacing.xxxSmall) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small).accessibilityHidden(true)
            }
            Text(text).lineLimit(1)
        }
        .font(Typography.metadataEmphasis)
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.xxSmallPlus)
        .padding(.vertical, Spacing.xxxSmall)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(border, lineWidth: 0.5)
        }
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Colors.statusNeutralText
        case .accent: return Colors.textSecondary
        case .safe: return Colors.statusSafeText
        case .warning: return Colors.statusCheckText
        case .danger: return Colors.statusDangerText
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: return Colors.statusNeutralFill
        case .accent: return Colors.fillSecondary
        case .safe: return Colors.statusSafeFill
        case .warning: return Colors.statusCheckFill
        case .danger: return Colors.statusDangerFill
        }
    }

    private var border: Color {
        tone == .accent ? Colors.borderSubtle : foreground.opacity(0.22)
    }
}

// MARK: - Cards

extension View {
    /// A card: surface fill, 14 pt continuous corners and a hairline instead of a shadow.
    /// Content is clipped to the shape so hover fills stay inside the corners.
    func card(fill: Color = Colors.surfaceCard) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        return background(shape.fill(fill))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Colors.borderSubtle, lineWidth: 0.5))
    }

    /// Settings groups and summary boxes: the secondary fill instead of the card surface.
    func insetCard() -> some View {
        card(fill: Colors.fillSecondary)
    }
}

struct CardDivider: View {
    var inset: CGFloat = Spacing.medium

    var body: some View {
        Rectangle().fill(Colors.borderSubtle).frame(height: 0.5).padding(.horizontal, inset)
    }
}

// MARK: - Icon tiles

/// A tinted tile with a white symbol: lighter at the top, a touch darker at the bottom, with a
/// thin rim. Corners are 26% of the width.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
            .frame(width: size, height: size)
            .background {
                shape.fill(color)
                    .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .top, endPoint: .bottom)))
                    .overlay(shape.fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom)))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                                   lineWidth: 0.5)
            }
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

// MARK: - Torrent states

/// How each torrent state looks everywhere: bar color, tile color, symbol and badge tone.
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
        case .downloading: return Colors.State.downloading
        case .seeding: return Colors.State.seeding
        case .done: return Colors.State.done
        case .checking: return Colors.State.checking
        case .queued: return Colors.State.queued
        case .paused: return Colors.State.paused
        case .error: return Colors.State.error
        }
    }

    /// Seeding and done share the green tile; the glyph tells them apart.
    var tileColor: Color {
        switch self {
        case .downloading: return Colors.Tile.blue
        case .seeding, .done: return Colors.Tile.green
        case .checking: return Colors.Tile.orange
        case .queued: return Colors.Tile.purple
        case .paused: return Colors.Tile.graphite
        case .error: return Colors.Tile.vermillion
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

    var badgeTone: Badge.Tone {
        switch self {
        case .error: return .danger
        case .checking: return .warning
        case .seeding: return .safe
        default: return .neutral
        }
    }
}

// MARK: - Search field

/// A capsule search field: a fill, a hairline that turns to the action color while focused,
/// Escape clears and then leaves, and a click anywhere in the capsule focuses it.
struct SearchCapsule: View {
    @Binding var text: String
    let prompt: String
    var width: CGFloat = 200
    @Binding var focusRequest: Bool
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xxSmallPlus) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(Colors.textSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Colors.textTertiary))
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Colors.textPrimary)
                .focused($focused)
                .focusEffectDisabled()
                .onExitCommand {
                    if text.isEmpty { focused = false } else { text = "" }
                }
            if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Colors.textTertiary)
                .help("Clear")
            }
        }
        .padding(.horizontal, Spacing.small)
        .frame(width: width, height: 30)
        .background(Capsule(style: .continuous).fill(Colors.fillSecondary))
        .overlay {
            Capsule(style: .continuous).strokeBorder(focused ? Colors.actionPrimary : Colors.borderSubtle, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { focused = true }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: focused)
        .onChange(of: focusRequest) {
            if focusRequest {
                focused = true
                focusRequest = false
            }
        }
    }
}

// MARK: - Tab chips

/// Capsule tabs: the selected one is raised; the rest sit on the secondary fill.
struct ChipTabs<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: Spacing.xxSmallPlus) {
            ForEach(tabs) { tab in
                let selected = tab == selection
                Button { selection = tab } label: {
                    Text(title(tab))
                        .font(selected ? Typography.headline : Typography.body)
                        .foregroundStyle(selected ? Colors.textPrimary : Colors.textSecondary)
                        .padding(.horizontal, Spacing.small)
                        .frame(height: 26)
                        .background(Capsule(style: .continuous).fill(selected ? Colors.surfaceRaised : Colors.fillSecondary))
                        .overlay(Capsule(style: .continuous).strokeBorder(Colors.borderSubtle, lineWidth: 1))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - List style

enum TorrentListStyle: String, CaseIterable, Identifiable {
    case cards, table
    static let storageKey = "torrentListStyle"
    var id: String { rawValue }
}
