//
//  CalendarMiniView.swift
//  Easy Schedule
//
import SwiftUI
import Foundation

// MARK: - Mini calendar
struct CalendarMiniView: View {
    @Binding var selectedDate: Date
    let busySlots: [CalendarEvent]
    let offDays: Set<Date>
    let maxBookingDays: Int

    @State private var month: Date = Date()

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday first
        return c
    }

    private var maxSelectableDate: Date {
        let raw = calendar.date(byAdding: .day, value: maxBookingDays, to: Date())!
        return calendar.startOfDay(for: raw)
    }

    // Weekday column symbols starting from Monday
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols // index 0 = Sunday
        let start = calendar.firstWeekday - 1          // 1 → Monday (0-based)
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    var body: some View {
        VStack(spacing: 10) {
            // ── Month navigator ──────────────────────────────────────────
            HStack {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(formattedMonth(month))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // ── Weekday header row ───────────────────────────────────────
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                }
            }
            .padding(.horizontal, 12)

            // ── Day cells ────────────────────────────────────────────────
            let days = daysInMonth(for: month)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 6
            ) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, maybeDay in
                    if let day = maybeDay {
                        let dayStart    = calendar.startOfDay(for: day)
                        let today       = calendar.startOfDay(for: Date())
                        let isPast      = dayStart < today
                        let outOfRange  = dayStart > maxSelectableDate
                        let isToday     = calendar.isDateInToday(day)
                        let isSelected  = calendar.isDate(selectedDate, inSameDayAs: day)
                        let isBusy      = busySlots.contains { calendar.isDate($0.date, inSameDayAs: day) }
                        let isOffDay    = offDays.contains(dayStart)

                        MiniCalDayCell(
                            day: day,
                            calendar: calendar,
                            isToday: isToday,
                            isSelected: isSelected,
                            isBusy: isBusy,
                            isOffDay: isOffDay,
                            isPast: isPast,
                            outOfRange: outOfRange
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !isPast, !outOfRange else { return }
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                selectedDate = day
                            }
                        }
                    } else {
                        Color.clear
                            .frame(height: 34)
                    }
                }
            }
            .padding(.horizontal, 12)

            // ── Legend ───────────────────────────────────────────────────
            HStack(spacing: 18) {
                legendItem(color: Color.red.opacity(0.55),    label: "Busy")
                legendItem(color: Color.orange.opacity(0.65), label: "Day off")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: – Helpers

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private func changeMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            withAnimation(.easeInOut(duration: 0.18)) { month = next }
        }
    }

    /// Returns days of the month prefixed with `nil` placeholders so the
    /// first day aligns to the correct weekday column.
    private func daysInMonth(for date: Date) -> [Date?] {
        guard
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)),
            let range = calendar.range(of: .day, in: .month, for: date)
        else { return [] }

        let weekdayOfFirst = calendar.component(.weekday, from: monthStart)
        let leadingBlanks  = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for i in range {
            if let d = calendar.date(byAdding: .day, value: i - 1, to: monthStart) {
                days.append(d)
            }
        }
        return days
    }
}

// MARK: - Mini Calendar Day Cell (named to avoid conflict with HorizontalDayPickerView.DayCell)

private struct MiniCalDayCell: View {
    let day:         Date
    let calendar:    Calendar
    let isToday:     Bool
    let isSelected:  Bool
    let isBusy:      Bool
    let isOffDay:    Bool
    let isPast:      Bool
    let outOfRange:  Bool

    private var dayNumber: Int { calendar.component(.day, from: day) }

    private var bgFill: Color {
        if isSelected { return Color.accentColor }
        if isOffDay   { return Color.orange.opacity(0.22) }
        if isBusy     { return Color.red.opacity(0.13) }
        if isToday    { return Color.accentColor.opacity(0.14) }
        return Color.clear
    }

    private var fgColor: Color {
        if isSelected           { return .white }
        if isPast || outOfRange { return Color(.tertiaryLabel) }
        if isToday              { return Color.accentColor }
        return .primary
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(bgFill)
                .frame(width: 34, height: 34)

            if isSelected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: 34, height: 34)
            } else if isToday {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 34, height: 34)
            }

            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(
                        size: 13,
                        weight: isSelected || isToday ? .semibold : .regular
                    ))
                    .foregroundStyle(fgColor)

                // Tiny busy dot below the number
                if isBusy && !isSelected && !isPast && !outOfRange {
                    Circle()
                        .fill(Color.red.opacity(0.7))
                        .frame(width: 3.5, height: 3.5)
                } else {
                    Color.clear.frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(height: 40)
        .opacity(isPast || outOfRange ? 0.35 : 1.0)
    }
}
