
import SwiftUI

// BusyHoursColor.swift (nên tách riêng)
enum BusyHoursColor {
    static let background = Color(hex: "#FFE082").opacity(0.14)
    static let icon = Color(hex: "#FFB300").opacity(0.7)
}



struct BusySlotCardView: View {

    let start: Date
    let end: Date
    let date: Date
    let startHour: Int

    @EnvironmentObject var uiAccent: UIAccentStore

    private var timelineStart: Date {
        Calendar.current.date(
            bySettingHour: startHour,
            minute: 0,
            second: 0,
            of: date
        )!
    }

    private var offsetY: CGFloat {
        let minutes = start.timeIntervalSince(timelineStart) / 60
        return CGFloat(minutes) * TimelineLayout.minuteHeight
    }

    private var height: CGFloat {
        let minutes = end.timeIntervalSince(start) / 60
        return max(24, CGFloat(minutes) * TimelineLayout.minuteHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(BusyHoursColor.icon)


                Text(String(localized: "busy"))
                    .font(.caption.weight(.semibold))
            }

            Text(
                EventTimeDisplayMode.timeRange
                    .primaryText(from: start, to: end)
            )
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height, alignment: .top)   // ⭐ KÉO DÀI THEO END
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BusyHoursColor.background)
        )
        .offset(
            x: TimelineLayout.busyCardOffsetX,
            y: offsetY
        )
        .allowsHitTesting(false)
    }
}
