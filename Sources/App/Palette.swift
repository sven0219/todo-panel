import SwiftUI

/// Semantic colors mapped to macOS system colors.
enum Palette {
    static let primary = Color.accentColor
    static let completed = Color(nsColor: .systemGreen)
    static let clockOut = Color(nsColor: .systemRed)
    static let followup = Color(nsColor: .systemOrange)
    static let uncompleted = Color.secondary
    static let synced = Color(nsColor: .systemGreen)
    static let unsynced = Color(nsColor: .systemOrange)

    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let controlBackground = Color(nsColor: .controlBackgroundColor)
}
