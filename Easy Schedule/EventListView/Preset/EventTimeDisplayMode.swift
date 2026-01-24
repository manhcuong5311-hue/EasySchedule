//
//  EventTimeDisplayMode.swift
//  Easy Schedule
//

import SwiftUI
import Combine
enum EventTimeDisplayMode: String, CaseIterable, Identifiable {

    case timeRange    // 09:00–10:30 + duration
    case countdown    // In 25 min / Ending in 40 min
    case anchor       // Morning / Afternoon / Evening

    var id: String { rawValue }

    /// Title hiển thị trong Settings
    var title: String {
        String(localized: String.LocalizationValue(titleKey))
    }


    /// Localization key
    private var titleKey: String {
        switch self {
        case .timeRange:
            return "time_display_timeline"

        case .countdown:
            return "time_display_countdown"

        case .anchor:
            return "time_display_anchor"
        }
    }
}

extension EventTimeDisplayMode {

    /// Label chính (dòng to)
    func primaryText(for event: CalendarEvent) -> String {
        let start = event.startTime
        let end = event.endTime
        let now = Date()

        switch self {

        case .timeRange:
            let s = start.formatted(date: .omitted, time: .shortened)
            let e = end.formatted(date: .omitted, time: .shortened)
            return "\(s)–\(e)"

        case .countdown:
            if now < start {
                let minutes = Int(start.timeIntervalSince(now) / 60)
                return String(
                    format: String(localized: "time_countdown_in"),
                    minutes
                )
            } else {
                let minutes = Int(end.timeIntervalSince(now) / 60)
                return String(
                    format: String(localized: "time_countdown_ending"),
                    max(minutes, 0)
                )
            }

        case .anchor:
            let hour = Calendar.current.component(.hour, from: start)
            return anchorLabel(for: hour)
        }
    }

    /// Label phụ (dòng nhỏ) — optional
    func secondaryText(for event: CalendarEvent) -> String? {
        let duration = Int(event.endTime.timeIntervalSince(event.startTime) / 60)

        switch self {
        case .timeRange:
            return String(
                format: String(localized: "time_duration_minutes"),
                duration
            )

        case .countdown:
            let s = event.startTime.formatted(date: .omitted, time: .shortened)
            let e = event.endTime.formatted(date: .omitted, time: .shortened)
            return "\(s)–\(e)"

        case .anchor:
            let s = event.startTime.formatted(date: .omitted, time: .shortened)
            let e = event.endTime.formatted(date: .omitted, time: .shortened)
            return "\(s)–\(e)"
        }
    }

    // MARK: - Anchor helper
    private func anchorLabel(for hour: Int) -> String {
        switch hour {
        case 5..<11:
            return String(localized: "time_anchor_morning")
        case 11..<14:
            return String(localized: "time_anchor_noon")
        case 14..<18:
            return String(localized: "time_anchor_afternoon")
        case 18..<22:
            return String(localized: "time_anchor_evening")
        default:
            return String(localized: "time_anchor_night")
        }
    }
}
