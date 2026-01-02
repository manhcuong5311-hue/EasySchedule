//
//  CustomizableCalendarView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 24/12/25.
//
import SwiftUI
import Combine
import FirebaseAuth


private func originLabel(for event: CalendarEvent) -> String {
    switch event.origin {
    case .myEvent:
        return String(localized: "origin_my_event")
    case .createdForMe:
        return String(localized: "origin_created_for_me")
    case .iCreatedForOther:
        return String(localized: "origin_i_created_for_other")
    case .busySlot:
        return String(localized: "origin_busy")
    }
}
private struct BusyKey: Hashable {
    let start: Date
    let end: Date

    init(_ start: Date, _ end: Date) {
        self.start = start
        self.end = end
    }
}

struct CustomizableCalendarView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var selectedDate: Date? = nil
    @State private var showAddSheet: Bool = false
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    @State private var showShareSheet = false
    @State private var shareItem: ShareItem?
    @State private var isTogglingOffDay = false
    @State private var isCooldown = false
    @State private var toggleCount = 0
    @State private var showCooldownToast = false
    @State private var cooldownRemaining = 0
    @State private var isLoadingOffDays = false
    @State private var showOffDayAlert = false
    @State private var offDayAlertMessage = ""
    @State private var showBusyHoursSheet = false
    @EnvironmentObject var network: NetworkMonitor
    @State private var localBusyIntervals: [(Date, Date)] = []   // CHỈ busy hours
    @State private var eventBusyIntervals: [(Date, Date)] = []   // event
    @State private var showConfirmOffDayAlert = false
    @State private var pendingOffDayDate: Date? = nil

   


    @State private var offDays: Set<Date> = [] {
        didSet {
            guard !isLoadingOffDays else { return }
            saveOffDaysToLocal()
        }
    }

    private func hasEventOrBusy(on date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let hasEvent =
            !eventManager.events(for: dayStart).isEmpty

        let hasBusy =
            localBusyIntervals.contains { interval in
                interval.0 < dayEnd && interval.1 > dayStart
            }

        return hasEvent || hasBusy
    }
    private func hasBusyHours(on date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        return localBusyIntervals.contains { interval in
            interval.0 < dayEnd && interval.1 > dayStart
        }
    }


    private func saveOffDaysToLocal() {
        let timestamps = offDays.map { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(timestamps, forKey: "offDays")
    }

    private func loadOffDaysFromLocal() {
        isLoadingOffDays = true

        let timestamps =
            UserDefaults.standard.array(forKey: "offDays") as? [Double] ?? []

        let dates = timestamps.map { Date(timeIntervalSince1970: $0) }
        offDays = Set(dates)

        isLoadingOffDays = false
    }

    private func cleanPastOffDays() {
        let today = calendar.startOfDay(for: Date())

        let cleaned = offDays.filter {
            calendar.startOfDay(for: $0) >= today
        }

        guard cleaned != offDays else { return }

        isLoadingOffDays = true
        offDays = cleaned
        isLoadingOffDays = false

        eventManager.syncOffDaysToFirebase(offDays: offDays)
    }
    private func isPastDay(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }


    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    var body: some View {
        NavigationStack {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {

            ScrollView {
                VStack(spacing: 12) {

                    CalendarGridView(
                        selectedDate: $selectedDate,
                        eventsByDay: eventManager.groupedByDay,
                        offDays: offDays,
                        isOwner: true,
                        maxBookingDays: PremiumLimits
                            .limits(for: PremiumStoreViewModel.shared.tier)
                            .maxBookingDaysAhead
                    )

                    .padding(.top, 8)

                    allowConflictToggle

                    Divider()

                    shareCalendarButton

                    selectedDaySection

                    Spacer(minLength: 40)
                }
            }

            cooldownToast
        }
        .navigationTitle(String(localized: "my_calendar"))
        .toolbar { addToolbar }
        .sheet(isPresented: $showAddSheet) { addEventSheet }
        .sheet(isPresented: $showBusyHoursSheet) { busyHoursSheet }
        .alert(String(localized: "delete_event_title"), isPresented: $showDeleteAlert) {
            deleteAlertButtons
        } message: {
            deleteAlertMessage
        }
        .alert(String(localized: "off_day_title"), isPresented: $showOffDayAlert) {
            Button(String(localized: "ok")) { }
        } message: {
            Text(offDayAlertMessage)
        }
        .alert(
            String(localized: "off_day_warning_title"),
            isPresented: $showConfirmOffDayAlert
        ) {
            Button(String(localized: "confirm"), role: .destructive) {
                if let date = pendingOffDayDate {
                    toggleOffDay(for: date)
                    eventManager.syncOffDaysToFirebase(offDays: offDays)
                }
                pendingOffDayDate = nil
            }

            Button(String(localized: "cancel"), role: .cancel) {
                pendingOffDayDate = nil

                // 🔁 RESTORE BUSY HOURS UI
                if let uid = eventManager.currentUserId,
                   let date = selectedDate {

                    let dayStart = calendar.startOfDay(for: date)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                    localBusyIntervals =
                        eventManager.partnerBusySlots[uid]?
                            .filter { slot in
                                slot.colorHex == "#FFA500" &&
                                slot.startTime < dayEnd &&
                                slot.endTime > dayStart
                            }
                            .map { ($0.startTime, $0.endTime) } ?? []
                }

            }

        } message: {
            Text(String(localized: "off_day_warning_message"))
        }

        .onAppear {
            loadOffDaysFromLocal()
            cleanPastOffDays()
        }
        .onChange(of: selectedDate, initial: false) { _, newValue in
            handleDateChange(newValue)
        }
        .onChange(of: showConfirmOffDayAlert) { _, isShown in
            if !isShown {
                handleDateChange(selectedDate)
            }
        }

    }

    private var allowConflictToggle: some View {
        Toggle(
            String(localized: "allow_conflict"),
            isOn: Binding(
                get: { eventManager.allowDuplicateEvents },
                set: { eventManager.allowDuplicateEvents = $0 }
            )
        )
        .padding(.horizontal)
    }

    private var shareCalendarButton: some View {
        Button {
            if let uid = Auth.auth().currentUser?.uid,
               let url = URL(string: "https://easyschedule-ce98a.web.app/calendar/\(uid)") {
                shareItem = ShareItem(url: url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.blue)

                Text(String(localized: "share_calendar"))
                    .font(.body.weight(.semibold))
            }
        }
        .calendarActionStyle()
        .padding(.horizontal)
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
    }


    private var deleteAlertButtons: some View {
        Group {
            Button(String(localized: "ok"), role: .destructive) {
                if let e = eventToDelete {
                    eventManager.deleteEvent(e)
                }
                eventToDelete = nil
            }

            Button(String(localized: "cancel"), role: .cancel) {
                eventToDelete = nil
            }
        }
    }
    private var deleteAlertMessage: some View {
        Text(
            String(
                format: String(localized: "delete_event_full"),
                eventToDelete?.title ?? ""
            )
        )

    }

    private var cooldownToast: some View {
        Group {
            if showCooldownToast {
                VStack {
                    Spacer()
                    Text(
                        String(
                            format: String(localized: "cooldown_message"),
                            cooldownRemaining
                        )
                    )
                        .padding()
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.bottom, 60)
                }
            }
        }
    }
    private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
    private var addEventSheet: some View {
        AddEventView(
            prefillDate: selectedDate,
            offDays: offDays,
            busyHours: localBusyIntervals   // 👈 TRUYỀN VÀO
        )
        .environmentObject(eventManager)
    }


    private var busyHoursSheet: some View {
        Group {
            if let date = selectedDate {

                // 1️⃣ Busy do EVENT (read-only, không undo)
                let eventBusyIntervals: [(Date, Date)] =
                    eventManager.events(for: date)
                        .map { ($0.startTime, $0.endTime) }

                BusyHoursPickerView(
                    date: date,
                    eventBusyIntervals: eventBusyIntervals,
                    busyHourIntervals: localBusyIntervals,
                    onSave: { addedSlots, removedSlots in
                        guard let uid = eventManager.currentUserId else { return }

                        // ➕ Firebase
                        if !addedSlots.isEmpty {
                            eventManager.addBusyHoursForDay(
                                userId: uid,
                                slots: addedSlots
                            )
                        }

                        if !removedSlots.isEmpty {
                            eventManager.removeManualBusySlots(
                                userId: uid,
                                slots: removedSlots
                            )
                        }

                        // ✅ OPTIMISTIC UI UPDATE (QUAN TRỌNG)
                        let addedIntervals = addedSlots.map { ($0.start, $0.end) }
                        let removedIntervals = removedSlots.map { ($0.start, $0.end) }

                        localBusyIntervals.append(contentsOf: addedIntervals)
                        localBusyIntervals.removeAll { interval in
                            removedIntervals.contains {
                                $0.0 == interval.0 && $0.1 == interval.1
                            }
                        }

                        showBusyHoursSheet = false
                    }
                )
                .environmentObject(network)
            }
        }
    }





    private func handleDateChange(_ newDate: Date?) {
        guard let date = newDate else { return }
        guard let uid = eventManager.currentUserId else {
            localBusyIntervals = []
            return
        }

        // 1️⃣ Busy do EVENT (read-only)
        eventBusyIntervals = eventManager.events(for: date)
            .map { ($0.startTime, $0.endTime) }

        // 2️⃣ Busy HOURS — CHỈ MANUAL
        localBusyIntervals =
            eventManager.partnerBusySlots[uid]?
                .filter { $0.colorHex == "#FFA500" }   // manual only
                .map { ($0.startTime, $0.endTime) } ?? []
    }



    
    
    func startCooldown(seconds: Int) {
        isCooldown = true
        cooldownRemaining = seconds
        showCooldownToast = true

        // Timer mỗi 1 giây
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            cooldownRemaining -= 1
            
            if cooldownRemaining <= 0 {
                timer.invalidate()
                isCooldown = false
                showCooldownToast = false
                toggleCount = 0
            }
        }
    }

    func showCooldownMessage() {
        showCooldownToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCooldownToast = false
        }
    }

    // MARK: - SUPPORT
    private func toggleOffDay(for date: Date) {
        let key = calendar.startOfDay(for: date)
        if offDays.contains(key) {
            offDays.remove(key)
        } else {
            offDays.insert(key)
        }
    }

    private func isOffDay(_ date: Date) -> Bool {
        offDays.contains(calendar.startOfDay(for: date))
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    private var selectedDaySection: some View {
        Group {
            if let date = selectedDate {
                selectedDayView(date: date)
            } else {
                EmptyView()   // 👈 THAY DÒNG TEXT
            }
        }
    }

    private func selectedDayView(date: Date) -> some View {
        VStack(spacing: 12) {
            // ===== DAY OFF =====
            Button {
                // ❗ KHÔNG CHO QUÁ KHỨ
                guard !isPastDay(date) else {
                    offDayAlertMessage = String(localized: "cannot_set_offday_in_past")
                    showOffDayAlert = true
                    return
                }

                // 🔒 COOLDOWN
                guard !isCooldown else {
                    showCooldownMessage()
                    return
                }

                // ⚠️ CẢNH BÁO NẾU CÓ EVENT / BUSY
                if !isOffDay(date) && hasEventOrBusy(on: date) {
                    pendingOffDayDate = date
                    showConfirmOffDayAlert = true
                    return
                }

                // ⏱️ COOLDOWN COUNT
                toggleCount += 1
                if toggleCount >= 3 {
                    startCooldown(seconds: 5)
                    return
                }

                toggleOffDay(for: date)
                eventManager.syncOffDaysToFirebase(offDays: offDays)

            } label: {

                // ===== UI CHUẨN HOÁ =====
                HStack(spacing: 10) {
                       Image(
                           systemName: isOffDay(date)
                           ? "xmark.circle"
                           : "bed.double"
                       )
                       .foregroundColor(.blue)

                       Text(
                           isOffDay(date)
                           ? String(localized: "reopen_day")
                           : String(localized: "set_day_off")
                       )
                       .font(.body.weight(.semibold))
                   }
               }
               .calendarActionStyle()
               .padding(.horizontal)
               .disabled(isCooldown)
            // ===== BUSY HOURS =====
            let hasBusy = hasBusyHours(on: date)

            Button {
                if isOffDay(date) {
                    offDayAlertMessage = String(
                        localized: "busy_hours_disabled_off_day"
                    )
                    showOffDayAlert = true
                    return
                }
                showBusyHoursSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .foregroundColor(hasBusy ? .orange : .blue)

                    Text(String(localized: "busy_hours"))
                        .font(.body.weight(.semibold))
                }
            }
            .calendarActionStyle(
                showsHint: isOffDay(date),
                hintText: nil
            )
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hasBusy ? Color.orange.opacity(0.15) : Color.clear)
            )
            .padding(.horizontal)


        }
    }
}


