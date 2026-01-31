//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 31/1/26.
//
import SwiftUI
import Combine
import FirebaseAuth

enum CalendarExpandMode {
    case collapsed
    case expanded
}


struct CalendarGridView: View {
    @Binding var selectedDate: Date?
    let eventsByDay: [Date: [CalendarEvent]]
    @EnvironmentObject var eventManager: EventManager
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    let offDays: Set<Date>
    let isOwner: Bool
    // Alert trạng thái chung, riêng cho CalendarGridView
    @State private var showOffDayAlert = false
    let maxBookingDays: Int
    private var maxSelectableDate: Date {
        let raw = calendar.date(
            byAdding: .day,
            value: maxBookingDays,
            to: Date()
        )!
        return calendar.startOfDay(for: raw)
    }

    //NEWWWWW
    @State private var showWeekView = false

    
    
    
    
    
    var body: some View {
        VStack(spacing: 8) {
            // MARK: - Header tháng
            HStack {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(formattedMonth(currentMonth))
                        .font(.headline)

                    Button {
                        showWeekView = true
                    } label: {
                        Image(systemName: "rectangle.split.3x1")
                            .font(.caption.weight(.semibold))
                    }
                }

                Spacer()

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
            }

            .padding(.horizontal)
            
            // MARK: - Tên thứ trong tuần
            HStack {
                let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols[1...6]) + [calendar.veryShortStandaloneWeekdaySymbols[0]]
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }

            }
            
            // MARK: - Lưới ngày
            LazyVGrid(columns: columns, spacing: 12) {
                let allDays = daysInMonth(for: currentMonth)
                    .map { calendar.startOfDay(for: $0) }

                if let firstDay = allDays.first {
                    let weekday = calendar.component(.weekday, from: firstDay)
                    let emptySlots = weekday - calendar.firstWeekday
                    if emptySlots > 0 {
                        ForEach(0..<emptySlots, id: \.self) { idx in
                            Text("")
                                .id("empty_\(currentMonth)_\(idx)") // ép ID duy nhất
                        }
                    }
                }
                
                // Hiển thị các ngày trong tháng
                ForEach(allDays.indices, id: \.self) { index in
                    let date = allDays[index]
                    let dayStart = calendar.startOfDay(for: date)
                    let today = calendar.startOfDay(for: Date())

                    let isPast = dayStart < today
                    let isOutOfRange = dayStart > maxSelectableDate
                    let isLocked = isPast || isOutOfRange

                    let day = calendar.component(.day, from: date)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isOffDay = offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) })

                    VStack(spacing: 4) {
                        Text("\(day)")
                            .font(.body)
                            .foregroundColor(isLocked ? .secondary : .primary)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(
                                        isSelected
                                        ? Color.accentColor.opacity(0.25)
                                        : (isOffDay
                                            ? Color.gray.opacity(0.4)
                                            : (isToday
                                                ? Color.green.opacity(0.3)
                                                : Color.clear)
                                        )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        isSelected ? Color.accentColor : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )



                        let key = calendar.startOfDay(for: date)
                        let events = eventsByDay[key] ?? []

                        VStack(spacing: 2) {
                            // Dot màu theo sự kiện đầu tiên
                            Circle()
                                .frame(width: 6, height: 6)
                                .foregroundColor(events.isEmpty ? .clear : Color(hex: events.first!.colorHex))

                            // Số lượng sự kiện
                            if events.count > 1 {
                                Text("\(events.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }


                    }
                    .opacity(isLocked ? 0.35 : 1.0)

                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isLocked else { return }

                        let key = calendar.startOfDay(for: date)

                        if !isOwner, offDays.contains(key) {
                            showOffDayAlert = true
                        } else {
                            selectedDate = date
                        }
                    }
                    .allowsHitTesting(!isLocked)


                }

            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showWeekView) {
            WeekPagerView(
                selectedDate: $selectedDate,
                eventsByDay: eventsByDay,
                offDays: offDays,
                isOwner: isOwner,
                maxBookingDays: maxBookingDays
            )
        }

        // ✅ Alert riêng cho CalendarGridView (ngày nghỉ)
        .alert(String(localized: "cannot_book"), isPresented: $showOffDayAlert) {
            Button(String(localized: "close"), role: .cancel) {}
        } message: {
            Text(String(localized: "day_off_message_full"))
        }
    }
    
    // MARK: - Month navigation
    @State private var currentMonth: Date = Date()
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    // MARK: - Ngày trong tháng
    private func daysInMonth(for date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }
    
    // MARK: - Định dạng tháng
    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

}

