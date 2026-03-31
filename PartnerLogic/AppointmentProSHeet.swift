//
// AppointmentProSheet.swift
// Easy Schedule
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore


// MARK: - SlotHighlight

/// Describes a slot's position within the currently booked time range.
/// Drives the visual style and per-cell animation delay in the slot grid.
private enum SlotHighlight: Equatable {
    case outside    // not inside the selected range
    case rangeSole  // entire booking is exactly one slot (30 min)
    case rangeStart // first slot of a multi-slot range
    case rangeMid   // interior slot(s) between start and end
    case rangeEnd   // last slot of a multi-slot range
}

struct AppointmentProSheet: View {
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var network: NetworkMonitor

    @Binding var isPresented: Bool
    let sharedUserId:   String?
    let sharedUserName: String?

    // Data
    @State private var selectedDate:   Date          = Date()
    @State private var selectedSlot:   ProSlot?      = nil
    @State private var busySlots:      [CalendarEvent] = []
    @State private var partnerOffDays: Set<Date>     = []
    @State private var partnerTier:    PremiumTier   = .free
    @State private var busyIntervals:  [(Date, Date)] = []
    @State private var loading:        Bool           = true

    // Custom time
    @State private var useCustomTime: Bool = false
    @State private var customStart:   Date = Date()

    // Duration — shared between slot-grid mode and custom-time mode
    @State private var durationMinutes: Int = 30

    // Input
    @State private var titleText: String = String(localized: "default_event_title")

    // Alerts
    @State private var errorMessage:     String? = nil
    @State private var showSuccessAlert: Bool    = false
    @State private var showPremiumAlert: Bool    = false

    // Day-bounds — same keys as AddEventView so settings stay in sync
    @AppStorage("morningStartHour") private var morningStartHour: Int = 7
    @AppStorage("nightSleepHour")   private var nightSleepHour:   Int = 22

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    // MARK: – Duration computed

    /// Max bookable duration (30-min steps, capped at 8 h) before the night
    /// boundary, relative to the currently selected start.
    private var maxDurationMinutes: Int {
        let start: Date
        if useCustomTime {
            start = customStart
        } else if let s = selectedSlot?.start {
            start = s
        } else {
            return 480
        }
        return computeMaxDuration(from: start)
    }

    private var durationOptions: [Int] {
        Array(stride(from: 30, through: max(30, maxDurationMinutes), by: 30))
    }

    private func computeMaxDuration(from start: Date) -> Int {
        let c = Calendar.current
        let h = c.component(.hour,   from: start)
        let m = c.component(.minute, from: start)
        let startTotal = h * 60 + m
        let nightTotal = nightSleepHour * 60
        guard nightTotal > startTotal else { return 30 }
        let available = ((nightTotal - startTotal) / 30) * 30
        return max(30, min(available, 480))
    }

    private func clampDuration(from start: Date) {
        let maxM = computeMaxDuration(from: start)
        if durationMinutes > maxM {
            durationMinutes = max(30, (maxM / 30) * 30)
        }
    }

    /// Returns the highlight role of `slot` relative to the current effective
    /// booking window. Only meaningful in grid mode (not custom-time mode).
    private func slotHighlight(for slot: ProSlot) -> SlotHighlight {
        // Custom-time mode: the grid is read-only, no range highlight.
        guard !useCustomTime, let eff = effectiveSlot else { return .outside }

        // Is this slot's start time inside [eff.start, eff.end)?
        guard slot.start >= eff.start, slot.start < eff.end else { return .outside }

        let isFirst = slot.start == eff.start
        // A slot is "last" when its 30-min window reaches or passes eff.end.
        let isLast  = slot.start.addingTimeInterval(1800) >= eff.end

        switch (isFirst, isLast) {
        case (true,  true):  return .rangeSole
        case (true,  false): return .rangeStart
        case (false, true):  return .rangeEnd
        default:             return .rangeMid
        }
    }

    private func syncSlotEnd() {
        guard let start = selectedSlot?.start else { return }
        selectedSlot = ProSlot(
            start: start,
            end:   start.addingTimeInterval(Double(durationMinutes) * 60)
        )
    }

