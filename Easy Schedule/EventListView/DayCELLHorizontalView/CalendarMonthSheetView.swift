//
//  CalendarMonthSheetView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 24/1/26.
//
import SwiftUI

struct CalendarDay: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let day: Int
    let isInCurrentMonth: Bool
}


struct CalendarMonthSheetView: View {

    // MARK: - External binding (sau này gắn logic)
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date

    // MARK: - Internal
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = .current                // 🌍 theo ngôn ngữ hệ thống
        f.calendar = .current
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }

    @EnvironmentObject var eventManager: EventManager

    let maxSelectableDate: Date
    
    
    
    
    
    
    var body: some View {
        VStack(spacing: 16) {

            MonthYearHeader(
                month: displayedMonth,
                onPrev: { shiftMonth(-1) },
                onNext: { shiftMonth(1) }
            )

            WeekdayRow()

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(generateDays()) { day in
                    let date = day.date
                    let key = Calendar.current.startOfDay(for: date)

                    let isSelected =
                        Calendar.current.isDate(date, inSameDayAs: selectedDate) &&
                        Calendar.current.isDate(
                            date,
                            equalTo: displayedMonth,
                            toGranularity: .month
                        )
                    let isToday = Calendar.current.isDateInToday(date)
                    let isPastDay = key < Calendar.current.startOfDay(for: Date())
                    let isOffDay = eventManager.isOffDay(date)

                    let unread = eventManager.unreadCountByDay[key] ?? 0
                    let hasNew = eventManager.hasNewByDay[key] ?? false
                    let dayStart = Calendar.current.startOfDay(for: date)

                    let isOutOfRange = dayStart > maxSelectableDate
                    let isLocked = isPastDay || isOutOfRange

                    MonthGridDayView(
                        date: date,
                        isSelected: isSelected,
                        isToday: isToday,
                        isPastDay: isPastDay,
                        isOffDay: isOffDay,
                        isLocked: isLocked,
                        unreadCount: unread,
                        hasNew: hasNew,
                        isInCurrentMonth: day.isInCurrentMonth
                    ) {
                        selectedDate = date
                        dismiss()
                    }
                }


            }
            .padding(.horizontal, 16)

            Spacer(minLength: 12)
        }
        .padding(.top, 12)
        .presentationDetents(
            UIDevice.current.userInterfaceIdiom == .pad
            ? [.large]
            : [.medium, .large]
        )
       

        .presentationCornerRadius(32)
    }
}

struct MonthYearHeader: View {

    let month: Date
    let onPrev: () -> Void
    let onNext: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = .current
        f.calendar = .current
        f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return f
    }

    var body: some View {
        VStack(spacing: 8) {

            HStack {
                Button(action: onPrev) {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(formatter.string(from: month))
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                Spacer()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
            }

            Divider()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}


struct WeekdayRow: View {

    private var symbols: [String] {
        let calendar = Calendar.current
        let raw = calendar.shortStandaloneWeekdaySymbols

        // Sắp xếp theo firstWeekday
        let startIndex = calendar.firstWeekday - 1
        return Array(raw[startIndex...] + raw[..<startIndex])
    }

    var body: some View {
        HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }
}


struct MonthGridDayView: View {

    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isPastDay: Bool
    let isOffDay: Bool
    let isLocked: Bool

    let unreadCount: Int
    let hasNew: Bool
    let isInCurrentMonth: Bool
    let onTap: () -> Void

    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var scheme

    private var size: CGFloat {
        isPad ? 56 : 44
    }

    
    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        Button {
            guard !(isLocked || !isInCurrentMonth) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            ZStack {

                // Background semantic
                Circle()
                    .fill(backgroundColor)

                // Today ring
                if isToday && !isSelected {
                    Circle()
                        .stroke(uiAccent.color, lineWidth: 2)
                }

                // Day number
                Text(date.formatted(.dateTime.day()))
                    .font(
                        isPad
                        ? .system(size: 20, weight: .semibold, design: .rounded)
                        : .system(size: 17, weight: .semibold, design: .rounded)
                    )
                    .foregroundColor(textColor)

                // Off day icon (nhẹ)
                if isOffDay && !isSelected {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: isPad ? 12 : 9))
                            .offset(x: isPad ? 14 : 9, y: isPad ? 14 : 9)
                        .foregroundColor(uiAccent.color.opacity(0.8))
                        .offset(x: isPad ? 14 : 9, y: isPad ? 14 : 9)
                }

                // Unread / new dot (góc trên)
                if unreadCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(
                            width: isPad ? 8 : 6,
                            height: isPad ? 8 : 6
                        )
                        .offset(
                            x: isPad ? 14 : 10,
                            y: isPad ? -14 : -10
                        )

                } else if hasNew {
                    Circle()
                        .fill(uiAccent.color)
                        .frame(
                            width: isPad ? 8 : 6,
                            height: isPad ? 8 : 6
                        )
                        .offset(
                            x: isPad ? 14 : 10,
                            y: isPad ? -14 : -10
                        )

                }
            }
            .frame(width: size, height: size)
        }
        .disabled(isLocked || !isInCurrentMonth)                  // ⭐ KHÔNG TAP
        .opacity(finalOpacity)
        .buttonStyle(.plain)
        .shadow(
            color: isSelected ? Color.black.opacity(0.25) : .clear,
            radius: isSelected ? 5 : 0,
            y: isSelected ? 3 : 0
        )
    }
    private var finalOpacity: Double {
        if !isInCurrentMonth { return 0.25 }
        if isLocked && !isSelected { return 0.45 }
        return 1
    }

    private var backgroundColor: Color {
        if isSelected {
            return uiAccent.color
        }
        if isOffDay {
            return Color.primary.opacity(scheme == .dark ? 0.20 : 0.10)
        }
        if isPastDay {
            return Color.primary.opacity(scheme == .dark ? 0.12 : 0.06)
        }
        return Color.clear
    }

    private var textColor: Color {
        isSelected ? .white : .primary
    }
}







extension CalendarMonthSheetView {

    func shiftMonth(_ value: Int) {
        displayedMonth = Calendar.current.date(
            byAdding: .month,
            value: value,
            to: displayedMonth
        ) ?? displayedMonth
    }

    func generateDays() -> [CalendarDay] {
        let calendar = Calendar.current

        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstWeek.start)
            else { return nil }

            let isInMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

            return CalendarDay(
                date: date,
                day: calendar.component(.day, from: date),
                isInCurrentMonth: isInMonth
            )
        }
    }
}
