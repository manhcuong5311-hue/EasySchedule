//
// AppointmentProSheet.swift
// Easy schedule
//
// Created by ChatGPT for Sam Manh Cuong
//

import SwiftUI
import FirebaseAuth

// NOTE: dùng tên ProSlot để tránh trùng với TimeSlot có thể đã tồn tại trong project
struct ProSlot: Hashable {
    let start: Date
    let end: Date
}

struct AppointmentProSheet: View {
    @EnvironmentObject var eventManager: EventManager

    @Binding var isPresented: Bool
    let sharedUserId: String?

    @State private var selectedDate: Date = Date()
    @State private var selectedSlot: ProSlot? = nil

    @State private var busySlots: [CalendarEvent] = []
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var partnerOffDays: Set<Date> = []

    @State private var titleText: String = "Cuộc hẹn"

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Người nhận").font(.caption).foregroundColor(.secondary)
                        Text(sharedUserId ?? "Chưa có UID").font(.subheadline).lineLimit(1)
                    }
                    Spacer()
                    if loading { ProgressView() }
                }
                .padding(.horizontal)

                // Mini calendar
                CalendarMiniView(
                    selectedDate: $selectedDate,
                    busySlots: busySlots,
                    offDays: partnerOffDays
                )
                    .frame(height: 260)
                // ⭐ THÔNG BÁO NGÀY NGHỈ
                if partnerOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                    Text("Chủ lịch nghỉ ngày này — không thể đặt lịch.")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .padding(.top, 4)
                }

                Divider()

                // Title + slots
                Form {
                    Section(header: Text("Tiêu đề")) {
                        TextField("Tiêu đề cuộc hẹn", text: $titleText)
                    }
                    Section(header: Text("Chọn khung giờ (30 phút)")) {
                        let slots = generateSlots(for: selectedDate) // precompute to help compiler
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(slots, id: \.self) { slot in
                                    SlotRowPro(
                                        slot: slot,
                                        isBusy: checkBusy(slot),
                                        isSelected: selectedSlot == slot
                                    ) {
                                        if !checkBusy(slot) {
                                            selectedSlot = slot
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
            .navigationTitle("Tạo cuộc hẹn")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đặt") { handleCreate() }
                        .disabled(selectedSlot == nil || sharedUserId == nil)
                }
            }
            .onAppear { loadBusy() }
            .alert(item: Binding(
                get: { errorMessage.map { SimpleError(id: 0, message: $0) } },
                set: { _ in errorMessage = nil }
            )) { err in
                Alert(title: Text("Lỗi"), message: Text(err.message), dismissButton: .default(Text("Đóng")))
            }
            .padding(.bottom)
        }
    }

    // Load busy slots from EventManager
    private func loadBusy() {
        guard let uid = sharedUserId else {
            loading = false
            busySlots = []
            errorMessage = "Không xác định UID người nhận."
            return
        }
        // 🔥 Lưu vào lịch sử của người B
        let fullLink = "https://easyschedule-ce98a.web.app/calendar/\(uid)"

        let link = SharedLink(
            id: UUID().uuidString,
            uid: uid,
            url: fullLink,
            createdAt: Date()
        )

        eventManager.sharedLinks.append(link)

        loading = true

        // 1️⃣ Load bận
        eventManager.fetchBusySlots(for: uid) { slots in
            DispatchQueue.main.async {
                self.busySlots = slots
            }
        }

        // 2️⃣ Load ngày nghỉ
        eventManager.fetchOffDays(for: uid) { offDays in
            DispatchQueue.main.async {
                self.partnerOffDays = offDays
                self.loading = false
            }
        }
    }


    private func handleCreate() {
        guard let uid = sharedUserId else {
            errorMessage = "Không xác định UID người nhận."
            return
        }
        guard let slot = selectedSlot else {
            errorMessage = "Chưa chọn khung giờ."
            return
        }
        guard Auth.auth().currentUser != nil else {
            errorMessage = "Bạn cần đăng nhập để đặt lịch."
            return
        }

        eventManager.addAppointment(forSharedUser: uid, title: titleText, start: slot.start, end: slot.end) { success, msg in
            DispatchQueue.main.async {
                if success {
                    isPresented = false
                } else {
                    errorMessage = msg ?? "Tạo lịch thất bại."
                }
            }
        }
    }

    private func checkBusy(_ slot: ProSlot) -> Bool {
        let day = Calendar.current.startOfDay(for: slot.start)
        if partnerOffDays.contains(day) { return true }   // 🔥 Block cả ngày
        return busySlots.contains { $0.startTime < slot.end && $0.endTime > slot.start }
    }


    private func generateSlots(for date: Date) -> [ProSlot] {
        var arr: [ProSlot] = []
        guard let startOfDay = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date) else { return [] }
        for i in 0..<32 { // 6:00 -> 22:00 (30-min slots)
            let s = startOfDay.addingTimeInterval(Double(i) * 1800)
            let e = s.addingTimeInterval(1800)
            arr.append(ProSlot(start: s, end: e))
        }
        return arr
    }

    struct SimpleError: Identifiable {
        let id: Int
        let message: String
    }
}

// MARK: - Mini calendar (unchanged logic)
struct CalendarMiniView: View {
    @Binding var selectedDate: Date
    let busySlots: [CalendarEvent]
    let offDays: Set<Date>

    @State private var month: Date = Date()
    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(formattedMonth(month)).font(.headline)
                Spacer()
                Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            let days = daysInMonth(for: month)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let isSelected = Calendar.current.isDate(selectedDate, inSameDayAs: day)
                    let isBusy = busySlots.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: day) })
                    let isOffDay = offDays.contains(Calendar.current.startOfDay(for: day))

                    VStack {
                        Text("\(Calendar.current.component(.day, from: day))")
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(
                                    isSelected ? Color.accentColor :
                                    (isOffDay ? Color.orange.opacity(0.4) :
                                    (isBusy ? Color.red.opacity(0.25) : Color.clear))
                                )
                            )

                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedDate = day }
                }
            }
            .padding(.horizontal)
        }
    }

    private func formattedMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
    }

    private func changeMonth(by v: Int) {
        if let n = calendar.date(byAdding: .month, value: v, to: month) { month = n }
    }

    private func daysInMonth(for date: Date) -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }
}

// MARK: - Slot row for ProSlot
struct SlotRowPro: View {
    let slot: ProSlot
    let isBusy: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(timeString(slot.start)).font(.subheadline)
            Text("-").font(.subheadline)
            Text(timeString(slot.end)).font(.subheadline)
            Spacer()
            if isBusy {
                Text("Bận").font(.caption).foregroundColor(.red)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            }
        }
        .padding(10)
        .background(isSelected ? Color.green.opacity(0.15) : (isBusy ? Color.red.opacity(0.06) : Color(UIColor.systemBackground)))
        .cornerRadius(8)
        .onTapGesture { action() }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.locale = Locale(identifier: "vi_VN")
        return f.string(from: d)
    }
}
struct HistoryView: View {
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        NavigationStack {
            List {
                ForEach(eventManager.sharedLinks.sorted { $0.createdAt > $1.createdAt }) { link in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(link.url)
                            .font(.subheadline)
                        Text(format(link.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Lịch sử đã xem")
        }
    }

    private func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Preview
struct AppointmentProSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AppointmentProSheet(isPresented: .constant(true), sharedUserId: "demoUID")
                .environmentObject(EventManager())
        }
    }
}
