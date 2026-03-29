//
//  CustomizableCalendarView.swift
//  Easy Schedule
//
import SwiftUI
import Combine
import FirebaseAuth

// MARK: - Style helpers (logic unchanged)

enum BusyHoursStyle {
    static let activeColor      = Color(hex: "#FFB020")
    static let activeBackground = Color(hex: "#FFB020").opacity(0.15)
    static func iconColor(hasBusy: Bool, accent: Color) -> Color {
        hasBusy ? activeColor : accent
    }
}

private struct BusyKey: Hashable {
    let start: Date; let end: Date
    init(_ start: Date, _ end: Date) { self.start = start; self.end = end }
}

// MARK: - Main view

struct CustomizableCalendarView: View {

    // ── Environment ──────────────────────────────────────────────
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var guideManager: GuideManager
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme

    // ── State (all original, untouched) ──────────────────────────
    @State private var selectedDate: Date? = nil
    @State private var showAddSheet         = false
    @State private var showDeleteAlert      = false
    @State private var eventToDelete: CalendarEvent? = nil
    @State private var showShareSheet       = false
    @State private var shareItem: ShareItem?
    @State private var isTogglingOffDay     = false
    @State private var isCooldown           = false
    @State private var toggleCount          = 0
    @State private var showCooldownToast    = false
    @State private var cooldownRemaining    = 0
    @State private var isLoadingOffDays     = false
    @State private var showOffDayAlert      = false
    @State private var offDayAlertMessage   = ""
    @State private var showBusyHoursSheet   = false
    @State private var localBusyIntervals: [(Date, Date)] = []
    @State private var eventBusyIntervals: [(Date, Date)] = []
    @State private var showConfirmOffDayAlert = false
    @State private var pendingOffDayDate: Date? = nil
    @State private var showCalendarGuide    = false

    @State private var offDays: Set<Date> = [] {
        didSet { guard !isLoadingOffDays else { return }; saveOffDaysToLocal() }
    }

