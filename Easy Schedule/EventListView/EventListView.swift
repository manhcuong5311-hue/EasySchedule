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
    @Binding var showPastEvents: Bool
    @State private var selectedWeek: (year: Int, week: Int)? = nil
    @State private var selectedDate: Date? = nil  // dùng để mở chi tiết ngày
    @State private var searchText: String = ""    // dùng để tìm kiếm
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    // MARK: — tùy chỉnh UI
    @State private var showCustomizeSheet = false
    @EnvironmentObject var session: SessionStore
    @State private var collapsedDays: Set<Date> = []
    @State private var unreadCountForDay: Int = 0
    @EnvironmentObject var guideManager: GuideManager
    @State private var userPinnedDays: Set<Date> = []


    // Lưu cấu hình hiển thị (AppStorage để giữ xuyên các lần chạy app)
    @AppStorage("showOwnerLabel") private var showOwnerLabel: Bool = true
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13.0
    @AppStorage("timeColorHex") private var timeColorHex: String = "#007AFF"

    var body: some View {
        ZStack {
            mainContent

            if guideManager.isActive(.eventsIntro) {
                eventsIntroOverlay
            }
        }
    }

    private func formattedMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    private var mainContent: some View {
        VStack {
            // Nút chuyển giữa 2 chế độ
            Picker("", selection: $showPastEvents) {
                Text(String(localized: "current_events")).tag(false)
                    Text(String(localized: "past_events")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Ô tìm kiếm chỉ hiện khi xem "lịch đã qua"
            if showPastEvents {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(String(localized: "search_placeholder"), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            if showPastEvents {
                pastEventsGroupedView
            } else {
                upcomingEventsList
            }
        }
        .navigationTitle(
            showPastEvents
            ? String(localized: "past_events")
            : String(localized: "current_events")
        )
        .toolbar {

            // ❓ Help — bên trái
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    guideManager.show(.eventsIntro)
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel(
                    String(localized: "help")
                )

            }

            // ⚙️ Customize — bên phải
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(
                    String(localized: "customize_events")
                )

            }
        }
        .task {
            await eventManager.loadUpcomingEvents()
        }
        .onChange(of: showPastEvents) {
            if !showPastEvents {
                Task {
                    await eventManager.loadUpcomingEvents()
                }
            }
        }
        .onAppear {
            eventManager.cleanUpPastEvents()
        }
        .sheet(isPresented: Binding(
            get: { selectedWeek != nil },
            set: { if !$0 { selectedWeek = nil } }
        )) {
            if let week = selectedWeek {
                PastEventsByWeekView(week: week)
                    .environmentObject(eventManager)
            }
        }
        .sheet(isPresented: $showCustomizeSheet) {
            CustomizeCalendarSettingsView()
        }
        .alert(String(localized: "delete_event_title"), isPresented: $showDeleteAlert) {
            Button(String(localized: "delete"), role: .destructive) {
                if let event = eventToDelete {
                    eventManager.deleteEvent(event)
                }
                eventToDelete = nil
            }

            Button(String(localized: "cancel"), role: .cancel) {
                eventToDelete = nil
            }
        } message: {
            let eventTitle = eventToDelete?.title ?? ""
            let prefix = String(localized: "delete_event_confirm_prefix")
            Text("\(prefix) “\(eventTitle)”?")
        }
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
                            guideManager.complete(.eventsIntro)
                        },
                        onDoNotShowAgain: {
                            guideManager.disablePermanently(.eventsIntro)
                        }
                    )
                    .frame(
                        maxWidth: min(420, geo.size.width * 0.9)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 140)
            }
        }
    }



    // MARK: - Lịch hiện tại (gộp theo Tháng → Tuần → Ngày)
    private var upcomingEventsList: some View {
        let groupedByMonth = EventGrouping.byMonth(eventManager.events)
        let sortedMonths = groupedByMonth.keys.sorted()

        return List {
            if eventManager.events.isEmpty {
                Text(String(localized: "no_upcoming_events"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    monthSection(
                        monthDate: monthDate,
                        events: groupedByMonth[monthDate] ?? []
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await eventManager.loadUpcomingEvents(force: true)
        }
        .onPreferenceChange(DayPositionKey.self) { positions in
            handleAutoCollapse(positions: positions)
        }
    }


    private func events(for day: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        return eventManager.events.filter {
            calendar.isDate($0.startTime, inSameDayAs: day)
        }
    }
    private func monthSection(
        monthDate: Date,
        events: [CalendarEvent]
    ) -> some View {
        let groupedByWeek = EventGrouping.byWeek(events)
        let sortedWeeks = groupedByWeek.keys.sorted()

        return Section(header: monthHeader(monthDate, count: events.count)) {
            ForEach(sortedWeeks, id: \.self) { week in
                weekSection(
                    week: week,
                    events: groupedByWeek[week] ?? []
                )
            }
        }
    }

    private func weekSection(
        week: Int,
        events: [CalendarEvent]
    ) -> some View {
        let groupedByDay = EventGrouping.byDay(events)
        let sortedDays = groupedByDay.keys.sorted()

        return Section(header: weekHeader(week)) {
            ForEach(sortedDays, id: \.self) { day in
                DaySectionView(
                    day: day,
                    dayEvents: groupedByDay[day] ?? [],
                    collapsedDays: $collapsedDays,
                    showOwnerLabel: showOwnerLabel,
                    timeFontSize: timeFontSize,
                    timeColorHex: timeColorHex,
                    session: session,
                    eventManager: eventManager,
                    onDelete: deleteUpcomingEvent,
                    showDeleteConfirmation: showDeleteConfirmation,
                    userPinnedDays: $userPinnedDays
                )

            }
        }
    }

    private func monthHeader(_ date: Date, count: Int) -> some View {
        HStack {
            Text(date.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            let template = String(localized: "number_of_events_month")
            Text(template.replacingOccurrences(of: "{count}", with: "\(count)"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func weekHeader(_ week: Int) -> some View {
        let prefix = String(localized: "week_prefix")
        return Text("\(prefix) \(week)")
            .font(.subheadline.bold())
            .foregroundColor(.secondary)
    }

    private func handleAutoCollapse(positions: [Date: CGFloat]) {
        let threshold: CGFloat = 80

        for (day, y) in positions {
            guard y < threshold else { continue }
            guard !Calendar.current.isDateInToday(day) else { continue }
            guard !userPinnedDays.contains(day) else { continue }
            guard !unreadDays.contains(day) else { continue }

            collapsedDays.insert(day)
        }
    }


    private var unreadDays: Set<Date> {
        let calendar = Calendar.current
        return Set(
            eventManager.events
                .filter { eventManager.chatMeta(for: $0.id).unread }
                .map { calendar.startOfDay(for: $0.startTime) }
        )
    }


    private func formattedDayHeader(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day())
    }


    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    
    // MARK: - Lịch đã qua (gộp theo tháng + tuần + tìm kiếm)
    private var pastEventsGroupedView: some View {
        // Lọc theo từ khóa tìm kiếm (title hoặc owner)
        let filteredEvents = eventManager.pastEvents.filter { event in
            searchText.isEmpty ||
            event.title.localizedCaseInsensitiveContains(searchText) ||
            event.owner.localizedCaseInsensitiveContains(searchText)
        }
        
        // Nhóm theo tháng (dựa trên năm + tháng)
        let groupedByMonth = Dictionary(grouping: filteredEvents) { event -> Date in
            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month], from: event.startTime)
            return calendar.date(from: comps)!
        }

        // Sắp xếp tháng mới nhất lên trên
        let sortedMonths = groupedByMonth.keys.sorted(by: >)
        
        return List {
            if filteredEvents.isEmpty {
                Text(
                    searchText.isEmpty
                    ? String(localized: "no_past_events")
                    : String(localized: "no_results_found")
                )

                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    
                    // Hiển thị tháng
                    Section(header:
                                HStack {
                        Text(formattedMonth(monthDate))
                            .font(.headline)
                        Spacer()
                        let template = String(localized: "number_of_events_month")
                        Text(template.replacingOccurrences(of: "{count}", with: "\(monthEvents.count)"))

                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // Nhóm trong tháng đó theo tuần
                        let groupedByWeek = Dictionary(grouping: monthEvents) { event -> Int in
                            Calendar.current.component(.weekOfMonth, from: event.date)
                        }
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            
                            Button {
                                // Gộp tuần này để mở danh sách chi tiết
                                let comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekEvents.first!.date)
                                selectedWeek = (comps.yearForWeekOfYear!, comps.weekOfYear!)

                            } label: {
                                HStack {
                                    let sampleDate = weekEvents.first!.date
                                    let week = Calendar.current.component(.weekOfMonth, from: sampleDate)

                                    let weekPrefix = String(localized: "week_prefix")
                                    let monthName = sampleDate.formatted(.dateTime.month(.wide))

                                    Text("\(weekPrefix) \(week) \(monthName)")
                                        .font(.body)

                                    Spacer()

                                    let template = String(localized: "number_of_events_week")
                                    Text(template.replacingOccurrences(of: "{count}",
                                                                       with: "\(weekEvents.count)"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }


                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
   
    // MARK: - Hàng hiển thị sự kiện
  
    
    private func safeDisplayName(for event: CalendarEvent, uid: String) -> String {
        let name = displayName(
            for: event,
            uid: uid,
            eventManager: eventManager
        )

        if name == uid || name.isEmpty {
            return String(localized: "someone")
        }

        return name
    }
    
    private func metadataAttributedText(for event: CalendarEvent) -> AttributedString {
        var result = AttributedString("")

        // ⏰ TIME
        var time = AttributedString(
            "\(formattedTime(event.startTime))–\(formattedTime(event.endTime))"
        )
        time.font = .system(size: CGFloat(timeFontSize))
        time.foregroundColor = Color(hex: timeColorHex)

        result += time

        // 👤 OWNER
        if showOwnerLabel {
            var ownerText = AttributedString(" · ")

            if event.origin == .iCreatedForOther {
                let ownerName = safeDisplayName(for: event, uid: event.owner)
                ownerText += AttributedString(
                    String(
                        format: String(localized: "created_for_format"),
                        ownerName
                    )
                )
            } else {
                let name = safeDisplayName(for: event, uid: event.createdBy)
                ownerText += AttributedString(name)
            }

            ownerText.font = .system(size: max(12, CGFloat(timeFontSize)))
            ownerText.foregroundColor = .secondary

            result += ownerText
        }

        return result
    }

    // MARK: - Xoá sự kiện hiện tại
    private func deleteUpcomingEvent(at offsets: IndexSet) {
        eventManager.events.remove(atOffsets: offsets)
    }
    
    // MARK: - Helper định dạng
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}

private struct DaySectionView: View {

    let day: Date
    let dayEvents: [CalendarEvent]
    @State private var unreadCountForDay: Int = 0
    @State private var unreadMap: [String: Bool] = [:]

    @Binding var collapsedDays: Set<Date>

    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String

    let session: SessionStore
    let eventManager: EventManager

    let onDelete: (IndexSet) -> Void
    let showDeleteConfirmation: (CalendarEvent) -> Void

    @State private var userInteracted = false
    @Binding var userPinnedDays: Set<Date>


    private var isCollapsed: Bool {
        collapsedDays.contains(day)
    }
    private var timeRailWidth: CGFloat {
        // base 44, tăng dần theo font size
        let base: CGFloat = 44
        let extra = max(0, CGFloat(timeFontSize) - 13) * 1.2
        return base + extra
    }

    private var isAfterToday: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: day) >
               calendar.startOfDay(for: Date())
    }


    var body: some View {
        Section(header: headerView) {
            if !isCollapsed {
                ForEach(dayEvents.sorted { $0.startTime < $1.startTime }) { event in
                    eventRow(event)
                }
                .onDelete(perform: onDelete)

            }
        }
        .onAppear {
            autoCollapseIfNeeded()
            updateUnreadCount()
        }

        .onChange(of: dayEvents) {
            updateUnreadCount()
        }
        .onChange(of: unreadCountForDay) { _, newValue in
            autoExpandIfNeeded(unreadCount: newValue)
        }


    }

}
private extension DaySectionView {

    func updateUnreadCount() {
        var count = 0
        var map: [String: Bool] = [:]

        for event in dayEvents {
            let unread = eventManager.chatMeta(for: event.id).unread
            map[event.id] = unread
            if unread { count += 1 }
        }

        if unreadCountForDay != count || unreadMap != map {
            unreadCountForDay = count
            unreadMap = map
        }

    }
    private func autoCollapseIfNeeded() {
        guard !collapsedDays.contains(day) else { return }
        guard !userPinnedDays.contains(day) else { return }   // ⭐ THÊM DÒNG NÀY

        if isAfterToday {
            collapsedDays.insert(day)
        }
    }

    private func autoExpandIfNeeded(unreadCount: Int) {
        guard unreadCount > 0 else { return }
        guard isCollapsed else { return }
        guard !userInteracted else { return }

        _ = withAnimation(.easeInOut(duration: 0.25)) {
            collapsedDays.remove(day)
        }
    }

}

private extension DaySectionView {

    var headerView: some View {
        HStack(spacing: 8) {
            Text(day.formatted(.dateTime.weekday(.wide).day()))
                .font(.headline)

            Spacer()

            if unreadCountForDay > 0 {
                Text("\(unreadCountForDay)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: DayPositionKey.self,
                        value: [day: geo.frame(in: .global).minY]
                    )
            }
        )
    }


    func toggle() {
        userInteracted = true

        if collapsedDays.contains(day) {
            collapsedDays.remove(day)
            userPinnedDays.insert(day)     // ⭐ user mở → pin
        } else {
            collapsedDays.insert(day)
            userPinnedDays.remove(day)     // ⭐ user đóng → bỏ pin
        }
    }


}
private extension DaySectionView {

    func eventRow(_ event: CalendarEvent) -> some View {
        let isMyEvent = event.createdBy == event.owner
        let showChat = !isMyEvent
        let hasUnread = unreadMap[event.id] ?? false

        return HStack(alignment: .top, spacing: 12) {

            // 1️⃣ TIME RAIL
            Text(event.startTime.formatted(date: .omitted, time: .shortened))
                .font(.system(size: CGFloat(timeFontSize), design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: timeRailWidth, alignment: .trailing)
                .padding(.top, 4)



            // 2️⃣ DOT
            Circle()
                .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                .frame(width: 10, height: 10)
                .padding(.top, 8)

            // 3️⃣ CONTENT
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)

                timeText(for: event)

                if showOwnerLabel && !isMyEvent {
                    HStack(spacing: 6) {
                        Text("You")
                        Image(systemName: "arrow.right")
                            .font(.caption)
                        Text(
                            displayName(
                                for: event,
                                uid: event.owner,
                                eventManager: eventManager
                            )
                        )
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            // 4️⃣ CHAT BADGE (BÊN PHẢI)
            if showChat {
                ChatButtonWithBadge(
                    event: event,
                    otherUserId: event.createdBy == session.currentUserId
                        ? event.owner
                        : event.createdBy
                )
                .opacity(hasUnread ? 1.0 : 0.35)
                .animation(.easeInOut(duration: 0.2), value: hasUnread)
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 6)
    }


   


    func timeText(for event: CalendarEvent) -> some View {
        Text(
            "\(event.startTime.formatted(date: .omitted, time: .shortened))" +
            "–" +
            "\(event.endTime.formatted(date: .omitted, time: .shortened))"
        )
        .font(.system(size: CGFloat(timeFontSize)))
        .foregroundColor(Color(hex: timeColorHex))
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
