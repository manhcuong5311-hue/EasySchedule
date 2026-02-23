//
//  EventListView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Combine

enum ActiveSheet1: Identifiable {
    case monthPicker
    case addEvent
    case share(ShareItem)
    case displaySettings
    case pastWeek(WeekKey)

    var id: String {
        switch self {
        case .monthPicker: return "month"
        case .addEvent: return "add"
        case .share: return "share"
        case .displaySettings: return "display"
        case .pastWeek(let w): return "week-\(w.year)-\(w.week)"
        }
    }
}


struct EventListView: View {
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var guideManager: GuideManager

    @AppStorage("showOwnerLabel") private var showOwnerLabel = true
    @AppStorage("timeFontSize_v2")
    private var timeFontSize: Int = 13

//NEW

    
    @State private var selectedDate: Date = Date()

 

    @AppStorage("event_time_display_mode")
    private var timeDisplayModeRaw: String = EventTimeDisplayMode.timeRange.rawValue


    private var timeDisplayMode: EventTimeDisplayMode {
        EventTimeDisplayMode(rawValue: timeDisplayModeRaw) ?? .timeRange
    }


    @EnvironmentObject var uiAccent: UIAccentStore

//NEWWWWWW

    let onBookPartner: () -> Void
    
    @State private var forceShowEventsGuide = false

    private var maxSelectableDate: Date {
        let cal = Calendar.current
        let days =
            PremiumLimits
                .limits(for: PremiumStoreViewModel.shared.tier)
                .maxBookingDaysAhead

        let raw = cal.date(byAdding: .day, value: days, to: Date())!
        return cal.startOfDay(for: raw)
    }

    
    private func week(from date: Date) -> WeekKey {
        let cal = Calendar.current
        return WeekKey(
            year: cal.component(.yearForWeekOfYear, from: date),
            week: cal.component(.weekOfYear, from: date)
        )
    }
    @State private var activeSheet: ActiveSheet1?
    @State private var monthCursor: Date = Date()
    @State private var isMonthPickerOpen = false

//NEWWWWWW
    @State private var didUserSelectDate = false

    
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
                timeFontSize: Double(timeFontSize),
                selectedDate: $selectedDate,

                onAddEvent: {
                    activeSheet = .addEvent
                },

                onShareCalendar: {
                    if let uid = session.currentUserId,
                       let url = URL(
                           string: "https://easyschedule-ce98a.web.app/calendar/\(uid)"
                       ) {
                        activeSheet = .share(ShareItem(url: url))
                    }
                },

                onBookPartner: onBookPartner,
                
                onViewSummary: { date in
                      activeSheet = .pastWeek(week(from: date))
                  },

                maxSelectableDate: maxSelectableDate,   // ✅ ĐƯA LÊN TRƯỚC

                timeDisplayMode: timeDisplayMode,

                isMonthPickerOpen: $isMonthPickerOpen,
                
                onOpenMonthPicker: {
                       isMonthPickerOpen = true
                       activeSheet = .monthPicker
                   },
                
                onOpenDisplaySettings: {
                      activeSheet = .displaySettings
                  },
                onUserSelectDay: {
                      didUserSelectDate = true   // ✅ SET ĐÚNG FLAG
                  }
                 
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
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {

            case .monthPicker:
                CalendarMonthSheetView(
                    selectedDate: $selectedDate,
                    displayedMonth: $monthCursor,
                    maxSelectableDate: maxSelectableDate
                )
                .environmentObject(eventManager)
                .onDisappear {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isMonthPickerOpen = false   // ⭐ CHEVRON QUAY LẠI
                    }
                }




            case .addEvent:
                AddEventView(
                    prefillDate: selectedDate,
                    offDays: [],
                    busyHours: []
                )
                .environmentObject(eventManager)
                .environmentObject(session)

            case .share(let item):
                ActivityView(activityItems: [item.url])

            case .displaySettings:
                DisplaySettingsSheet()

            case .pastWeek(let week):
                PastWeeklySummaryView(
                    week: (year: week.year, week: week.week)
                )
                .environmentObject(eventManager)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }

        .onChange(of: selectedDate) { _, newDate in

            guard didUserSelectDate else { return }   // ⭐ CHẶN RESET ẢO

            eventManager.markDayEventsAsSeen(newDate)

            didUserSelectDate = false                 // ⭐ RESET FLAG

            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let selected = cal.startOfDay(for: newDate)

            if selected < today {
                activeSheet = .pastWeek(week(from: newDate))
            }
        }

   
    }
    
    
    
    
  
    
    
    
    
}







