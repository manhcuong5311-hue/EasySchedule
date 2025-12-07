//
// PartnerCalendarTabView.swift
// Easy Schedule
//
// Updated for EventManager v2 (stable IDs, pendingDelete handling).
//

import SwiftUI
import FirebaseAuth

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

                    // ================================
                    // MARK: INPUT UID AREA
                    // ================================
                    inputArea
                        .padding(.horizontal)


                    // ================================
                    // MARK: ACTION BUTTONS
                    // ================================
                    VStack(spacing: 14) {

                        // LỊCH SỬ ĐÃ XEM
                        Button {
                            showHistorySheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)

                                Text(String(localized: "viewed_history"))
                                    .font(.system(size: 16, weight: .semibold))

                                Spacer()
                            }
                            .padding()
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(14)
                        }

                        // LỊCH TÔI TẠO CHO NGƯỜI KHÁC
                        Button {
                            showMyCreatedEvents = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)

                                Text(String(localized: "created_for_others"))
                                    .font(.system(size: 16, weight: .semibold))

                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(14)
                        }

                        // QUẢN LÝ QUYỀN TRUY CẬP
                        Button {
                            showAccessSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2.checkmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.blue)

                                Text(String(localized: "manage_access"))
                                    .font(.system(size: 16, weight: .semibold))

                                Spacer()
                            }
                            .padding()
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal)


                    // ================================
                    // MARK: UID INFO
                    // ================================
                    VStack(alignment: .leading, spacing: 6) {
                        if let uid = parsedUID {
                            HStack {
                                Text("UID:")
                                    .bold()

                                Text(uid)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(String(localized: "logged_in"))
                                    .foregroundColor(.green)
                                    .font(.subheadline)
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
                // NÚT HELP BÊN TRÁI
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHelpSheet = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20, weight: .semibold))
                    }
                }

                // NÚT + BÊN PHẢI (đã có)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
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
            .sheet(isPresented: $showHelpSheet) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {

                            Text(String(localized: "help_title"))
                                .font(.title2.bold())
                                .padding(.bottom, 10)

                            Group {
                                Text(String(localized: "help_section_paste_uid_title"))
                                    .font(.headline)
                                Text(String(localized: "help_section_paste_uid_desc"))
                                    .foregroundColor(.secondary)
                            }

                            Group {
                                Text(String(localized: "help_section_history_title"))
                                    .font(.headline)
                                Text(String(localized: "help_section_history_desc"))
                                    .foregroundColor(.secondary)
                            }

                            Group {
                                Text(String(localized: "help_section_created_for_others_title"))
                                    .font(.headline)
                                     Text(String(localized: "help_section_created_for_others_desc"))
                                    .foregroundColor(.secondary)
                            }

                            Group {
                                Text(String(localized: "help_section_access_title"))
                                    .font(.headline)
                                Text(String(localized: "help_section_access_desc"))
                                    .foregroundColor(.secondary)
                            }

                            Group {
                                Text(String(localized: "help_section_add_event_title"))
                                    .font(.headline)
                                Text(String(localized: "help_section_add_event_desc"))
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 40)
                        }
                        .padding()
                    }
                    .navigationTitle(String(localized: "help_nav_title"))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(String(localized:"close")) { showHelpSheet = false }
                        }
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
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(String(localized: "notification")),
                    message: Text(alertMessage),
                    dismissButton: .default(Text(String(localized: "close")))
                )
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
                Button(action: { parseAndLoad() }) {
                    HStack {
                        if isLoading { ProgressView().scaleEffect(0.7) }
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
                    Text("UID:").bold()
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
                Text("\(ownerPrefix) \(ev.owner)")
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
        guard let uid = parsedUID else {
            alertMessage = String(localized: "uid_required")
            showAlert = true
            return
        }
        guard Auth.auth().currentUser != nil else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        selectedSharedUserId = uid
        showAddAppointmentSheet = true
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

        if let url = URL(string: input),
           let last = url.pathComponents.last,
           !last.isEmpty {
            parsedUID = last
        } else {
            parsedUID = input
        }

        guard let uid = parsedUID else {
            errorMessage = String(localized: "cannot_extract_uid")
            return
        }

        loadBusySlots(uid: uid)
    }

    private func loadBusySlots(uid: String) {
        isLoading = true
        errorMessage = nil
        fetchedEvents.removeAll()
        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, isPremiumUser in
            DispatchQueue.main.async {
                self.isLoading = false

                let filtered = slots.filter { slot in
                    !self.eventManager.events.contains(where: { local in
                        local.pendingDelete && local.id == slot.id
                    })
                }

                self.fetchedEvents = filtered.sorted { $0.startTime < $1.startTime }
                eventManager.partnerBusySlots[uid] = filtered
               

                if !isPremiumUser {
                    self.errorMessage = String(localized: "seven_day_limit")
                } else if filtered.isEmpty {
                    self.errorMessage = String(localized: "no_busy_events_for_uid")
                }
            }
        }
    }


    private func sectionHeader(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }


    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}

struct HistoryLinksView: View {
    @EnvironmentObject var eventManager: EventManager
    var onSelect: (String) -> Void

    @State private var showCopied = false
    @State private var showConfirmClear = false
    @State private var searchText: String = ""

    var sortedLinks: [SharedLink] {
        eventManager.sharedLinks.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var filteredLinks: [SharedLink] {
        if searchText.isEmpty {
            return sortedLinks
        } else {
            return sortedLinks.filter { link in
                (link.displayName ?? "")
                    .lowercased()
                    .contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredLinks) { link in
                VStack(alignment: .leading) {
                    Text(link.displayName ?? "")
                        .font(.headline)

                    Text("UID: \(link.uid)")
                        .font(.caption)

                    Text(formatDate(link.createdAt))
                        .font(.caption2)
                }
                .onTapGesture { onSelect(link.uid) }
                .onLongPressGesture {
                    UIPasteboard.general.string = link.url
                    showCopied = true
                }
            }
            .onDelete(perform: deleteAt)
        }
        .navigationTitle(String(localized: "viewed_history"))
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: String(localized: "search_name"))
        .alert(String(localized:"link_copied"), isPresented: $showCopied) {
            Button("OK") {}
        }
    }

    private func deleteAt(at offsets: IndexSet) {
        let sorted = sortedLinks
        for index in offsets {
            let item = sorted[index]
            if let originalIndex = eventManager.sharedLinks.firstIndex(where: { $0.id == item.id }) {
                eventManager.sharedLinks.remove(at: originalIndex)
            }
        }
        eventManager.saveSharedLinks()
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
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