    /// The effective booking slot used in validation and saving.
    private var effectiveSlot: ProSlot? {
        if useCustomTime {
            let start = combine(selectedDate, customStart)
            let end   = start.addingTimeInterval(Double(durationMinutes) * 60)
            return ProSlot(start: start, end: end)
        }
        return selectedSlot
    }

    // MARK: – Filtered slots

    private var slotsForSelectedDate: [ProSlot] {
        generateSlots(for: selectedDate).filter { slot in
            let h = Calendar.current.component(.hour, from: slot.start)
            // Only show hours within the user's schedule window
            guard morningStartHour < nightSleepHour else { return true }
            return h >= morningStartHour && h < nightSleepHour
        }
    }

    // MARK: – Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    partnerHeaderCard
                    calendarCard

                    if partnerOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                        offDayBanner
                    }

                    titleCard
                    timePickerCard         // ← unified time + duration section
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
                        eventManager.isAdding
                        || (effectiveSlot == nil)
                        || sharedUserId == nil
                        || !NetworkMonitor.shared.isOnline
                        || loading
                    )
                }
            }
            .onAppear {
                if busySlots.isEmpty { loadBusy() }
                resetToMorningStart()
            }
            .onChange(of: sharedUserId) { _, newValue in
                if newValue != nil { loadBusy() }
            }
            .onChange(of: selectedDate) { _, newDate in
                // Clear slot selection when date changes
                selectedSlot = nil
                guard let maxDate = cal.date(
                    byAdding: .day, value: partnerMaxBookingDays, to: Date()
                ) else { return }
                if newDate > maxDate { selectedSlot = nil }
                resetToMorningStart()
            }
            .onChange(of: durationMinutes) {
                syncSlotEnd()
            }
            // Error alert
            .alert(item: Binding(
                get:  { errorMessage.map { SimpleError(id: 0, message: $0) } },
                set:  { _ in errorMessage = nil }
            )) { err in
                Alert(
                    title:         Text(String(localized: "cant_book_title")),
                    message:       Text(err.message),
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

    // MARK: – Partner header card

    private var partnerHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                Text(partnerInitials)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "recipient"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sharedUserName ?? sharedUserId ?? String(localized: "no_name"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                tierBadge
            }

            Spacer()

            if loading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.85)
                    Text(String(localized: "loading_slots"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var tierBadge: some View {
        if !loading {
            HStack(spacing: 4) {
                Circle()
                    .fill(tierColor)
                    .frame(width: 6, height: 6)
                Text(tierLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tierColor)
            }
        }
    }

    private var tierColor: Color {
        switch partnerTier {
        case .free:    return .secondary
        case .premium: return Color(hex: "#F5A623")
        case .pro:     return Color(hex: "#7B68EE")
        }
    }

    private var tierLabel: String {
        switch partnerTier {
        case .free:    return "Free · Book up to \(partnerMaxBookingDays) days ahead"
        case .premium: return "Premium · Book up to \(partnerMaxBookingDays) days ahead"
        case .pro:     return "Pro · Book up to \(partnerMaxBookingDays) days ahead"
        }
    }

    private var partnerInitials: String {
        let name = sharedUserName ?? sharedUserId ?? "?"
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return name.prefix(2).uppercased()
    }

    // MARK: – Calendar card

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "select_date"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            CalendarMiniView(
                selectedDate: $selectedDate,
                busySlots:    busySlots,
                offDays:      partnerOffDays,
                maxBookingDays: partnerMaxBookingDays
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: – Off-day banner

    private var offDayBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "owner_day_off"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(String(localized: "partner_day_unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: – Title card

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

            Text("appointment_name_hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: – Unified time picker card

    /// One card that contains:
    ///  • Custom-time toggle + start wheel (when toggled on)
    ///  • Slot grid (when toggle is off)
    ///  • Duration presets + wheel (always, below whichever picker is active)
    private var timePickerCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Section header ────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "select_time_section").uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()

                // Custom-time toggle (pill style)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        useCustomTime.toggle()
                        selectedSlot = nil
                        if useCustomTime {
                            clampDuration(from: customStart)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: useCustomTime ? "pencil.circle.fill" : "pencil.circle")
                            .font(.caption)
                        Text(useCustomTime ? "Custom" : "Grid")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(useCustomTime ? Color.accentColor : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(useCustomTime
                                  ? Color.accentColor.opacity(0.12)
                                  : Color(.systemGray5))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            if useCustomTime {
                // ── Custom start time ─────────────────────────────────────
                customStartRow
            } else {
                // ── 30-min slot grid ──────────────────────────────────────
                slotGridBody
            }

            // ── Duration section (always visible once time is chosen) ─────
            if effectiveSlot != nil || useCustomTime {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                durationBody
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.22), value: useCustomTime)
        .animation(.easeInOut(duration: 0.18), value: selectedSlot?.start)
    }

    // MARK: – Custom start row

    private var customStartRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                // LEFT: Start time wheel
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(String(localized: "start_time"))
                    } icon: {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    DatePicker(
                        "",
                        selection: $customStart,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(width: 130, height: 120)
                    .clipped()
                    .onChange(of: customStart) {
                        clampDuration(from: customStart)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Conflict warning (right side of custom start row)
                if let slot = effectiveSlot, checkBusy(slot) {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(String(localized: "time_unavailable"))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Text("custom_window_hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: – Slot grid body

    @ViewBuilder
    private var slotGridBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isDayBlocked {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(String(localized: "outside_booking_window"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if slotsForSelectedDate.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No time slots in your schedule window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                    spacing: 8
                ) {
                    // Use enumerated so we can key on start-time (stable identity)
                    // while still having an integer offset for nothing else.
                    ForEach(Array(slotsForSelectedDate.enumerated()), id: \.element.start) { _, slot in
                        let pastSlot = isPastSlot(slot)
                        let busy     = checkBusy(slot)
                        let blocked  = isDayBlocked || pastSlot
                        let hl       = slotHighlight(for: slot)

                        // Stagger delay: slots farther from the range start
                        // animate in slightly later, producing a cascade wave.
                        let rangeDelay: Double = {
                            guard hl != .outside,
                                  let rangeStart = effectiveSlot?.start else { return 0 }
                            let steps = slot.start.timeIntervalSince(rangeStart) / 1800
                            return max(0, steps) * 0.045
                        }()

                        slotCell(slot: slot, isBusy: busy, isPast: pastSlot, highlight: hl)
                            .opacity(blocked ? 0.30 : 1.0)
                            .allowsHitTesting(!blocked)
                            // Per-cell spring with stagger — triggers whenever this
                            // slot's highlight role changes (enter / leave / shift range).
                            .animation(
                                .spring(response: 0.32, dampingFraction: 0.70)
                                    .delay(rangeDelay),
                                value: hl
                            )
                            .onTapGesture {
                                guard !isDayBlocked, !busy, !pastSlot else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.22)) {
                                    if selectedSlot?.start == slot.start {
                                        // Deselect
                                        selectedSlot = nil
                                    } else {
                                        // Select: anchor start, clamp + compute end
                                        clampDuration(from: slot.start)
                                        selectedSlot = ProSlot(
                                            start: slot.start,
                                            end:   slot.start.addingTimeInterval(Double(durationMinutes) * 60)
                                        )
                                    }
                                }
                            }
                    }
                }

                // Legend
                HStack(spacing: 14) {
                    legendDot(color: Color(.systemGray4),             label: "Available")
                    legendDot(color: .red.opacity(0.55),              label: "Busy")
                    legendDot(color: Color.accentColor.opacity(0.90), label: "Start")
                    legendDot(color: Color.accentColor.opacity(0.50), label: "Range")
                }
                .font(.caption2)
                .padding(.top, 4)

                Text("Tap a slot to set start time. Use Duration below to extend the range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: – Duration body

    /// Preset chips + wheel + end-time preview.
    /// Shown below both the slot grid and the custom start picker.
    private var durationBody: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("DURATION")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                // Live end-time badge
                if let slot = effectiveSlot {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                        Text(slot.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.10))
                    )
                }
            }

            // ── Preset chips (1 row of 4) ─────────────────────────────────
            HStack(spacing: 8) {
                ForEach([30, 60, 90, 120], id: \.self) { mins in
                    durationChip(mins)
                }
            }

            // ── Duration wheel ────────────────────────────────────────────
            HStack(alignment: .center, spacing: 0) {
                Spacer()
                Picker("", selection: $durationMinutes) {
                    ForEach(durationOptions, id: \.self) { mins in
                        Text(formatDuration(mins)).tag(mins)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 160, height: 96)
                Spacer()
            }

            // ── Busy conflict warning ─────────────────────────────────────
            if let slot = effectiveSlot, checkBusy(slot) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(String(localized: "time_unavailable"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text("Tap a preset or spin the wheel to set the appointment length.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: – Duration chip

    @ViewBuilder
    private func durationChip(_ mins: Int) -> some View {
        let isSelected  = durationMinutes == mins
        let isAvailable = durationOptions.contains(mins)

        Button {
            guard isAvailable else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                durationMinutes = mins
                syncSlotEnd()
            }
        } label: {
            Text(formatDuration(mins))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.88)
                                : isAvailable
                                    ? Color(.systemGray5)
                                    : Color(.systemGray6)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 1.5
                        )
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

    // MARK: – Slot cell

    @ViewBuilder
    private func slotCell(slot: ProSlot, isBusy: Bool, isPast: Bool, highlight: SlotHighlight) -> some View {
        let label = slot.start.formatted(date: .omitted, time: .shortened)

        // ── Background ────────────────────────────────────────────────────
        // Opacity gradient across the range:
        //   rangeStart / rangeSole → brightest (anchor, user-tapped slot)
        //   rangeEnd               → medium    (visual "landing" point)
        //   rangeMid               → softest   (continuation fills)
        // Immediately-invoked closures keep imperative switch/if logic out of
        // the @ViewBuilder result-builder context (where every statement is
        // interpreted as a View expression, making `x = …` produce `()` which
        // doesn't conform to View).
        let bgColor: Color = {
            switch highlight {
            case .rangeSole, .rangeStart: return Color.accentColor.opacity(0.92)
            case .rangeEnd:               return Color.accentColor.opacity(0.68)
            case .rangeMid:               return Color.accentColor.opacity(0.46)
            case .outside:
                return isBusy ? Color.red.opacity(0.14)
                      : isPast ? Color(.systemGray5)
                      : Color(.systemGray6)
            }
        }()

        let fgColor: Color = {
            switch highlight {
            case .rangeSole, .rangeStart, .rangeMid, .rangeEnd: return .white
            case .outside:
                return isBusy ? .red.opacity(0.80)
                      : isPast ? Color(.systemGray3)
                      : .primary
            }
        }()

        let weight: Font.Weight = {
            switch highlight {
            case .rangeSole, .rangeStart: return .bold
            case .rangeEnd:               return .semibold
            case .rangeMid, .outside:     return .regular
            }
        }()

        // Stroke border only on the anchor (start / sole) slot so the user
        // can always see exactly where the booking begins.
        let hasBorder = (highlight == .rangeSole || highlight == .rangeStart)

        Text(label)
            .font(.system(size: 11, weight: weight, design: .monospaced))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(bgColor))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        hasBorder ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
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
            loading      = false
            busySlots    = []
            errorMessage = String(localized: "no_internet_connection")
            return
        }
        guard let uid = sharedUserId else {
            loading      = false
            errorMessage = String(localized: "unknown_uid")
            return
        }

        loading = true

        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, tier in
            DispatchQueue.main.async {
                self.busySlots     = slots
                self.partnerTier   = tier
                self.busyIntervals = slots.map { ($0.startTime, $0.endTime) }
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

        // ── Derive slot from mode ─────────────────────────────────────────
        let slot: ProSlot
        if useCustomTime {
            let start = combine(selectedDate, customStart)
            let end   = start.addingTimeInterval(Double(durationMinutes) * 60)
            guard end > start else {
                errorMessage = String(localized: "invalid_time_range")
                return
            }
            if cal.isDateInToday(selectedDate) && start < Date() {
                errorMessage = String(localized: "cannot_book_past_time")
                return
            }
            slot = ProSlot(start: start, end: end)
        } else {
            guard let s = selectedSlot else {
                errorMessage = String(localized: "no_time_slot_selected")
                return
            }
            slot = s
        }

        // ── Past date guard ────────────────────────────────────────────────
        let startOfSelected = Calendar.current.startOfDay(for: selectedDate)
        let today           = Calendar.current.startOfDay(for: Date())
        if startOfSelected < today {
            errorMessage = String(localized: "cannot_book_past_date")
            return
        }

        // ── Off-day guard ──────────────────────────────────────────────────
        if partnerOffDays.contains(startOfSelected) {
            errorMessage = String(localized: "owner_day_off_no_booking")
            return
        }

        // ── Booking range guard ────────────────────────────────────────────
        let maxDate = cal.date(byAdding: .day, value: partnerMaxBookingDays, to: Date())!
        if selectedDate > maxDate {
            switch partnerTier {
            case .free:    errorMessage = String(localized: "booking_limit_7_days")
            case .premium: errorMessage = String(localized: "premium_booking_limit_90_days")
            case .pro:     errorMessage = String(localized: "pro_booking_limit_270_days")
            }
            return
        }

        // ── Daily event limit (creator) ───────────────────────────────────
        let creatorUid    = Auth.auth().currentUser?.uid ?? ""
        let myEventsToday = eventManager.events.filter {
            $0.createdBy == creatorUid &&
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
        let limits = PremiumStoreViewModel.shared.limits
        if myEventsToday.count >= limits.maxEventsPerDay {
            errorMessage = String(localized: "event_limit_reached")
            return
        }

        // ── Network guard ──────────────────────────────────────────────────
        guard NetworkMonitor.shared.isOnline else {
            errorMessage = String(localized: "no_internet_connection")
            return
        }

        // ── Required fields ───────────────────────────────────────────────
        guard let uid = sharedUserId else {
            errorMessage = String(localized: "unknown_uid")
            return
        }
        guard Auth.auth().currentUser != nil else {
            errorMessage = String(localized: "login_required")
            return
        }

        // ── Own-calendar conflict ─────────────────────────────────────────
        if checkMyOwnConflict(slot) {
            errorMessage = String(localized: "you_have_event_this_time")
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // ── Create booking ────────────────────────────────────────────────
        eventManager.addAppointment(
            forSharedUser: uid,
            title:         titleText,
            start:         slot.start,
            end:           slot.end
        ) { success, msg in
            DispatchQueue.main.async {
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.loadBusy()
                    self.selectedSlot = nil
                    self.showSuccessAlert = true
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
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

    private func resetToMorningStart() {
        customStart = Calendar.current.date(
            bySettingHour: morningStartHour, minute: 0, second: 0, of: selectedDate
        ) ?? selectedDate
    }

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

    private func formatDuration(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
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
                isPresented:    .constant(true),
                sharedUserId:   "demoUID",
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
        if let arr = data["participants"] as? [String]   { participants = arr }
        else if let arr = data["participants"] as? [Any] { participants = arr.compactMap { $0 as? String } }

        var admins: [String]? = nil
        if let arr = data["admins"] as? [String]         { admins = arr }
        else if let arr = data["admins"] as? [Any]       { admins = arr.compactMap { $0 as? String } }

        let participantNames = data["participantNames"] as? [String: String] ?? [:]
        let creatorName      = data["creatorName"]      as? String ?? ""

        let current       = Auth.auth().currentUser?.uid ?? ""
        let isMyCalendar  = (owner == current)
        let isCreatedByMe = (createdBy == current)

        let origin: EventOrigin = isMyCalendar
            ? (isCreatedByMe ? .myEvent       : .createdForMe)
            : (isCreatedByMe ? .iCreatedForOther : .createdForMe)

        return CalendarEvent(
            id:               doc.documentID,
            title:            title,
            date:             Calendar.current.startOfDay(for: s),
            startTime:        s,
            endTime:          e,
            owner:            owner,
            sharedUser:       sharedUser,
            createdBy:        createdBy,
            participants:     participants,
            admins:           admins,
            participantNames: participantNames,
            creatorName:      creatorName,
            colorHex:         colorHex,
            pendingDelete:    false,
            origin:           origin
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d  = value as? Double    { return Date(timeIntervalSince1970: d) }
        if let i  = value as? Int       { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }
}
