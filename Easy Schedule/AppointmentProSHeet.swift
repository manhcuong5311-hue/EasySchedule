//
// AppointmentProSheet.swift
// Easy schedule
//
// Created by ChatGPT for Sam Manh Cuong
//


import SwiftUI
import FirebaseAuth

// NOTE: dùng tên ProSlot để tránh trùng với TimeSlot
struct ProSlot: Hashable {
    let start: Date
    let end: Date
}

struct AppointmentProSheet: View {
    @EnvironmentObject var eventManager: EventManager

    @Binding var isPresented: Bool
    let sharedUserId: String?
    let sharedUserName: String?

    @State private var showSuccessAlert = false

    @State private var selectedDate: Date = Date()
    @State private var selectedSlot: ProSlot? = nil
    @State private var busySlots: [CalendarEvent] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var partnerOffDays: Set<Date> = []
    @State private var partnerIsPremium: Bool = true
    @State private var showPremiumAlert = false
    @EnvironmentObject var network: NetworkMonitor
    @State private var busyIntervals: [(Date, Date)] = []
    @State private var customStart: Date = Date()
    @State private var customEnd: Date = Date()
    @State private var useCustomTime: Bool = false

    @State private var titleText: String = String(localized: "default_event_title")

   
    @EnvironmentObject var session: SessionStore

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "recipient")).font(.caption).foregroundColor(.secondary)
                        Text(sharedUserName ?? sharedUserId ?? String(localized: "no_name"))
                            .font(.subheadline).lineLimit(1)
                    }
                    Spacer()
                    if loading { ProgressView() }
                }
                .padding(.horizontal)

                // Mini calendar
                CalendarMiniView(
                    selectedDate: $selectedDate,
                    busySlots: busySlots,
                    offDays: partnerOffDays
                )
                .frame(height: 260)

                if partnerOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                    Text(String(localized: "owner_day_off"))
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .padding(.top, 4)
                }

                Divider()

                // Form
                Form {

                    // TIÊU ĐỀ
                    Section(header: Text(String(localized: "title_section"))) {
                        TextField(String(localized: "event_title_placeholder"), text: $titleText)
                    }

                    // ⭐ GIỜ TÙY CHỈNH
                    Section(header: Text(String(localized: "custom_time_section"))) {
                        Toggle(String(localized: "use_custom_time"), isOn: $useCustomTime)

                        if useCustomTime {

                            DatePicker(String(localized: "start_time"), selection: $customStart, displayedComponents: .hourAndMinute)

                            DatePicker(String(localized: "end_time"), selection: $customEnd, displayedComponents: .hourAndMinute)
                                .onChange(of: customEnd) {
                                    if customEnd <= customStart {
                                        customEnd = Calendar.current.date(
                                            byAdding: .minute,
                                            value: 15,
                                            to: customStart
                                        )!
                                    }
                                }

                            let merged = ProSlot(
                                start: combine(selectedDate, customStart),
                                end: combine(selectedDate, customEnd)
                            )

                            if checkBusy(merged) {
                                Text(String(localized: "time_unavailable"))
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }

                    // ⭐ KHUNG GIỜ 30P
                    Section(header: Text(String(localized: "time_slots_30min"))) {
                        timeSlotsSection
                    }

                }

            }
            .navigationTitle(String(localized: "create_appointment"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized:"cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "book")) {

                        if useCustomTime {
                            selectedSlot = ProSlot(
                                start: combine(selectedDate, customStart),
                                end: combine(selectedDate, customEnd)
                            )
                        }

                        handleCreate()
                    }
                    .disabled(
                        (!useCustomTime && selectedSlot == nil) ||
                        sharedUserId == nil ||
                        !NetworkMonitor.shared.isOnline ||   // ⛔ OFFLINE thì khóa nút
                        loading                              // đang load lịch thì KHÔNG cho tạo
                    )

                }
            }
            .onAppear {
                if busySlots.isEmpty {
                    loadBusy()
                }
            }
            .onChange(of: sharedUserId) { _, newValue in
                if newValue != nil {
                    loadBusy()
                }
            }


            // Popup lỗi chung — ƯU TIÊN CAO NHẤT
            .alert(item: Binding(
                get: { errorMessage.map { SimpleError(id: 0, message: $0) } },
                set: { _ in errorMessage = nil }
            )) { err in
                Alert(title:  Text(String(localized: "error_title")),
                      message: Text(err.message),
                      dismissButton: .default(Text(String(localized: "close"))))
            }

            // Popup thành công
            .alert( String(localized: "success"), isPresented: $showSuccessAlert) {
                Button("OK") {
                    isPresented = false
                }
            } message: {
                Text(String(localized: "booking_success_for_user"))
            }

            // Popup Premium — KHÔNG dùng lại errorMessage nữa
            .alert(String(localized: "notification"), isPresented: $showPremiumAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "user_not_premium"))
            }
            .padding(.bottom)
        }

        .onChange(of: selectedDate) { _, newValue in
            guard let maxDate = calendar.date(
                byAdding: .day,
                value: partnerIsPremium ? 180 : 7,
                to: Date()
            ) else { return }


            if newValue > maxDate {
                selectedSlot = nil
            }
        }
    }
    private var timeSlotsSection: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(slotsForSelectedDate, id: \.self) { slot in
                    SlotRowPro(
                        slot: slot,
                        isBusy: checkBusy(slot),
                        isSelected: selectedSlot == slot,
                        action: {
                            if !isDayBlocked && !useCustomTime && !checkBusy(slot) {
                                selectedSlot = slot
                            }
                        }
                    )
                    .opacity(isDayBlocked ? 0.35 : 1.0)
                    .allowsHitTesting(!isDayBlocked)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 300)
    }

    private var slotsForSelectedDate: [ProSlot] {
        generateSlots(for: selectedDate)
    }

    private var isDayBlocked: Bool {
        guard let maxDate = calendar.date(
            byAdding: .day,
            value: partnerIsPremium ? 180 : 7,
            to: Date()
        ) else { return false }

        return selectedDate > maxDate
    }

    
    // MARK: Load dữ liệu
    private func loadBusy() {
        guard NetworkMonitor.shared.isOnline else {
               loading = false
               busySlots = []
               partnerOffDays = []
               errorMessage = String(localized: "no_internet_connection")
               return
           }

        guard let uid = sharedUserId else {
            loading = false
            busySlots = []
            errorMessage = String(localized: "unknown_uid")
            return
        }
        loading = true

        // 1️⃣ Load busy slots + premium
        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, premium in
            DispatchQueue.main.async {
                print("🔥 UI nhận busySlots:", slots.count)

                self.busySlots = slots
                self.partnerIsPremium = premium

                self.busyIntervals = slots.map {
                    ($0.startTime, $0.endTime)
                }


                // ⭐ LƯU LOCAL CACHE TRONG EVENTMANAGER — KHÔNG sync vào events
               
            }
        }

        // 2️⃣ Load ngày nghỉ
        eventManager.fetchOffDays(for: uid, forceRefresh: true) { offDays in
            DispatchQueue.main.async {
                self.partnerOffDays = offDays
                self.loading = false
            }
        }
    }


    // MARK: Xử lý đặt lịch
    private func handleCreate() {

        let now = Date()
        _ = calendar.date(byAdding: .day, value: 7, to: now)!
        if useCustomTime {
            selectedSlot = ProSlot(
                start: combine(selectedDate, customStart),
                end: combine(selectedDate, customEnd)
            )
        }
        // ❗ CHẶN NGÀY NGHỈ — áp dụng cho cả custom và preset slots
        let startOfSelectedDay = Calendar.current.startOfDay(for: selectedDate)
        if partnerOffDays.contains(startOfSelectedDay) {
            errorMessage = String(localized: "owner_day_off_no_booking")
            return
        }
        // ⭐ BOOKING RANGE LIMIT (UI safety check)
        let maxDate = calendar.date(
            byAdding: .day,
            value: partnerIsPremium ? 180 : 7,
            to: Date()
        )!

        if selectedDate > maxDate {
            errorMessage = partnerIsPremium
                ? String(localized: "premium_booking_limit_180_days")
                : String(localized: "You_can_only_book_within_the_next_7days.")
            return
        }

        // ⭐ CHECK FREE USER LIMIT (giống AddEventView)
        let calendar = Calendar.current
        let creatorUid = Auth.auth().currentUser?.uid ?? ""
        let eventsCreatedByMeToday = eventManager.events.filter {
            $0.createdBy == creatorUid &&
            calendar.isDate($0.startTime, inSameDayAs: selectedDate)
        }



        // ⭐ Giới hạn theo người tạo (B)
        let creatorIsPremium = PremiumStoreViewModel.shared.isPremium

        if !creatorIsPremium {
            // B không premium ⇒ 2 lịch/ngày
            if eventsCreatedByMeToday.count >= 2 {
                errorMessage = String(localized: "limit_2_events_per_day")
                return
            }
        } else {
            // B premium ⇒ 30 lịch/ngày
            if eventsCreatedByMeToday.count >= 30 {
                 errorMessage = String(localized: "premium_limit_30_per_day")
                 return
             }
        }


        guard NetworkMonitor.shared.isOnline else {
            errorMessage = String(localized: "no_internet_connection")
            return
        }

        guard let uid = sharedUserId else {
            errorMessage = String(localized: "unknown_uid")
            return
        }
        guard let slot = selectedSlot else {
            errorMessage = String(localized: "no_time_slot_selected")
            return
        }
        guard Auth.auth().currentUser != nil else {
            errorMessage = String(localized: "login_required")
            return
        }

        eventManager.addAppointment(
            forSharedUser: uid,
            title: titleText,
            start: slot.start,
            end: slot.end,
            createdBy: Auth.auth().currentUser?.uid ?? ""
        ) { success, msg in
            DispatchQueue.main.async {
                if success { showSuccessAlert = true }
                else { errorMessage = msg ?? String(localized: "create_event_failed") }
            }
        }
        
    }

    // MARK: Helper

    private func combine(_ date: Date, _ time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(
            year: d.year, month: d.month, day: d.day,
            hour: t.hour, minute: t.minute
        ))!
    }

    private func checkBusy(_ slot: ProSlot) -> Bool {
        let day = Calendar.current.startOfDay(for: slot.start)
        if partnerOffDays.contains(day) { return true }

        return busyIntervals.contains {
            $0.0 < slot.end && $0.1 > slot.start
        }
    }


    private func generateSlots(for date: Date) -> [ProSlot] {
        var arr: [ProSlot] = []
        
        // Bắt đầu từ 00:00 của ngày
        guard let startOfDay = calendar.date(
            bySettingHour: 0,
            minute: 0,
            second: 0,
            of: date
        ) else { return [] }
        
        // 48 slot (mỗi slot 30 phút → 24h)
        for i in 0..<48 {
            let s = startOfDay.addingTimeInterval(Double(i) * 1800)
            let e = s.addingTimeInterval(1800)
            arr.append(ProSlot(start: s, end: e))
        }
        
        return arr
    }


    struct SimpleError: Identifiable {
        let id: Int
        let message: String
    }
}


