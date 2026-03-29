//
//  HorizontalDayPickerView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct DayCardHintBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - HorizontalDayPickerView (swipe-based week strip)

struct HorizontalDayPickerView: View {

    @Binding var selectedDate: Date
    let maxSelectableDate: Date
    let onUserSelectDay: (Date) -> Void

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    // MARK: Swipe state
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    private let swipeThreshold: CGFloat = 50

    private var cellWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : 44
    }

    // Strict 7-day week containing the given date
    private func weekDates(for date: Date) -> [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday first, consistent with rest of app
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Previous week (left)
                weekRow(offsetWeeks: -1, width: geo.size.width)
                    .offset(x: -geo.size.width + dragOffset)

                // Current week (center)
                weekRow(offsetWeeks: 0, width: geo.size.width)
                    .offset(x: dragOffset)

                // Next week (right)
                weekRow(offsetWeeks: 1, width: geo.size.width)
                    .offset(x: geo.size.width + dragOffset)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        isDragging = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        guard isDragging else { return }
                        isDragging = false
                        let velocity = value.predictedEndTranslation.width
                        let shouldSwipe = abs(dragOffset) > swipeThreshold || abs(velocity) > 300

                        if shouldSwipe {
                            if dragOffset < 0 {
                                // Swipe left → next week
                                withAnimation(.easeOut(duration: 0.25)) { dragOffset = -geo.size.width }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if let next = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) {
                                        selectedDate = next
                                    }
                                    dragOffset = 0
                                }
                            } else {
                                // Swipe right → previous week
                                withAnimation(.easeOut(duration: 0.25)) { dragOffset = geo.size.width }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) {
                                        selectedDate = prev
                                    }
                                    dragOffset = 0
                                }
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                        }
                    }
            )
        }
        .frame(height: 102)
    }

    // MARK: Week Row

    private func weekRow(offsetWeeks: Int, width: CGFloat) -> some View {
        let baseDate = Calendar.current.date(byAdding: .weekOfYear, value: offsetWeeks, to: selectedDate)!
        let dates = weekDates(for: baseDate)

        return HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                let dayStart  = Calendar.current.startOfDay(for: date)
                let today     = Calendar.current.startOfDay(for: Date())
                let isPast    = dayStart < today
                let isOut     = dayStart > maxSelectableDate
                let isLocked  = isPast || isOut
                let key       = dayStart

                let dayEvents = eventManager.events(for: date)
                    .filter { $0.origin != .busySlot }
                    .sorted { $0.startTime < $1.startTime }

                DayCell(
                    day: date,
                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                    isPastDay: isPast,
                    isOffDay: eventManager.isOffDay(date),
                    isLocked: isLocked,
                    unreadCount: eventManager.unreadCountByDay[key] ?? 0,
                    hasNew: eventManager.hasNewByDay[key] ?? false,
                    width: cellWidth,
                    dayEvents: dayEvents
                )
                .opacity(isLocked ? 0.35 : 1)
                .allowsHitTesting(!isLocked)
                .onTapGesture {
                    guard !isLocked else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedDate = date
                    }
                    onUserSelectDay(date)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, alignment: .center)
    }
}

// MARK: - Day Cell

struct DayCell: View {

    let day: Date
    let isSelected: Bool
    let isPastDay: Bool
    let isOffDay: Bool
    let isLocked: Bool
    let unreadCount: Int
    let hasNew: Bool
    let width: CGFloat
    var dayEvents: [CalendarEvent] = []

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var uiAccent: UIAccentStore
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 4) {
            weekdayLabel
            dayCircle
            eventIconRow
        }
        .frame(width: width + 12)
        .opacity(contentOpacity)
    }
}

// MARK: - Event Icon Row

private extension DayCell {

    /// Primary event: for today pick the active/next-upcoming; for other days pick the first.
    var primaryEvent: CalendarEvent? {
        guard !dayEvents.isEmpty else { return nil }
        if Calendar.current.isDateInToday(day) {
            let nowMins = Calendar.current.component(.hour, from: Date()) * 60
                        + Calendar.current.component(.minute, from: Date())
            if let active = dayEvents.first(where: {
                $0.startMinutes <= nowMins && $0.endMinutes >= nowMins
            }) { return active }
            return dayEvents.first(where: { $0.startMinutes >= nowMins }) ?? dayEvents.first
        }
        return dayEvents.first
    }

