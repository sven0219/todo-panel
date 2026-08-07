import Foundation

/// Simple zh/en switching for UI strings.
enum I18n {
    enum Language: String, CaseIterable, Identifiable {
        case system
        case zh
        case en
        var id: String { rawValue }
    }

    /// Driven by settings; defaults to the system language.
    static var mode: Language = .system

    static var isZH: Bool {
        switch mode {
        case .zh: return true
        case .en: return false
        case .system: return (Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }

    static func t(_ zh: String, _ en: String) -> String {
        isZH ? zh : en
    }
}
