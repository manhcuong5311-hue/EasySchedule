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

    // Prefill start time when AddEventView is opened from a free-gap tap
    @State private var pendingPrefillMinutes: Int? = nil

    
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
                    pendingPrefillMinutes = nil
                    activeSheet = .addEvent
                },

                onAddInGap: { minutes in
                    pendingPrefillMinutes = minutes
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
                    busyHours: [],
                    prefillStartMinutes: pendingPrefillMinutes
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
            // Past days now open the read-only day timeline (archive-backed) directly,
            // instead of auto-popping the weekly summary sheet.
        }

   
    }
    
    
    
    
  
    
    
    
    
}







enum CalendarViewMode { case day, month }   // Tab 1 Day ↔ Month switch (Phase A demo)

struct EventScrollContent: View {

    let events: [CalendarEvent]
    let showOwnerLabel: Bool
    let timeFontSize: Double
    
    @Binding var selectedDate: Date
    
    let onAddEvent: () -> Void
    let onAddInGap: (Int) -> Void
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
        let liveForDay = events.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
        // Include archive-only past events so past days aren't treated as empty.
        let liveIds = Set(liveForDay.map(\.id))
        let archiveForDay = eventManager.pastEvents.filter {
            !liveIds.contains($0.id) &&
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
        return (liveForDay + archiveForDay).sorted { $0.startTime < $1.startTime }
    }
    
    private var isOffDay: Bool {
        eventManager.isOffDay(selectedDate)
    }
   
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.timeline.rawValue

    @State private var viewMode: CalendarViewMode = .day   // Day timeline ↔ Month grid
    @State private var requestMonthAdd = false             // top-right "+" → month add sheet

    let onUserSelectDay: () -> Void

    private var headerHeight: CGFloat { isPad ? 72 : 56 }
    private var dayPickerHeight: CGFloat { isPad ? 134 : 118 }
    private let topSpacing: CGFloat = 40
    private var dayCardInset: CGFloat {
        isPad ? 12 : 8
    }
    
    private var bottomCardInset: CGFloat {
        isPad ? 16 : 12
    }

    var body: some View {
        GeometryReader { geo in

            let dayAvail   = max(0, geo.size.height - headerHeight - dayPickerHeight)
            let monthAvail = max(0, geo.size.height - headerHeight)

            VStack(spacing: 0) {

                headerBar
                    .frame(height: headerHeight)

                if viewMode == .day {
                    HorizontalDayPickerView(
                        selectedDate: $selectedDate,
                        maxSelectableDate: maxSelectableDate,
                        onUserSelectDay: { _ in
                            onUserSelectDay()
                        }
                    )
                    .frame(height: dayPickerHeight)

                    dayCard
                        .frame(maxWidth: .infinity, maxHeight: dayAvail)
                        .transition(.opacity)
                } else {
                    // Month mode = the former Tab 2 (grid + availability), embedded,
                    // now on the same rounded card as the day timeline.
                    monthCard
                        .frame(maxWidth: .infinity, maxHeight: monthAvail)
                        .transition(.opacity)
                }
            }
            .background(
                AppBackground.settings(scheme)
                    .ignoresSafeArea()
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }





    
    
    
    private var dayCard: some View {

        // 1️⃣ Chiều cao hint cố định (chrome, không phải content)
        let _: CGFloat = isPad ? 36 : 24

        return ZStack(alignment: .top) {

            // ===== SCROLL CONTENT =====
            ScrollView {

                VStack(spacing: 0) {


                    // Always render the timeline — DragDropTimelineDayView builds
                    // Morning Start + Night Sleep even when dayEvents is empty.
                    DaySectionView(
                        day: selectedDate,
                        dayEvents: eventsOfSelectedDay,
                        showOwnerLabel: showOwnerLabel,
                        timeFontSize: timeFontSize,
                        timeDisplayMode: timeDisplayMode,
                        onAddEvent: onAddEvent,
                        onShareCalendar: onShareCalendar,
                        onBookPartner: onBookPartner,
                        onAddInGap: onAddInGap
                    )
                    .padding(.bottom, eventsOfSelectedDay.isEmpty ? 8 : 16)

                    // Off days keep their dedicated summary prompt. Normal empty
                    // days now surface Add / Share / Book as small pills on the
                    // timeline itself (see DDTimelineActionStack), so no card here.
                    if eventsOfSelectedDay.isEmpty, isOffDay {
                        OffDayEmptyStateView(
                            date: selectedDate,
                            onViewSummary: {
                                onViewSummary(selectedDate)
                            }
                        )
                    }
                }
                // floatingTabBarHeight + 12 (gap) + home-indicator safe area (read in ContentView)
                // safeAreaInsets.bottom is not directly available here; use a generous constant
                // that matches what ContentView adds (bottomSafeArea ≈ 34 on notched devices).
                .safeAreaPadding(.bottom)
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

    private var monthCard: some View {
        CustomizableCalendarView(embedded: true, addRequest: $requestMonthAdd)
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
        HStack(spacing: 4) {

            modeToggleButton

            BigDateHeaderView(
                date: selectedDate,
                isExpanded: $isMonthPickerOpen
            ) {
                isMonthPickerOpen = true
                onOpenMonthPicker()
            }

            Spacer()

            if viewMode == .month {
                monthAddButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // Single icon toggle (top-left) — collapses the old Day | Month segmented
    // control into one compact button. The glyph shows the mode you'll switch TO:
    // grid = jump to Month, day-timeline = jump back to Day.
    private var modeToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                viewMode = (viewMode == .day) ? .month : .day
            }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            Image(systemName: viewMode == .day
                  ? "square.grid.3x3.fill"
                  : "calendar.day.timeline.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(uiAccent.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(uiAccent.color.opacity(0.12)))
                .overlay(Circle().stroke(uiAccent.color.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            viewMode == .day
            ? Text("switch_to_month")
            : Text("switch_to_day")
        )
    }

    // Primary "add" action for Month mode — top-right of the header, replacing
    // the old floating FAB that drifted into the empty space below the grid.
    private var monthAddButton: some View {
        Button {
            requestMonthAdd = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [uiAccent.color, uiAccent.color.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: uiAccent.color.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(Text("add_event_label"))
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
        var onAddInGap: ((Int) -> Void)? = nil
    
    
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

//new
    
    @State private var expandedEvents: Set<String> = []

    private func isExpanded(_ event: CalendarEvent) -> Bool {
        expandedEvents.contains(event.id)
    }


    @EnvironmentObject var uiAccent: UIAccentStore

    // Timeline is the only layout. The AppStorage key is kept for compatibility
    // but the rendered layout is always .timeline.
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.timeline.rawValue

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
            

            // Always render the timeline view.
            // Merge live Firestore events with locally-cached past events for this day
            // so that events deleted from Firestore by a cloud function still appear.
            let liveIds = Set(dayEvents.map(\.id))
            let pastForDay = eventManager.pastEvents.filter {
                Calendar.current.isDate($0.startTime, inSameDayAs: day) &&
                !liveIds.contains($0.id)
            }
            DragDropTimelineDayView(
                date: day,
                events: dayEvents + pastForDay,
                onAddInGap: onAddInGap,
                onAddSelf: onAddEvent,
                onShare: onShareCalendar,
                onBookPartner: onBookPartner
            )
            .padding(.top, 8)
            .padding(.horizontal, 16)
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
