//
//  EventListView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Combine


struct EventListView: View {
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var guideManager: GuideManager

    @Binding var showPastEvents: Bool

    @AppStorage("showOwnerLabel") private var showOwnerLabel = true
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13
    @AppStorage("timeColorHex") private var timeColorHex: String = "#007AFF"
//NEW
    @State private var currentMonth: Date?
    
    @State private var selectedDate: Date = Date()

    
    
    
    
    var body: some View {
        ZStack {
            if showPastEvents {
                PastEventsView()
            } else {
                EventScrollContent(
                    events: eventManager.events,
                    showOwnerLabel: showOwnerLabel,
                    timeFontSize: timeFontSize,
                    timeColorHex: timeColorHex,
                    currentMonth: $currentMonth,
                    selectedDate: $selectedDate
                )
            }

            if guideManager.isActive(.eventsIntro) {
                EventsIntroOverlay()
            }
        }
    }
}







struct EventScrollContent: View {
    let events: [CalendarEvent]



    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String

    private var groupedByMonth: [Date: [CalendarEvent]] {
        EventGrouping.byMonth(events)
    }
//NEW
    
    @Binding var currentMonth: Date?
    @Binding var selectedDate: Date 
    
    
    
    
    
    
    
    
    
    var body: some View {
        ScrollView {

            BigDateHeaderView(
                date: selectedDate
            )

            HorizontalDayPickerView(
                selectedDate: $selectedDate
            )
            .padding(.bottom, 8)

            LazyVStack(alignment: .leading, spacing: 24) {

                ForEach(groupedByMonth.keys.sorted(), id: \.self) { month in
                    MonthSectionView(
                        month: month,
                        events: groupedByMonth[month] ?? [],
                        showOwnerLabel: showOwnerLabel,
                        timeFontSize: timeFontSize,
                        timeColorHex: timeColorHex,
                        currentMonth: currentMonth,
                        selectedDate: selectedDate
                    )
                }
            }
            .padding(.horizontal, 0)
            .padding(.bottom, 80)
            .onPreferenceChange(MonthHeaderPositionKey.self) { values in
                let sorted = values
                    .filter { $0.value > 0 }
                    .sorted { $0.value < $1.value }

                if let first = sorted.first {
                    if !Calendar.current.isDate(first.key, equalTo: selectedDate, toGranularity: .month) {
                        selectedDate = first.key
                    }
                }
            }
        }
    }


    private var horizontalPadding: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 48 : 16
    }
}



struct MonthSectionView: View {
    let month: Date
    let events: [CalendarEvent]



    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String

    private var groupedByWeek: [Int: [CalendarEvent]] {
        EventGrouping.byWeek(events)
    }
//NEW
    let currentMonth: Date?
    let selectedDate: Date   // ✅ thêm
    
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

                // Vẫn giữ Geometry để sync, nhưng không vẽ chữ
                Color.clear
                    .frame(height: 1)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: MonthHeaderPositionKey.self,
                                value: [month: geo.frame(in: .global).minY]
                            )
                        }
                    )
            



            ForEach(groupedByWeek.keys.sorted(), id: \.self) { week in
                WeekSectionView(
                    week: week,
                    events: groupedByWeek[week] ?? [],
                    showOwnerLabel: showOwnerLabel,
                    timeFontSize: timeFontSize,
                    timeColorHex: timeColorHex,
                    selectedDate: selectedDate
                )
            }
        }
    }
}

struct WeekSectionView: View {
    let week: Int
    let events: [CalendarEvent]

    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String
    let selectedDate: Date   // ✅ thêm

    private var groupedByDay: [Date: [CalendarEvent]] {
        EventGrouping.byDay(events)
    }

