//
//  Case.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
import SwiftUI

enum EventCardLayout: String, CaseIterable, Identifiable {
    case normal
    case compact
<<<<<<< HEAD
    case timeline
=======
    case timeline   // ⭐ NEW – Timeline View Mode
>>>>>>> 2f1e950 (feat(event): update event feature)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return String(localized: "layout_normal")

        case .compact:
            return String(localized: "layout_compact")
<<<<<<< HEAD

=======
>>>>>>> 2f1e950 (feat(event): update event feature)
        case .timeline:
            return String(localized: "layout_timeline")
        }
    }

    /// Chỉ dùng để preset ban đầu – KHÔNG lock UI
    var defaultTimeDisplayMode: EventTimeDisplayMode? {
        switch self {
        case .compact:
<<<<<<< HEAD
            return .timeRange

        case .timeline:
            return .anchor   // ⭐ hợp với Timeline (mốc giờ)

        case .normal:
=======
            return .timeRange          // preset cũ
        case .timeline:
            return .timeRange          // ⭐ timeline v1 dùng time range
        default:
>>>>>>> 2f1e950 (feat(event): update event feature)
            return nil
        }
    }
}
