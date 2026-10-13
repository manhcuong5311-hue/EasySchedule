//
//  BookingHoursSheet.swift
//  Easy Schedule
//
//  "Giờ nhận lịch" — which weekdays / hours other people may book me, an
//  optional break between appointments and an optional daily cap. Saved to
//  publicCalendar/{me}.bookingHours (shared schema with the web booking page).
//  Free for every tier; never restricts my own Add Event screen.
//

import SwiftUI

struct BookingHoursSheet: View {
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let eventManager = EventManager.shared

    // Loaded state (nil = never configured)
    @State private var original: BookingHours? = nil
    @State private var loading = true
    @State private var saving = false
    @State private var errorText: String? = nil

    // Editing state
    @State private var enabled = false
    @State private var days: [Int: BookingHours.DayRange] = [:]
    /// Hours of weekdays switched off in this session → restored when switched back on.
    @State private var parkedDays: [Int: BookingHours.DayRange] = [:]
    @State private var bufferMin = 0
    @State private var maxPerDay = 0

    /// Monday → Sunday as Calendar weekday numbers.
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    private static let fallbackRange = BookingHours.DayRange(start: 540, end: 1080)

    private var accent: Color { uiAccent.color }

    private var hasInvalidRange: Bool {
        enabled && days.values.contains { $0.start >= $0.end }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .background(AppBackground.settings(colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "booking_hours_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(String(localized: "save")) { save() }
                            .fontWeight(.semibold)
                            .disabled(loading || hasInvalidRange)
                    }
                }
            }
            .alert(
                String(localized: "error_title"),
                isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )
            ) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .tint(accent)
        .task { await load() }
    }

    // MARK: - Form

    private var form: some View {
        Form {
            Section {
                Toggle(String(localized: "booking_hours_enable"), isOn: $enabled.animation())
            } footer: {
                Text(String(localized: "booking_hours_footer"))
            }

            if enabled {
                Section {
                    ForEach(weekdayOrder, id: \.self) { weekday in
                        dayRow(weekday)
                    }
                }

                Section {
                    Picker(String(localized: "booking_buffer"), selection: $bufferMin) {
                        ForEach(BookingHours.bufferOptions, id: \.self) { mins in
                            Text(bufferLabel(mins)).tag(mins)
                        }
                    }

                    Stepper(value: $maxPerDay, in: 0...20) {
                        HStack {
                            Text(String(localized: "booking_max_per_day"))
                            Spacer()
                            Text(maxPerDay == 0 ? String(localized: "unlimited") : "\(maxPerDay)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Day row

    private func dayRow(_ weekday: Int) -> some View {
        let range = days[weekday]
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: dayEnabledBinding(weekday).animation()) {
                Text(weekdayName(weekday))
                    .font(.body.weight(.medium))
            }

            if let range {
                HStack(spacing: 8) {
                    DatePicker("", selection: timeBinding(weekday, isStart: true),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: timeBinding(weekday, isStart: false),
                               displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Spacer(minLength: 0)
                }

                if range.start >= range.end {
                    Text(String(localized: "invalid_time_range"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bindings

    private func dayEnabledBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { days[weekday] != nil },
            set: { isOn in
                if isOn {
                    days[weekday] = parkedDays[weekday] ?? Self.fallbackRange
                } else if let current = days[weekday] {
                    parkedDays[weekday] = current
                    days[weekday] = nil
                }
            }
        )
    }

    /// Minutes-from-midnight ⇄ Date on a fixed reference day (no DST jumps).
    /// 24:00 (1440) shows as 23:59, and picking 23:59 means "until midnight".
    private func timeBinding(_ weekday: Int, isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let range = days[weekday] ?? Self.fallbackRange
                return Self.date(forMinutes: isStart ? range.start : range.end)
            },
            set: { newDate in
                guard var range = days[weekday] else { return }
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                if isStart {
                    range.start = min(minutes, 1439)
                } else {
                    if minutes == 1439 { minutes = 1440 }
                    range.end = minutes
                }
                days[weekday] = range
            }
        )
    }

    private static func date(forMinutes minutes: Int) -> Date {
        let m = min(max(minutes, 0), 1439)
        return Calendar.current.date(from: DateComponents(
            year: 2001, month: 1, day: 1, hour: m / 60, minute: m % 60
        )) ?? Date()
    }

    // MARK: - Labels

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols   // index 0 = Sunday
        guard symbols.indices.contains(weekday - 1) else { return "\(weekday)" }
        return symbols[weekday - 1]
    }

    private func bufferLabel(_ minutes: Int) -> String {
        minutes == 0
            ? String(localized: "none_option")
            : String(format: String(localized: "time_duration_minutes"), minutes)
    }

    // MARK: - Load / save

    private func load() async {
        let hours = await eventManager.fetchMyBookingHours()
        original = hours
        // Never configured → show the defaults, switched off
        let start = hours ?? {
            var d = BookingHours.defaultHours
            d.enabled = false
            return d
        }()
        enabled   = start.enabled
        days      = start.days
        bufferMin = BookingHours.bufferOptions.contains(start.bufferMin) ? start.bufferMin : 0
        maxPerDay = min(max(start.maxPerDay, 0), 20)
        loading   = false
    }

    private func save() {
        guard !hasInvalidRange else { return }
        // Disabled → still saved (enabled = false) so the configured hours are kept.
        let hours = BookingHours(
            enabled: enabled,
            tz: TimeZone.current.identifier,
            days: days.filter { $0.value.isValid },
            bufferMin: bufferMin,
            maxPerDay: maxPerDay
        )

        // Nothing to write: never set up and still off, or unchanged.
        if original == nil && !enabled { dismiss(); return }
        if let original, original == hours { dismiss(); return }

        saving = true
        Task {
            do {
                try await eventManager.saveMyBookingHours(hours)
                AppAnalytics.log(AppAnalyticsEvent.bookingHoursSaved,
                                 ["enabled": hours.enabled,
                                  "days": hours.days.count,
                                  "buffer": hours.bufferMin,
                                  "max_per_day": hours.maxPerDay])
                saving = false
                dismiss()
            } catch {
                saving = false
                errorText = error.localizedDescription
            }
        }
    }
}

#Preview {
    BookingHoursSheet()
        .environmentObject(UIAccentStore())
}
