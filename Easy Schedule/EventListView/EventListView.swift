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
                .accessibilityLabel("Help")
            }

            // ⚙️ Customize — bên phải
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCustomizeSheet = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Customize events")
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

        func formattedMonth(_ date: Date) -> String {
            date.formatted(.dateTime.month(.wide).year())
        }

        func formattedMediumDate(_ date: Date) -> String {
            date.formatted(date: .numeric, time: .omitted)
        }

        func formattedTime(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .shortened)
        }

        let groupedByMonth = EventGrouping.byMonth(eventManager.events)
        let sortedMonths = groupedByMonth.keys.sorted()

        return List {
            if eventManager.events.isEmpty {
                Text(String(localized: "no_upcoming_events"))
                    .foregroundColor(.secondary)
            } else {

                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []

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

                        let groupedByWeek = EventGrouping.byWeek(monthEvents)
                        let sortedWeeks = groupedByWeek.keys.sorted()

                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            let weekPrefix = String(localized: "week_prefix")

                            Section(header:
                                Text("\(weekPrefix) \(week)")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.secondary)
                            ) {

                                let groupedByDay = EventGrouping.byDay(weekEvents)
                                let sortedDays = groupedByDay.keys.sorted()

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
                                        showDeleteConfirmation: showDeleteConfirmation
                                    )
                                }

                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {

            // ⭐ Tiêu đề
            Text(event.title)
                .font(.headline)

            // ⭐ Hàng thông tin người tạo + ngày
            HStack(spacing: 4) {

                if showOwnerLabel {
                    if event.origin == .iCreatedForOther {
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)
                            Text("→")
                            UserNameView(uid: event.owner)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Text(String(localized: "bullet_separator"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(formattedDate(event.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // ⭐ Thời gian
            Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                .font(.system(size: CGFloat(timeFontSize), weight: .regular))
                .foregroundColor(Color(hex: timeColorHex))
        }
        .padding(.vertical, 4)
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

    @Binding var collapsedDays: Set<Date>

    let showOwnerLabel: Bool
    let timeFontSize: Double
    let timeColorHex: String

    let session: SessionStore
    let eventManager: EventManager

    let onDelete: (IndexSet) -> Void
    let showDeleteConfirmation: (CalendarEvent) -> Void

    private var isCollapsed: Bool {
        collapsedDays.contains(day)
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
            updateUnreadCount()   // ⭐ BƯỚC 3.1
        }
        .onChange(of: dayEvents) {
            updateUnreadCount()
        }

    }

}
private extension DaySectionView {

    func updateUnreadCount() {
        let count = dayEvents.filter { event in
            eventManager.chatMeta(for: event.id).unread
        }.count

        // ⚠️ BẮT BUỘC dùng async để tránh update trong render
        DispatchQueue.main.async {
            unreadCountForDay = count
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
        .contentShape(Rectangle())
    }

    func toggle() {
        if isCollapsed {
            collapsedDays.remove(day)
        } else {
            collapsedDays.insert(day)
        }
    }
}
private extension DaySectionView {

    func eventRow(_ event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {

            Circle()
                .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)

                if showOwnerLabel {
                    Text(event.originLabel)
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if showOwnerLabel {
                    if event.origin == .iCreatedForOther {
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)
                            Text("→")
                            UserNameView(uid: event.owner)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Text(displayName(
                            for: event,
                            uid: event.createdBy,
                            eventManager: eventManager
                        ))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }

                Text(
                    "\(event.startTime.formatted(date: .omitted, time: .shortened)) - " +
                    "\(event.endTime.formatted(date: .omitted, time: .shortened))"
                )
                .font(.system(size: CGFloat(timeFontSize)))
                .foregroundColor(Color(hex: timeColorHex))
            }

            Spacer()

            if event.createdBy != event.owner {
                ChatButtonWithBadge(
                    event: event,
                    otherUserId: event.createdBy == session.currentUserId
                        ? event.owner
                        : event.createdBy
                )
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .swipeActions {
            Button(role: .destructive) {
                showDeleteConfirmation(event)
            } label: {
                Label(String(localized: "delete"), systemImage: "trash")
            }
        }
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

