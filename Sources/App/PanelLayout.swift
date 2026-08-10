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
