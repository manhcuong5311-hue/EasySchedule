//
// AppointmentProSheet.swift
// Easy schedule
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore


struct AppointmentProSheet: View {
    @EnvironmentObject var eventManager: EventManager

    @Binding var isPresented: Bool
    let sharedUserId: String?
    let sharedUserName: String?

    @State private var showSuccessAlert  = false
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

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Partner info ──────────────────────────────────────
                    partnerHeaderCard

                    // ── Mini calendar ─────────────────────────────────────
                    calendarCard

                    // ── Off-day warning ───────────────────────────────────
                    if partnerOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                        offDayBanner
                    }

                    // ── Title ─────────────────────────────────────────────
                    titleCard

                    // ── Custom time ───────────────────────────────────────
                    customTimeCard

                    // ── 30-min slots ──────────────────────────────────────
                    if !useCustomTime {
                        slotsCard
                    }

                    Spacer(minLength: 24)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "create_appointment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { handleCreate() } label: {
                        if eventManager.isAdding {
                            ProgressView()
                        } else {
                            Text(String(localized: "book")).fontWeight(.semibold)
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
                if busySlots.isEmpty { loadBusy() }
            }
            .onChange(of: sharedUserId) { _, newValue in
                if newValue != nil { loadBusy() }
            }
            .onChange(of: selectedDate) { _, newDate in
                guard let maxDate = cal.date(
                    byAdding: .day, value: partnerMaxBookingDays, to: Date()
                ) else { return }
                if newDate > maxDate { selectedSlot = nil }
            }
            // Error alert
            .alert(item: Binding(
                get: { errorMessage.map { SimpleError(id: 0, message: $0) } },
                set: { _ in errorMessage = nil }
            )) { err in
                Alert(
                    title: Text(String(localized: "cant_book_title")),
                    message: Text(err.message),
                    dismissButton: .default(Text(String(localized: "close")))
                )
            }
            // Success alert
            .alert(String(localized: "success"), isPresented: $showSuccessAlert) {
                Button(String(localized: "ok")) { isPresented = false }
            } message: {
                Text(String(localized: "booking_success_for_user"))
            }
            // Premium alert
            .alert(String(localized: "notification"), isPresented: $showPremiumAlert) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                Text(String(localized: "user_not_premium"))
            }
        }
    }

    // MARK: – Subviews

    private var partnerHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: "person.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "recipient"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sharedUserName ?? sharedUserId ?? String(localized: "no_name"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            if loading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.85)
                    Text("Loading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var calendarCard: some View {
        CalendarMiniView(
            selectedDate: $selectedDate,
            busySlots: busySlots,
            offDays: partnerOffDays,
            maxBookingDays: partnerMaxBookingDays
        )
        .frame(height: 260)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var offDayBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "owner_day_off"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                Text("No appointments can be booked on this day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "title_section"), systemImage: "pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(String(localized: "event_title_placeholder"), text: $titleText)
            }
            .padding(14)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Give the appointment a descriptive name so the recipient knows what it's for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var customTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "custom_time_section"), systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle(String(localized: "use_custom_time"), isOn: $useCustomTime)
                .tint(.accentColor)

            if useCustomTime {
                Divider()

                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "start_time"))
                            .font(.subheadline)
                        Spacer()
                        DatePicker("", selection: $customStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)

                    Divider()

                    HStack {
                        Text(String(localized: "end_time"))
                            .font(.subheadline)
                        Spacer()
                        DatePicker("", selection: $customEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: customEnd) {
                                if customEnd <= customStart {
                                    customEnd = Calendar.current.date(
                                        byAdding: .minute, value: 15, to: customStart
                                    ) ?? customEnd
                                }
                            }
                    }
                    .padding(.vertical, 6)
                }

                let previewSlot = ProSlot(
                    start: combine(selectedDate, customStart),
                    end:   combine(selectedDate, customEnd)
                )
                if checkBusy(previewSlot) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(String(localized: "time_unavailable"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }

                Text("Choose a specific start and end time instead of a preset 30-minute slot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: useCustomTime)
    }

    private var slotsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "time_slots_30min"), systemImage: "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isDayBlocked {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("This date is outside the partner's booking window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 8
                ) {
                    ForEach(slotsForSelectedDate, id: \.self) { slot in
                        let pastSlot = isPastSlot(slot)
                        let busy     = checkBusy(slot)
                        let blocked  = isDayBlocked || pastSlot
                        let isSelected = selectedSlot == slot

                        slotCell(
                            slot:       slot,
                            isBusy:     busy,
                            isPast:     pastSlot,
                            isSelected: isSelected
                        )
                        .opacity(blocked ? 0.35 : 1.0)
                        .allowsHitTesting(!blocked)
                        .onTapGesture {
                            guard !isDayBlocked, !busy, !pastSlot else { return }
                            withAnimation(.spring(response: 0.22)) {
                                selectedSlot = (selectedSlot == slot) ? nil : slot
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 14) {
                    legendDot(color: Color(.systemGray4),      label: "Available")
                    legendDot(color: .red.opacity(0.55),       label: "Busy")
                    legendDot(color: Color.accentColor.opacity(0.8), label: "Selected")
                }
                .font(.caption2)
                .padding(.top, 4)

                Text("Tap a slot to select it. Busy and past slots cannot be booked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func slotCell(slot: ProSlot, isBusy: Bool, isPast: Bool, isSelected: Bool) -> some View {
        let start = slot.start.formatted(date: .omitted, time: .shortened)
        let bgColor: Color = isSelected ? Color.accentColor.opacity(0.85)
                           : isBusy    ? Color.red.opacity(0.16)
                           : isPast    ? Color(.systemGray5)
                           : Color(.systemGray6)
        let fgColor: Color = isSelected ? .white
                           : isBusy    ? .red.opacity(0.75)
                           : isPast    ? Color(.systemGray3)
                           : .primary

        Text(start)
            .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(bgColor))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(fgColor)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: – Computed

    private var slotsForSelectedDate: [ProSlot] { generateSlots(for: selectedDate) }

    private var isDayBlocked: Bool {
        guard let maxDate = cal.date(byAdding: .day, value: partnerMaxBookingDays, to: Date())
        else { return false }
        return selectedDate > maxDate
    }

    private var partnerMaxBookingDays: Int {
        switch partnerTier {
        case .free:    return 7
        case .premium: return 180
        case .pro:     return 270
        }
    }

    // MARK: – Data loading

    private func loadBusy() {
        guard NetworkMonitor.shared.isOnline else {
            loading        = false
            busySlots      = []
            partnerOffDays = []
            errorMessage   = String(localized: "no_internet_connection")
            return
        }

        guard let uid = sharedUserId else {
            loading      = false
            busySlots    = []
            errorMessage = String(localized: "unknown_uid")
            return
        }

        loading = true

        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, tier in
            DispatchQueue.main.async {
                self.busySlots      = slots
                self.partnerTier    = tier
                self.busyIntervals  = slots.map { ($0.startTime, $0.endTime) }
            }
        }

        eventManager.fetchOffDays(for: uid, forceRefresh: true) { offDays in
            DispatchQueue.main.async {
                self.partnerOffDays = offDays
                self.loading        = false
            }
        }
    }

    // MARK: – Booking

    private func handleCreate() {

        // ── Custom time: validate, check past, then set selectedSlot ──
        if useCustomTime {
            guard customEnd > customStart else {
                errorMessage = String(localized: "invalid_time_range")
                return
            }

            let start = combine(selectedDate, customStart)
            let end   = combine(selectedDate, customEnd)

            if cal.isDateInToday(selectedDate) && start < Date() {
                errorMessage = String(localized: "cannot_book_past_time")
                return
            }

            selectedSlot = ProSlot(start: start, end: end)
        }

        // ── Past date check ───────────────────────────────────────────
        let startOfSelected = Calendar.current.startOfDay(for: selectedDate)
        let today           = Calendar.current.startOfDay(for: Date())

        if startOfSelected < today {
            errorMessage = String(localized: "cannot_book_past_date")
            return
        }

        // ── Off-day check ─────────────────────────────────────────────
        if partnerOffDays.contains(startOfSelected) {
            errorMessage = String(localized: "owner_day_off_no_booking")
            return
        }

        // ── Booking range limit ───────────────────────────────────────
        let maxDate = cal.date(byAdding: .day, value: partnerMaxBookingDays, to: Date())!
        if selectedDate > maxDate {
            switch partnerTier {
            case .free:    errorMessage = String(localized: "booking_limit_7_days")
            case .premium: errorMessage = String(localized: "premium_booking_limit_90_days")
            case .pro:     errorMessage = String(localized: "pro_booking_limit_270_days")
            }
            return
        }

        // ── Per-day event limit (for the requester) ───────────────────
        let creatorUid  = Auth.auth().currentUser?.uid ?? ""
        let myEventsToday = eventManager.events.filter {
            $0.createdBy == creatorUid &&
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
        let limits = PremiumStoreViewModel.shared.limits
        if myEventsToday.count >= limits.maxEventsPerDay {
            errorMessage = String(localized: "event_limit_reached")
            return
        }

        // ── Network ───────────────────────────────────────────────────
        guard NetworkMonitor.shared.isOnline else {
            errorMessage = String(localized: "no_internet_connection")
            return
        }

        // ── Required fields ───────────────────────────────────────────
        guard let uid  = sharedUserId else {
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

        // ── Own calendar conflict ─────────────────────────────────────
        if checkMyOwnConflict(slot) {
            errorMessage = String(localized: "you_have_event_this_time")
            return
        }

        // ── Create ────────────────────────────────────────────────────
        eventManager.addAppointment(
            forSharedUser: uid,
            title: titleText,
            start: slot.start,
            end:   slot.end
        ) { success, msg in
            DispatchQueue.main.async {
                if success {
                    self.showSuccessAlert = true
                } else {
                    if let msg = msg,
                       msg.contains("granted access") || msg.contains("permission") {
                        self.errorMessage = String(localized: "booking_permission_required")
                    } else {
                        self.errorMessage = msg ?? String(localized: "create_event_failed")
                    }
                }
            }
        }
    }

    private func checkMyOwnConflict(_ slot: ProSlot) -> Bool {
        eventManager.events.contains {
            $0.startTime < slot.end && $0.endTime > slot.start
        }
    }

    // MARK: – Helpers

    private func combine(_ date: Date, _ time: Date) -> Date {
        let c = Calendar.current
        let d = c.dateComponents([.year, .month, .day], from: date)
        let t = c.dateComponents([.hour, .minute], from: time)
        return c.date(from: DateComponents(
            year: d.year, month: d.month, day: d.day,
            hour: t.hour, minute: t.minute
        ))!
    }

    private func checkBusy(_ slot: ProSlot) -> Bool {
        let day = Calendar.current.startOfDay(for: slot.start)
        if partnerOffDays.contains(day) { return true }
        return busyIntervals.contains { $0.0 < slot.end && $0.1 > slot.start }
    }

    private func generateSlots(for date: Date) -> [ProSlot] {
        guard let startOfDay = cal.date(bySettingHour: 0, minute: 0, second: 0, of: date)
        else { return [] }
        return (0..<48).map { i in
            let s = startOfDay.addingTimeInterval(Double(i) * 1800)
            return ProSlot(start: s, end: s.addingTimeInterval(1800))
        }
    }

    private func isPastSlot(_ slot: ProSlot) -> Bool {
        guard Calendar.current.isDateInToday(slot.start) else { return false }
        return slot.start < Date().addingTimeInterval(-60)
    }

    struct SimpleError: Identifiable {
        let id: Int
        let message: String
    }
}


// MARK: – Preview

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


// MARK: – CalendarEvent from Firestore

extension CalendarEvent {
    static func from(_ doc: DocumentSnapshot) -> CalendarEvent? {
        let data = doc.data() ?? [:]

        let start = parseDate(data["startTime"] ?? data["start"])
        let end   = parseDate(data["endTime"]   ?? data["end"])
        guard let s = start, let e = end else { return nil }
        guard let title = data["title"] as? String else { return nil }
        guard let owner = data["owner"] as? String else { return nil }

        let sharedUser = data["sharedUser"] as? String ?? ""
        let createdBy  = data["createdBy"]  as? String ?? ""
        let colorHex   = data["colorHex"]   as? String ?? "#007AFF"

        var participants: [String] = []
        if let arr = data["participants"] as? [String]     { participants = arr }
        else if let arr = data["participants"] as? [Any]   { participants = arr.compactMap { $0 as? String } }

        var admins: [String]? = nil
        if let arr = data["admins"] as? [String]           { admins = arr }
        else if let arr = data["admins"] as? [Any]         { admins = arr.compactMap { $0 as? String } }

        let participantNames = data["participantNames"] as? [String: String] ?? [:]
        let creatorName      = data["creatorName"]      as? String ?? ""

        let current      = Auth.auth().currentUser?.uid ?? ""
        let isMyCalendar = (owner == current)
        let isCreatedByMe = (createdBy == current)

        let origin: EventOrigin = isMyCalendar
            ? (isCreatedByMe ? .myEvent      : .createdForMe)
            : (isCreatedByMe ? .iCreatedForOther : .createdForMe)

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
            participantNames: participantNames,
            creatorName: creatorName,
            colorHex: colorHex,
            pendingDelete: false,
            origin: origin
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d  = value as? Double    { return Date(timeIntervalSince1970: d) }
        if let i  = value as? Int       { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }
}