struct WeekPagerView: View {

    @Binding var selectedDate: Date?
    let eventsByDay: [Date: [CalendarEvent]]
    let offDays: Set<Date>
    let isOwner: Bool
    let maxBookingDays: Int

    private let calendar = Calendar.current
    @Environment(\.dismiss) private var dismiss

    @State private var currentWeekStart: Date
    @State private var showRotateHint = false

    init(
        selectedDate: Binding<Date?>,
        eventsByDay: [Date: [CalendarEvent]],
        offDays: Set<Date>,
        isOwner: Bool,
        maxBookingDays: Int
    ) {
        self._selectedDate = selectedDate
        self.eventsByDay = eventsByDay
        self.offDays = offDays
        self.isOwner = isOwner
        self.maxBookingDays = maxBookingDays

        let base = Calendar.current.startOfWeek(for: selectedDate.wrappedValue ?? Date())
        _currentWeekStart = State(initialValue: base)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentWeekStart) {
                ForEach(weeksAroundReference, id: \.self) { weekStart in
                    WeekRowView(
                        weekStart: weekStart,
                        selectedDate: $selectedDate,
                        eventsByDay: eventsByDay,
                        offDays: offDays,
                        isOwner: isOwner,
                        maxBookingDays: maxBookingDays
                    )
                    .tag(weekStart)
                    .padding(.top)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("Week View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showRotateHint = true
                    } label: {
                        Image(systemName: "iphone.landscape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }

        }
        .alert("Rotate your device", isPresented: $showRotateHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Rotate your phone to landscape for a wider and clearer week view.")
        }
        .onAppear {
            guard !showRotateHint else { return }

            if !UserDefaults.standard.bool(forKey: "didShowRotateHint") {
                showRotateHint = true
                UserDefaults.standard.set(true, forKey: "didShowRotateHint")
            }
        }


    }

    private var weeksAroundReference: [Date] {
        (-8...8).compactMap {
            calendar.date(byAdding: .weekOfYear, value: $0, to: currentWeekStart)
        }
    }

}


struct WeekRowView: View {

    let weekStart: Date
    @Binding var selectedDate: Date?

    let eventsByDay: [Date: [CalendarEvent]]
    let offDays: Set<Date>
    let isOwner: Bool
    let maxBookingDays: Int

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text(weekTitle)
                .font(.headline)
                .padding(.horizontal)

            TabView {
                dayPage(days: Array(daysInWeek.prefix(4)))
                dayPage(days: Array(daysInWeek.dropFirst(4)))
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
        }
    }

    private func dayPage(days: [Date]) -> some View {
        HStack(spacing: 12) {
            ForEach(days, id: \.self) { date in
                WeekDayCard(
                    date: date,
                    selectedDate: $selectedDate,
                    events: eventsByDay[calendar.startOfDay(for: date)] ?? [],
                    isOffDay: offDays.contains {
                        calendar.isDate($0, inSameDayAs: date)
                    },
                    isOwner: isOwner,
                    maxBookingDays: maxBookingDays
                )
            }
        }
        .padding(.horizontal)
    }

    private var daysInWeek: [Date] {
        (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private var weekTitle: String {
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return "\(weekStart.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}


struct WeekDayCard: View {

    let date: Date
    @Binding var selectedDate: Date?

    let events: [CalendarEvent]
    let isOffDay: Bool
    let isOwner: Bool
    let maxBookingDays: Int

    private let calendar = Calendar.current

    var body: some View {
        let dayStart = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())
        let isLocked = dayStart < today ||
            dayStart > calendar.startOfDay(
                for: calendar.date(byAdding: .day, value: maxBookingDays, to: Date())!
            )

        VStack(alignment: .leading, spacing: 8) {

            // ===== HEADER =====
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(calendar.component(.day, from: date))")
                    .font(.title2.bold())
            }

            Divider()

            // ===== EVENT LIST (SCROLLABLE) =====
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {

                    if events.isEmpty {
                        Text("No events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    } else {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(Color(hex: event.colorHex))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)

                                Text(event.title)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    calendar.isDate(selectedDate ?? Date(), inSameDayAs: date)
                    ? Color.accentColor.opacity(0.15)
                    : Color(.secondarySystemBackground)
                )
        )
        .opacity(isLocked ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLocked else { return }
            selectedDate = date
        }
    }
}


extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)!.start
    }
}
