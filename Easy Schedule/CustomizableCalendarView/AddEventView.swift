//
//  AddEventView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

// MARK: - Alert Enums

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

    var id: String { String(describing: self) }
}

enum SlotInfoAlert: Identifiable {
    case event(CalendarEvent)
    case busyHours
    case offDay

    var id: String { String(describing: self) }
}

enum AddEventAlert: Identifiable {
    case save(SaveEventAlert)
    case slot(SlotInfoAlert)

    var id: String {
        switch self {
        case .save(let a): return "save-\(a.id)"
        case .slot(let a): return "slot-\(a.id)"
        }
    }
}

// MARK: - AddEventView

struct AddEventView: View {

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss

    // Appearance
    @State private var selectedColor: Color = .blue
    @State private var selectedColorIndex: Int = 0
    @State private var selectedIcon: String = ""
    @State private var showIconPicker = false

    let prefillDate: Date?
    let offDays: Set<Date>
    let busyHours: [(Date, Date)]

    // Core time state
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800)

    // Duration state (drives endTime)
    @State private var durationMinutes: Int = 30

    // Day bounds — persisted in UserDefaults
    @AppStorage("morningStartHour") private var morningStartHour: Int = 7
    @AppStorage("nightSleepHour")   private var nightSleepHour:   Int = 22

    @State private var showDayBoundsSettings = false

    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var session: SessionStore
    @State private var hasSelectedSlot = false
    @State private var isSaving = false

    @State private var activeAlert: AddEventAlert?
    @State private var showUpgradeSheet = false
    @State private var showPremiumIntro = false
    @Environment(\.requestReview) private var requestReview

    private let paletteColors: [Color] = [
        .blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal
    ]

    // MARK: – Day-bounds computed

    /// Hours visible in the grid: [morningStartHour ..< nightSleepHour].
    /// Falls back to all 24 if the configuration is invalid.
    private var visibleHours: [Int] {
        guard morningStartHour >= 0,
              nightSleepHour <= 24,
              morningStartHour < nightSleepHour
        else { return Array(0..<24) }
        return Array(morningStartHour..<nightSleepHour)
    }

    /// Maximum bookable duration (30-min steps, up to 8 h) before the night
    /// boundary, computed from the current startTime.
    private var maxDurationMinutes: Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: startTime)
        let m = cal.component(.minute, from: startTime)
        let startTotal = h * 60 + m
        let nightTotal = nightSleepHour * 60
        guard nightTotal > startTotal else { return 30 }
        let available = ((nightTotal - startTotal) / 30) * 30
        return max(30, min(available, 480)) // cap at 8 h
    }

    /// Selectable duration options in 30-min steps.
    private var durationOptions: [Int] {
        Array(stride(from: 30, through: max(30, maxDurationMinutes), by: 30))
    }

    // MARK: – Date binding (resets slot + startTime when date changes)

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newDate in
                date = newDate
                hasSelectedSlot = false
                startTime = morningStart(for: newDate)
                clampDuration()
            }
        )
    }

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
                hourGridSection

                // ── 5. Fine-tune time ─────────────────────────────────────
                fineTuneSection

            } // Form
            .onAppear {
                let d = prefillDate ?? date
                if let prefill = prefillDate { date = prefill }
                startTime = morningStart(for: d)
                syncEndTime()
            }
            // React to settings changes from DayBoundsSettingsSheet
            .onChange(of: nightSleepHour) {
                clampDuration()
            }
            .onChange(of: morningStartHour) {
                // If current startTime is now outside the visible window, reset it
                let h = Calendar.current.component(.hour, from: startTime)
                if !visibleHours.contains(h) {
                    startTime = morningStart(for: date)
                }
                clampDuration()
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
            .sheet(isPresented: $showDayBoundsSettings) {
                DayBoundsSettingsSheet()
            }
        }
    }

    // MARK: – Section 4: Hour Grid

    @ViewBuilder
    private var hourGridSection: some View {
        let eventsToday = eventManager.events(for: date)
        let isOffDay    = offDays.contains { Calendar.current.isDate($0, inSameDayAs: date) }

        Section {

            // ── Day-bounds settings row ───────────────────────────────────
            Button {
                showDayBoundsSettings = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "sun.and.horizon.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Schedule hours")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(hourLabel(morningStartHour)) – \(hourLabel(nightSleepHour))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "slider.horizontal.3")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            // ── Off-day banner ────────────────────────────────────────────
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

            // ── Hour cells ────────────────────────────────────────────────
            if visibleHours.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No hours available — adjust schedule settings above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 8
                ) {
                    ForEach(visibleHours, id: \.self) { hour in
                        hourCell(hour: hour, isOffDay: isOffDay, eventsToday: eventsToday)
                    }
                }
                .padding(.vertical, 6)
            }

        } header: {
            sectionHeader(String(localized: "select_time_section"), icon: "clock")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "tap_block_quick_select_hint"))
                HStack(spacing: 14) {
                    legendDot(color: Color(.systemGray4),  label: String(localized: "availability_available"))
                    legendDot(color: .red.opacity(0.55),   label: String(localized: "availability_busy"))
                    legendDot(color: Color(.systemGray3),  label: String(localized: "availability_past"))
                }
                .padding(.top, 2)
            }
            .font(.caption)
        }
    }

    // MARK: – Section 5: Fine-tune

    private var fineTuneSection: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {

                // ── LEFT: Start time ──────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {

                    Label {
                        Text(String(localized: "start_label"))
                    } icon: {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(selectedColor)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    // Wheel picker for start time — compact and constrained
                    DatePicker(
                        "",
                        selection: $startTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(width: 126, height: 120)
                    .clipped()
                    .onChange(of: startTime) {
                        clampDuration()
                    }

                    // Live end-time preview
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                        Text(formattedTime(endTime))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(selectedColor.opacity(0.9))
                }
                .padding(.trailing, 12)

                // Thin vertical separator
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 0.5)
                    .padding(.vertical, 8)

                // ── RIGHT: Duration ───────────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {

                    Label {
                        Text("Duration")
                    } icon: {
                        Image(systemName: "timer")
                            .foregroundStyle(selectedColor)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    // 2 × 2 preset chips
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 6
                    ) {
                        ForEach([30, 60, 90, 120], id: \.self) { mins in
                            durationChip(mins)
                        }
                    }

                    // Duration wheel — custom Picker, 30-min steps
                    Picker("", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.self) { mins in
                            Text(formatDuration(mins)).tag(mins)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 82)
                    .onChange(of: durationMinutes) {
                        syncEndTime()
                    }

                    // End-time label beneath wheel
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                            .font(.caption2)
                        Text("Ends \(formattedTime(endTime))")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.leading, 12)
            }
            .padding(.vertical, 6)

        } header: {
            sectionHeader(String(localized: "fine_tune_time"), icon: "slider.horizontal.3")
        } footer: {
            Text("Tap a preset or spin the wheel to set duration. The start wheel syncs from the grid above.")
                .font(.caption)
        }
    }

    // MARK: – Duration preset chip

    @ViewBuilder
    private func durationChip(_ mins: Int) -> some View {
        let isSelected  = durationMinutes == mins
        let isAvailable = durationOptions.contains(mins)

        Button {
            guard isAvailable else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                durationMinutes = mins
                syncEndTime()
            }
        } label: {
            Text(formatDuration(mins))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected
                                ? selectedColor.opacity(0.9)
                                : isAvailable
                                    ? Color(.systemGray5)
                                    : Color(.systemGray6)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? selectedColor : .clear, lineWidth: 1.5)
                )
                .foregroundStyle(
                    isSelected
                        ? .white
                        : isAvailable ? .primary : Color(.systemGray3)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    // MARK: – Hour cell

    @ViewBuilder
    private func hourCell(hour: Int, isOffDay: Bool, eventsToday: [CalendarEvent]) -> some View {
        let slotStart  = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        let slotEnd    = slotStart.addingTimeInterval(3600)
        let isToday    = Calendar.current.isDateInToday(date)
        let isDayPast  = !isToday && Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
        let isPastSlot = isDayPast || (isToday && slotEnd <= Date())

        let busyEvent  = eventsToday.first { $0.startTime < slotEnd && $0.endTime > slotStart }
        let busyHour   = busyHours.first   { $0.0 < slotEnd && $0.1 > slotStart }
        let isBusy     = (busyEvent != nil) || (busyHour != nil) || isOffDay || isPastSlot

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
            .background(RoundedRectangle(cornerRadius: 10).fill(bgColor))
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
                    // Clamp duration to the night boundary from this new slot
                    let maxM = computeMaxDuration(from: slotStart)
                    if durationMinutes > maxM {
                        durationMinutes = max(30, (maxM / 30) * 30)
                    }
                    syncEndTime()
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    activeAlert = nil
                    DispatchQueue.main.async {
                        if let ev = busyEvent   { activeAlert = .slot(.event(ev)) }
                        else if busyHour != nil { activeAlert = .slot(.busyHours) }
                        else if isOffDay        { activeAlert = .slot(.offDay) }
                    }
                }
            )
    }

    // MARK: – Shared subviews

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

    // MARK: – Duration / time helpers

    /// Compute maxDuration from an arbitrary start Date (used in tap gesture
    /// before @State has updated).
    private func computeMaxDuration(from start: Date) -> Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: start)
        let m = cal.component(.minute, from: start)
        let startTotal = h * 60 + m
        let nightTotal = nightSleepHour * 60
        guard nightTotal > startTotal else { return 30 }
        let available = ((nightTotal - startTotal) / 30) * 30
        return max(30, min(available, 480))
    }

    private func syncEndTime() {
        endTime = startTime.addingTimeInterval(Double(durationMinutes) * 60)
    }

    /// Ensures durationMinutes stays within the valid range for the current
    /// startTime, then syncs endTime.
    private func clampDuration() {
        let maxM = maxDurationMinutes
        if durationMinutes > maxM {
            durationMinutes = max(30, (maxM / 30) * 30)
        }
        syncEndTime()
    }

    private func morningStart(for d: Date) -> Date {
        Calendar.current.date(bySettingHour: morningStartHour, minute: 0, second: 0, of: d) ?? d
    }

    private func hourLabel(_ h: Int) -> String {
        guard let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) else {
            return "\(h):00"
        }
        return d.formatted(.dateTime.hour())
    }

    private func formatDuration(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: – Validation

    private func validateBeforeSave() -> SaveEventAlert? {
        let calendar = Calendar.current
        let now      = Date()

        if title.trimmingCharacters(in: .whitespaces).isEmpty { return .emptyTitle }

        let start = combine(date: date, time: startTime)
        let end   = combine(date: date, time: endTime)

        if end <= start { return .endBeforeStart }
        if calendar.isDateInToday(date) && start < now { return .pastTime }
        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) { return .offDay(date) }

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

    // MARK: – Date helpers

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

// MARK: - DayBoundsSettingsSheet

/// Bottom sheet for configuring morningStartHour and nightSleepHour.
/// Changes are written to AppStorage immediately and picked up by AddEventView
/// via .onChange observers.
struct DayBoundsSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("morningStartHour") private var morningStartHour: Int = 7
    @AppStorage("nightSleepHour")   private var nightSleepHour:   Int = 22

    // Temporary local copies so the user can "cancel" changes
    @State private var localMorning: Int = 7
    @State private var localNight:   Int = 22

    private var isValid: Bool { localMorning < localNight }

    private var activeWindowHours: Int {
        max(0, localNight - localMorning)
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── Visual day-timeline preview ───────────────────────────
                Section {
                    dayTimelinePreview
                } header: {
                    Label("Your day", systemImage: "eye")
                        .textCase(nil)
                        .font(.subheadline.weight(.semibold))
                } footer: {
                    if isValid {
                        Label(
                            "\(activeWindowHours) hour\(activeWindowHours == 1 ? "" : "s") available for scheduling",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                        .font(.caption)
                    } else {
                        Label("Night must be later than morning.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                // ── Morning start ─────────────────────────────────────────
                Section {
                    Picker("", selection: $localMorning) {
                        ForEach(0..<13, id: \.self) { h in
                            Text(hourPickerLabel(h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 130)
                    .labelsHidden()
                } header: {
                    Label("Morning starts at", systemImage: "sunrise.fill")
                        .textCase(nil)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                } footer: {
                    Text("First selectable hour in the time picker. Default: 7 AM.")
                        .font(.caption)
                }

                // ── Night sleep ───────────────────────────────────────────
                Section {
                    Picker("", selection: $localNight) {
                        ForEach(12..<24, id: \.self) { h in
                            Text(hourPickerLabel(h)).tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 130)
                    .labelsHidden()
                } header: {
                    Label("Night sleep at", systemImage: "moon.fill")
                        .textCase(nil)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.indigo)
                } footer: {
                    Text("Hours from this time onward are hidden from the picker. Default: 10 PM.")
                        .font(.caption)
                }

            } // Form
            .navigationTitle("Schedule Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        morningStartHour = localMorning
                        nightSleepHour   = localNight
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                localMorning = morningStartHour
                localNight   = nightSleepHour
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: – Day timeline bar

    private var dayTimelinePreview: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let nightBefore  = CGFloat(localMorning) / 24.0 * w
                let activeWidth  = CGFloat(max(0, localNight - localMorning)) / 24.0 * w
                let nightAfter   = CGFloat(max(0, 24 - localNight)) / 24.0 * w

                HStack(spacing: 0) {
                    // Night before morning
                    Rectangle()
                        .fill(Color.indigo.opacity(0.18))
                        .frame(width: nightBefore)

                    // Active / schedulable window
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.55), Color.yellow.opacity(0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: activeWidth)

                    // Night after sleep
                    Rectangle()
                        .fill(Color.indigo.opacity(0.18))
                        .frame(width: nightAfter)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .frame(height: 36)

            // Hour labels row
            HStack {
                Text("12am")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("6am")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("12pm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("6pm")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("12am")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Morning / Night badge row
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(hourPickerLabel(localMorning))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill")
                        .foregroundStyle(.indigo)
                        .font(.caption)
                    Text(hourPickerLabel(localNight))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.indigo)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: – Helpers

    private func hourPickerLabel(_ h: Int) -> String {
        guard let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) else {
            return "\(h):00"
        }
        return d.formatted(.dateTime.hour())
    }
}