struct AddEventView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color = .blue // ✅ màu mặc định
    // Pre-fill date if user selected a date in calendar
    let prefillDate: Date?
    let offDays: Set<Date>        // ✅ THÊM MỚI — danh sách ngày nghỉ truyền từ ngoài vào
    let busyHours: [(Date, Date)]
    @State private var selectedDate: Date = Date()
   
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800) // default +1h
    // ✅ THÊM MỚI — biến trạng thái popup
    @State private var showOffDayAlert = false
    @State private var offDayMessage = ""
    @EnvironmentObject var premium: PremiumStoreViewModel
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @EnvironmentObject var session: SessionStore
    @State private var showBusyInfo = false
    @State private var busyInfoEvent: CalendarEvent? = nil
    @State private var hasSelectedSlot = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "info_section"))) {
                    TextField(String(localized: "title_placeholder"), text: $title)
                }

                Section(header: Text(String(localized: "date_time_section"))) {
                    DatePicker(
                        String(localized: "date_label"),
                        selection: $date,
                        displayedComponents: .date
                    )
                    .onChange(of: date) { _, _ in
                        hasSelectedSlot = false
                    }

                    Section(String(localized: "select_time_section")) {
                        let hours = Array(0..<24)
                        let eventsToday = eventManager.events(for: date)

                        // Kiểm tra ngày nghỉ
                        let isOffDay = offDays.contains {
                            Calendar.current.isDate($0, inSameDayAs: date)
                        }


                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {

                            ForEach(hours, id: \.self) { hour in

                                let slotStart = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                                let slotEnd   = slotStart.addingTimeInterval(3600)
                                // ✅ CHECK SLOT ĐÃ QUA (CHỈ ÁP DỤNG CHO HÔM NAY)
                                let isToday = Calendar.current.isDateInToday(date)
                                let now = Date()

                                let isPastSlot =
                                    isToday &&
                                    slotEnd <= now

                                // Check giờ bận
                                // 1️⃣ Busy do EVENT
                                let busyEvent = eventsToday.first {
                                    $0.startTime < slotEnd && $0.endTime > slotStart
                                }

                                // 2️⃣ Busy do BUSY HOURS
                                let busyHour = busyHours.first {
                                    $0.0 < slotEnd && $0.1 > slotStart
                                }

                                // 3️⃣ Tổng hợp
                                let isBusy =
                                    (busyEvent != nil) ||
                                    (busyHour != nil) ||
                                    isOffDay ||
                                    isPastSlot



                                // Check giờ được chọn
                                let selectedHour = Calendar.current.component(.hour, from: startTime)
                                let isSelected = hasSelectedSlot && (hour == selectedHour)

                                // Màu nền
                                let bgColor: Color = {
                                    if isSelected {
                                        return .blue.opacity(0.7)
                                    }
                                    if isPastSlot {
                                        return .gray.opacity(0.25)
                                    }
                                    if isBusy {
                                        return .red.opacity(0.40)
                                    }
                                    return .gray.opacity(0.15)
                                }()



                                Text(String(format: "%02d:00", hour))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(bgColor)
                                    .foregroundColor(isBusy ? .white : .primary)
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())

                                    // TAP để chọn giờ
                                    .onTapGesture {
                                        if !isBusy {
                                            hasSelectedSlot = true
                                            startTime = slotStart
                                            endTime = slotStart.addingTimeInterval(1800)
                                        }
                                    }


                                    // LONG PRESS để xem giờ bận
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.4)
                                            .onEnded { _ in
                                                if let ev = busyEvent {
                                                    busyInfoEvent = ev
                                                    showBusyInfo = true

                                                } else if busyHour != nil {
                                                    alertMessage = String(localized: "busy_hours")
                                                    showAlert = true

                                                } else if isOffDay {
                                                    alertMessage = String(localized: "off_day")
                                                    showAlert = true
                                                }
                                            }

                                    )
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    DatePicker( String(localized: "start_label"), selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker( String(localized: "end_label"), selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text(String(localized: "event_color_section"))) {
 
                    ColorPicker(String(localized: "pick_color"), selection: $selectedColor, supportsOpacity: false)
                }
               

            }
            .onAppear {
                if let d = prefillDate {
                    date = d
                    selectedDate = d                  // <- QUAN TRỌNG: đồng bộ
                    // set startTime/endTime to that day same hour as current
                    let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                    if let dayStart = Calendar.current.date(from: comps) {
                        // keep times (only change date portion)
                        startTime = combine(date: dayStart, time: startTime)
                        endTime = combine(date: dayStart, time: endTime)
                    }
                }
            }

            .navigationTitle(String(localized: "add_event_title"))

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {

                        guard !isSaving else { return }
                        isSaving = true

                        let calendar = Calendar.current
                        let now = Date()

                        // 1️⃣ OFF DAY
                        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                            let template = String(localized: "off_day_full_message")
                            offDayMessage = template
                                .replacingOccurrences(of: "{date}", with: formattedDate(date))
                            showOffDayAlert = true
                            isSaving = false
                            return
                        }

                        // 2️⃣ EMPTY TITLE
                        if title.trimmingCharacters(in: .whitespaces).isEmpty {
                            alertMessage = String(localized: "empty_title")
                            showAlert = true
                            isSaving = false
                            return
                        }

                        // 3️⃣ TIME
                        let s = combine(date: date, time: startTime)
                        var e = combine(date: date, time: endTime)

                        if e <= s {
                            e = s.addingTimeInterval(1800)
                        }

                        if !calendar.isDate(e, inSameDayAs: s) {
                            e = calendar.date(
                                bySettingHour: 23,
                                minute: 59,
                                second: 0,
                                of: s
                            )!
                        }

                        // 4️⃣ LIMIT
                        let tier = premium.tier
                        let limits = PremiumLimits.limits(for: tier)

                        if let maxDate = calendar.date(byAdding: .day,
                                                       value: limits.maxBookingDaysAhead,
                                                       to: now),
                           date > maxDate {

                            alertMessage = {
                                switch tier {
                                case .free: return String(localized: "limit_7_days")
                                case .premium: return String(localized: "limit_90_days")
                                case .pro: return String(localized: "limit_270_days")
                                }
                            }()

                            showAlert = true
                            isSaving = false
                            return
                        }
                        // 4️⃣b LIMIT SỐ EVENT / NGÀY
                        let sameDayEvents = eventManager.events.filter {
                            calendar.isDate($0.date, inSameDayAs: date)
                        }

                        if sameDayEvents.count >= limits.maxEventsPerDay {
                            alertMessage = String(localized: "event_limit_reached")
                            showAlert = true
                            isSaving = false
                            return
                        }

                        // 5️⃣ ADD EVENT
                        let success = eventManager.addEvent(
                            title: title,
                            ownerName: session.currentUserName,
                            date: date,
                            startTime: s,
                            endTime: e,
                            colorHex: selectedColor.toHex() ?? "#007AFF"
                        )

                        if success {
                            isSaving = false
                            dismiss()          // ✔️ feedback thành công
                        } else {
                            alertMessage = String(localized: "cannot_create_event")
                            showAlert = true  // ✔️ feedback thất bại
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)   // ⭐ CỰC KỲ QUAN TRỌNG CHO APPLE
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            // OFFDAY popup
            .alert(String(localized: "cannot_book"), isPresented: $showOffDayAlert) {
                Button(String(localized: "close"), role: .cancel) { }
            } message: {
                Text(offDayMessage)
            }

            // PREMIUM popup
            .alert(alertMessage, isPresented: $showAlert) {
                Button(String(localized:"ok"), role: .cancel) {}
            }
            .alert(
                String(localized: "busy_time"),
                isPresented: $showBusyInfo
            ) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                if let ev = busyInfoEvent {
                    Text("\(ev.title)\n\(formattedTime(ev.startTime)) – \(formattedTime(ev.endTime))")
                }
            }

        }
    }
    
    // Helper: combine date portion of `date` with time portion of `time`
    private func combine(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dComp = cal.dateComponents([.year, .month, .day], from: date)
        let tComp = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = dComp.year
        comps.month = dComp.month
        comps.day = dComp.day
        comps.hour = tComp.hour
        comps.minute = tComp.minute
        comps.second = tComp.second ?? 0
        return cal.date(from: comps) ?? date
    }
  
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    // ✅ THÊM MỚI — định dạng ngày hiển thị trong popup
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    
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

    var body: some View {
        VStack(spacing: 8) {
            // MARK: - Header tháng
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(formattedMonth(currentMonth))
                    .font(.headline)
                    

                Spacer()
                Button(action: { changeMonth(by: 1) }) {
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


struct DayEventsSheetView: View {
    @EnvironmentObject var eventManager: EventManager
    let date: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(eventManager.events(for: date)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    
                    // ⭐ Tiêu đề sự kiện
                    Text(event.title)
                        .font(.headline)
                    
                    // ⭐ Thêm hiển thị tên người tạo / người được tạo
                    if event.origin == .iCreatedForOther {
                        // A tạo cho B
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)   // A
                            Text(String(localized: "arrow_right"))
                            UserNameView(uid: event.owner)       // B
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    } else {
                        // Tự tạo hoặc người khác tạo cho tôi
                        Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // ⭐ Thời gian sự kiện
                    Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(String(localized: "day_prefix")) \(formattedDate(date))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }
        }
    }
    
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

}

struct CalendarActionButtonStyle: ViewModifier {

    let showsHint: Bool
    let hintText: String?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(12)
            .overlay(alignment: .bottom) {
                if showsHint, let hintText {
                    Text(hintText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }
            }
    }
}


extension View {
    func calendarActionStyle(
        showsHint: Bool = false,
        hintText: String? = nil
    ) -> some View {
        modifier(
            CalendarActionButtonStyle(
                showsHint: showsHint,
                hintText: hintText
            )
        )
    }
}

