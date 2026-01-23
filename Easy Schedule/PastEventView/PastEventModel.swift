//
//  PastEventRefactor.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 23/1/26.
//
import SwiftUI
import Combine

struct WeeklyStats {
    let totalEvents: Int
    let byOrigin: [EventOrigin: Int]
    let byWeekday: [Int: Int]   // 1 = Sun ... 7 = Sat
    let busiestWeekday: Int?
    let peakHourRange: ClosedRange<Int>?
}

struct WeeklyComparison {
    let deltaTotal: Int
    let deltaWithOthers: Int
}

struct WeekKey: Identifiable, Equatable {
    let year: Int
    let week: Int

    var id: String { "\(year)-\(week)" }
}

enum SummaryMode: String, CaseIterable {
    case week
    case month
}


struct WeeklyStatsBuilder {

    static func build(
        events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> WeeklyStats {

        let total = events.count

        let byOrigin = Dictionary(grouping: events) {
            $0.origin
        }.mapValues { $0.count }

        let byWeekday = Dictionary(grouping: events) {
            calendar.component(.weekday, from: $0.startTime)
        }.mapValues { $0.count }

        let busiestWeekday = byWeekday
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value      // nhiều event hơn
                } else {
                    return lhs.key < rhs.key          // cùng số → ngày sớm hơn (Sun thắng)
                }
            }
            .first?
            .key


        let byHour = Dictionary(grouping: events) {
            calendar.component(.hour, from: $0.startTime)
        }.mapValues { $0.count }

        let peakHour = byHour
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value     // nhiều event hơn thắng
                } else {
                    return lhs.key < rhs.key         // bằng nhau → giờ sớm hơn thắng
                }
            }
            .first?
            .key

        let peakRange = peakHour.map {
            let end = min($0 + 1, 23)
            return $0...end
        }



        return WeeklyStats(
            totalEvents: total,
            byOrigin: byOrigin,
            byWeekday: byWeekday,
            busiestWeekday: busiestWeekday,
            peakHourRange: peakRange
        )
    }
}


