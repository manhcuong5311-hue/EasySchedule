//
//  EventDetailExtras.swift
//  Easy Schedule
//
//  Extra cards for EventDetailView: location + directions, confirm / decline /
//  propose another time, and "Add to iPhone Calendar".
//

import SwiftUI
import EventKit
import EventKitUI
import FirebaseAuth

// MARK: - Location

struct EventLocationCard: View {
    let event: CalendarEvent
    let canManage: Bool

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.openURL) private var openURL
    @State private var showPicker = false
    @State private var showDirections = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(String(localized: "location_title"), systemImage: "mappin.and.ellipse")
                    .font(.headline)
                Spacer()
                if canManage {
                    Button(event.location == nil ? String(localized: "location_add")
                                                 : String(localized: "edit")) {
                        showPicker = true
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if let location = event.location {
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name).font(.subheadline.weight(.semibold))
                    if let address = location.address, !address.isEmpty {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button {
                    showDirections = true
                } label: {
                    Label(String(localized: "location_directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .confirmationDialog(String(localized: "location_directions"),
                                    isPresented: $showDirections, titleVisibility: .visible) {
                    Button("Apple Maps") { DirectionsLauncher.openAppleMaps(to: location) }
                    if let url = DirectionsLauncher.googleMapsURL(to: location) {
                        Button("Google Maps") { openURL(url) }
                    }
                    if canManage {
                        Button(String(localized: "location_remove"), role: .destructive) {
                            eventManager.updateLocation(nil, for: event)
                        }
                    }
                    Button(String(localized: "cancel"), role: .cancel) {}
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .sheet(isPresented: $showPicker) {
            LocationPickerSheet { picked in eventManager.updateLocation(picked, for: event) }
        }
    }
}

// MARK: - Confirm / decline / propose

struct EventResponseCard: View {
    let event: CalendarEvent
    let canManage: Bool

    @EnvironmentObject var eventManager: EventManager
    @State private var showPropose = false
    @State private var isSaving = false
    @State private var showSaveError = false
    /// After answering, my part collapses to one line until I tap "Thay đổi".
    @State private var editingMyResponse = false

    private var myUid: String? { Auth.auth().currentUser?.uid }

    private var others: [String] {
        Array(Set(event.participants + [event.owner]))
            .filter { !$0.isEmpty && $0 != myUid }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "response_title"), systemImage: "checkmark.seal")
                .font(.headline)

            if let proposal = event.proposal {
                proposalBanner(proposal)
            }

            // Everyone else's answer
            ForEach(others, id: \.self) { uid in
                HStack {
                    Text(eventManager.displayName(for: uid)).font(.subheadline)
                    Spacer()
                    statusBadge(event.response(of: uid))
                }
            }

            // My answer (whoever created the appointment has implicitly accepted it)
            if let me = myUid {
                let mine = event.response(of: me)
                let isCreator = event.createdBy == me

                if let mine, !editingMyResponse {
                    // Already answered → one compact line
                    HStack(spacing: 8) {
                        Text(String(localized: "response_you")).font(.subheadline.weight(.semibold))
                        statusBadge(mine).font(.subheadline)
                        Spacer()
                        Button(String(localized: "response_change")) {
                            withAnimation { editingMyResponse = true }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                } else {
                    HStack(spacing: 8) {
                        if !isCreator {
                            responseButton(String(localized: "response_accept"), "checkmark",
                                           selected: mine == .accepted, tint: .green) {
                                await eventManager.respond(.accepted, to: event)
                            }
                            responseButton(String(localized: "response_decline"), "xmark",
                                           selected: mine == .declined, tint: .red) {
                                await eventManager.respond(.declined, to: event)
                            }
                        }
                        if event.proposal == nil {
                            responseButton(String(localized: "response_propose"), "clock.arrow.2.circlepath",
                                           selected: false, tint: .orange) {
                                showPropose = true
                                return true
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .disabled(isSaving)
        .sheet(isPresented: $showPropose) {
            ProposeTimeSheet(event: event) { start, end in
                run { await eventManager.proposeTime(start: start, end: end, for: event) }
            }
            .presentationDetents([.medium])
        }
        .alert(String(localized: "error"), isPresented: $showSaveError) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "proposal_save_failed"))
        }
    }

    // MARK: Proposal + votes

    @ViewBuilder
    private func proposalBanner(_ proposal: TimeProposal) -> some View {
        let isMine = proposal.by == myUid
        let when = EventManager.proposalTimeText(start: proposal.start, end: proposal.end)
        let iAgree = myUid.map { proposal.yes.contains($0) } ?? false
        let iDisagree = myUid.map { proposal.no.contains($0) } ?? false

        VStack(alignment: .leading, spacing: 10) {
            Text(isMine
                 ? String(format: String(localized: "proposal_mine_format"), when)
                 : String(format: String(localized: "proposal_other_format"),
                          eventManager.displayName(for: proposal.by), when))
                .font(.subheadline)

            // Progress toward the votes needed + tally: "1/2 đồng ý (cần 2)"
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule().fill(Color.orange)
                            .frame(width: geo.size.width * voteFraction(proposal))
                    }
                }
                .frame(height: 5)

                Text(String(format: String(localized: "proposal_tally_format"),
                            proposal.yes.count, event.voterCount, event.votesNeeded))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            if !proposal.no.isEmpty {
                Text(String(format: String(localized: "proposal_against_format"),
                            proposal.no.map { eventManager.displayName(for: $0) }.sorted().joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if isMine {
                    Button(String(localized: "proposal_withdraw")) {
                        run { await eventManager.withdrawProposal(for: event) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    voteButton(String(localized: "proposal_accept"),
                               selected: iAgree, prominent: true) {
                        await eventManager.voteOnProposal(true, for: event)
                    }
                    voteButton(String(localized: "proposal_decline"),
                               selected: iDisagree, prominent: false) {
                        await eventManager.voteOnProposal(false, for: event)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Helpers

    /// Runs a save; shows an error when Firestore rejected it (e.g. no permission / offline).
    private func run(_ action: @escaping () async -> Bool) {
        isSaving = true
        Task {
            let ok = await action()
            isSaving = false
            if ok {
                withAnimation { editingMyResponse = false }
            } else {
                showSaveError = true
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ response: EventResponse?) -> some View {
        switch response {
        case .accepted:
            Label(String(localized: "response_status_accepted"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .declined:
            Label(String(localized: "response_status_declined"), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case nil:
            Label(String(localized: "response_status_pending"), systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private func responseButton(_ title: String, _ icon: String, selected: Bool,
                                tint: Color, action: @escaping () async -> Bool) -> some View {
        Button {
            // Already my choice → no write, no chat message; just fold the row back
            guard !selected else {
                withAnimation { editingMyResponse = false }
                return
            }
            run(action)
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? tint : tint.opacity(0.12)))
                .foregroundStyle(selected ? .white : tint)
        }
        .buttonStyle(.plain)
    }

    /// Equal-width vote button: prominent = solid green "Agree", otherwise a plain
    /// "Keep current time". A checkmark marks the option I already picked.
    private func voteButton(_ title: String, selected: Bool, prominent: Bool,
                            action: @escaping () async -> Bool) -> some View {
        Button {
            // Already my choice → no write, no chat message; just fold the row back
            guard !selected else {
                withAnimation { editingMyResponse = false }
                return
            }
            run(action)
        } label: {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(prominent ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.systemBackground))))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .stroke(Color.primary.opacity(prominent ? 0 : 0.08), lineWidth: 1))
            .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    /// Share of the votes needed that already agreed (0…1) — same numbers as the tally.
    private func voteFraction(_ proposal: TimeProposal) -> CGFloat {
        guard event.votesNeeded > 0 else { return 0 }
        return min(max(CGFloat(proposal.yes.count) / CGFloat(event.votesNeeded), 0), 1)
    }
}

// MARK: - Propose another time

struct ProposeTimeSheet: View {
    let event: CalendarEvent
    var onSend: (Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var durationMinutes: Int

    init(event: CalendarEvent, onSend: @escaping (Date, Date) -> Void) {
        self.event = event
        self.onSend = onSend
        _start = State(initialValue: event.startTime)
        let mins = Int(event.endTime.timeIntervalSince(event.startTime) / 60)
        _durationMinutes = State(initialValue: max(15, mins))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(String(localized: "start_label"), selection: $start, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                Stepper(value: $durationMinutes, in: 15...480, step: 15) {
                    Text(String(format: String(localized: "duration_minutes_format"), durationMinutes))
                }
            }
            .navigationTitle(String(localized: "response_propose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "proposal_send")) {
                        onSend(start, start.addingTimeInterval(TimeInterval(durationMinutes * 60)))
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add to iPhone Calendar

/// Apple's own "new event" screen, pre-filled. Runs out of process, so on
/// iOS 17+ it needs no calendar permission.
struct AddToDeviceCalendarSheet: UIViewControllerRepresentable {
    let event: CalendarEvent
    var onDone: () -> Void

    /// Marks events we put into the iPhone calendar so the busy-time import skips them.
    static func marker(for eventId: String) -> URL? { URL(string: "easyschedule://event/\(eventId)") }

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let ek = EKEvent(eventStore: store)
        ek.title = event.title
        ek.startDate = event.startTime
        ek.endDate = event.endTime
        ek.url = Self.marker(for: event.id)
        if let loc = event.location {
            let structured = EKStructuredLocation(title: loc.name)
            structured.geoLocation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            ek.structuredLocation = structured
        }

        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = ek
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
