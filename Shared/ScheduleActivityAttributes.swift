//
//  ScheduleActivityAttributes.swift
//  Easy Schedule — Shared (app + widget)
//
//  Mô tả Live Activity cho "việc đang/sắp diễn ra". Dùng chung giữa app
//  (start/update/end) và widget extension (render).
//
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

struct ScheduleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var eventID: String
        var title: String
        var start: Date
        var end: Date
        var colorHex: String
        /// `true` khi việc chưa bắt đầu (đếm ngược tới `start`);
        /// `false` khi đang diễn ra (đếm ngược tới `end`).
        var isUpcoming: Bool

        var color: Color { snapshotColor(from: colorHex) }
        /// Mốc thời gian để đếm ngược (start nếu sắp tới, end nếu đang chạy).
        var target: Date { isUpcoming ? start : end }
    }

    // Metadata tĩnh — giữ tối thiểu cho v1.
    var kind: String = "next_event"
}
#endif
