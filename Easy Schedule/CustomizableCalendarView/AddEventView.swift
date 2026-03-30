//
//  AddEventView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

enum SaveEventAlert: Identifiable {
    case offDay(Date)
    case emptyTitle
    case pastTime
    case busyHours
    case conflict
    case overBookingDays(Int)
    case overEventsPerDay
    case cannotCreate
    case endBeforeStart

    var id: String {
        String(describing: self)
    }
}

enum SlotInfoAlert: Identifiable {
    case event(CalendarEvent)
    case busyHours
    case offDay

    var id: String {
        String(describing: self)
    }
}

enum AddEventAlert: Identifiable {
    case save(SaveEventAlert)
    case slot(SlotInfoAlert)

    var id: String {
        switch self {
        case .save(let alert):  return "save-\(alert.id)"
        case .slot(let alert):  return "slot-\(alert.id)"
        }
    }
}


struct AddEventView: View {

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColor: Color = .blue
    @State private var selectedColorIndex: Int = 0
    @State private var selectedIcon: String = ""
    @State private var showIconPicker = false

    let prefillDate: Date?
    let offDays: Set<Date>
    let busyHours: [(Date, Date)]

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800)

    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var session: SessionStore
    @State private var hasSelectedSlot = false
    @State private var isSaving = false

    /// Wraps `date` so changing the calendar selection also resets the hour grid.
    private var dateBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newDate in
                date = newDate
                hasSelectedSlot = false
            }
        )
    }

    @State private var activeAlert: AddEventAlert?
    @State private var showUpgradeSheet = false
    @State private var showPremiumIntro = false
    @Environment(\.requestReview) private var requestReview

    private let paletteColors: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal
    ]

    // MARK: – Body

    var body: some View {
        NavigationStack {
            Form {

                // ── 1. Title ───────────────────────────────────────────────
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        TextField(String(localized: "title_placeholder"), text: $title)
                    }
                } header: {
                    sectionHeader(String(localized: "info_section"), icon: "doc.text")
                } footer: {
                    Text("event_title_hint")
                }

                // ── 2. Appearance ─────────────────────────────────────────
                Section {
                    // Icon picker row
                    Button { showIconPicker = true } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(selectedColor.opacity(0.15))
                                    .frame(width: 48, height: 48)
                                Circle()
                                    .strokeBorder(selectedColor.opacity(0.40), lineWidth: 1.5)
                                    .frame(width: 48, height: 48)
                                Image(systemName: selectedIcon.isEmpty ? "face.smiling" : selectedIcon)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(selectedColor)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(selectedIcon.isEmpty
                                     ? String(localized: "choose_icon_title")
                                     : String(localized: "change"))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if selectedIcon.isEmpty {
                                    Text("Tap to pick an icon for this event")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }

                    // Color palette
                    VStack(alignment: .leading, spacing: 10) {
                        Text("event_color")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(paletteColors.indices, id: \.self) { idx in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                        selectedColor = paletteColors[idx]
                                        selectedColorIndex = idx
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(paletteColors[idx])
                                            .frame(width: 30, height: 30)
                                            .shadow(
                                                color: paletteColors[idx].opacity(0.5),
                                                radius: selectedColorIndex == idx ? 5 : 0,
                                                y: 2
                                            )

                                        if selectedColorIndex == idx {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .scaleEffect(selectedColorIndex == idx ? 1.18 : 1.0)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)

                } header: {
                    sectionHeader("Appearance", icon: "paintpalette")
                } footer: {
                    Text(String(localized: "event_color_hint"))
                }

                // ── 3. Date (mini calendar) ───────────────────────────────
                Section {
                    CalendarMiniView(
                        selectedDate: dateBinding,
                        busySlots: eventManager.events,
                        offDays: offDays,
                        maxBookingDays: PremiumLimits.limits(for: premium.tier).maxBookingDaysAhead
                    )
                    .padding(.vertical, 6)
                } header: {
                    sectionHeader(String(localized: "date_time_section"), icon: "calendar")
                } footer: {
                    HStack(spacing: 14) {
                        legendDot(color: .blue.opacity(0.55),   label: "Today")
                        legendDot(color: .red.opacity(0.55),    label: "Has event")
                        legendDot(color: .orange.opacity(0.65), label: "Day off")
                    }
                    .font(.caption)
                }

                // ── 4. Hour grid ──────────────────────────────────────────
                Section {
                    let hours        = Array(0..<24)
                    let eventsToday  = eventManager.events(for: date)
                    let isOffDay     = offDays.contains {
                        Calendar.current.isDate($0, inSameDayAs: date)
                    }

                    if isOffDay {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(.orange)
                            Text(String(localized: "day_off_no_booking"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 4)
                    }

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 8
                    ) {
                        ForEach(hours, id: \.self) { hour in
                            hourCell(
                                hour: hour,
                                isOffDay: isOffDay,
                                eventsToday: eventsToday
                            )
                        }
                    }
                    .padding(.vertical, 6)

                } header: {
                    sectionHeader(String(localized: "select_time_section"), icon: "clock")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "tap_block_quick_select_hint"))

                        HStack(spacing: 14) {
                            legendDot(
                                color: Color(.systemGray4),
                                label: String(localized: "availability_available")
                            )
                            legendDot(
                                color: .red.opacity(0.55),
                                label: String(localized: "availability_busy")
                            )
                            legendDot(
                                color: Color(.systemGray3),
                                label: String(localized: "availability_past")
                            )
                        }
                        .padding(.top, 2)
                    }
                    .font(.caption)
                }

                // ── 5. Fine-tune time ─────────────────────────────────────
                Section {
                    DatePicker(
                        String(localized: "start_label"),
                        selection: $startTime,
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        String(localized: "end_label"),
                        selection: $endTime,
                        displayedComponents: .hourAndMinute
                    )
                } header: {
                    sectionHeader(
                        String(localized: "fine_tune_time"),
                        icon: "slider.horizontal.3"
                    )
                } footer: {
                    Text("adjust_time_hint")
                }

            } // Form
            .onAppear {
                if let d = prefillDate {
                    date = d
                    let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                    if let dayStart = Calendar.current.date(from: comps) {
                        startTime = combine(date: dayStart, time: startTime)
                        endTime   = combine(date: dayStart, time: endTime)
                    }
                }
            }
            .navigationTitle(String(localized: "add_event_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {
                        guard !isSaving else { return }
                        isSaving = true

                        if let error = validateBeforeSave() {
                            switch error {
                            case .overBookingDays, .overEventsPerDay:
                                if PremiumIntroGate.shouldShowToday() {
                                    PremiumIntroGate.markShown()
                                    showPremiumIntro = true
                                } else {
                                    activeAlert = .save(error)
                                }
                            default:
                                activeAlert = .save(error)
                            }
                            isSaving = false
                            return
                        }

                        let start = combine(date: date, time: startTime)
                        let end   = combine(date: date, time: endTime)

                        let newEventId = eventManager.addEvent(
                            title: title,
                            ownerName: session.currentUserName,
                            date: date,
                            startTime: start,
                            endTime: end,
                            colorHex: selectedColor.toHex() ?? "#007AFF"
                        )

                        if let eventId = newEventId {
                            if !selectedIcon.isEmpty {
                                EventIconStore.shared.setIcon(selectedIcon, for: eventId)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                ReviewManager.shared.requestAfterEventSuccess(requestReview)
                            }
                            dismiss()
                        } else {
                            activeAlert = nil
                            DispatchQueue.main.async {
                                activeAlert = .save(.cannotCreate)
                            }
                        }

                        isSaving = false
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
            .alert(item: $activeAlert) { buildAlert($0) }
            .fullScreenCover(isPresented: $showPremiumIntro) {
                PremiumIntroView(isPresented: $showPremiumIntro) {
                    showUpgradeSheet = true
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                PremiumUpgradeSheet(preselectProductID: nil, autoPurchase: false)
                    .environmentObject(premium)
            }
            .sheet(isPresented: $showIconPicker) {
                IconPicker(icon: $selectedIcon, color: $selectedColor)
                    .environmentObject(premium)
            }
        }
    }

    // MARK: – Subviews

    @ViewBuilder
    private func hourCell(hour: Int, isOffDay: Bool, eventsToday: [CalendarEvent]) -> some View {
        let slotStart    = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        let slotEnd      = slotStart.addingTimeInterval(3600)
        let isToday      = Calendar.current.isDateInToday(date)
        let isDayPast    = !isToday && Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
        // Past if: entire day is past, OR it's today and this hour has already ended
        let isPastSlot   = isDayPast || (isToday && slotEnd <= Date())

        let busyEvent = eventsToday.first { $0.startTime < slotEnd && $0.endTime > slotStart }
        let busyHour  = busyHours.first   { $0.0 < slotEnd && $0.1 > slotStart }
        let isBusy    = (busyEvent != nil) || (busyHour != nil) || isOffDay || isPastSlot

        let selectedHour = Calendar.current.component(.hour, from: startTime)
        let isSelected   = hasSelectedSlot && (hour == selectedHour)

        let bgColor: Color = isSelected  ? selectedColor.opacity(0.85)
                           : isPastSlot  ? Color(.systemGray5)
                           : isBusy      ? Color.red.opacity(0.18)
                           : Color(.systemGray6)

        let fgColor: Color = isSelected  ? .white
                           : isPastSlot  ? Color(.systemGray3)
                           : isBusy      ? .red.opacity(0.75)
                           : .primary

        Text(String(format: "%02d:00", hour))
            .font(.system(size: 13, weight: isSelected ? .bold : .regular, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(bgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? selectedColor : .clear, lineWidth: 1.5)
            )
            .foregroundStyle(fgColor)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isBusy else { return }
                withAnimation(.spring(response: 0.25)) {
                    hasSelectedSlot = true
                    startTime = slotStart
                    endTime   = slotStart.addingTimeInterval(1800)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    activeAlert = nil
                    DispatchQueue.main.async {
                        if let ev = busyEvent        { activeAlert = .slot(.event(ev)) }
                        else if busyHour != nil      { activeAlert = .slot(.busyHours) }
                        else if isOffDay             { activeAlert = .slot(.offDay) }
                    }
                }
            )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .textCase(nil)
            .font(.subheadline.weight(.semibold))
    }

    // MARK: – Validation

    private func validateBeforeSave() -> SaveEventAlert? {
        let calendar = Calendar.current
        let now      = Date()

        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }

        let start = combine(date: date, time: startTime)
        let end   = combine(date: date, time: endTime)

        // End must be strictly after start
        if end <= start {
            return .endBeforeStart
        }

        if calendar.isDateInToday(date) && start < now {
            return .pastTime
        }

        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return .offDay(date)
        }

        let busyHourConflict = busyHours.contains { $0.0 < end && $0.1 > start }
        if busyHourConflict { return .busyHours }

        let eventConflict = eventManager.events.contains {
            calendar.isDate($0.date, inSameDayAs: date) &&
            $0.startTime < end && $0.endTime > start
        }
        if eventConflict { return .conflict }

        let limits = PremiumLimits.limits(for: premium.tier)
        if let maxDate = calendar.date(byAdding: .day, value: limits.maxBookingDaysAhead, to: now),
           date > maxDate {
            return .overBookingDays(limits.maxBookingDaysAhead)
        }

        let sameDayEvents = eventManager.events.filter {
            calendar.isDate($0.date, inSameDayAs: date)
        }
        if sameDayEvents.count >= limits.maxEventsPerDay { return .overEventsPerDay }

        return nil
    }

    // MARK: – Alert builders

    private func buildAlert(_ alert: AddEventAlert) -> Alert {
        switch alert {
        case .save(let s): return buildSaveAlert(s)
        case .slot(let s): return buildSlotAlert(s)
        }
    }

    private func buildSaveAlert(_ alert: SaveEventAlert) -> Alert {
        switch alert {
        case .emptyTitle:
            return Alert(
                title: Text(String(localized: "missing_info")),
                message: Text(String(localized: "empty_title")),
                dismissButton: okDismiss
            )
        case .endBeforeStart:
            return Alert(
                title: Text(String(localized: "invalid_time")),
                message: Text("end_time_validation_error"),
                dismissButton: okDismiss
            )
        case .pastTime:
            return Alert(
                title: Text(String(localized: "invalid_time")),
                message: Text(String(localized: "cannot_book_in_past")),
                dismissButton: okDismiss
            )
        case .offDay(let date):
            return Alert(
                title: Text(String(localized: "cannot_book")),
                message: Text(String(format: String(localized: "off_day_full_message"), formattedDate(date))),
                dismissButton: okDismiss
            )
        case .busyHours:
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text(String(localized: "busy_hours")),
                dismissButton: okDismiss
            )
        case .conflict:
            return Alert(
                title: Text(String(localized: "time_conflict")),
                message: Text(String(localized: "event_conflict")),
                dismissButton: okDismiss
            )
        case .overBookingDays(let days):
            return Alert(
                title: Text(String(localized: "limit_reached")),
                message: Text(String(format: String(localized: "limit_days_format"), days)),
                dismissButton: okDismiss
            )
        case .overEventsPerDay:
            return Alert(
                title: Text(String(localized: "limit_reached")),
                message: Text(String(localized: "event_limit_reached")),
                dismissButton: okDismiss
            )
        case .cannotCreate:
            return Alert(
                title: Text(String(localized: "error")),
                message: Text(String(localized: "cannot_create_event")),
                dismissButton: okDismiss
            )
        }
    }

    private func buildSlotAlert(_ alert: SlotInfoAlert) -> Alert {
        switch alert {
        case .event(let ev):
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text("\(ev.title)\n\(formattedTime(ev.startTime)) – \(formattedTime(ev.endTime))"),
                dismissButton: okDismiss
            )
        case .busyHours:
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text(String(localized: "busy_hours")),
                dismissButton: okDismiss
            )
        case .offDay:
            return Alert(
                title: Text(String(localized: "cannot_book")),
                message: Text(String(localized: "off_day")),
                dismissButton: okDismiss
            )
        }
    }

    private var okDismiss: Alert.Button {
        .default(Text(String(localized: "ok"))) { activeAlert = nil }
    }

    // MARK: – Helpers

    private func combine(date: Date, time: Date) -> Date {
        let cal   = Calendar.current
        let dComp = cal.dateComponents([.year, .month, .day], from: date)
        let tComp = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year   = dComp.year
        comps.month  = dComp.month
        comps.day    = dComp.day
        comps.hour   = tComp.hour
        comps.minute = tComp.minute
        comps.second = tComp.second ?? 0
        return cal.date(from: comps) ?? date
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }
}
