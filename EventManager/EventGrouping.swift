//
//  EventGrouping.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import Foundation

struct EventGrouping {

    // MARK: - Group by Month (Year + Month)
    static func byMonth(_ events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) { event in
            let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
            return Calendar.current.date(from: comps)!
        }
    }

    // MARK: - Group by Week (Week of Month)
    static func byWeek(_ events: [CalendarEvent]) -> [Int: [CalendarEvent]] {
        Dictionary(grouping: events) { event in
            Calendar.current.component(.weekOfMonth, from: event.date)
        }
    }

    // MARK: - Group by Day
    static func byDay(_ events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
}
