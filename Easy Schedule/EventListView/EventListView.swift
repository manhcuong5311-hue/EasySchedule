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

    @AppStorage("showOwnerLabel") private var showOwnerLabel = true
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13
//NEW

    
    @State private var selectedDate: Date = Date()

    @State private var showDisplaySettings = false

    @AppStorage("event_time_display_mode")
    private var timeDisplayModeRaw: String = EventTimeDisplayMode.timeRange.rawValue


    private var timeDisplayMode: EventTimeDisplayMode {
        EventTimeDisplayMode(rawValue: timeDisplayModeRaw) ?? .timeRange
    }

    
    @EnvironmentObject var uiAccent: UIAccentStore

//NEWWWWWW
    @State private var selectedPastWeek: WeekKey?

    @State private var showAddSheet = false
    @State private var shareItem: ShareItem?
    let onBookPartner: () -> Void
    
    @State private var forceShowEventsGuide = false

    
    
    private func week(from date: Date) -> WeekKey {
        let cal = Calendar.current
        return WeekKey(
            year: cal.component(.yearForWeekOfYear, from: date),
            week: cal.component(.weekOfYear, from: date)
        )
    }


    private var eventsIntroOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guideManager.complete(.eventsIntro)
                    }

                VStack {
                    GuideBubble(
                        textKey: "events_guide_intro",
                        onNext: {
                            // 1️⃣ TẮT KÍCH HOẠT CỤC BỘ
                            forceShowEventsGuide = false

                            // 2️⃣ NẾU GUIDE ĐANG ACTIVE THẬT → COMPLETE
                            if guideManager.isActive(.eventsIntro) {
                                guideManager.complete(.eventsIntro)
                            }
                        },
                        onDoNotShowAgain: {
                            // 1️⃣ TẮT KÍCH HOẠT CỤC BỘ
                            forceShowEventsGuide = false

                            // 2️⃣ DISABLE PERMANENT
                            guideManager.disablePermanently(.eventsIntro)
                        }
                    )
                    .frame(maxWidth: min(420, geo.size.width * 0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 140)
            }
        }
    }


    
    
    
    var body: some View {
        ZStack {
           
                EventScrollContent(
                    events: eventManager.events,
                    showOwnerLabel: showOwnerLabel,
                    timeFontSize: timeFontSize,
                    selectedDate: $selectedDate,

                    // ⭐ ADD EVENT
                    onAddEvent: {
                        showAddSheet = true
                    },

                    // ⭐ SHARE CALENDAR
                    onShareCalendar: {
                        if let uid = session.currentUserId,
                           let url = URL(
                               string: "https://easyschedule-ce98a.web.app/calendar/\(uid)"
                           ) {
                            shareItem = ShareItem(url: url)
                        }
                    },   // 👈 👈 👈 DẤU PHẨY BỊ THIẾU

                    // ⭐ BOOK PARTNER
                    onBookPartner: onBookPartner  ,
                    timeDisplayMode: timeDisplayMode
                )


            

            if guideManager.isActive(.eventsIntro) || forceShowEventsGuide {
                eventsIntroOverlay
            }

        }
        .onChange(of: guideManager.activeGuide) { _, newGuide in
            if newGuide == .calendarIntro {
                forceShowEventsGuide = true
            }
        }

        .onAppear {
            guideManager.startIfNeeded()   // ⭐ DÒNG QUAN TRỌNG
        }
        // ⭐ NÚT EDIT Ở GÓC PHẢI
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDisplaySettings = true
                } label: {
                    Image(systemName: "paintpalette")
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }

        .sheet(isPresented: $showAddSheet) {
            AddEventView(
                prefillDate: selectedDate,
                offDays: [],          // EventListView KHÔNG QUẢN → để rỗng
                busyHours: []         // EventListView KHÔNG QUẢN → để rỗng
            )
            .environmentObject(eventManager)
            .environmentObject(session)
        }

        .sheet(isPresented: $showDisplaySettings) {
            DisplaySettingsSheet()
        }
        .onChange(of: selectedDate) { _, newDate in

            // ⭐ 1️⃣ ĐÁNH DẤU ĐÃ XEM EVENT TRONG NGÀY (XOÁ DOT NEW)
            eventManager.markDayEventsAsSeen(newDate)

            // ⭐ 2️⃣ LOGIC CŨ CỦA BẠN – GIỮ NGUYÊN
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let selected = cal.startOfDay(for: newDate)

            if selected < today {
                selectedPastWeek = week(from: newDate)
            }
        }

    .sheet(item: $selectedPastWeek) { week in
            PastWeeklySummaryView(week: (year: week.year, week: week.week))
                .environmentObject(eventManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }

    }
    
    
    
    
    
    
    
    
    
}