    // MARK: body
    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
                if guideManager.isActive(.calendarIntro) { calendarIntroOverlay }
            }
        }
    }

    // MARK: - Main content
    private var mainContent: some View {
        ZStack(alignment: .bottomTrailing) {

            ScrollView {
                VStack(spacing: 0) {

                    HStack(alignment: .top) {
                        headerSection
                        Spacer()
                        fab
                    }
                    .padding(.top, 16)
                    .padding(.horizontal)

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

                    // ── Settings cards ──
                    settingsSection
                        .padding(.top, 20)
                        .padding(.horizontal)

                    // ── Selected day panel ──
                    if let date = selectedDate {
                        selectedDayPanel(date: date)
                            .padding(.top, 20)
                            .padding(.horizontal)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Spacer(minLength: 100)
                }
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: selectedDate)
            }

            // ── Cooldown toast ──
            cooldownToast
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddSheet)      { addEventSheet }
        .sheet(isPresented: $showBusyHoursSheet){ busyHoursSheet }
        .sheet(item: $shareItem)                { ActivityView(activityItems: [$0.url]) }
        .alert(String(localized: "delete_event_title"),     isPresented: $showDeleteAlert)      { deleteAlertButtons }   message: { deleteAlertMessage }
        .alert(String(localized: "off_day_title"),          isPresented: $showOffDayAlert)       { Button(String(localized: "ok")) {} }  message: { Text(offDayAlertMessage) }
        .alert(String(localized: "off_day_warning_title"),  isPresented: $showConfirmOffDayAlert){ offDayWarningButtons } message: { Text(String(localized: "off_day_warning_message")) }
        .onAppear { loadOffDaysFromLocal(); cleanPastOffDays() }
        .onChange(of: selectedDate, initial: false) { _, v in handleDateChange(v) }
        .onChange(of: showConfirmOffDayAlert) { _, shown in if !shown { handleDateChange(selectedDate) } }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(String(localized: "title_my"))
                    .foregroundColor(uiAccent.color)
                Text(String(localized: "title_calendar"))
                    .foregroundColor(.primary)
            }
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .tracking(-0.4)
            .modifier(TitleShadow.primary(colorScheme))

            Text(String(localized: "view_and_manage_your_calendar"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Settings section
    private var settingsSection: some View {
        VStack(spacing: 10) {

            // Allow overlap toggle card
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(uiAccent.color.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(uiAccent.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "allow_conflict"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "allow_conflict_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { eventManager.allowDuplicateEvents },
                    set: { eventManager.allowDuplicateEvents = $0 }
                ))
                .labelsHidden()
                .tint(uiAccent.color)
            }
            .padding(14)
            .background(settingsCardBackground)
            .modifier(ActionButtonShadow.primary(colorScheme))

            // Share calendar card
            Button {
                if let uid = Auth.auth().currentUser?.uid,
                   let url = URL(string: "https://easyschedule-ce98a.web.app/calendar/\(uid)") {
                    shareItem = ShareItem(url: url)
                }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "share_calendar"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "share_calendar_hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(settingsCardBackground)
            }
            .buttonStyle(.plain)
            .modifier(ActionButtonShadow.primary(colorScheme))
        }
    }

    private var settingsCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.systemGray6))
    }

    // MARK: - Selected day panel
    private func selectedDayPanel(date: Date) -> some View {
        VStack(spacing: 12) {

            // Day header
            dayHeaderCard(date: date)

            // Action tiles (2-column grid)
            HStack(spacing: 12) {
                dayOffTile(date: date)
                busyHoursTile(date: date)
            }

            // Mini event list for this day
            let dayEvents = eventManager.events(for: date).filter { $0.origin != .busySlot }
            if !dayEvents.isEmpty {
                dayEventsPreview(events: dayEvents)
            }
        }
    }

    // ── Day header card ──
    private func dayHeaderCard(date: Date) -> some View {
        let eventCount = eventManager.events(for: date).filter { $0.origin != .busySlot }.count
        let hasBusy    = hasBusyHours(on: date)
        let off        = isOffDay(date)

        return HStack(spacing: 12) {
            // Large date badge
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(uiAccent.color)
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(width: 52, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(uiAccent.color.opacity(0.1))
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 6) {
                    if eventCount > 0 {
                        Label("\(eventCount)", systemImage: "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if hasBusy {
                        Label(String(localized: "busy_hours"), systemImage: "clock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BusyHoursStyle.activeColor)
                    }
                    if off {
                        Label(String(localized: "day_off_badge"), systemImage: "moon.zzz.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if eventCount == 0 && !hasBusy && !off {
                        Text(String(localized: "no_events_today"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
        )
        .modifier(ActionButtonShadow.primary(colorScheme))
    }

    // ── Day Off tile ──
    private func dayOffTile(date: Date) -> some View {
        let off        = isOffDay(date)
        let isPast     = isPastDay(date)
        let tileColor  = off ? Color.secondary : uiAccent.color

        return Button {
            guard !isPast else {
                offDayAlertMessage = String(localized: "cannot_set_offday_in_past")
                showOffDayAlert = true
                return
            }
            guard !isCooldown else { showCooldownMessage(); return }

            if !off && hasEventOrBusy(on: date) {
                pendingOffDayDate = date
                showConfirmOffDayAlert = true
                return
            }

            toggleCount += 1
            if toggleCount >= 3 { startCooldown(seconds: 5); return }
            toggleOffDay(for: date)
            eventManager.syncOffDaysToFirebase(offDays: offDays)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(tileColor.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: off ? "xmark.circle.fill" : "bed.double.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tileColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(off
                         ? String(localized: "reopen_day")
                         : String(localized: "set_day_off"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPast ? .secondary : .primary)

                    Text(off
                         ? String(localized: "day_off_tile_hint_active")
                         : String(localized: "day_off_tile_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(off
                          ? tileColor.opacity(0.08)
                          : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(off ? tileColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPast || isCooldown)
        .modifier(ActionButtonShadow.primary(colorScheme))
    }

    // ── Busy Hours tile ──
    private func busyHoursTile(date: Date) -> some View {
        let hasBusy    = hasBusyHours(on: date)
        let off        = isOffDay(date)
        let tileColor  = hasBusy ? BusyHoursStyle.activeColor : uiAccent.color

        // Count blocked slots for subtitle
        let blockedCount = localBusyIntervals.filter {
            Calendar.current.isDate($0.0, inSameDayAs: date)
        }.count

        // Slots for this day, sorted by start time
        let daySlots = localBusyIntervals
            .filter { Calendar.current.isDate($0.0, inSameDayAs: date) }
            .sorted { $0.0 < $1.0 }

        return Button {
            guard !off else {
                offDayAlertMessage = String(localized: "busy_hours_disabled_off_day")
                showOffDayAlert = true
                return
            }
            showBusyHoursSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(tileColor.opacity(off ? 0.06 : 0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: hasBusy ? "clock.badge.exclamationmark.fill" : "clock.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tileColor.opacity(off ? 0.4 : 1))
                    }

                    if hasBusy && !off {
                        Text("\(blockedCount) \(String(localized: "slots_blocked"))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(BusyHoursStyle.activeColor))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "busy_hours"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(off ? .secondary : .primary)

                    Text(off
                         ? String(localized: "busy_hours_off_day_hint")
                         : (hasBusy
                            ? String(localized: "busy_hours_tile_hint_active")
                            : String(localized: "busy_hours_tile_hint")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ── Time chips: show up to 3 slots inline ──
                if hasBusy && !off && !daySlots.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(daySlots.prefix(3).enumerated()), id: \.offset) { _, slot in
                            HStack(spacing: 4) {
                                Image(systemName: "minus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(BusyHoursStyle.activeColor.opacity(0.8))
                                Text("\(formattedTime(slot.0)) – \(formattedTime(slot.1))")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(BusyHoursStyle.activeColor)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(BusyHoursStyle.activeColor.opacity(0.12))
                            )
                        }
                        if daySlots.count > 3 {
                            Text("more_slots_format \(daySlots.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 2)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hasBusy && !off
                          ? BusyHoursStyle.activeBackground
                          : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(hasBusy && !off ? BusyHoursStyle.activeColor.opacity(0.35) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .modifier(ActionButtonShadow.primary(colorScheme))
    }

    // ── Mini event list ──
    private func dayEventsPreview(events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "events_on_this_day"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(events.prefix(3)) { event in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(event.eventColor)
                        .frame(width: 3, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("\(event.formattedStartTime) – \(event.formattedEndTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: event.participants.count > 1 ? "person.2.fill" : "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemGray6))
                )
            }

            if events.count > 3 {
                Text(String(format: String(localized: "and_more_events"), events.count - 3))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Floating Action Button
    private var fab: some View {
        Button {
            showAddSheet = true
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [uiAccent.color, uiAccent.color.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .shadow(
                    color: uiAccent.color.opacity(colorScheme == .dark ? 0.5 : 0.4),
                    radius: 10, y: 5
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }

    // MARK: - Cooldown toast
    private var cooldownToast: some View {
        VStack {
            Spacer()
            if showCooldownToast {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(.white.opacity(0.8))
                    Text(String(format: String(localized: "cooldown_message"), cooldownRemaining))
                        .foregroundStyle(.white)
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .background(Capsule().fill(Color.black.opacity(0.78)))
                )
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCooldownToast)
    }

    // MARK: - Guide overlay
    private var calendarIntroOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { guideManager.complete(.calendarIntro) }

                VStack {
                    GuideBubble(
                        textKey: "calendar_intro_text",
                        onNext: { guideManager.complete(.calendarIntro) },
                        onDoNotShowAgain: { guideManager.disablePermanently(.calendarIntro) }
                    )
                    .frame(maxWidth: min(420, geo.size.width * 0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 140)
            }
        }
    }

    // MARK: - Sheets
    private var addEventSheet: some View {
        AddEventView(prefillDate: selectedDate, offDays: offDays, busyHours: localBusyIntervals)
            .environmentObject(eventManager)
    }

    private var busyHoursSheet: some View {
        Group {
            if let date = selectedDate {
                let eventBusy: [(Date, Date)] = eventManager.events(for: date).map { ($0.startTime, $0.endTime) }
                BusyHoursPickerView(
                    date: date,
                    eventBusyIntervals: eventBusy,
                    busyHourIntervals: localBusyIntervals,
                    onSave: { added, removed in
                        guard let uid = eventManager.currentUserId else { return }
                        if !added.isEmpty   { eventManager.addBusyHoursForDay(userId: uid, slots: added) }
                        if !removed.isEmpty { eventManager.removeManualBusySlots(userId: uid, slots: removed) }
                        localBusyIntervals.append(contentsOf: added.map { ($0.start, $0.end) })
                        let removedPairs = removed.map { ($0.start, $0.end) }
                        localBusyIntervals.removeAll { i in removedPairs.contains { $0.0 == i.0 && $0.1 == i.1 } }
                        showBusyHoursSheet = false
                    }
                )
                .environmentObject(network)
            }
        }
    }

    // MARK: - Alert content
    private var deleteAlertButtons: some View {
        Group {
            Button(String(localized: "ok"), role: .destructive) {
                if let e = eventToDelete { eventManager.deleteEvent(e) }
                eventToDelete = nil
            }
            Button(String(localized: "cancel"), role: .cancel) { eventToDelete = nil }
        }
    }
    private var deleteAlertMessage: some View {
        Text(String(format: String(localized: "delete_event_full"), eventToDelete?.title ?? ""))
    }
    private var offDayWarningButtons: some View {
        Group {
            Button(String(localized: "confirm"), role: .destructive) {
                if let date = pendingOffDayDate {
                    toggleOffDay(for: date)
                    eventManager.syncOffDaysToFirebase(offDays: offDays)
                }
                pendingOffDayDate = nil
            }
            Button(String(localized: "cancel"), role: .cancel) {
                pendingOffDayDate = nil
                if let uid = eventManager.currentUserId, let date = selectedDate {
                    let dayStart = calendar.startOfDay(for: date)
                    let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                    localBusyIntervals = eventManager.partnerBusySlots[uid]?
                        .filter { $0.colorHex == "#FFA500" && $0.startTime < dayEnd && $0.endTime > dayStart }
                        .map { ($0.startTime, $0.endTime) } ?? []
                }
            }
        }
    }

    // MARK: - Business logic (all original, untouched)

    private var calendar: Calendar {
        var cal = Calendar.current; cal.firstWeekday = 2; return cal
    }
    private func hasEventOrBusy(on date: Date) -> Bool {
        let s = calendar.startOfDay(for: date)
        let e = calendar.date(byAdding: .day, value: 1, to: s)!
        return !eventManager.events(for: s).isEmpty ||
               localBusyIntervals.contains { $0.0 < e && $0.1 > s }
    }
    private func hasBusyHours(on date: Date) -> Bool {
        let s = calendar.startOfDay(for: date)
        let e = calendar.date(byAdding: .day, value: 1, to: s)!
        return localBusyIntervals.contains { $0.0 < e && $0.1 > s }
    }
    private func saveOffDaysToLocal() {
        UserDefaults.standard.set(offDays.map { $0.timeIntervalSince1970 }, forKey: "offDays")
    }
    private func loadOffDaysFromLocal() {
        isLoadingOffDays = true
        let ts = UserDefaults.standard.array(forKey: "offDays") as? [Double] ?? []
        offDays = Set(ts.map { Date(timeIntervalSince1970: $0) })
        isLoadingOffDays = false
    }
    private func cleanPastOffDays() {
        let today   = calendar.startOfDay(for: Date())
        let cleaned = offDays.filter { calendar.startOfDay(for: $0) >= today }
        guard cleaned != offDays else { return }
        isLoadingOffDays = true; offDays = cleaned; isLoadingOffDays = false
        eventManager.syncOffDaysToFirebase(offDays: offDays)
    }
    private func isPastDay(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }
    private func toggleOffDay(for date: Date) {
        let key = calendar.startOfDay(for: date)
        if offDays.contains(key) { offDays.remove(key) } else { offDays.insert(key) }
    }
    private func isOffDay(_ date: Date) -> Bool {
        offDays.contains(calendar.startOfDay(for: date))
    }
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    private func handleDateChange(_ newDate: Date?) {
        guard let date = newDate else { return }
        eventBusyIntervals = eventManager.events(for: date).map { ($0.startTime, $0.endTime) }
        localBusyIntervals = eventManager.myManualBusySlots
            .filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
            .map { ($0.startTime, $0.endTime) }
    }
    func startCooldown(seconds: Int) {
        isCooldown = true; cooldownRemaining = seconds; showCooldownToast = true
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            self.cooldownRemaining -= 1
            if self.cooldownRemaining <= 0 {
                timer.invalidate()
                self.isCooldown = false; self.showCooldownToast = false; self.toggleCount = 0
            }
        }
    }
    func showCooldownMessage() {
        showCooldownToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showCooldownToast = false }
    }
    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event; showDeleteAlert = true
    }
}

// MARK: - Shared shadow modifier (unchanged)

struct ActionButtonShadow {
    static func primary(_ scheme: ColorScheme) -> some ViewModifier {
        ShadowModifier(
            main:            scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.18),
            mainRadius:      8, mainY: 4,
            secondary:       scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08),
            secondaryRadius: 3, secondaryY: 1
        )
    }
}

private struct ShadowModifier: ViewModifier {
    let main: Color; let mainRadius: CGFloat; let mainY: CGFloat
    let secondary: Color; let secondaryRadius: CGFloat; let secondaryY: CGFloat
    func body(content: Content) -> some View {
        content
            .shadow(color: main,      radius: mainRadius,      y: mainY)
            .shadow(color: secondary, radius: secondaryRadius, y: secondaryY)
    }
}
