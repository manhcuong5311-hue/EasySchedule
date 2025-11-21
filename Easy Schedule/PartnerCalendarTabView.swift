//
//  PartnerCalendarTabView.swift
//  Easy schedule
//
//  Created by ChatGPT for Sam Manh Cuong on 11/11/25.
//  Usage: Thêm file này vào project. ContentView đã reference PartnerCalendarTabView().
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
    @State private var appointmentDate: Date = Date()
    @State private var appointmentStart: Date = Date()
    @State private var appointmentEnd: Date = Date().addingTimeInterval(3600)
    @State private var appointmentTitle: String = ""
    @State private var selectedSharedUserId: String?

    // Alert
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    private var groupedByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: fetchedEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }

    // MARK: - BODY
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                // ------- INPUT LINK ------
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

                Divider()

                // ------- UID INFO ------
                if let uid = parsedUID {
                    HStack {
                        Text("UID:").bold()
                        Text(uid)
                        Spacer()
                        Text(Auth.auth().currentUser == nil ? "Chưa đăng nhập" : "Đã đăng nhập")
                            .font(.caption)
                            .foregroundColor(Auth.auth().currentUser == nil ? .red : .green)
                    }
                    .padding(.horizontal)
                }

                // ------- ERROR -------
                if let err = errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // ------- LIST EVENTS -------
                if isLoading {
                    Spacer()
                    ProgressView("Đang tải lịch...")
                    Spacer()
                }
                else if fetchedEvents.isEmpty {
                    Spacer()
                    Text(parsedUID == nil
                         ? "Chưa có UID. Dán link rồi bấm Load."
                         : "Không có lịch bận.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                else {
                    scheduleListView
                }
            }

            // ------- TOOLBAR (+) -------
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

            // ------- SHEET -------
            .sheet(isPresented: $showAddAppointmentSheet) {
                AppointmentProSheet(
                    isPresented: $showAddAppointmentSheet,
                    sharedUserId: selectedSharedUserId
                )
                .environmentObject(eventManager)
            }

            // ------- ALERT -------
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Thông báo"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("Đóng"))
                )
            }
        }
    }

    // MARK: - LIST VIEW (TÁCH RA CHO NHẸ)
    private var scheduleListView: some View {
        List {
            let days = groupedByDay.keys.sorted(by: >)

            ForEach(days, id: \.self) { day in
                Section(header: Text(sectionHeader(for: day))) {

                    // Tách event để compiler dễ xử lý
                    let events = (groupedByDay[day] ?? [])
                        .sorted { $0.startTime < $1.startTime }

                    ForEach(events) { ev in
                        eventRow(ev)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - EVENT ROW (TÁCH RA CHO NHẸ)
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
                    return
                }

                // 🔥 SỬA LỖI UID — kiểm tra chắc chắn trước khi mở sheet
                guard let uid = parsedUID, !uid.isEmpty else {
                    alertMessage = "Không xác định UID người nhận."
                    showAlert = true
                    return
                }

                // Prefill
                appointmentDate = ev.startTime
                appointmentStart = ev.startTime
                appointmentEnd = ev.startTime.addingTimeInterval(1800)
                appointmentTitle = "Cuộc hẹn"

                selectedSharedUserId = uid    // 🔥 chuyển sang UID đã kiểm tra
                showAddAppointmentSheet = true

            } label: {
                Text("Đặt")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }


    // MARK: - ACTIONS

    private func addAppointmentPressed() {
        guard let uid = parsedUID, !uid.isEmpty else {
            alertMessage = "Bạn cần nhập link hoặc UID trước."
            showAlert = true
            return
        }
        guard Auth.auth().currentUser != nil else {
            alertMessage = "Bạn cần đăng nhập để đặt lịch."
            showAlert = true
            return
        }

        selectedSharedUserId = uid   // 🔥 UID đảm bảo chắc chắn hợp lệ
        showAddAppointmentSheet = true
    }


    // MARK: - HELPERS

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

        eventManager.fetchBusySlots(for: uid) { slots in
            DispatchQueue.main.async {
                self.isLoading = false
                self.fetchedEvents = slots.sorted { $0.startTime < $1.startTime }
                if slots.isEmpty {
                    self.errorMessage = "Không tìm thấy lịch bận cho UID này."
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


// MARK: - Appointment create sheet
struct AppointmentCreateSheet: View {
    @EnvironmentObject var eventManager: EventManager

    @Binding var isPresented: Bool
    let sharedUserId: String?

    @Binding var date: Date
    @Binding var start: Date
    @Binding var end: Date
    @Binding var titleText: String

    // completion handler (success, optional message)
    var completion: ((Bool, String?) -> Void)? = nil

    @State private var isAdding: Bool = false
    @State private var localMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tiêu đề", text: $titleText)
                }
                Section("Ngày & giờ") {
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    DatePicker("Bắt đầu", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("Kết thúc", selection: $end, displayedComponents: .hourAndMinute)
                }
                if let msg = localMessage {
                    Section {
                        Text(msg).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Tạo cuộc hẹn")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createAppointment()
                    } label: {
                        if isAdding { ProgressView() }
                        else { Text("Gửi") }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { isPresented = false }
                }
            }
        }
    }

    private func createAppointment() {
        guard let sharedId = sharedUserId else {
            localMessage = "Không xác định được UID người nhận."
            return
        }
        guard !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localMessage = "Vui lòng nhập tiêu đề."
            return
        }

        // Merge date + times
        let startDT = combine(date: date, time: start)
        let endDT = combine(date: date, time: end)
        if endDT <= startDT {
            localMessage = "Thời gian kết thúc phải sau thời gian bắt đầu."
            return
        }

        guard Auth.auth().currentUser != nil else {
            localMessage = "Bạn cần đăng nhập để đặt lịch."
            return
        }

        isAdding = true
        eventManager.addAppointment(forSharedUser: sharedId, title: titleText, start: startDT, end: endDT) { success, message in
            DispatchQueue.main.async {
                self.isAdding = false
                if success {
                    completion?(true, nil)
                    isPresented = false
                } else {
                    localMessage = message ?? "Lỗi khi tạo lịch."
                    completion?(false, message)
                }
            }
        }
    }

    private func combine(date day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = d.year; comps.month = d.month; comps.day = d.day
        comps.hour = t.hour ?? 0; comps.minute = t.minute ?? 0; comps.second = t.second ?? 0
        return cal.date(from: comps) ?? day
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


