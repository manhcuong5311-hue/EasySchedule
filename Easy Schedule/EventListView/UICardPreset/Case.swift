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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            return String(localized: "layout_normal")
        case .compact:
            return String(localized: "layout_compact")
        }
    }

    /// Chỉ dùng để preset ban đầu – KHÔNG lock UI
    var defaultTimeDisplayMode: EventTimeDisplayMode? {
        switch self {
        case .compact:
            return .timeRange   // ⭐ “chế độ đầu tiên” bạn nói
        default:
            return nil
        }
    }
}
