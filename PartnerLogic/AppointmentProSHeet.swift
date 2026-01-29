//
// AppointmentProSheet.swift
// Easy schedule
//
// Created by ChatGPT for Sam Manh Cuong
//


import SwiftUI
import FirebaseAuth
import FirebaseFirestore


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
    @State private var partnerTier: PremiumTier = .free
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
                    offDays: partnerOffDays,
                    maxBookingDays: partnerMaxBookingDays
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
                    Button {
                        handleCreate()
                    } label: {
                        if eventManager.isAdding {
                            ProgressView()
                        } else {
                            Text(String(localized: "book"))
                        }
                    }
                    .disabled(
                        eventManager.isAdding ||
                        (!useCustomTime && selectedSlot == nil) ||
                        sharedUserId == nil ||
                        !NetworkMonitor.shared.isOnline ||
                        loading
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
                Alert(title:  Text(String(localized: "cant_book_title")),
                      message: Text(err.message),
                      dismissButton: .default(Text(String(localized: "close"))))
            }

            // Popup thành công
            .alert( String(localized: "success"), isPresented: $showSuccessAlert) {
                Button(String(localized:"ok")) {
                    isPresented = false
                }
            } message: {
                Text(String(localized: "booking_success_for_user"))
            }

            // Popup Premium — KHÔNG dùng lại errorMessage nữa
            .alert(String(localized: "notification"), isPresented: $showPremiumAlert) {
                Button(String(localized:"ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "user_not_premium"))
            }
            .padding(.bottom)
        }

        .onChange(of: selectedDate) { _, newValue in
            guard let maxDate = calendar.date(
                byAdding: .day,
                value: partnerMaxBookingDays,
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
                    let pastSlot = isPastSlot(slot)
                    let busy = checkBusy(slot)

                    SlotRowPro(
                        slot: slot,
                        isBusy: busy || pastSlot,   // 👈 coi slot quá giờ là busy
                        isSelected: selectedSlot == slot,
                        action: {
                            guard !isDayBlocked,
                                  !useCustomTime,
                                  !busy,
                                  !pastSlot else { return }

                            selectedSlot = slot
                        }
                    )
                    .opacity((isDayBlocked || pastSlot) ? 0.35 : 1.0)
                    .allowsHitTesting(!isDayBlocked && !pastSlot)
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
            value: partnerMaxBookingDays,
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
        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, tier in
            DispatchQueue.main.async {
                self.busySlots = slots
                self.partnerTier = tier
                self.busyIntervals = slots.map { ($0.startTime, $0.endTime) }
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

    private var partnerMaxBookingDays: Int {
        switch partnerTier {
        case .free:
            return 7
        case .premium:
            return 180
        case .pro:
            return 270   // hoặc 270 nếu bạn muốn
        }
    }

    // MARK: Xử lý đặt lịch
    private func handleCreate() {

        // ⭐ CUSTOM TIME VALIDATION — ĐẶT ĐẦU TIÊN
           if useCustomTime {

               guard customEnd > customStart else {
                   errorMessage = String(localized: "invalid_time_range")
                   return
               }

               selectedSlot = ProSlot(
                   start: combine(selectedDate, customStart),
                   end: combine(selectedDate, customEnd)
               )
           }
        if useCustomTime {
            let now = Date()
            let start = combine(selectedDate, customStart)

            if calendar.isDateInToday(start) && start < now {
                errorMessage = String(localized: "cannot_book_past_time")
                return
            }
        }

        // ❌ CHẶN ĐẶT LỊCH QUÁ KHỨ
        let startOfSelectedDay = Calendar.current.startOfDay(for: selectedDate)
        let today = Calendar.current.startOfDay(for: Date())

        if startOfSelectedDay < today {
            errorMessage = String(localized: "cannot_book_past_date")
            return
        }
        // ❗ CHẶN NGÀY NGHỈ — áp dụng cho cả custom và preset slots
        if partnerOffDays.contains(startOfSelectedDay) {
            errorMessage = String(localized: "owner_day_off_no_booking")
            return
        }
        // ⭐ BOOKING RANGE LIMIT (UI safety check)
        let maxDate = calendar.date(
            byAdding: .day,
            value: partnerMaxBookingDays,
            to: Date()
        )!


        if selectedDate > maxDate {
            errorMessage = {
                switch partnerTier {
                case .free:
                    return String(localized: "booking_limit_7_days")
                case .premium:
                    return String(localized: "premium_booking_limit_90_days")
                case .pro:
                    return String(localized: "pro_booking_limit_270_days")
                }
            }()

            return
        }

        // ⭐ CHECK FREE USER LIMIT (giống AddEventView)
        let calendar = Calendar.current
        let creatorUid = Auth.auth().currentUser?.uid ?? ""
        let eventsCreatedByMeToday = eventManager.events.filter {
            $0.createdBy == creatorUid &&
            calendar.isDate($0.startTime, inSameDayAs: selectedDate)
        }



        // ⭐ LIMIT CHECK — theo người tạo (B)
        let premium = PremiumStoreViewModel.shared
        let limits = premium.limits

        if eventsCreatedByMeToday.count >= limits.maxEventsPerDay {
            errorMessage = String(localized: "event_limit_reached")
            return
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
        if checkMyOwnConflict(slot) {
            errorMessage = String(localized: "you_have_event_this_time")
            return
        }

        eventManager.addAppointment(
            forSharedUser: uid,
            title: titleText,
            start: slot.start,
            end: slot.end
        ) { success, msg in
            DispatchQueue.main.async {
                if success { showSuccessAlert = true }
                else {
                    if let msg = msg,
                       msg.contains("granted access") || msg.contains("permission") {

                        errorMessage = String(localized: "booking_permission_required")

                    } else {
                        errorMessage = msg ?? String(localized: "create_event_failed")
                    }
                }

            }
        }
        
    }

    private func checkMyOwnConflict(_ slot: ProSlot) -> Bool {
        eventManager.events.contains {
            $0.startTime < slot.end &&
            $0.endTime > slot.start
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
    
    private func isPastDay(_ date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        return target < today
    }
    private func isPastSlot(_ slot: ProSlot) -> Bool {
        let calendar = Calendar.current

        // Chỉ áp dụng cho hôm nay
        guard calendar.isDateInToday(slot.start) else {
            return false
        }

        // Slot đã qua thời điểm hiện tại
        return slot.start < Date().addingTimeInterval(-60)
    }


    struct SimpleError: Identifiable {
        let id: Int
        let message: String
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

        // admins
        var admins: [String]? = nil
        if let arr = data["admins"] as? [String] {
            admins = arr
        } else if let arrAny = data["admins"] as? [Any] {
            admins = arrAny.compactMap { $0 as? String }
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
            admins: admins,
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

