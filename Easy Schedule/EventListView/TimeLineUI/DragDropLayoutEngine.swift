import SwiftUI

// MARK: - System event identity (shared across files)

extension DragDropLayoutEngine {
    static let wakeID  = "__system_wake__"
    static let sleepID = "__system_sleep__"
}

// MARK: - CalendarEvent timing helpers

extension CalendarEvent {
    var startMinutes: Int {
        let c = Calendar.current
        return c.component(.hour, from: startTime) * 60 + c.component(.minute, from: startTime)
    }
    var endMinutes: Int {
        let c = Calendar.current
        return c.component(.hour, from: endTime) * 60 + c.component(.minute, from: endTime)
    }
    var durationMinutes: Int {
        max(0, endMinutes - startMinutes)
    }
    var formattedStartTime: String {
        String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60)
    }
    var formattedEndTime: String {
        String(format: "%02d:%02d", endMinutes / 60, endMinutes % 60)
    }
    var originIcon: String {
        switch origin {
        case .myEvent:          return "calendar"
        case .createdForMe:     return "person.crop.circle.fill"
        case .iCreatedForOther: return "person.badge.plus.fill"
        case .busySlot:         return "clock.fill"
        }
    }
    var eventColor: Color { Color(hex: colorHex) }
}

// MARK: - Layout Engine

struct DragDropLayoutEngine {

    static let snapStep = 5

    // Card height scales with event duration; system events use the flat 64 pt base
    static func eventHeight(_ event: CalendarEvent) -> CGFloat {
        if event.id == wakeID || event.id == sleepID { return 64 }
        let d = event.durationMinutes
        guard d > 0 else { return 64 }
        return min(max(64 + CGFloat(d - 30) * (50.0 / 90.0), 64), 120)
    }

    // Spacing between consecutive events based on time gap
    static func spacing(current: CalendarEvent, next: CalendarEvent) -> CGFloat {
        let diff = max(0, next.startMinutes - current.endMinutes)
        let base: CGFloat = 40
        if diff <= 5  { return base }
        if diff <= 15 { return base + CGFloat(diff) * 2 }
        if diff <= 60 { return base + CGFloat(diff) * 0.7 }
        return min(160, base + CGFloat(diff) * 0.35)
    }

    // Y-centre of event at index within the VStack
    static func yPosition(for index: Int, in events: [CalendarEvent]) -> CGFloat {
        var y: CGFloat = 0
        for i in 0..<index {
            y += eventHeight(events[i])
            if i < events.count - 1 {
                y += spacing(current: events[i], next: events[i + 1])
            }
        }
        return y + eventHeight(events[index]) / 2
    }

    // Y offset of the current time within the timeline VStack
    static func nowY(events: [CalendarEvent]) -> CGFloat {
        let now = currentMinutes()
        for i in 0..<events.count {
            let s = events[i].startMinutes, e = events[i].endMinutes
            if now >= s && now <= e {
                let topY = yPosition(for: i, in: events) - eventHeight(events[i]) / 2
                let prog = CGFloat(now - s) / CGFloat(max(e - s, 1))
                return topY + eventHeight(events[i]) * prog
            }
            if i < events.count - 1 {
                let nextS = events[i + 1].startMinutes
                if now > e && now < nextS {
                    let gapTop = yPosition(for: i, in: events) + eventHeight(events[i]) / 2
                    let gapBot = yPosition(for: i + 1, in: events) - eventHeight(events[i + 1]) / 2
                    let prog   = CGFloat(now - e) / CGFloat(max(nextS - e, 1))
                    return gapTop + (gapBot - gapTop) * prog
                }
            }
        }
        return 0
    }

    static func isNowInsideTimeline(events: [CalendarEvent]) -> Bool {
        guard let first = events.first, let last = events.last else { return false }
        let now = currentMinutes()
        return now >= first.startMinutes && now <= last.endMinutes
    }

    static func currentMinutes() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func snap(_ minutes: Int) -> Int {
        Int((Double(minutes) / Double(snapStep)).rounded()) * snapStep
    }

    static func minuteDelta(from translation: CGFloat) -> Int {
        Int(translation * 0.7 / 10)
    }

    // New start minutes for a regular event — does NOT clamp against system event anchors,
    // so events can freely drag through the wake/sleep boundary positions.
    static func newStartMinutes(
        for event: CalendarEvent,
        delta: Int,
        in events: [CalendarEvent]
    ) -> Int {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else {
            return event.startMinutes
        }
        let dur = event.durationMinutes
        var newStart = snap(event.startMinutes + delta)
        newStart = max(0, min(1380, newStart))

        // Only clamp against other REGULAR events (skip system anchors)
        if index > 0 {
            let prev = events[index - 1]
            if prev.id != wakeID {
                newStart = max(newStart, prev.endMinutes + 5)
            }
        }
        if index < events.count - 1 {
            let next = events[index + 1]
            if next.id != sleepID {
                newStart = min(newStart, next.startMinutes - 5 - dur)
            }
        }
        return newStart
    }

    // New start minutes for a system event — constrained to its allowed range
    static func newStartMinutesForSystem(
        currentMinutes: Int,
        delta: Int,
        constraint: ClosedRange<Int>
    ) -> Int {
        let raw = snap(currentMinutes + delta)
        return max(constraint.lowerBound, min(constraint.upperBound, raw))
    }

    // Build updated Date values from a new start-minute value
    static func updatedTimes(for event: CalendarEvent, newStartMinutes: Int) -> (start: Date, end: Date) {
        let cal  = Calendar.current
        let base = cal.startOfDay(for: event.startTime)
        let dur  = event.durationMinutes
        let start = base.addingTimeInterval(TimeInterval(newStartMinutes * 60))
        let end   = base.addingTimeInterval(TimeInterval((newStartMinutes + dur) * 60))
        return (start, end)
    }

    // Dash style for the connecting line
    static func dashStyle(gapMinutes: Int, isDragging: Bool) -> StrokeStyle {
        let lw: CGFloat = isDragging ? 3.5 : 2.5
        let ratio = CGFloat(min(max(gapMinutes, 0), 300)) / 300.0
        return StrokeStyle(lineWidth: lw, lineCap: .round, dash: [6 + ratio * 10, 4 + ratio * 8])
    }

    // Push adjacent regular events away from the moved one.
    // Stops at system event anchors — never pushes them.
    static func autoPush(events: inout [CalendarEvent], movedID: String, minGap: Int = 5) {
        guard let movedIndex = events.firstIndex(where: { $0.id == movedID }) else { return }

        // Push events after movedIndex downward
        for i in (movedIndex + 1)..<events.count {
            if events[i].id == sleepID { break }  // anchor — stop
            let required = events[i - 1].endMinutes + minGap
            if events[i].startMinutes < required {
                let times = updatedTimes(for: events[i], newStartMinutes: snap(required))
                events[i].startTime = times.start
                events[i].endTime   = times.end
            } else { break }
        }

        // Push events before movedIndex upward
        if movedIndex > 0 {
            for i in stride(from: movedIndex - 1, through: 0, by: -1) {
                if events[i].id == wakeID { break }  // anchor — stop
                let required = events[i + 1].startMinutes - minGap - events[i].durationMinutes
                if events[i].startMinutes > required {
                    let times = updatedTimes(for: events[i], newStartMinutes: snap(required))
                    events[i].startTime = times.start
                    events[i].endTime   = times.end
                } else { break }
            }
        }
    }
}
