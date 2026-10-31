import AppKit
import SwiftUI

/// One meaning per color across the app. These are the system's dynamic colors, so they adapt
/// to light and dark appearance and to Increase Contrast; meaning is always also carried by a
/// symbol or text next to the color.
enum Palette {
    static let error = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)
    static let info = Color.accentColor

    /// Tinted backgrounds get stronger when Increase Contrast is on.
    static func fillOpacity(_ contrast: ColorSchemeContrast, standard: Double) -> Double {
        contrast == .increased ? min(1, standard * 2) : standard
    }
}

/// A sidebar beside a detail view with a divider people can drag. The width is remembered, and
/// the sidebar can be hidden.
struct SidebarSplit<Sidebar: View, Detail: View>: View {
    @AppStorage private var width: Double
    private let range: ClosedRange<Double>
    private let isCollapsed: Bool
    private let sidebar: Sidebar
    private let detail: Detail
    @State private var dragStart: Double?

    init(storageKey: String, defaultWidth: Double, range: ClosedRange<Double>, isCollapsed: Bool = false,
         @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail) {
        _width = AppStorage(wrappedValue: defaultWidth, storageKey)
        self.range = range
        self.isCollapsed = isCollapsed
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isCollapsed {
                sidebar.frame(width: min(max(width, range.lowerBound), range.upperBound))
                divider
            }
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let start = dragStart ?? width
                            dragStart = start
                            width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in dragStart = nil })
            }
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 20.0 : -20.0
                width = min(max(width + step, range.lowerBound), range.upperBound)
            }
    }
}
