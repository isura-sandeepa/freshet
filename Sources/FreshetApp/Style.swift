import AppKit
import SwiftUI

// Components shared by every window: the window shell (sidebar, header, sheet layout) and the
// controls that hold values (fields, number inputs, pickers, switches, checkboxes). Actions
// are capsules (FreshetButtonStyle); anything that holds a value is an 8 pt rounded rectangle.

let settingsWindowID = "settings"

// MARK: - Window shell

extension View {
    /// The look every Freshet window starts from: Onest text in graphite on the warm base.
    func themedWindow() -> some View {
        font(Typography.body)
            .foregroundStyle(Colors.textPrimary)
            .tint(Colors.textPrimary)
            .background(Colors.surfaceBase)
    }

    /// Padding for a row inside a form group.
    func formRowPadding() -> some View {
        padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: 44)
    }
}

/// Lets View › Hide Sidebar act on whichever window is in front.
struct SidebarHiddenKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var sidebarHidden: Binding<Bool>? {
        get { self[SidebarHiddenKey.self] }
        set { self[SidebarHiddenKey.self] = newValue }
    }
}

/// A window's sidebar: a title under the window buttons, scrolling rows and a footer. With a
/// `hidden` binding it gets a button beside the window buttons that hides it.
struct SidebarColumn<Header: View, Rows: View, Footer: View>: View {
    private let hidden: Binding<Bool>?
    private let header: Header
    private let rows: Rows
    private let footer: Footer

    init(hidden: Binding<Bool>? = nil, @ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows,
         @ViewBuilder footer: () -> Footer) {
        self.hidden = hidden
        self.header = header()
        self.rows = rows()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, PageLayout.sidebarTopInset)
                .padding(.bottom, Spacing.medium)
                .padding(.horizontal, Spacing.small + Spacing.xSmall)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxxSmall) { rows }
                    .padding(.horizontal, Spacing.small)
                    .padding(.bottom, Spacing.small)
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(width: PageLayout.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Colors.surfaceCard)
        .overlay(alignment: .topTrailing) {
            if let hidden {
                SidebarToggleButton(hidden: hidden)
                    .padding(.top, Spacing.xxSmall)
                    .padding(.trailing, Spacing.small)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

extension SidebarColumn where Footer == EmptyView {
    init(hidden: Binding<Bool>? = nil, @ViewBuilder header: () -> Header, @ViewBuilder rows: () -> Rows) {
        self.init(hidden: hidden, header: header, rows: rows) { EmptyView() }
    }
}

/// The hairline between a sidebar and its page, running up under the window buttons.
struct SidebarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Colors.borderSubtle)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
    }
}

struct SidebarToggleButton: View {
    @Binding var hidden: Bool

    var body: some View {
        Button { hidden.toggle() } label: {
            Label(hidden ? "Show Sidebar" : "Hide Sidebar", systemImage: "sidebar.left")
        }
        .buttonStyle(.freshet(.quiet, size: .small, width: .square))
        .help(hidden ? "Show the sidebar (⌃⌘S)" : "Hide the sidebar (⌃⌘S)")
    }
}

/// A sidebar's section label.
struct SidebarSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Typography.metadata.weight(.semibold))
            .foregroundStyle(Colors.textTertiary)
            .padding(.horizontal, Spacing.xSmall)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.xxxSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A two-line sidebar row: an icon, a title and a quiet status line, for lists of things
