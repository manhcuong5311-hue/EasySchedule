import SwiftUI


struct TimelineNowIndicatorView: View {
    
    let date: Date
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    
    @EnvironmentObject var uiAccent: UIAccentStore
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, 0), 24)
    }

    
    private var timelineStart: Date {
        Calendar.current.date(
            bySettingHour: safeStartHour,
            minute: 0,
            second: 0,
            of: date
        )!
    }

    
    private var timelineEnd: Date {
        if safeEndHour == 24 {
            return Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: Calendar.current.startOfDay(for: date)
            )!
        }

        return Calendar.current.date(
            bySettingHour: safeEndHour,
            minute: 0,
            second: 0,
            of: date
        )!
    }

    
    private var now: Date {
        Date()
    }
    
    /// Clamp current time vào timeline
    private var clampedNow: Date {
        min(max(now, timelineStart), timelineEnd)
    }
    
    private var topOffset: CGFloat {
        let delta = clampedNow.timeIntervalSince(timelineStart)
        return CGFloat(delta / 3600) * hourHeight
    }
    
    @ViewBuilder
    var body: some View {
        if isToday {
            HStack(spacing: 6) {
                
                Circle()
                    .fill(uiAccent.color)
                    .frame(width: 8, height: 8)
                
                Rectangle()
                    .fill(uiAccent.color)
                    .frame(height: 1)
            }
            .offset(x: 48, y: topOffset)
        }
    }
}
