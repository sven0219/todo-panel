import SwiftUI
import AppKit

/// Reports the ScrollView content height for auto-sizing the panel on collapse/expand.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension Notification.Name {
    static let panelContentHeightChanged = Notification.Name("panelContentHeightChanged")
}

/// Collapsed mini-float pill size (must match `MiniFloatView` frame).
enum MiniFloatLayout {
    static let size = NSSize(width: 88, height: 40)
}

/// Menu-bar and mini-float status symbols.
enum WorkStatusSymbol {
    static func name(isWorking: Bool, clockedOut: Bool) -> String {
        if isWorking { return "figure.and.laptop" }
        if clockedOut { return "figure.wave" }
        return "figure.stand"
    }
}