/// (feeds, filters) rather than places.
struct SidebarItemRow: View {
    let title: String
    var subtitle: String?
    var subtitleColor: Color = Colors.textTertiary
    let systemImage: String
    var symbolColor: Color?
    var isDimmed = false
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.xSmall) {
                Image(systemName: systemImage)
                    .font(Typography.rowTitle)
                    .foregroundStyle(symbolColor ?? (isSelected ? Colors.textPrimary : Colors.textSecondary))
                    .frame(width: 16)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.body.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Colors.textPrimary : Colors.textSecondary)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.metadata)
                            .foregroundStyle(subtitleColor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, Spacing.xxSmallPlus)
            .background(isSelected ? Colors.fillSecondary : (hovering ? Colors.surfaceCardHover : .clear),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(isDimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A page header for windows other than the main one: the title and a status line on the
/// left, actions on the right. When the window's sidebar is hidden it moves clear of the
/// window buttons and offers the button that brings the sidebar back.
struct WindowHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    /// The status line is mostly figures, so it's set in SF Rounded.
    var figures = false
    var sidebarHidden: Binding<Bool>?
    /// For windows without a sidebar: room for the window buttons.
    var clearsWindowButtons = false
    @ViewBuilder var actions: Actions

    var body: some View {
        let hidden = sidebarHidden?.wrappedValue ?? false
        HStack(alignment: .top, spacing: Spacing.medium) {
            if hidden, let sidebarHidden {
                SidebarToggleButton(hidden: sidebarHidden)
                    .padding(.top, Spacing.xxxSmall)
            }
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .font(Typography.pageTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(figures ? Typography.metadata.numbers : Typography.metadata)
                        .monospacedDigit()
                        .foregroundStyle(Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.medium)
            HStack(spacing: Spacing.xSmall) { actions }
                .fixedSize()
        }
        .padding(.leading, PageLayout.horizontalInset + (hidden || clearsWindowButtons ? PageLayout.windowButtonsWidth : 0))
        .padding(.trailing, PageLayout.horizontalInset)
        .padding(.top, PageLayout.topInset)
        .padding(.bottom, Spacing.small)
    }
}

/// A sheet: title and description, the content, then the buttons — Cancel first, the one
/// main action last.
struct SheetLayout<Content: View, Actions: View>: View {
    let title: String
    var message: String?
    var width: CGFloat = 480
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(title)
                    .font(Typography.pageTitle)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(Typography.callout)
                        .foregroundStyle(Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
            HStack(spacing: Spacing.small) {
                Spacer()
                actions
            }
        }
        .padding(Spacing.large)
        .frame(width: width)
        .themedWindow()
    }
}

// MARK: - Form groups and rows

/// A titled group of rows on an inset card, with an optional note under it.
struct FormGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            if let title {
                Text(title)
                    .font(Typography.metadataEmphasis)
                    .foregroundStyle(Colors.textSecondary)
                    .padding(.horizontal, Spacing.xxSmall)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetCard()
            if let footer {
                Text(footer)
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.xxSmall)
            }
        }
    }
}

struct FormDivider: View {
    var body: some View { CardDivider() }
}

/// A row's title with an optional caption under it.
struct FormLabel: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Colors.textPrimary)
            if let caption {
                Text(caption)
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Title and caption on the left, the control on the right.
struct FormRow<Control: View>: View {
    let title: String
    var caption: String?
    let control: Control
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            FormLabel(title: title, caption: caption)
                .opacity(isEnabled ? 1 : 0.45)
            control
        }
        .formRowPadding()
    }
}

/// Title above a control that needs the full width, such as a command or a list of trackers,
/// with an optional note under it.
struct FormStackRow<Control: View>: View {
    let title: String
    var note: String?
    let control: Control
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title).opacity(isEnabled ? 1 : 0.45)
            control
            if let note {
                Text(note)
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isEnabled ? 1 : 0.45)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }
}

/// A setting that's on or off: the label on the left, a green switch on the right.
struct SwitchRow: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: Spacing.medium) {
            FormLabel(title: title, caption: caption)
                .opacity(isEnabled ? 1 : 0.45)
                .accessibilityHidden(true)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Colors.statusSafeText)
                .accessibilityHint(caption ?? "")
        }
        .formRowPadding()
    }
}

/// A file or folder location with a button that changes it.
struct PathRow: View {
    let title: String
    let path: String
    var placeholder = "Not set"
    var buttonTitle = "Choose…"
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.xxxSmall) {
                Text(title)
                Text(path.isEmpty ? placeholder : (path as NSString).abbreviatingWithTildeInPath)
                    .font(Typography.callout)
                    .foregroundStyle(path.isEmpty ? Colors.textTertiary : Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityElement(children: .combine)
            Button(buttonTitle, action: action)
                .buttonStyle(.freshet(.secondary, size: .small))
                .accessibilityLabel("\(buttonTitle.replacingOccurrences(of: "…", with: "")) \(title)")
        }
        .formRowPadding()
    }
}

/// A folder setting with a Choose… button.
struct FolderRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        PathRow(title: title, path: path) { choose() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { path = url.path }
    }
}

// MARK: - Value controls

/// The chrome for text fields: an inset well with an 8 pt corner and a 1 pt outline that
/// turns to the action color while the field is being edited.
struct FieldChrome: ViewModifier {
    var style: TextStyle = Typography.body
    var focus: FocusState<Bool>.Binding?
    @FocusState private var ownFocus: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let binding = focus ?? $ownFocus
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(style)
            .foregroundStyle(Colors.textPrimary)
            .focused(binding)
            .focusEffectDisabled()
            .padding(.horizontal, Spacing.xSmall)
            .frame(height: PageLayout.controlHeight)
            .background(shape.fill(Colors.surfaceCard))
            .overlay {
                shape.strokeBorder(binding.wrappedValue ? Colors.actionPrimary
                                                         : (contrast == .increased ? Colors.textSecondary : Colors.borderStrong),
                                   lineWidth: 1)
            }
            .contentShape(shape)
            .onTapGesture { if isEnabled { binding.wrappedValue = true } }
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: binding.wrappedValue)
    }
}

