import SwiftUI

/// Things 3 / Todoist inspired palette
enum Palette {
    /// Primary blue (todo, clock-in, titles)
    static let primary = Color(red: 0.04, green: 0.52, blue: 1.00)        // #0A84FF
    /// Completed green
    static let completed = Color(red: 0.20, green: 0.78, blue: 0.35)      // #34C759
    /// Clock-out coral (Todoist)
    static let clockOut = Color(red: 0.89, green: 0.27, blue: 0.23)       // #E44332
    /// Follow-up orange
    static let followup = Color(red: 1.00, green: 0.58, blue: 0.00)       // #FF9500
    /// Unfinished gray
    static let uncompleted = Color(red: 0.55, green: 0.58, blue: 0.63)
    /// Synced green
    static let synced = Color(red: 0.20, green: 0.78, blue: 0.35)
    /// Unsynced orange
    static let unsynced = Color(red: 1.00, green: 0.58, blue: 0.00)
}