struct EventScrollContent: View {
    
    let events: [CalendarEvent]
    let showOwnerLabel: Bool
    let timeFontSize: Double
    
    @Binding var selectedDate: Date
    
    let onAddEvent: () -> Void
    let onShareCalendar: () -> Void
    let onBookPartner: () -> Void
    let onViewSummary: (Date) -> Void
    let maxSelectableDate: Date
    let timeDisplayMode: EventTimeDisplayMode
    
    @Binding var isMonthPickerOpen: Bool
    let onOpenMonthPicker: () -> Void
    let onOpenDisplaySettings: () -> Void

    
    
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isPad: Bool {
        hSizeClass == .regular
    }

    
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore
   
    @Environment(\.colorScheme) private var scheme
    
    private var eventsOfSelectedDay: [CalendarEvent] {
        events
            .filter {
                Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
            }
            .sorted { $0.startTime < $1.startTime }
    }
    
    private var isOffDay: Bool {
        eventManager.isOffDay(selectedDate)
    }
   
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.normal.rawValue

    private var cardLayout: EventCardLayout {
        EventCardLayout(rawValue: cardLayoutRaw) ?? .normal
    }

    let onUserSelectDay: () -> Void

    private let headerHeight: CGFloat = 56
    private let dayPickerHeight: CGFloat = 92
    private let topSpacing: CGFloat = 40
    private var dayCardInset: CGFloat {
        isPad ? 12 : 8
    }
    
    private var bottomCardInset: CGFloat {
        isPad ? 16 : 12
    }

