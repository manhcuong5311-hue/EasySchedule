//
//  CalendarMiniView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Foundation

// MARK: - Mini calendar (unchanged logic)
struct CalendarMiniView: View {
    @Binding var selectedDate: Date
    let busySlots: [CalendarEvent]
    let offDays: Set<Date>
    let maxBookingDays: Int
    @State private var month: Date = Date()
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }
    private var maxSelectableDate: Date {
        let raw = calendar.date(
            byAdding: .day,
            value: maxBookingDays,
            to: Date()
        )!
        return calendar.startOfDay(for: raw)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(formattedMonth(month)).font(.headline)
                Spacer()
                Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            let days = daysInMonth(for: month)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let dayStart = calendar.startOfDay(for: day)
                    let today = calendar.startOfDay(for: Date())

                    let isPast = dayStart < today
                    let isOutOfRange = dayStart > maxSelectableDate

                    let isToday = Calendar.current.isDateInToday(day)
                    let isSelected = Calendar.current.isDate(selectedDate, inSameDayAs: day)
                    let isBusy = busySlots.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })
                    let isOffDay = offDays.contains(Calendar.current.startOfDay(for: day))

                    VStack {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.body)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(
                                        isSelected
                                        ? Color.clear                       // selected: chỉ viền
                                        : (isOffDay
                                            ? Color.orange.opacity(0.35)   // ngày nghỉ
                                            : (isBusy
                                                ? Color.red.opacity(0.18)  // 🔴 ngày có lịch bận (nhẹ)
                                                : (isToday
                                                    ? Color.blue.opacity(0.25) // hôm nay
                                                    : Color.clear)))
                                    )
                            )

                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ? Color.accentColor : Color.clear,
                                        lineWidth: 2                      // ✅ khoanh vòng rõ
                                    )
                            )
                            .foregroundColor(
                                isSelected
                                ? Color.accentColor
                                : (isToday ? Color.blue : .primary)
                            )

                    }
                    .opacity(isPast || isOutOfRange ? 0.35 : 1.0)

                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isPast && !isOutOfRange else { return }
                        selectedDate = day
                    }

                }
            }

            .padding(.horizontal)
        }
    }

    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }


    private func changeMonth(by v: Int) {
        if let n = calendar.date(byAdding: .month, value: v, to: month) { month = n }
    }

    private func daysInMonth(for date: Date) -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }
}
