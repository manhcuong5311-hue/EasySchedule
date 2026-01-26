import SwiftUI

enum EventCardLayout: String, CaseIterable, Identifiable {
    case normal
    case compact
    case timeline   // ⭐ ADD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return String(localized: "layout_normal")
        case .compact:
            return String(localized: "layout_compact")
        case .timeline:
            return String(localized: "layout_timeline")
        }
    }

    /// Chỉ dùng để preset ban đầu – KHÔNG lock UI
    var defaultTimeDisplayMode: EventTimeDisplayMode? {
        switch self {
        case .compact:
            return .timeRange
        case .timeline:
            return .timeRange   // timeline luôn cần time
        default:
            return nil
        }
    }
}
