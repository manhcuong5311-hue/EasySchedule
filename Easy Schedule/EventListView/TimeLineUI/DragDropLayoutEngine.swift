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
        let raw = endMinutes - startMinutes
        return raw >= 0 ? raw : raw + 1440   // event ending after midnight
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
        // Past the last anchor (Night Sleep 23:59, whose end wraps to 00:00) →
        // park the indicator on the last node instead of snapping back to 0.
        if let last = events.last, now >= last.startMinutes {
            return yPosition(for: events.count - 1, in: events)
        }
        return 0
    }

    static func isNowInsideTimeline(events: [CalendarEvent]) -> Bool {
        guard let first = events.first, let last = events.last else { return false }
        let now = currentMinutes()
        // The Night Sleep anchor sits at 23:59, whose endTime rolls over to 00:00
        // → endMinutes == 0. Fall back to its start so "inside the timeline" stays
        // true through the whole evening (otherwise the now-time hides after ~18:00).
        let upper = last.endMinutes >= last.startMinutes ? last.endMinutes : last.startMinutes
        return now >= first.startMinutes && now <= upper
    }

    static func currentMinutes() -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func snap(_ minutes: Int) -> Int {
        Int((Double(minutes) / Double(snapStep)).rounded()) * snapStep
    }

    static func minuteDelta(from translation: CGFloat) -> Int {
        Int(translation / 15)
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

// MARK: - Proportional timeline (Structured-style) helpers
//
// The card's vertical position is a pure function of its start minute, so the
// finger maps 1:1 to time while dragging — no rubber-band, no compounding.

extension DragDropLayoutEngine {

    /// Pixels per minute — shared with the existing proportional timeline scale.
    static var minuteHeight: CGFloat { TimelineLayout.minuteHeight }

    /// Minimum card heights so short events / anchors stay readable.
    static let minCardHeight: CGFloat = 30
    static let systemCardHeight: CGFloat = 40

    /// Proportional pixel height of a card based on its duration.
    static func pxHeight(_ event: CalendarEvent) -> CGFloat {
        if event.id == wakeID || event.id == sleepID { return systemCardHeight }
        let d = event.durationMinutes
        return max(minCardHeight, CGFloat(d) * minuteHeight)
    }

    /// Hour-aligned [start, end] minute bounds of the day grid, derived from the
    /// wake/sleep anchors (falling back to the events themselves on off-days).
    static func gridBounds(events: [CalendarEvent]) -> (start: Int, end: Int) {
        let regular  = events.filter { $0.id != wakeID && $0.id != sleepID }
        let wakeMin  = events.first(where: { $0.id == wakeID  })?.startMinutes
        let sleepMin = events.first(where: { $0.id == sleepID })?.startMinutes

        let lo = [wakeMin,  regular.map(\.startMinutes).min()].compactMap { $0 }.min() ?? 480
        let hi = [sleepMin, regular.map(\.endMinutes).max()].compactMap { $0 }.max() ?? 1320

        let startHour = max(0, lo / 60)
        let endHour   = min(24, (hi + 59) / 60)
        return (startHour * 60, max(endHour, startHour + 1) * 60)
    }

    /// Y offset (pt) of a given minute relative to the grid top.
    static func y(forMinute minute: Int, gridStartMin: Int) -> CGFloat {
        CGFloat(minute - gridStartMin) * minuteHeight
    }

    /// New start minute for a free (1:1) vertical drag: original start + pixel delta
    /// converted straight to minutes, snapped to the grid, clamped inside the window.
    static func freeStart(originalStart: Int,
                          translationPx: CGFloat,
                          duration: Int,
                          window: ClosedRange<Int>) -> Int {
        let deltaMin = Int((translationPx / minuteHeight).rounded())
        let snapped  = snap(originalStart + deltaMin)
        return max(window.lowerBound, min(window.upperBound - duration, snapped))
    }

    /// Magnetic pull toward the previous event's end and the nearest hour mark.
    static func magneticSnap(_ minutes: Int, movedID: String, in events: [CalendarEvent]) -> Int {
        var result = minutes
        let pullRadius = 8
        let gap = 5

        let neighbors = events.filter { $0.id != movedID && $0.id != wakeID && $0.id != sleepID }
        if let prev = neighbors
            .filter({ $0.endMinutes <= minutes + pullRadius })
            .max(by: { $0.endMinutes < $1.endMinutes }) {
            let target = prev.endMinutes + gap
            if abs(result - target) <= pullRadius { result = target }
        }

        let hourMins = (result / 60) * 60
        if result - hourMins < 5 { result = hourMins }
        else if (hourMins + 60) - result < 5 { result = hourMins + 60 }
        return result
    }
}