/// The same well for multi-line text such as tracker lists.
struct EditorChrome: ViewModifier {
    let height: CGFloat
    var style: TextStyle = Typography.callout.monospaced()
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        content
            .font(style)
            .foregroundStyle(Colors.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.vertical, Spacing.xxSmallPlus)
            .frame(height: height)
            .background(shape.fill(Colors.surfaceCard))
            .overlay {
                shape.strokeBorder(focused ? Colors.actionPrimary : (contrast == .increased ? Colors.textSecondary : Colors.borderStrong),
                                   lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A one-line text field.
struct TextInput: View {
    let title: String
    @Binding var text: String
    var prompt: String
    var width: CGFloat?
    var monospaced: Bool
    var secure: Bool
    var focus: FocusState<Bool>.Binding?

    init(_ title: String, text: Binding<String>, prompt: String = "", width: CGFloat? = 240, monospaced: Bool = false,
         secure: Bool = false, focus: FocusState<Bool>.Binding? = nil) {
        self.title = title
        _text = text
        self.prompt = prompt
        self.width = width
        self.monospaced = monospaced
        self.secure = secure
        self.focus = focus
    }

    var body: some View {
        Group {
            if secure {
                SecureField(title, text: $text, prompt: placeholder)
            } else {
                TextField(title, text: $text, prompt: placeholder)
            }
        }
        .labelsHidden()
        .modifier(FieldChrome(style: monospaced ? Typography.callout.monospaced() : Typography.body, focus: focus))
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }

    private var placeholder: Text {
        Text(prompt).foregroundStyle(Colors.textTertiary)
    }
}

/// A whole-number field with an optional unit after it. With a `step`, round − and + buttons
/// sit either side of it.
struct NumberInput: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>?
    var step: Int?
    var unit: String
    var width: CGFloat

    init(_ title: String, value: Binding<Int>, range: ClosedRange<Int>? = nil, step: Int? = nil, unit: String = "",
         width: CGFloat = 72) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.width = width
    }

    var body: some View {
        HStack(spacing: Spacing.xxSmallPlus) {
            if let step {
                stepButton("Decrease", symbol: "minus") { set(value - step) }
                    .disabled(value <= (range?.lowerBound ?? 0))
            }
            TextField(title, value: clamped, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .modifier(FieldChrome(style: Typography.body.numbers))
                .frame(width: width)
            if let step {
                stepButton("Increase", symbol: "plus") { set(value + step) }
                    .disabled(value >= (range?.upperBound ?? .max))
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(Typography.callout)
                    .foregroundStyle(Colors.textSecondary)
                    .fixedSize()
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { set($0) })
    }

    private func set(_ newValue: Int) {
        if let range {
            value = min(max(newValue, range.lowerBound), range.upperBound)
        } else {
            value = max(0, newValue)
        }
    }

    private func stepButton(_ verb: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("\(verb) \(title)", systemImage: symbol) }
            .buttonStyle(.freshet(.secondary, size: .small, width: .square))
            .help("\(verb) by \(step ?? 1)")
    }
}

/// A pop-up menu for choosing one value: a raised 8 pt rounded rectangle with the current
/// value and a chevron.
struct ValuePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    var minWidth: CGFloat
    let label: (Value) -> String

    init(_ title: String, selection: Binding<Value>, options: [Value], minWidth: CGFloat = 140,
         label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.options = options
        self.minWidth = minWidth
        self.label = label
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in Text(label(option)).tag(option) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Spacing.xSmall) {
                Text(label(selection)).lineLimit(1)
                Spacer(minLength: Spacing.xxSmall)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Colors.textSecondary)
            }
            .frame(minWidth: minWidth)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(ValueControlStyle())
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

/// The raised rounded rectangle that pop-up menus use.
struct ValueControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ValueControlBody(configuration: configuration)
    }
}

private struct ValueControlBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        configuration.label
            .font(Typography.body)
            .foregroundStyle(Colors.textPrimary)
            .padding(.horizontal, Spacing.small - 2)
            .frame(height: PageLayout.controlHeight)
            .background(shape.fill(configuration.isPressed ? Colors.fillSecondaryPressed
                                                           : (hovering && isEnabled ? Colors.fillSecondaryHover : Colors.surfaceRaised)))
            .overlay {
                shape.strokeBorder(contrast == .increased ? Colors.textSecondary : Colors.borderStrong, lineWidth: 1)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}

/// A checkbox in the action color, for lists of things to include rather than settings.
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CheckboxBody(configuration: configuration)
    }
}

private struct CheckboxBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
        HStack(spacing: Spacing.xSmall) {
            ZStack {
                shape.fill(configuration.isOn ? Colors.actionPrimary : Colors.surfaceCard)
                shape.strokeBorder(configuration.isOn ? Colors.actionPrimary
                                                      : (contrast == .increased ? Colors.textSecondary : Colors.borderStrong),
                                   lineWidth: 1)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Colors.onActionPrimary)
                }
            }
            .frame(width: 14, height: 14)
            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
