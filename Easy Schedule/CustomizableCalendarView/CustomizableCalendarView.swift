//
//  CustomizableCalendarView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 24/12/25.
//
import SwiftUI
import Combine
import FirebaseAuth

enum BusyHoursStyle {

    /// Màu semantic cho trạng thái "có busy hours"
    static let activeColor = Color(hex: "#FFB020")   // amber, KHÔNG trùng accent iOS

    /// Background nhẹ cho trạng thái active
    static let activeBackground = Color(hex: "#FFB020").opacity(0.15)

    /// Icon khi chưa có busy hours → dùng accent
    static func iconColor(
        hasBusy: Bool,
        accent: Color
    ) -> Color {
        hasBusy ? activeColor : accent
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
    @EnvironmentObject var guideManager: GuideManager

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
    @State private var showCalendarGuide = false
//NEWWWWWWWWWW
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme


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
            calendarContentWithGuide
        }
    }


    private var mainContent: some View {
        ZStack {

            ScrollView {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {

                        HStack(spacing: 8) {
                            Text(String(localized: "title_my"))
                                .foregroundColor(uiAccent.color)

                            Text(String(localized: "title_calendar"))
                                .foregroundColor(.primary)
                        }

                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(TitleShadow.primary(colorScheme))   // ⭐ NEW


                        Text(String(localized: "view_and_manage_your_calendar"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .shadow(
                                color: colorScheme == .dark
                                    ? Color.white.opacity(0.15)
                                    : Color.black.opacity(0.10),
                                radius: 1,
                                y: 1
                            )

                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

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
            // ⭐⭐ NÚT + FLOATING (TO – RÕ – PREMIUM) ⭐⭐
            VStack {
                HStack {
                    Spacer()

                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))   // ⭐ TO RÕ HƠN
                            .foregroundColor(uiAccent.color)
                            .frame(width: 52, height: 52)             // ⭐ KÍCH THƯỚC NÚT
                            .background(
                                Circle()
                                    .fill(Color(.systemBackground))
                            )
                            .shadow(
                                color: colorScheme == .dark
                                    ? Color.white.opacity(0.35)
                                    : Color.black.opacity(0.25),
                                radius: 6,
                                y: 3
                            )
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 10)

                Spacer()
            }

        }
        .toolbar(.hidden, for: .navigationBar)

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

    private var calendarContentWithGuide: some View {
        ZStack {
            mainContent

            if guideManager.isActive(.calendarIntro) {
                calendarIntroOverlay
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
                    .foregroundColor(uiAccent.color)

                Text(String(localized: "share_calendar"))
                    .font(.body.weight(.semibold))
            }
        }
        .calendarActionStyle()
        .padding(.horizontal)
        .modifier(ActionButtonShadow.primary(colorScheme))
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
   
    private var addEventSheet: some View {
        AddEventView(
            prefillDate: selectedDate,
            offDays: offDays,
            busyHours: localBusyIntervals   // 👈 TRUYỀN VÀO
        )
        .environmentObject(eventManager)
    }
    
    private var calendarIntroOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guideManager.complete(.calendarIntro)
                    }

                VStack {
                    GuideBubble(
                        textKey: "calendar_intro_text",
                        onNext: {
                            guideManager.complete(.calendarIntro)
                        },
                        onDoNotShowAgain: {
                            guideManager.disablePermanently(.calendarIntro)
                        }
                    )

                    .frame(maxWidth: min(420, geo.size.width * 0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 140)
            }
        }
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

        // 1️⃣ Event busy
        eventBusyIntervals = eventManager.events(for: date)
            .map { ($0.startTime, $0.endTime) }

        // 2️⃣ Manual busy – OWNER (NGUỒN CHUẨN)
        localBusyIntervals =
            eventManager.myManualBusySlots
                .filter {
                    Calendar.current.isDate($0.startTime, inSameDayAs: date)
                }
                .map { ($0.startTime, $0.endTime) }
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
                       .foregroundColor(uiAccent.color)

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
               .modifier(ActionButtonShadow.primary(colorScheme))
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
                    Image(systemName: hasBusy ? "clock.badge.exclamationmark" : "clock")
                        .foregroundColor(
                            BusyHoursStyle.iconColor(
                                hasBusy: hasBusy,
                                accent: uiAccent.color
                            )
                        )

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
                    .fill(
                        hasBusy
                        ? BusyHoursStyle.activeBackground
                        : Color.clear
                    )
            )
            .modifier(ActionButtonShadow.primary(colorScheme))
            .overlay(alignment: .topTrailing) {
                if hasBusy {
                    Circle()
                        .fill(BusyHoursStyle.activeColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -6, y: 6)
                }
            }

            .padding(.horizontal)



        }
    }
    
    
}

struct ActionButtonShadow {

    static func primary(_ scheme: ColorScheme) -> some ViewModifier {
        ShadowModifier(
            main: scheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.18),
            mainRadius: 8,
            mainY: 4,
            secondary: scheme == .dark
                ? Color.white.opacity(0.06)
                : Color.black.opacity(0.08),
            secondaryRadius: 3,
            secondaryY: 1
        )
    }
}

private struct ShadowModifier: ViewModifier {
    let main: Color
    let mainRadius: CGFloat
    let mainY: CGFloat
    let secondary: Color
    let secondaryRadius: CGFloat
    let secondaryY: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: main, radius: mainRadius, y: mainY)
            .shadow(color: secondary, radius: secondaryRadius, y: secondaryY)
    }
}




