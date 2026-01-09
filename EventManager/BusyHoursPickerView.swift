import SwiftUI

struct BusyHoursPickerView: View {

    // MARK: - Input
    let date: Date
    let eventBusyIntervals: [(Date, Date)]
    let busyHourIntervals: [(Date, Date)]
    let onSave: ([ProSlot], [ProSlot]) -> Void

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var network: NetworkMonitor

    // MARK: - State
    @State private var selectedSlots: Set<ProSlot>
    private let initialSlots: Set<ProSlot>

    // MARK: - Init (QUAN TRỌNG)
    init(
        date: Date,
        eventBusyIntervals: [(Date, Date)],
        busyHourIntervals: [(Date, Date)],
        onSave: @escaping ([ProSlot], [ProSlot]) -> Void
    ) {
        self.date = date
        self.eventBusyIntervals = eventBusyIntervals
        self.busyHourIntervals = busyHourIntervals
        self.onSave = onSave

        let initial = Set(
            busyHourIntervals.map {
                ProSlot(start: $0.0, end: $0.1)
            }
        )
        _selectedSlots = State(initialValue: initial)
        self.initialSlots = initial
    }

    // MARK: - Derived
    private var hasChanges: Bool {
        selectedSlots != initialSlots
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(slotsForDay, id: \.self) { slot in

                            // ⚠️ CACHE STATE – CỨU COMPILER
                            let past = isPast(slot)
                            let eventBusy = isEventBusy(slot)
                            let busyHour = isBusyHour(slot)
                            let selected = selectedSlots.contains(slot)

                            Button {
                                if past || eventBusy { return }

                                if selected {
                                    selectedSlots.remove(slot)
                                } else {
                                    selectedSlots.insert(slot)
                                }


                                UIImpactFeedbackGenerator(style: .light)
                                    .impactOccurred()

                            } label: {
                                slotRow(
                                    slot: slot,
                                    past: past,
                                    eventBusy: eventBusy,
                                    busyHour: busyHour,
                                    selected: selected
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(eventBusy || past)
                            .opacity(past ? 0.35 : 1)
                        }
                    }
                    .padding()
                }

                if !network.isOnline {
                       OfflineBannerView()
                           .listRowInsets(EdgeInsets())
                           .listRowBackground(Color.clear)
                   }
            }
            .navigationTitle(String(localized: "set_busy_hours"))
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {

                        let added = selectedSlots.subtracting(initialSlots)
                        let removed = initialSlots.subtracting(selectedSlots)

                        onSave(
                            Array(added).sorted { $0.start < $1.start },
                            Array(removed).sorted { $0.start < $1.start }
                        )
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                        dismiss()
                    }
                    .disabled(!hasChanges || !network.isOnline)
                }
            }
        }
    }

    // MARK: - Slot Row View
    private func slotRow(
        slot: ProSlot,
        past: Bool,
        eventBusy: Bool,
        busyHour: Bool,
        selected: Bool
    ) -> some View {
        HStack {
            Text("\(formatted(slot.start)) – \(formatted(slot.end))")

            Spacer()

            if eventBusy {
                Text(String(localized: "busy_event"))
                    .font(.caption)
                    .foregroundColor(.red)

            } else if selected {
                Text(String(localized: "selected_busy_hours"))
                    .font(.caption)
                    .foregroundColor(.orange)
            }

        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    backgroundColor(
                        past: past,
                        eventBusy: eventBusy,
                        busyHour: busyHour,
                        selected: selected
                    )
                )
        )
    }

    // MARK: - Helpers
    private var slotsForDay: [ProSlot] {
        generateSlots(for: date)
    }

    private func isEventBusy(_ slot: ProSlot) -> Bool {
        eventBusyIntervals.contains {
            $0.0 < slot.end && $0.1 > slot.start
        }
    }

    private func isBusyHour(_ slot: ProSlot) -> Bool {
        selectedSlots.contains(slot)
    }



    private func isPast(_ slot: ProSlot) -> Bool {
        slot.end <= Date()
    }

    private func backgroundColor(
        past: Bool,
        eventBusy: Bool,
        busyHour: Bool,
        selected: Bool
    ) -> Color {

        if eventBusy {
            return Color.red.opacity(0.15)
        }

        if selected {
            return Color.orange.opacity(0.25)   // ưu tiên draft
        }

        if busyHour {
            return Color.orange.opacity(0.18)
        }

        return Color.gray.opacity(0.1)

    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func generateSlots(for date: Date) -> [ProSlot] {
        var slots: [ProSlot] = []

        guard let startOfDay = calendar.date(
            bySettingHour: 0,
            minute: 0,
            second: 0,
            of: date
        ) else { return [] }

        for i in 0..<48 {
            let start = startOfDay.addingTimeInterval(Double(i) * 1800)
            let end = start.addingTimeInterval(1800)
            slots.append(ProSlot(start: start, end: end))
        }

        return slots
    }
}
