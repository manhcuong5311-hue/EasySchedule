//
// AppointmentProSheet.swift
// Easy Schedule
//

import SwiftUI
import StoreKit
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
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview

    /// User-chosen accent (Settings), not the static asset-catalog blue.
    private var accent: Color { uiAccent.color }
    @Namespace private var timeModeNS

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

    // Partner's booking hours ("Giờ nhận lịch") — nil = no restriction
    @State private var bookingHours:       BookingHours? = nil
    @State private var partnerEventStarts: [Date]        = []
    /// My-local days (inside the booking window) with no open booking time.
    @State private var bookingClosedDays:  Set<Date>     = []

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

                    if calendarOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                        offDayBanner
                    } else if selectedDayFullyBooked {
                        dayFullBanner
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
                                .tint(.white)
                        } else {
                            Text(String(localized: "book")).fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(accent)
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
            AvatarView(uid: sharedUserId ?? "", size: 50) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Text(partnerInitials)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
    }

    @ViewBuilder
    private var tierBadge: some View {
        if !loading {
            HStack(spacing: 4) {
                Circle()
                    .fill(tierColor)
                    .frame(width: 6, height: 6)
                Text(tierLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tierColor)
            }
        }
    }

    // Everyone shares the same free plan; only a legacy Pro plan still has its own badge.
    private var tierColor: Color {
        switch partnerTier {
        case .free, .premium: return .secondary
        case .pro:            return Color(hex: "#7B68EE")
        }
    }

    private var tierLabel: String {
        switch partnerTier {
        case .free, .premium: return String(format: String(localized: "booking_window_badge"), partnerMaxBookingDays)
        case .pro:            return String(format: String(localized: "tier_badge_pro"), partnerMaxBookingDays)
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
                offDays:      calendarOffDays,
                maxBookingDays: partnerMaxBookingDays
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
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

    // MARK: – Day-full banner (partner's maxPerDay reached)

    private var dayFullBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(String(localized: "day_fully_booked"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
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
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
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

                // Grid / Custom mode — small two-segment control
                HStack(spacing: 0) {
                    timeModeSegment("Grid", custom: false)
                    timeModeSegment("Custom", custom: true)
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            if !useCustomTime {
                suggestionsRow
            }

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
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .animation(.easeInOut(duration: 0.22), value: useCustomTime)
        .animation(.easeInOut(duration: 0.18), value: selectedSlot?.start)
    }

    /// One segment of the Grid / Custom control. Same toggle behaviour as
    /// before — tapping the already-active segment does nothing.
    private func timeModeSegment(_ title: LocalizedStringKey, custom: Bool) -> some View {
        let isActive = useCustomTime == custom
        return Button {
            guard !isActive else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                useCustomTime.toggle()
                selectedSlot = nil
                if useCustomTime {
                    clampDuration(from: customStart)
                }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(colorScheme == .dark ? Color(.systemGray4) : Color(.systemBackground))
                            .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "timeModeThumb", in: timeModeNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
                            .foregroundStyle(accent)
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
                if let slot = effectiveSlot, let message = conflictMessage(for: slot) {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(message)
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
                        Text("appt_no_slots")
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
                        // Partner's booking hours / buffer / daily cap → looks like a past cell
                        let outside  = !busy && isBlockedByBookingHours(slot)
                        let blocked  = isDayBlocked || pastSlot || outside
                        let hl       = slotHighlight(for: slot)

                        // Stagger delay: slots farther from the range start
                        // animate in slightly later, producing a cascade wave.
                        let rangeDelay: Double = {
                            guard hl != .outside,
                                  let rangeStart = effectiveSlot?.start else { return 0 }
                            let steps = slot.start.timeIntervalSince(rangeStart) / 1800
                            return max(0, steps) * 0.045
                        }()

                        slotCell(slot: slot, isBusy: busy, isPast: pastSlot || outside, highlight: hl)
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
                                guard !isDayBlocked, !busy, !pastSlot, !outside else { return }
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
                    legendDot(color: Color(.systemGray4),  label: String(localized: "availability_available"))
                    legendDot(color: .red.opacity(0.55),   label: String(localized: "availability_busy"))
                    legendDot(color: accent.opacity(0.90), label: String(localized: "start_label"))
                    legendDot(color: accent.opacity(0.50), label: String(localized: "legend_range"))
                }
                .font(.caption)
                .padding(.top, 4)
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
                    .foregroundStyle(accent)
                Text("duration_label")
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
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(accent.opacity(0.10))
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

            // ── Busy / booking-hours conflict warning ─────────────────────
            if let slot = effectiveSlot, let message = conflictMessage(for: slot) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
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
                    RoundedRectangle(cornerRadius: AppRadius.chip)
                        .fill(
                            isSelected
                                ? accent.opacity(0.88)
                                : isAvailable
                                    ? Color(.systemGray5)
                                    : Color(.systemGray6)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.chip)
                        .strokeBorder(
                            isSelected ? accent : Color.clear,
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
            case .rangeSole, .rangeStart: return accent.opacity(0.92)
            case .rangeEnd:               return accent.opacity(0.68)
            case .rangeMid:               return accent.opacity(0.46)
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
            case .rangeSole, .rangeStart:          return .bold
            case .rangeEnd, .rangeMid, .outside:   return .semibold
            }
        }()

        // Stroke border only on the anchor (start / sole) slot so the user
        // can always see exactly where the booking begins.
        let hasBorder = (highlight == .rangeSole || highlight == .rangeStart)

        Text(label)
            .font(.system(size: 14, weight: weight, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: AppRadius.chip).fill(bgColor))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.chip)
                    .strokeBorder(
                        hasBorder ? accent : Color.clear,
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

    // Same windows as the web booking page (90 days for everyone · legacy Pro 270)
    private var partnerMaxBookingDays: Int {
        PremiumLimits.limits(for: partnerTier).maxBookingDaysAhead
    }

    // MARK: – Booking hours (partner's "Giờ nhận lịch")

    /// Off days for the mini calendar: real off days + weekdays the partner
    /// doesn't take bookings on.
    private var calendarOffDays: Set<Date> {
        bookingClosedDays.isEmpty ? partnerOffDays : partnerOffDays.union(bookingClosedDays)
    }

    /// Outside the partner's hours, too close to another of their slots
    /// (buffer), or on a day that already has their max appointments.
    private func isBlockedByBookingHours(_ slot: ProSlot) -> Bool {
        guard let hours = bookingHours else { return false }
        return !hours.allows(start: slot.start, end: slot.end)
            || hours.isDayFull(slot.start, eventStarts: partnerEventStarts)
            || hours.violatesBuffer(start: slot.start, end: slot.end, busy: busyIntervals)
    }

    /// Red caption under the time picker: busy/off day first, then booking hours.
    private func conflictMessage(for slot: ProSlot) -> String? {
        if checkBusy(slot) { return String(localized: "time_unavailable") }
        guard let hours = bookingHours else { return nil }
        if hours.isDayFull(slot.start, eventStarts: partnerEventStarts) {
            return String(localized: "day_fully_booked")
        }
        return isBlockedByBookingHours(slot) ? String(localized: "outside_booking_hours") : nil
    }

    /// The partner already has `maxPerDay` appointments on the selected day.
    private var selectedDayFullyBooked: Bool {
        guard let hours = bookingHours, hours.maxPerDay > 0 else { return false }
        let dayStart = cal.startOfDay(for: selectedDate)
        guard let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        // Owner may be in another time zone → both owner days touching my day must be full
        return hours.isDayFull(dayStart, eventStarts: partnerEventStarts)
            && hours.isDayFull(nextDay.addingTimeInterval(-1), eventStarts: partnerEventStarts)
    }

    /// My-local days from today through the booking window that have no open
    /// booking time at all (closed weekdays in the partner's time zone).
    private func closedDays(for hours: BookingHours?) -> Set<Date> {
        guard let hours else { return [] }
        let today = cal.startOfDay(for: Date())
        var result: Set<Date> = []
        for offset in 0...max(0, partnerMaxBookingDays) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let next = cal.date(byAdding: .day, value: 1, to: day)
            else { break }
            if !hours.hasOpenTime(from: day, to: next) { result.insert(day) }
        }
        return result
    }

    private func applyBookingHours(for uid: String) {
        let hours = eventManager.partnerBookingHours[uid]
        bookingHours       = (hours?.enabled == true) ? hours : nil
        partnerEventStarts = eventManager.partnerEventStarts[uid] ?? []
        bookingClosedDays  = closedDays(for: bookingHours)
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

                // fetchBusySlots just refreshed the off-day cache from the same
                // publicCalendar doc → no second read here.
                self.eventManager.fetchOffDays(for: uid) { offDays in
                    DispatchQueue.main.async {
                        self.partnerOffDays = offDays
                        // Same doc, cached by fetchBusySlots → booking hours too
                        self.applyBookingHours(for: uid)
                        self.loading        = false
                    }
                }
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

        // ── Booking-hours guard (partner's hours / buffer / daily cap) ─────
        // Plain overlaps with their busy slots stay with addAppointment's check.
        if let hours = bookingHours {
            if hours.isDayFull(slot.start, eventStarts: partnerEventStarts) {
                errorMessage = String(localized: "day_fully_booked")
                return
            }
            if !hours.allows(start: slot.start, end: slot.end)
                || (!checkBusy(slot) && hours.violatesBuffer(start: slot.start, end: slot.end, busy: busyIntervals)) {
                errorMessage = String(localized: "outside_booking_hours")
                return
            }
        }

        // ── Booking range guard ────────────────────────────────────────────
        let maxDate = cal.date(byAdding: .day, value: partnerMaxBookingDays, to: Date())!
        if selectedDate > maxDate {
            switch partnerTier {
            case .free, .premium: errorMessage = String(localized: "premium_booking_limit_90_days")
            case .pro:            errorMessage = String(localized: "pro_booking_limit_270_days")
            }
            return
        }

        // ── Daily event limit (creator) ───────────────────────────────────
        let creatorUid    = Auth.auth().currentUser?.uid ?? ""
        let myEventsToday = eventManager.events.filter {
            $0.createdBy == creatorUid &&
            Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate)
        }
        let maxEvents = PremiumStoreViewModel.shared.limits.maxEventsPerDay
        if myEventsToday.count >= maxEvents {
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
                    AppAnalytics.log(AppAnalyticsEvent.bookingCreated,
                                     ["minutes": Int(slot.end.timeIntervalSince(slot.start) / 60)])
                    ReviewManager.shared.requestAfterEventSuccess(self.requestReview)
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
        } || DeviceCalendarSync.shared.isBusy(from: slot.start, to: slot.end)
    }

    // MARK: – Suggested common free slots

    /// My own busy intervals: events, manual busy hours, iPhone Calendar.
    private func myBusyIntervals(on day: Date) -> [(Date, Date)] {
        eventManager.events
            .filter { cal.isDate($0.startTime, inSameDayAs: day) || cal.isDate($0.endTime, inSameDayAs: day) }
            .map { ($0.startTime, $0.endTime) }
        + eventManager.myManualBusySlots
            .filter { cal.isDate($0.startTime, inSameDayAs: day) }
            .map { ($0.startTime, $0.endTime) }
        + DeviceCalendarSync.shared.intervals(on: day)
    }

    /// Up to `limit` start times on `day` when both of us are free for the chosen
    /// duration, spread ≥ 2h apart so the options feel different.
    private func suggestedSlots(on day: Date, limit: Int = 3) -> [ProSlot] {
        let dayStart = cal.startOfDay(for: day)
        guard !partnerOffDays.contains(dayStart),
              !bookingClosedDays.contains(dayStart),
              let dayEnd = cal.date(bySettingHour: nightSleepHour, minute: 0, second: 0, of: dayStart)
        else { return [] }

        let duration = TimeInterval(durationMinutes * 60)
        let earliest = Date().addingTimeInterval(15 * 60)
        let mine = myBusyIntervals(on: dayStart)
        var picked: [ProSlot] = []

        for cell in generateSlots(for: dayStart) {
            let hour = cal.component(.hour, from: cell.start)
            guard hour >= morningStartHour else { continue }

            let candidate = ProSlot(start: cell.start, end: cell.start.addingTimeInterval(duration))
            guard candidate.start >= earliest, candidate.end <= dayEnd else { continue }
            guard !busyIntervals.contains(where: { $0.0 < candidate.end && $0.1 > candidate.start }) else { continue }
            guard !mine.contains(where: { $0.0 < candidate.end && $0.1 > candidate.start }) else { continue }
            guard !isBlockedByBookingHours(candidate) else { continue }
            if let last = picked.last, candidate.start < last.start.addingTimeInterval(2 * 3600) { continue }

            picked.append(candidate)
            if picked.count == limit { break }
        }
        return picked
    }

    /// Suggestions for the selected day, or the next day (within the partner's
    /// booking window) that has any.
    private var suggestions: [ProSlot] {
        guard !loading, sharedUserId != nil else { return [] }
        let horizon = min(partnerMaxBookingDays, 14)
        for offset in 0...horizon {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: selectedDate)),
                  let maxDate = cal.date(byAdding: .day, value: partnerMaxBookingDays, to: Date()),
                  day <= maxDate
            else { break }
            let found = suggestedSlots(on: day)
            if !found.isEmpty { return found }
        }
        return []
    }

    private func applySuggestion(_ slot: ProSlot) {
        useCustomTime = false
        let select = {
            clampDuration(from: slot.start)
            selectedSlot = ProSlot(start: slot.start,
                                   end: slot.start.addingTimeInterval(TimeInterval(durationMinutes * 60)))
        }
        if cal.isDate(slot.start, inSameDayAs: selectedDate) {
            select()
        } else {
            // onChange(selectedDate) clears the selection — pick the slot after it runs.
            selectedDate = cal.startOfDay(for: slot.start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { select() }
        }
    }

    @ViewBuilder
    private var suggestionsRow: some View {
        let items = suggestions
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "suggested_free_slots"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { slot in
                        let isChosen = selectedSlot?.start == slot.start
                        Button {
                            applySuggestion(slot)
                        } label: {
                            VStack(spacing: 2) {
                                Text(slot.start.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                if !cal.isDate(slot.start, inSameDayAs: selectedDate) {
                                    Text(slot.start.formatted(.dateTime.weekday(.abbreviated).day()))
                                        .font(.caption2)
                                        .opacity(0.8)
                                }
                            }
                            .foregroundStyle(isChosen ? Color.white : accent)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                                    .fill(isChosen ? accent : accent.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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
            .environmentObject(UIAccentStore())
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
            origin:           origin,
            location:         EventLocation.from(data["location"]),
            responses:        data["responses"] as? [String: String],
            proposal:         TimeProposal.from(data["proposal"]),
            seriesId:         data["seriesId"] as? String
        )
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let d  = value as? Double    { return Date(timeIntervalSince1970: d) }
        if let i  = value as? Int       { return Date(timeIntervalSince1970: TimeInterval(i)) }
        return nil
    }
}
