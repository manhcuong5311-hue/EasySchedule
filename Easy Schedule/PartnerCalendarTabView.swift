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

    // Link input
    @State private var linkText: String = ""
    @State private var parsedUID: String? = nil

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

    // Group by day for UI
    private var groupedByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: fetchedEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                inputArea
                Divider()
                uidInfoArea
                errorArea
                contentArea
            }
            .navigationTitle("Lịch đối tác")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addAppointmentPressed()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .padding(.bottom, 8)
            .sheet(isPresented: $showAddAppointmentSheet) {
                // AppointmentProSheet expected to accept sharedUserId param
                AppointmentProSheet(
                    isPresented: $showAddAppointmentSheet,
                    sharedUserId: selectedSharedUserId
                )
                .environmentObject(eventManager)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Thông báo"), message: Text(alertMessage), dismissButton: .default(Text("Đóng")))
            }
        }
    }

    // MARK: - Subviews

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                TextField("Dán link chia sẻ hoặc UID", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            HStack {
                Button(action: { parseAndLoad() }) {
                    HStack {
                        if isLoading { ProgressView().scaleEffect(0.7) }
                        Text("Load lịch")
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
                    Text(Auth.auth().currentUser == nil ? "Chưa đăng nhập" : "Đã đăng nhập")
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
                ProgressView("Đang tải lịch...")
                Spacer()
            } else if fetchedEvents.isEmpty {
                Spacer()
                Text(parsedUID == nil ? "Chưa có UID. Dán link rồi bấm Load." : "Không có lịch bận.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                scheduleListView
            }
        }
    }

    private var scheduleListView: some View {
        List {
            let days = groupedByDay.keys.sorted(by: >)
            ForEach(days, id: \.self) { day in
                Section(header: Text(sectionHeader(for: day))) {
                    let events = (groupedByDay[day] ?? []).sorted { $0.startTime < $1.startTime }
                    ForEach(events) { ev in
                        eventRow(ev)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                Text("Chủ: \(ev.owner)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if Auth.auth().currentUser == nil {
                    alertMessage = "Bạn cần đăng nhập để đặt lịch."
                    showAlert = true
                } else {
                    // ensure uid is set before opening sheet
                    if let uid = parsedUID {
                        selectedSharedUserId = uid
                        // open pro sheet (your AppointmentProSheet should read sharedUserId)
                        showAddAppointmentSheet = true
                    } else {
                        alertMessage = "Bạn cần load UID trước."
                        showAlert = true
                    }
                }
            } label: {
                Text("Đặt")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions & Helpers

    private func addAppointmentPressed() {
        guard let uid = parsedUID else {
            alertMessage = "Bạn cần nhập link hoặc UID trước."
            showAlert = true
            return
        }
        guard Auth.auth().currentUser != nil else {
            alertMessage = "Bạn cần đăng nhập để đặt lịch."
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
            errorMessage = "Vui lòng dán link hoặc UID."
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
            errorMessage = "Không lấy được UID từ link."
            return
        }

        loadBusySlots(uid: uid)
    }

    private func loadBusySlots(uid: String) {
        isLoading = true
        errorMessage = nil
        fetchedEvents.removeAll()

        // fetch from EventManager (one-shot)
        eventManager.fetchBusySlots(for: uid) { slots in
            DispatchQueue.main.async {
                self.isLoading = false

                // filter out slots that match a local event pendingDelete
                let filtered = slots.filter { slot in
                    !self.eventManager.events.contains(where: { local in
                        // if local is pendingDelete and id matches slot.id -> drop slot
                        return local.pendingDelete && local.id == slot.id
                    })
                }

                self.fetchedEvents = filtered.sorted { $0.startTime < $1.startTime }

                if filtered.isEmpty {
                    self.errorMessage = "Không tìm thấy lịch bận cho UID này (hoặc chưa có dữ liệu)."
                }
            }
        }
    }

    private func sectionHeader(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .full
        return f.string(from: day)
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Preview
struct PartnerCalendarTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PartnerCalendarTabView()
                .environmentObject(EventManager())
        }
    }
}