struct EventScrollContent: View {
    let events: [CalendarEvent]



    let showOwnerLabel: Bool
    let timeFontSize: Double

    private var groupedByMonth: [Date: [CalendarEvent]] {
        EventGrouping.byMonth(events)
    }
//NEW
    
    @Binding var selectedDate: Date 
    
    let onAddEvent: () -> Void
    let onShareCalendar: () -> Void
    let onBookPartner: () -> Void
    let timeDisplayMode: EventTimeDisplayMode

    private var eventsForSelectedDay: [CalendarEvent] {
        events.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
    }
    
    
    
    
    
    var body: some View {
        ScrollView {

            BigDateHeaderView(
                date: selectedDate
            )

            HorizontalDayPickerView(
                selectedDate: $selectedDate
            )
            .padding(.bottom, 8)

            if eventsForSelectedDay.isEmpty {

                EmptyEventsStateView(
                       onAdd: onAddEvent,
                       onShare: onShareCalendar,
                       onBookPartner: onBookPartner
                   )

            } else {

                LazyVStack(alignment: .leading, spacing: 24) {

                    ForEach(groupedByMonth.keys.sorted(), id: \.self) { month in
                        MonthSectionView(
                            month: month,
                            events: groupedByMonth[month] ?? [],
                            showOwnerLabel: showOwnerLabel,
                            timeFontSize: timeFontSize,
                            selectedDate: selectedDate,
                            timeDisplayMode: timeDisplayMode
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
       
    }

}



struct MonthSectionView: View {
    let month: Date
    let events: [CalendarEvent]



    let showOwnerLabel: Bool
    let timeFontSize: Double


    private var groupedByWeek: [Int: [CalendarEvent]] {
        EventGrouping.byWeek(events)
    }
//NEW
    let selectedDate: Date   // ✅ thêm
    let timeDisplayMode: EventTimeDisplayMode

    
    
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
                    selectedDate: selectedDate,
                    timeDisplayMode: timeDisplayMode
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
    let selectedDate: Date   // ✅ thêm
    let timeDisplayMode: EventTimeDisplayMode

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
                    timeDisplayMode: timeDisplayMode   // ⭐ THÊM
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
    let timeDisplayMode: EventTimeDisplayMode
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

//new
    
    @State private var expandedEvents: Set<String> = []

    private func isExpanded(_ event: CalendarEvent) -> Bool {
        expandedEvents.contains(event.id)
    }


    @EnvironmentObject var uiAccent: UIAccentStore

    
    
    
    

    var body: some View {

        let unreadCount = eventManager.unreadCount(for: day)
        let hasNew = eventManager.hasNewEvent(for: day)

        VStack(alignment: .leading, spacing: 8) {

            headerView(
                unreadCount: unreadCount,
                hasNew: hasNew
            )

            VStack(alignment: .leading, spacing: 6) {
                ForEach(dayEvents.sorted { $0.startTime < $1.startTime }) { event in
                    EventRowView(
                        event: event,
                        showOwnerLabel: showOwnerLabel,
                        timeFontSize: timeFontSize,
                        expandedEvents: $expandedEvents,
                        chatMeta: eventManager.chatMeta(for: event.id),
                        timeDisplayMode: timeDisplayMode   // ✅ DÙNG MODE MỚI
                    )

                }
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 8)
    }



}










private extension DaySectionView {

    func headerView(
        unreadCount: Int,
        hasNew: Bool
    ) -> some View {

        HStack {
            Spacer()

            if unreadCount > 0 || hasNew {
                DayStatusBadgeView(
                    unreadCount: unreadCount,
                    hasNew: hasNew
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
