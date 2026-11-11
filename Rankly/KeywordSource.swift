import Foundation

/// Where a candidate keyword came from. Stored as a stable code in analysis results
/// (older results stored Turkish labels; those are still understood).
enum KeywordSource {
    static let name = "name"
    static let subtitle = "subtitle"
    static let description = "description"
    static let suggestion = "suggestion"
    static let competitor = "competitor"

    static func label(_ code: String) -> String {
        switch code {
        case name, "ad": return String(localized: "name", comment: "Keyword source: app name")
        case subtitle, "alt başlık": return String(localized: "subtitle", comment: "Keyword source: app subtitle")
        case description, "açıklama": return String(localized: "description", comment: "Keyword source: app description")
        case suggestion, "öneri": return String(localized: "suggestion", comment: "Keyword source: App Store autocomplete")
        case competitor, "rakip": return String(localized: "competitor", comment: "Keyword source: competitor metadata")
        default: return code
        }
    }
}
