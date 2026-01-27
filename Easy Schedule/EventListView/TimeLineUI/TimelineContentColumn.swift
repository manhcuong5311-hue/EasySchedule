
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

    private var mergedBusySlots: [MergedBusySlot] {
        mergeBusySlots(allItems)
    }

    
    var body: some View {
        ZStack(alignment: .topLeading) {

            // 🔴 NOW INDICATOR
            TimelineNowIndicatorView(
                date: date,
                startHour: startHour,
                endHour: endHour,
                now: now,
                occlusionRanges: occlusionRanges
            )
            .zIndex(0)

            // 🟡 BUSY SLOT (MERGED – 1 CARD DUY NHẤT)
            ForEach(
                mergeBusySlots(manualBusySlots),
                id: \.start
            ) { slot in
                BusySlotCardView(
                    start: slot.start,
                    end: slot.end,
                    date: date,
                    startHour: startHour
                )
                .zIndex(0.5)
            }

            // 🟦 EVENT THẬT (KHÔNG BAO GIỜ LẪN BUSY)
            ForEach(events) { event in
                TimelineEventNodeView(
                    event: event,
                    date: date,
                    startHour: startHour,
                    endHour: endHour,
                    timeDisplayMode: timeDisplayMode
                )
                .zIndex(1)
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
    
    
    private func mergeBusySlots(
        _ slots: [CalendarEvent]
    ) -> [MergedBusySlot] {

        let busy = slots
            .filter { $0.origin == .busySlot }
            .sorted { $0.startTime < $1.startTime }

        guard !busy.isEmpty else { return [] }

        var result: [MergedBusySlot] = []
        var currentStart = busy[0].startTime
        var currentEnd   = busy[0].endTime

        for slot in busy.dropFirst() {

            // ⭐ CHẠM GIỜ hoặc liền kề (<= 1 phút)
            if slot.startTime <= currentEnd.addingTimeInterval(60) {
                currentEnd = max(currentEnd, slot.endTime)
            } else {
                result.append(
                    MergedBusySlot(start: currentStart, end: currentEnd)
                )
                currentStart = slot.startTime
                currentEnd   = slot.endTime
            }
        }

        result.append(
            MergedBusySlot(start: currentStart, end: currentEnd)
        )

        return result
    }

    
    
}

struct TimelineOcclusionRange {
    let minY: CGFloat
    let maxY: CGFloat

    func contains(_ y: CGFloat) -> Bool {
        y >= minY && y <= maxY
    }
}
