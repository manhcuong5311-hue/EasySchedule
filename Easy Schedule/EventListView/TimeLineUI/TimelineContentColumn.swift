
import SwiftUI
import Combine

struct TimelineContentColumn: View {

    let date: Date
    let startHour: Int
    let endHour: Int

    let events: [CalendarEvent]
    let manualBusySlots: [CalendarEvent]
    let timeDisplayMode: EventTimeDisplayMode

    private var allItems: [CalendarEvent] {
        events + manualBusySlots
    }
    
    @State private var now = Date()

    private let timer = Timer.publish(
        every: 60,
        on: .main,
        in: .common
    ).autoconnect()

    
    var body: some View {
        ZStack(alignment: .topLeading) {

            // 🔴 NOW INDICATOR — LUÔN Ở DƯỚI
            TimelineNowIndicatorView(
                date: date,
                startHour: startHour,
                endHour: endHour,
                now: now,
                occlusionRanges: occlusionRanges
            )

            .zIndex(0)   // ⭐ QUAN TRỌNG

            // 🟦 EVENTS — LUÔN Ở TRÊN
            ForEach(allItems) { event in
                TimelineEventNodeView(
                    event: event,
                    date: date,
                    startHour: startHour,
                    endHour: endHour,
                    timeDisplayMode: timeDisplayMode
                )
                .zIndex(1)   // ⭐ QUAN TRỌNG
            }
        }
        .onReceive(timer) { now = $0 }

      
    }

    private var occlusionRanges: [TimelineOcclusionRange] {
        allItems.compactMap { event in
            guard
                let start = Calendar.current.date(
                    bySettingHour: startHour,
                    minute: 0,
                    second: 0,
                    of: date
                )
            else { return nil }

            let visibleStart = max(event.startTime, start)
            let visibleEnd   = min(event.endTime, now)

            guard visibleEnd > visibleStart else { return nil }

            let startMin = visibleStart.timeIntervalSince(start) / 60
            let endMin   = visibleEnd.timeIntervalSince(start) / 60

            let minY = CGFloat(startMin) * TimelineLayout.minuteHeight
            let maxY = CGFloat(endMin) * TimelineLayout.minuteHeight

            return TimelineOcclusionRange(minY: minY, maxY: maxY)
        }
    }

}

struct TimelineOcclusionRange {
    let minY: CGFloat
    let maxY: CGFloat

    func contains(_ y: CGFloat) -> Bool {
        y >= minY && y <= maxY
    }
}
