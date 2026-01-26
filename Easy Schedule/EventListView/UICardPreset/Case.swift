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
    case timeline

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
            return .anchor   // ⭐ hợp với Timeline (mốc giờ)

        case .normal:
            return nil
        }
    }
}
