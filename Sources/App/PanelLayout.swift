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
    static let miniFloatExpandRequested = Notification.Name("miniFloatExpandRequested")
    static let settingsPopoverVisibilityChanged = Notification.Name("settingsPopoverVisibilityChanged")
}

/// Collapsed mini-float pill size (must match `MiniFloatView` frame).
enum MiniFloatLayout {
    static let size = NSSize(width: 88, height: 40)
}

/// Menu-bar and mini-float status symbols.
enum WorkStatusSymbol {
    static func name(isWorking: Bool, clockedOut: Bool) -> String {
        if isWorking {
            return resolve(
                "figure.and.laptop",
                "figure.seated.side",
                "laptopcomputer"
            )
        }
        if clockedOut {
            return resolve("figure.wave", "figure.walk.departure")
        }
        return resolve("figure.stand", "person.fill")
    }

    /// Pick the first SF Symbol that exists on this macOS version.
    private static func resolve(_ candidates: String...) -> String {
        for name in candidates {
            if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                return name
            }
        }
        return candidates.last ?? "person.fill"
    }
}