    var eventIconRow: some View {
        Group {
            if let primary = primaryEvent {
                let others = dayEvents
                    .filter { $0.id != primary.id }
                    .prefix(2)
                let left  = others.count > 0 ? others[0] : nil
                let right = others.count > 1 ? others[1] : nil
                let isToday = Calendar.current.isDateInToday(day)

                HStack(alignment: .center, spacing: 3) {

                    // Left side — smaller
                    if let l = left {
                        sideIcon(l)
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }

                    // Center — primary, larger + pulse on today
                    primaryIcon(primary, pulse: isToday)
                        .onAppear {
                            if isToday { isPulsing = true }
                        }

                    // Right side — smaller
                    if let r = right {
                        sideIcon(r)
                    } else {
                        Color.clear.frame(width: 14, height: 14)
                    }
                }
                .frame(height: 20)

            } else {
                Color.clear.frame(height: 20)
            }
        }
    }

    // Small flanking icon
    func sideIcon(_ event: CalendarEvent) -> some View {
        let size: CGFloat = 14
        let icon = EventIconStore.shared.icon(for: event.id) ?? event.originIcon
        return ZStack {
            Circle()
                .fill(event.eventColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(event.eventColor.opacity(0.85))
        }
        .shadow(color: event.eventColor.opacity(0.15), radius: 2)
    }

    // Large center icon, pulses on today
    func primaryIcon(_ event: CalendarEvent, pulse: Bool) -> some View {
        let size: CGFloat = 20
        let icon = EventIconStore.shared.icon(for: event.id) ?? event.originIcon
        return ZStack {
            // Glow ring
            Circle()
                .fill(event.eventColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                .frame(width: size + 6, height: size + 6)
                .blur(radius: pulse ? 4 : 2)
                .opacity(pulse ? (isPulsing ? 0.9 : 0.4) : 0.5)
                .animation(
                    pulse
                        ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            // Main circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            event.eventColor.opacity(0.85),
                            event.eventColor.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: event.eventColor.opacity(0.4), radius: pulse ? 5 : 3, y: 1)

            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(pulse && isPulsing ? 1.12 : 1.0)
        .animation(
            pulse
                ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
    }
}

// MARK: - Weekday Label

private extension DayCell {
    var weekdayLabel: some View {
        Text(day.formatted(.dateTime.weekday(.short)))
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - Day Circle

private extension DayCell {

    var dayCircle: some View {
        ZStack {
            Text(day.formatted(.dateTime.day()))
                .font(.headline.bold())
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: width, height: width)
                .background(circleBackground)
                .overlay(todayRing)
                .overlay(darkSelectedRing)
                .overlay(offDayIcon, alignment: .bottomTrailing)
                .dayCellShadow(scheme: colorScheme, isSelected: isSelected)
        }
    }

    @ViewBuilder
    var hintStack: some View {
        if unreadCount > 0 || hasNew {
            HStack(spacing: 0) {
                if unreadCount > 0 { unreadBadge }
                Spacer(minLength: 0)
                if hasNew { newEventBadge }
            }
            .frame(width: width - 8)
            .offset(y: 6)
        }
    }
}

// MARK: - Badges

private extension DayCell {

    var unreadBadge: some View {
        Text("\(unreadCount)")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.85)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            )
    }

    var newEventBadge: some View {
        Image(systemName: "sparkles")
            .font(.caption2)
            .foregroundStyle(
                LinearGradient(
                    colors: [uiAccent.color, uiAccent.color.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .padding(4)
            .background(
                Circle()
                    .fill(uiAccent.color.opacity(0.18))
                    .shadow(color: uiAccent.color.opacity(0.4), radius: 4)
            )
    }
}

// MARK: - Circle backgrounds / decorations

private extension DayCell {
    var circleBackground: some View {
        Group {
            if isSelected {
                Circle().fill(uiAccent.color)
            } else if isOffDay {
                Circle().fill(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10))
            } else if isPastDay {
                Circle().fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            }
        }
    }

    var todayRing: some View {
        Group {
            if Calendar.current.isDateInToday(day) && !isSelected {
                Circle().stroke(uiAccent.color, lineWidth: 1.5)
            }
        }
    }

    var darkSelectedRing: some View {
        Group {
            if isSelected && colorScheme == .dark {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
        }
    }

    var offDayIcon: some View {
        Group {
            if isOffDay && !isSelected {
                Image(systemName: "bed.double.fill")
                    .font(.caption)
                    .foregroundColor(uiAccent.color.opacity(0.8))
                    .offset(x: -2, y: -2)
            }
        }
    }

    var contentOpacity: Double {
        (isPastDay || isOffDay) && !isSelected ? 0.45 : 1
    }
}

// MARK: - Day Status Badge (kept for compatibility)

struct DayStatusBadgeView: View {

    let unreadCount: Int
    let hasNew: Bool
    @EnvironmentObject var uiAccent: UIAccentStore

    private var text: String {
        if unreadCount > 0 && hasNew {
            return String(format: String(localized: "day_badge_new_with_count"), unreadCount)
        }
        if unreadCount > 0 { return "\(unreadCount)" }
        return String(localized: "day_badge_new")
    }

    private var backgroundColor: Color {
        unreadCount > 0 ? .red : uiAccent.color
    }

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}