    var body: some View {
        GeometryReader { geo in

            let availableHeight = max(
                0,
                geo.size.height
                    - headerHeight
                    - dayPickerHeight
            )

            VStack(spacing: 0) {

                headerBar
                    .frame(height: headerHeight)

                HorizontalDayPickerView(
                    selectedDate: $selectedDate,
                    maxSelectableDate: maxSelectableDate,
                    onUserSelectDay: { _ in
                        onUserSelectDay()
                    }
                )
                .frame(height: dayPickerHeight)

                dayCard
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: availableHeight
                    )
            }
         
            .background(
                AppBackground.settings(scheme)
                    .ignoresSafeArea()
            )
        }
    }





    
    
    
    private var dayCard: some View {

        // 1️⃣ Chiều cao hint cố định (chrome, không phải content)
        let hintHeight: CGFloat = isPad ? 36 : 24

        return ZStack(alignment: .top) {

            // ===== SCROLL CONTENT =====
            ScrollView {

                VStack(spacing: 0) {


                    if eventsOfSelectedDay.isEmpty {

                        if isOffDay {
                            OffDayEmptyStateView(
                                date: selectedDate,
                                onViewSummary: {
                                    onViewSummary(selectedDate)
                                }
                            )
                        } else {
                            EmptyEventsStateView(
                                onAdd: onAddEvent,
                                onShare: onShareCalendar,
                                onBookPartner: onBookPartner
                            )
                        }

                    } else {
                        DaySectionView(
                            day: selectedDate,
                            dayEvents: eventsOfSelectedDay,
                            showOwnerLabel: showOwnerLabel,
                            timeFontSize: timeFontSize,
                            timeDisplayMode: timeDisplayMode,
                            onAddEvent: onAddEvent,
                            onShareCalendar: onShareCalendar,
                            onBookPartner: onBookPartner
                        )
                        .padding(.bottom, 16)
                    }
                }
                .padding(.bottom, AppLayout.floatingTabBarHeight + 12)
            }

            // ===== HINT (OVERLAY – KHÔNG BAO GIỜ BỊ CHE) =====
        }
        .background(
            AppBackground.card(scheme)
                .ignoresSafeArea(edges: .bottom)
        )

        .clipShape(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(
            color: AppBackground.panelShadow(scheme),
            radius: 12,
            y: -2
        )
    }


    
    private var headerBar: some View {
        HStack {

            BigDateHeaderView(
                date: selectedDate,
                isExpanded: $isMonthPickerOpen
            ) {
                isMonthPickerOpen = true
                onOpenMonthPicker()
            }

            Spacer()

            Button {
                onOpenDisplaySettings()
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(uiAccent.color)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(AppBackground.card(scheme))
                    )
                    .shadow(
                        color: AppBackground.panelShadow(scheme),
                        radius: 4,
                        y: 2
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // ❌ KHÔNG background ở đây
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
    // ✅ THÊM 3 ACTION
       let onAddEvent: () -> Void
       let onShareCalendar: () -> Void
       let onBookPartner: () -> Void
    
    
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
                                   timeDisplayMode: timeDisplayMode,
                                   onAddEvent: onAddEvent,
                                   onShareCalendar: onShareCalendar,
                                   onBookPartner: onBookPartner
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
    // ✅ THÊM 3 ACTION
       let onAddEvent: () -> Void
       let onShareCalendar: () -> Void
       let onBookPartner: () -> Void

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
                    timeDisplayMode: timeDisplayMode,
                    onAddEvent: onAddEvent,
                    onShareCalendar: onShareCalendar,
                    onBookPartner: onBookPartner
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
    
    // ✅ THÊM 3 ACTION
        let onAddEvent: () -> Void
        let onShareCalendar: () -> Void
        let onBookPartner: () -> Void
    
    
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

//new
    
    @State private var expandedEvents: Set<String> = []

    private func isExpanded(_ event: CalendarEvent) -> Bool {
        expandedEvents.contains(event.id)
    }


    @EnvironmentObject var uiAccent: UIAccentStore

    private var shouldShowLightSuggestion: Bool {
        let isTodayOrFuture =
            Calendar.current.startOfDay(for: day) >=
            Calendar.current.startOfDay(for: Date())

        let key = dayKey(day)

        return isTodayOrFuture
            && !dayEvents.isEmpty
            && dayEvents.count < 4
            && !collapsedDays.contains(key)
    }


    @AppStorage("collapsed_light_suggestion_days")
    private var collapsedDaysRaw: String = ""

    private var collapsedDays: Set<String> {
        Set(collapsedDaysRaw.split(separator: ",").map(String.init))
    }

    private func dayKey(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return "\(comps.year!)-\(comps.month!)-\(comps.day!)"
    }

    
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.normal.rawValue

    private var cardLayout: EventCardLayout {
        EventCardLayout(rawValue: cardLayoutRaw) ?? .normal
    }

    private var manualBusySlotsOfDay: [CalendarEvent] {
        eventManager.myManualBusySlots.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: day)
        }
    }


    var body: some View {

        let unreadCount = eventManager.unreadCount(for: day)
        let hasNew = eventManager.hasNewEvent(for: day)

        VStack(alignment: .leading, spacing: 8) {

            headerView(
                unreadCount: unreadCount,
                hasNew: hasNew
            )
            

            VStack(alignment: .leading, spacing: 6) {

                switch cardLayout {

                case .timeline:
                    TimelineDayView(
                        date: day,
                        events: dayEvents,
                        manualBusySlots: manualBusySlotsOfDay,
                        timeDisplayMode: timeDisplayMode
                    )
                    .padding(.top, 8)

                case .normal, .compact:
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(dayEvents) { event in
                            switch cardLayout {

                            case .normal:
                                EventRowView(
                                    event: event,
                                    showOwnerLabel: showOwnerLabel,
                                    
                                    expandedEvents: $expandedEvents,
                                    chatMeta: eventManager.chatMeta(for: event.id),
                                    timeDisplayMode: timeDisplayMode
                                )

                            case .compact:
                                CompactEventRowView(
                                    event: event,
                                    timeFontSize: timeFontSize,
                                    timeDisplayMode: timeDisplayMode,
                                    expandedEvents: $expandedEvents,
                                    chatMeta: eventManager.chatMeta(for: event.id)
                                )

                            default:
                                EmptyView()
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }

            
    // ===== < 4 EVENTS SUGGESTION (BOTTOM) =====
            if shouldShowLightSuggestion {
                LightDaySuggestionView(
                    onAdd: onAddEvent,
                    onShare: onShareCalendar,
                    onBookPartner: onBookPartner,
                    onCollapse: {
                        let key = dayKey(day)

                        if !collapsedDays.contains(key) {
                            let updated = collapsedDays
                                .union([key])
                                .joined(separator: ",")

                            collapsedDaysRaw = updated
                        }
                    }
                )


                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .onAppear {
            resetCollapseIfNeeded()
        }
        .onChange(of: dayEvents.count) { _, _ in
            resetCollapseIfNeeded()
        }

        .padding(.vertical, 8)
    }




    
    private func resetCollapseIfNeeded() {
        let key = dayKey(day)

        guard dayEvents.count >= 4,
              collapsedDays.contains(key)
        else { return }

        let updated = collapsedDays
            .subtracting([key])
            .joined(separator: ",")

        collapsedDaysRaw = updated
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