    private var filteredDays: [Date] {
        groupedByDay.keys
            .filter {
                Calendar.current.isDate($0, inSameDayAs: selectedDate)
            }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            ForEach(filteredDays, id: \.self) { day in
                DaySectionView(
                    day: day,
                    dayEvents: groupedByDay[day] ?? [],
                    showOwnerLabel: showOwnerLabel,
                    timeFontSize: timeFontSize,
                    timeColorHex: timeColorHex
                 
                )
            }
        }
    }
}


private struct DaySectionView: View {

    let day: Date
    let dayEvents: [CalendarEvent]
  
    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

//new
    
    @State private var expandedEvents: Set<String> = []

    private func isExpanded(_ event: CalendarEvent) -> Bool {
        expandedEvents.contains(event.id)
    }

 


    
    
    
    

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            headerView

          
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dayEvents.sorted { $0.startTime < $1.startTime }) { event in
                        EventRowView(
                            event: event,
                            showOwnerLabel: showOwnerLabel,
                            timeFontSize: timeFontSize,
                            timeColorHex: timeColorHex,
                            expandedEvents: $expandedEvents,
                            chatMeta: eventManager.chatMeta(for: event.id)
                        )
                    }

                }
                .padding(.leading, 16)
            
            
        }
        .padding(.vertical, 8)

    }


}
private extension DaySectionView {

    var unreadCountForDay: Int {
        eventManager.unreadCount(for: day)
    }

    var hasNewEventForDay: Bool {
        eventManager.hasNewEvent(for: day)
    }
}









private extension DaySectionView {

    var headerView: some View {
        HStack {
            Spacer()

            if unreadCountForDay > 0 || hasNewEventForDay {
                DayStatusBadgeView(
                    unreadCount: unreadCountForDay,
                    hasNew: hasNewEventForDay
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}











private extension DaySectionView {


    func timeText(for event: CalendarEvent) -> some View {
        let duration = event.endTime.timeIntervalSince(event.startTime)
        let minutes = Int(duration / 60)

        return VStack(alignment: .leading, spacing: 2) {

            Text(event.startTime.formatted(date: .omitted, time: .shortened))
                .font(.system(size: CGFloat(timeFontSize), weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: timeColorHex))

            Text("\(minutes) min")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(hex: timeColorHex))
                .frame(width: 2)
        }
    }


    func metadataAttributedText(for event: CalendarEvent) -> AttributedString {
        var result = AttributedString("")

        // ⏰ TIME
        var time = AttributedString(
            "\(event.startTime.formatted(date: .omitted, time: .shortened))" +
            "–" +
            "\(event.endTime.formatted(date: .omitted, time: .shortened))"
        )
        time.font = .system(size: CGFloat(timeFontSize))
        time.foregroundColor = Color(hex: timeColorHex)

        result += time

        // 👤 OWNER
        if showOwnerLabel {
            var ownerText = AttributedString(" · ")

            if event.origin == .iCreatedForOther {
                let ownerName = displayName(
                    for: event,
                    uid: event.owner,
                    eventManager: eventManager
                )
                ownerText += AttributedString("You → \(ownerName)")
            } else {
                let name = displayName(
                    for: event,
                    uid: event.createdBy,
                    eventManager: eventManager
                )
                ownerText += AttributedString(name)
            }

            ownerText.font = .caption
            ownerText.foregroundColor = .secondary

            result += ownerText
        }

        return result
    }

    
    
    
}


struct UserNameView: View {
    @EnvironmentObject var eventManager: EventManager
    let uid: String
    @State private var name: String = ""
    
    var body: some View {
        Text(name.isEmpty ? uid : name)
            .onAppear {
                eventManager.name(for: uid) { fetched in
                    self.name = fetched
                }
            }
    }
}

struct DayPositionKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(
        value: inout [Date: CGFloat],
        nextValue: () -> [Date: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
struct EventsIntroOverlay: View {
    var body: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .overlay(
                Text("Events intro")
                    .foregroundColor(.white)
            )
    }
}
struct PastEventsView: View {
    var body: some View {
        Text("Past events")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}
