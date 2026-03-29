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

    let occlusionRanges: [TimelineOcclusionRange]

    private var isOccludedByEvent: Bool {
        occlusionRanges.contains { $0.contains(offsetY) }
    }

    
    
    
    var body: some View {
        if isVisible {
            ZStack(alignment: .leading) {

                // LINE — chỉ hiện khi KHÔNG bị che
                if !isOccludedByEvent {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.35))
                        .fill(Color.red.opacity(0.6))
                        .frame(height: 1)
                }

                // DOT — LUÔN LUÔN HIỆN
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: offsetY)
            .allowsHitTesting(false)
        }
    }

}