// MARK: - Mini calendar (unchanged logic)
struct CalendarMiniView: View {
    @Binding var selectedDate: Date
    let busySlots: [CalendarEvent]
    let offDays: Set<Date>

    @State private var month: Date = Date()
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
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

                    let isToday = Calendar.current.isDateInToday(day)
                    let isSelected = Calendar.current.isDate(selectedDate, inSameDayAs: day)
                    let isBusy = busySlots.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })
                    let isOffDay = offDays.contains(Calendar.current.startOfDay(for: day))

                    VStack {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(
                                    isToday ? Color.blue.opacity(0.35) :    // 🔵 TODAY highlight
                                    (isSelected ? Color.accentColor :
                                    (isOffDay ? Color.orange.opacity(0.4) :
                                    (isBusy ? Color.red.opacity(0.25) : Color.clear)))
                                )
                            )
                            .foregroundColor(
                                isToday ? Color.blue :                     // chữ Today
                                (isSelected ? .white : .primary)
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDate = day }
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

// MARK: - Slot row for ProSlot
struct SlotRowPro: View {
    let slot: ProSlot
    let isBusy: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(timeString(slot.start)).font(.subheadline)
            Text("-").font(.subheadline)
            Text(timeString(slot.end)).font(.subheadline)
            Spacer()
            if isBusy {
                Text(String(localized: "busy")).font(.caption).foregroundColor(.red)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .padding(10)
        .background(isSelected ? Color.green.opacity(0.15) : (isBusy ? Color.red.opacity(0.06) : Color(UIColor.systemBackground)))
        .cornerRadius(8)
        .onTapGesture { action() }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.locale = Locale(identifier: "vi_VN")
        return f.string(from: d)
    }
}
struct HistoryView: View {
    @EnvironmentObject var eventManager: EventManager
    var onSelect: (String) -> Void = { _ in }

    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            List {
                // ⭐ Sắp xếp: pinned trước, sau đó theo thời gian
                let sortedLinks = eventManager.sharedLinks.sorted {
                    if $0.isPinned == $1.isPinned { return $0.createdAt > $1.createdAt }
                    return $0.isPinned && !$1.isPinned
                }

                ForEach(sortedLinks) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.displayName ?? String(localized: "no_name"))
                                .font(.headline)

