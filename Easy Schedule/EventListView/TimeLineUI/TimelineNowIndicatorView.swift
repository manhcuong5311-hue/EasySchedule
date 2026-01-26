//
//  TimelineNowIndicatorView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//

import SwiftUI

struct TimelineNowIndicatorView: View {

    let date: Date
    let startHour: Int
    let endHour: Int
    let now: Date
    
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 23)
    }


    private var timelineStart: Date? {
        Calendar.current.date(
            bySettingHour: safeStartHour,
            minute: 0,
            second: 0,
            of: date
        )
    }

    private var timelineEnd: Date? {
        if endHour >= 24 {
            // 23:59:59 của ngày hiện tại
            return Calendar.current.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: date
            )
        }

        return Calendar.current.date(
            bySettingHour: endHour,
            minute: 0,
            second: 0,
            of: date
        )
    }


    private var isToday: Bool {
        Calendar.current.isDate(now, inSameDayAs: date)
    }

    private var isVisible: Bool {
        guard let start = timelineStart,
              let end = timelineEnd
        else { return false }

        return isToday && now >= start && now <= end
    }

    private var offsetY: CGFloat {
        guard let start = timelineStart else { return 0 }
        let minutes = now.timeIntervalSince(start) / 60
        return CGFloat(minutes) * TimelineLayout.minuteHeight
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 6) {

                // 🔴 DOT — CHẠM SPINE
                    Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .offset(x: 0) // ⭐ ăn nửa vào spine

                Rectangle()
                    .fill(Color.red.opacity(0.6))
                    .frame(height: 1)
            }
            .offset(y: offsetY)
        }
    }
}
