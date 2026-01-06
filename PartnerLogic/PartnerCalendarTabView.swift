//
// PartnerCalendarTabView.swift
// Easy Schedule
//
// Updated for EventManager v2 (stable IDs, pendingDelete handling).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PartnerCalendarTabView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var showMyCreatedEvents = false
    @EnvironmentObject var session: SessionStore
    // Link input
    @State private var linkText: String = ""
    @State private var parsedUID: String? = nil
    @State private var showAccessSheet = false
    // Fetching state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var fetchedEvents: [CalendarEvent] = []

    // Sheet for creating appointment
    @State private var showAddAppointmentSheet: Bool = false
    @State private var selectedSharedUserId: String?

    // Alert
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showHistorySheet: Bool = false
    @State private var showHelpSheet = false
    @EnvironmentObject var network: NetworkMonitor

    // Group by day for UI
    private var groupedByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: fetchedEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }

    var body: some View {
        NavigationStack {

            ScrollView {
                VStack(spacing: 20) {
                    if !network.isOnline {
                               OfflineBannerView()
                                   .padding(.horizontal)
                           }
                    // ================================
                    // MARK: INPUT UID AREA
                    // ================================
                    inputArea
                        .padding(.horizontal)


                    // ================================
                    // MARK: ACTION BUTTONS
                    // ================================
                    VStack(alignment: .leading, spacing: 12) {

                        Text(String(localized: "manage_sharing"))
                            .font(.headline)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {

                            manageRow(
                                icon: "clock.arrow.circlepath",
                                title: String(localized: "viewed_history")
                            ) {
                                showHistorySheet = true
                            }

                            Divider()

                            manageRow(
                                icon: "person.crop.circle.badge.plus",
                                title: String(localized: "created_for_others")
                            ) {
                                showMyCreatedEvents = true
                            }

                            Divider()

                            manageRow(
                                icon: "person.2.fill",
                                title: String(localized: "manage_access")
                            ) {
                                showAccessSheet = true
                            }
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.15))
                        )
                    }
                    .padding(.horizontal)



                    // ================================
                    // MARK: UID INFO
                    // ================================
                    VStack(alignment: .leading, spacing: 6) {
                        if let uid = parsedUID {
                            HStack {
                                Text(String(localized: "uid_label") + ":")
                                    .bold()


                                Text(uid)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(String(localized: "account_active"))
                                    .foregroundColor(.green)
                                    .font(.caption)

                            }
                        }
                    }
                    .padding(.horizontal)


                    // ================================
                    // MARK: ERROR AREA
                    // ================================
                    if let error = errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }


                    // ================================
                    // MARK: CONTENT AREA (DANH SÁCH LỊCH)
                    // ================================
                    contentArea
                        .padding(.top, 8)

                }
                .padding(.top, 12)
            }

            // ================================
            // MARK: TITLE + TOOLBAR
            // ================================
            .navigationTitle(String(localized: "partner_calendar"))
            .toolbar {
                // NÚT + BÊN PHẢI (đã có)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        guard !isLoading else { return }
                                addAppointmentPressed()
                    } label: {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            )
                    }
                }
                
            }
            

            // ================================
            // MARK: SHEETS
            // ================================
            .sheet(isPresented: $showHistorySheet) {
                NavigationStack {
                    HistoryLinksView { uid in
                        linkText = uid
                        parsedUID = uid
                        parseAndLoad()
                        showHistorySheet = false
                    }
                    .environmentObject(eventManager)
                }
            }

            .sheet(isPresented: $showMyCreatedEvents) {
                MyCreatedEventsView()
                    .environmentObject(eventManager)
            }

            .sheet(isPresented: $showAccessSheet) {
                NavigationStack {
                    AccessManagementView()
                        .environmentObject(eventManager)
                        .environmentObject(session)
                }
            }

            .sheet(isPresented: $showAddAppointmentSheet) {
                AppointmentProSheet(
                    isPresented: $showAddAppointmentSheet,
                    sharedUserId: selectedSharedUserId,
                    sharedUserName: eventManager.userNames[selectedSharedUserId ?? ""]
                )
                .environmentObject(eventManager)
                .environmentObject(session)
            }


            // ================================
            // MARK: ALERT
            // ================================
            .alert(
                String(localized: "unable_to_proceed"),
                isPresented: $showAlert
            ) {
                Button(String(localized: "close"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }

        }
    }


    // MARK: - Subviews

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                TextField(String(localized: "paste_link_or_uid"), text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            HStack {
                Button(action: {
                    guard !isLoading else { return }
                    parseAndLoad()
                }) {
                    HStack {
                        if isLoading {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(String(localized: "load_calendar"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    linkText = ""
                    parsedUID = nil
                    fetchedEvents.removeAll()
                    errorMessage = nil
                }) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
        .padding()
    }

    private var uidInfoArea: some View {
        Group {
            if let uid = parsedUID {
                HStack {
                    Text(String(localized: "uid_label") + ":")
                        .bold()
                    Text(uid).lineLimit(1)
                    Spacer()
                    Text(
                        Auth.auth().currentUser == nil
                        ? String(localized: "not_logged_in")
                        : String(localized: "logged_in")
                    )
                        .font(.caption)
                        .foregroundColor(Auth.auth().currentUser == nil ? .red : .green)
                }
                .padding(.horizontal)
            }
        }
    }

    private var errorArea: some View {
        Group {
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var contentArea: some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView(String(localized: "loading_calendar"))
                Spacer()
            } else if fetchedEvents.isEmpty {
                Spacer()
                Text(
                    parsedUID == nil
                    ? String(localized: "no_uid_yet")
                    : String(localized: "no_busy_events")
                )
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                EmptyView()
            }
        }
    }

   

    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: ev.colorHex.isEmpty ? "#007AFF" : ev.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading) {
                Text(ev.title).font(.headline)
                Text("\(formattedTime(ev.startTime)) — \(formattedTime(ev.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                let ownerPrefix = String(localized: "owner_prefix")
                Text("\(ownerPrefix) \(eventManager.displayName(for: ev.owner))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if Auth.auth().currentUser == nil {
                    alertMessage = String(localized: "login_required")
                    showAlert = true
                } else {
                    // ensure uid is set before opening sheet
                    if let uid = parsedUID {
                        selectedSharedUserId = uid
                        // open pro sheet (your AppointmentProSheet should read sharedUserId)
                        showAddAppointmentSheet = true
                    } else {
                        alertMessage = String(localized: "uid_required")
                        showAlert = true
                    }
                }
            } label: {
                Text(String(localized: "book"))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions & Helpers
    private func addAppointmentPressed() {
        let input = linkText.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1️⃣ Chưa nhập gì
        guard !input.isEmpty else {
            alertMessage = String(localized: "uid_required")
            showAlert = true
            return
        }

        // 2️⃣ Parse UID
        let parsed: String
        if let url = URL(string: input),
           let last = url.pathComponents.last,
           !last.isEmpty {
            parsed = last
        } else {
            parsed = input
        }

        // 3️⃣ Check format UID (NGĂN UID RÁC)
        guard isValidUIDFormat(parsed) else {
            alertMessage = String(localized: "invalid_uid")
            showAlert = true
            return
        }

        // 4️⃣ Check đăng nhập
        guard Auth.auth().currentUser != nil else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        // 5️⃣ Check UID tồn tại (ASYNC)
        isLoading = true
        eventManager.validateUserExists(uid: parsed) { exists in
            DispatchQueue.main.async {
                self.isLoading = false

                guard exists else {
                    self.alertMessage = String(localized: "uid_not_found")
                    self.showAlert = true
                    return
                }

                // ✅ OK → mới cho mở sheet
                self.parsedUID = parsed
                self.selectedSharedUserId = parsed
                self.showAddAppointmentSheet = true
            }
        }
    }

    private func isValidUIDFormat(_ uid: String) -> Bool {
        let regex = "^[A-Za-z0-9_-]{20,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: uid)
    }

    private func parseAndLoad() {
        errorMessage = nil
        fetchedEvents.removeAll()
        parsedUID = nil

        let input = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = String(localized: "paste_link_or_uid_first")
            return
        }

        let uid: String
        if let url = URL(string: input),
           let last = url.pathComponents.last,
           !last.isEmpty {
            uid = last
        } else {
            uid = input
        }

        // ❌ UID sai format → dừng luôn
        guard isValidUIDFormat(uid) else {
            errorMessage = String(localized: "invalid_uid")
            return
        }

        isLoading = true

        // ❌ UID không tồn tại → dừng
        eventManager.validateUserExists(uid: uid) { exists in
            DispatchQueue.main.async {
                self.isLoading = false

                guard exists else {
                    self.errorMessage = String(localized: "uid_not_found")
                    return
                }

                // ✅ UID hợp lệ → mới load
                self.parsedUID = uid
                self.loadBusySlots(uid: uid)
            }
        }
    }

    private func loadBusySlots(uid: String) {
        isLoading = true
        errorMessage = nil
        fetchedEvents.removeAll()

        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, tier in
            DispatchQueue.main.async {
                self.isLoading = false

                let filtered = slots.filter { slot in
                    !self.eventManager.events.contains(where: { local in
                        local.pendingDelete && local.id == slot.id
                    })
                }

                self.fetchedEvents = filtered.sorted { $0.startTime < $1.startTime }
                self.eventManager.partnerBusySlots[uid] = filtered

                // ===============================
                // MESSAGE THEO TIER (KHÔNG DÙNG BOOL)
                // ===============================
                if tier == .free {
                    self.errorMessage = String(localized: "seven_day_limit")
                } else if filtered.isEmpty {
                    self.errorMessage = String(localized: "no_busy_events_for_uid")
                }

                // ===============================
                // SHARED LINK (GIỮ NGUYÊN)
                // ===============================
                if !self.eventManager.sharedLinks.contains(where: { $0.uid == uid }) {
                    self.eventManager.sharedLinks.append(
                        SharedLink(
                            id: UUID().uuidString,
                            uid: uid,
                            url: linkText,
                            createdAt: Date(),
                            displayName: self.eventManager.userNames[uid]
                        )
                    )
                    self.eventManager.saveSharedLinks()
                }
            }
        }
    }

    @ViewBuilder
    private func manageRow(
        icon: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 16, weight: .medium))

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }


    private func sectionHeader(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }


    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}




// MARK: - Preview
struct PartnerCalendarTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PartnerCalendarTabView()
                .environmentObject(EventManager.shared)
        }
    }
}