                            Text(link.url)
                                .font(.subheadline)


                            Text("UID: \(link.uid)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(link.createdAt))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        // ⭐ Nút PIN
                        Button {
                            eventManager.togglePin(link)
                        } label: {
                            Image(systemName: link.isPinned ? "pin.fill" : "pin")
                                .foregroundColor(link.isPinned ? .orange : .gray)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(link.url) // Load ngay
                    }
                    .onLongPressGesture {
                        UIPasteboard.general.string = link.url
                        showCopied = true
                    }
                }
                .onDelete { indexSet in
                    eventManager.sharedLinks.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle(String(localized: "viewed_history"))
            .alert(String(localized: "link_copied"), isPresented: $showCopied) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

}


// MARK: - Preview
struct AppointmentProSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AppointmentProSheet(
                isPresented: .constant(true),
                sharedUserId: "demoUID",
                sharedUserName: "Demo User"
            )
            .environmentObject(EventManager.shared)
        }
    }
}



//
// MyCreatedEventsView.swift
// Easy Schedule
//
// Version 2.0 — giống hệt EventListView, có Upcoming + Past
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyCreatedEventsView: View {

    @EnvironmentObject var eventManager: EventManager

    @State private var createdUpcoming: [CalendarEvent] = []
    @State private var createdPast: [CalendarEvent] = []

    @State private var loading = true
    @State private var showPast = false
    @State private var selectedDate: Date? = nil
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            VStack {

                Picker("", selection: $showPast) {
                    Text(String(localized: "upcoming")).tag(false)
                    Text(String(localized: "past")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if showPast {
                    searchBar
                }

                if loading {
                    ProgressView(String(localized: "loading"))
                        .padding()
                } else {
                    if showPast { pastList }
                    else { upcomingList }
                }
            }
            .navigationTitle(String(localized: "my_created_events"))
            .onAppear { loadEvents() }
            .sheet(isPresented: Binding(
                get: { selectedDate != nil },
                set: { if !$0 { selectedDate = nil } }
            )) {
                if let date = selectedDate {
                    CreatedEventsByDateView(date: date, events: createdPast)
                }
            }
        }
    }

    // MARK: Search bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField(String(localized: "search_placeholder"), text: $searchText)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }

    // MARK: Upcoming list
    private var upcomingList: some View {
        let grouped = groupedByMonth(events: createdUpcoming)
        let sortedMonths = grouped.keys.sorted()

        return List {
            if createdUpcoming.isEmpty {
                Text(String(localized: "no_upcoming_events"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = grouped[monthDate] ?? []
                    Section(header: headerMonth(monthDate, count: monthEvents.count)) {

                        let weeks = groupedByWeek(events: monthEvents)
                        let sortedWeeks = weeks.keys.sorted()

                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = weeks[week] ?? []

                            let weekPrefix = String(localized: "week_prefix")

                            Section(header:
                                Text("\(weekPrefix) \(week)")
                            )
 {

                                let days = groupedByDay(events: weekEvents)
                                let sortedDays = days.keys.sorted()

                                ForEach(sortedDays, id: \.self) { day in
                                    Section(header: Text(formatDate(day)).fontWeight(.bold)) {

                                        ForEach(days[day]!.sorted { $0.startTime < $1.startTime }) { ev in
                                            createdEventRow(ev)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Past list
    private var pastList: some View {
        let filtered = createdPast.filter { ev in
            searchText.isEmpty ||
            ev.title.localizedCaseInsensitiveContains(searchText) ||
            ev.owner.localizedCaseInsensitiveContains(searchText)
        }

        let grouped = groupedByMonth(events: filtered)
        let sortedMonths = grouped.keys.sorted(by: >)

        return List {
            if filtered.isEmpty {
                Text(
                    searchText.isEmpty
                    ? String(localized: "no_past_events")
                    : String(localized: "no_results")
                )
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = grouped[monthDate] ?? []

                    Section(header: headerMonth(monthDate, count: monthEvents.count)) {

                        let weeks = groupedByWeek(events: monthEvents)
                        let sortedWeeks = weeks.keys.sorted()

                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = weeks[week] ?? []

                            Button {
                                selectedDate = weekEvents.first?.date
                            } label: {
                                HStack {
                                    let weekPrefix = String(localized: "week_prefix")
                                    Text("\(weekPrefix) \(week)")
                                    Spacer()
                                    let template = String(localized: "events_count")
                                    Text(template.replacingOccurrences(of: "{count}", with: "\(weekEvents.count)"))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Row
    private func createdEventRow(_ ev: CalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ev.title).font(.headline)

            HStack {
                Image(systemName: "person.fill")
                let ownerPrefix = String(localized: "owner_prefix")
                Text("\(ownerPrefix) \(ev.owner)")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text("\(formatTime(ev.startTime)) → \(formatTime(ev.endTime))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Load data
    private func loadEvents() {
        loading = true
        let now = Date()

        // Lấy toàn bộ events trong máy
        let allEvents = eventManager.events
        let pastEvents = eventManager.pastEvents

        // Chỉ lấy lịch tôi tạo cho đối tác
        let createdForOtherUpcoming = allEvents.filter {
            $0.origin == .iCreatedForOther && $0.endTime >= now
        }

        let createdForOtherPast = pastEvents.filter {
            $0.origin == .iCreatedForOther && $0.endTime < now
        }

        self.createdUpcoming = createdForOtherUpcoming
        self.createdPast = createdForOtherPast

        loading = false
    }
    private func formattedFullDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }



    // MARK: Group helpers
    private func groupedByMonth(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.date(from:
                Calendar.current.dateComponents([.year, .month], from: $0.date)
            )!
        }
    }

    private func groupedByWeek(events: [CalendarEvent]) -> [Int: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.component(.weekOfMonth, from: $0.date)
        }
    }

    private func groupedByDay(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
        Dictionary(grouping: events) {
            Calendar.current.startOfDay(for: $0.date)
        }
    }

    // MARK: Date formatting helpers
    private func headerMonth(_ date: Date, count: Int) -> some View {
        HStack {
            Text(formatMonth(date)).font(.headline)
            Spacer()
            let template = String(localized: "events_count")
            Text(template.replacingOccurrences(of: "{count}", with: "\(count)"))
.foregroundColor(.secondary)
        }
    }

    private func formatMonth(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }


    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }



    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}


// MARK: - DAY DETAILS VIEW
struct CreatedEventsByDateView: View {
    let date: Date
    let events: [CalendarEvent]

    @Environment(\.dismiss) private var dismiss

    private var eventsForDay: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            List(eventsForDay) { ev in
                VStack(alignment: .leading) {
                    Text(ev.title).font(.headline)
                    let template = String(localized: "event_owner")
                    Text(template.replacingOccurrences(of: "{name}", with: ev.owner))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(formatTime(ev.startTime)) – \(formatTime(ev.endTime))")
                        .font(.caption)
                }
            }
            .navigationTitle(formatDate(date))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }


    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}



extension CalendarEvent {
    static func from(_ doc: DocumentSnapshot) -> CalendarEvent? {
        let data = doc.data() ?? [:]

        func parseDate(_ value: Any?) -> Date? {
            if let ts = value as? Timestamp { return ts.dateValue() }
            if let d = value as? Double { return Date(timeIntervalSince1970: d) }
            if let i = value as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
            return nil
        }

        let start = parseDate(data["startTime"] ?? data["start"])
        let end   = parseDate(data["endTime"] ?? data["end"])
        guard let s = start, let e = end else { return nil }

        guard let title = data["title"] as? String else { return nil }
        guard let owner = data["owner"] as? String else { return nil }

        let sharedUser = data["sharedUser"] as? String ?? ""
        let createdBy  = data["createdBy"] as? String  ?? ""
        let colorHex   = data["colorHex"] as? String  ?? "#007AFF"

        // participants
        var participants: [String] = []
        if let arr = data["participants"] as? [String] {
            participants = arr
        } else if let arrAny = data["participants"] as? [Any] {
            participants = arrAny.compactMap { $0 as? String }
        }

        // ⭐ NEW: Read participantNames + creatorName
        let participantNames = data["participantNames"] as? [String: String] ?? [:]
        let creatorName = data["creatorName"] as? String ?? ""

        // Determine origin
        let current = Auth.auth().currentUser?.uid ?? ""
        var origin: EventOrigin
        let isMyCalendar = (owner == current)
        let isCreatedByMe = (createdBy == current)

        if isMyCalendar {
            origin = isCreatedByMe ? .myEvent : .createdForMe
        } else {
            origin = isCreatedByMe ? .iCreatedForOther : .createdForMe
        }

        return CalendarEvent(
            id: doc.documentID,
            title: title,
            date: Calendar.current.startOfDay(for: s),
            startTime: s,
            endTime: e,
            owner: owner,
            sharedUser: sharedUser,
            createdBy: createdBy,
            participants: participants,
            participantNames: participantNames,  // ⭐ ADDED
            creatorName: creatorName,            // ⭐ ADDED
            colorHex: colorHex,
            pendingDelete: false,
            origin: origin
        )
    }



    private static func parseDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d = value as? Double { return Date(timeIntervalSince1970: d) }
        if let i = value as? Int { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }
}

