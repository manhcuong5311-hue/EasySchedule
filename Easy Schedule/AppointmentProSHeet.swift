//
// AppointmentProSheet.swift
// Easy schedule
//
// Created by ChatGPT for Sam Manh Cuong
//


import SwiftUI
import FirebaseAuth

// NOTE: dùng tên ProSlot để tránh trùng với TimeSlot
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
    @State private var partnerIsPremium: Bool = true
    @State private var showPremiumAlert = false

    @State private var customStart: Date = Date()
    @State private var customEnd: Date = Date()
    @State private var useCustomTime: Bool = false

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
                        Text(sharedUserId ?? "Chưa có UID")
                            .font(.subheadline).lineLimit(1)
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

                if partnerOffDays.contains(Calendar.current.startOfDay(for: selectedDate)) {
                    Text("Chủ lịch nghỉ ngày này — không thể đặt lịch.")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .padding(.top, 4)
                }

                Divider()

                // Form
                Form {

                    // TIÊU ĐỀ
                    Section(header: Text("Tiêu đề")) {
                        TextField("Tiêu đề cuộc hẹn", text: $titleText)
                    }

                    // ⭐ GIỜ TÙY CHỈNH
                    Section(header: Text("Khung giờ tuỳ chỉnh")) {

                        Toggle("Dùng giờ tuỳ chỉnh", isOn: $useCustomTime)

                        if useCustomTime {

                            DatePicker("Bắt đầu", selection: $customStart, displayedComponents: .hourAndMinute)

                            DatePicker("Kết thúc", selection: $customEnd, displayedComponents: .hourAndMinute)
                                .onChange(of: customEnd) {
                                    if customEnd <= customStart {
                                        customEnd = Calendar.current.date(
                                            byAdding: .minute,
                                            value: 15,
                                            to: customStart
                                        )!
                                    }
                                }

                            let merged = ProSlot(
                                start: combine(selectedDate, customStart),
                                end: combine(selectedDate, customEnd)
                            )

                            if checkBusy(merged) {
                                Text("Khung giờ này đã bận hoặc rơi vào ngày nghỉ.")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }

                    // ⭐ KHUNG GIỜ 30P
                    Section(header: Text("Khung giờ (30 phút)")) {

                        let slots = generateSlots(for: selectedDate)
                        let now = Date()
                        let maxPremiumDate = calendar.date(byAdding: .day, value: 7, to: now)!
                        let dayBlocked = (!partnerIsPremium && selectedDate > maxPremiumDate)

                        Toggle("Dùng giờ tuỳ chỉnh", isOn: $useCustomTime)
                            .disabled(dayBlocked)
                            .opacity(dayBlocked ? 0.35 : 1)

                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(slots, id: \.self) { slot in

                                    let blocked = dayBlocked

                                    SlotRowPro(
                                        slot: slot,
                                        isBusy: checkBusy(slot),
                                        isSelected: selectedSlot == slot,
                                        action: {
                                            if !blocked && !useCustomTime && !checkBusy(slot) {
                                                selectedSlot = slot
                                            }
                                        }
                                    )
                                    .opacity(blocked ? 0.35 : 1.0)
                                    .allowsHitTesting(!blocked)
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
                    Button("Đặt") {

                        if useCustomTime {
                            selectedSlot = ProSlot(
                                start: combine(selectedDate, customStart),
                                end: combine(selectedDate, customEnd)
                            )
                        }

                        handleCreate()
                    }
                    .disabled((!useCustomTime && selectedSlot == nil) || sharedUserId == nil)
                }
            }
            .onAppear { loadBusy() }

            // Popup lỗi chung
            .alert(item: Binding(
                get: { errorMessage.map { SimpleError(id: 0, message: $0) } },
                set: { _ in errorMessage = nil }
            )) { err in
                Alert(title: Text("Lỗi"),
                      message: Text(err.message),
                      dismissButton: .default(Text("Đóng")))
            }

            // Popup Premium
            .alert("Thông báo", isPresented: $showPremiumAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Người này chưa đăng Premium.")
            }
            .padding(.bottom)
        }
       
        .onChange(of: selectedDate) { oldValue, newValue in
            let limitDate = calendar.date(byAdding: .day, value: 7, to: Date())!
            let dayBlocked = (!partnerIsPremium && newValue > limitDate)

            if dayBlocked {
                selectedSlot = nil
            }
        }


    }

    // MARK: Load dữ liệu
    private func loadBusy() {
        guard let uid = sharedUserId else {
            loading = false
            busySlots = []
            errorMessage = "Không xác định UID người nhận."
            return
        }

        // SAVE HISTORY
        let link = SharedLink(
            id: UUID().uuidString,
            uid: uid,
            url: "https://easyschedule-ce98a.web.app/calendar/\(uid)",
            createdAt: Date()
        )
        eventManager.sharedLinks.append(link)

        loading = true

        // 1️⃣ Load busy + premium
        eventManager.fetchBusySlots(for: uid) { slots, isPremium in
            DispatchQueue.main.async {
                self.busySlots = slots
                self.partnerIsPremium = isPremium
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

    // MARK: Xử lý đặt lịch
    private func handleCreate() {

        let now = Date()
        let maxPremiumDate = calendar.date(byAdding: .day, value: 7, to: now)!

        if !partnerIsPremium && selectedDate > maxPremiumDate {
            errorMessage = "Chủ lịch chưa đăng Premium — bạn chỉ được đặt lịch trong 7 ngày tới."
            showPremiumAlert = true
            return
        }

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

        eventManager.addAppointment(
            forSharedUser: uid,
            title: titleText,
            start: slot.start,
            end: slot.end
        ) { success, msg in
            DispatchQueue.main.async {
                if success { isPresented = false }
                else { errorMessage = msg ?? "Tạo lịch thất bại." }
            }
        }
        
    }

    // MARK: Helper

    private func combine(_ date: Date, _ time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let t = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(from: DateComponents(
            year: d.year, month: d.month, day: d.day,
            hour: t.hour, minute: t.minute
        ))!
    }

    private func checkBusy(_ slot: ProSlot) -> Bool {
        let day = Calendar.current.startOfDay(for: slot.start)
        if partnerOffDays.contains(day) { return true }
        return busySlots.contains {
            $0.startTime < slot.end && $0.endTime > slot.start
        }
    }

    private func generateSlots(for date: Date) -> [ProSlot] {
        var arr: [ProSlot] = []
        guard let startOfDay = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: date) else { return [] }
        for i in 0..<32 {
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
    var onSelect: (String) -> Void = { _ in }

    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            List {
                // ⭐ Sắp xếp: pinned trước, sau đó theo thời gian
                let sortedLinks = eventManager.sharedLinks.sorted {
                    if $0.isPinned == $1.isPinned { return $0.createdAt > $1.createdAt }
                    return $0.isPinned && !$1.isPinned
                }

                ForEach(sortedLinks) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(link.url)
                                .font(.body)
                                .lineLimit(1)

                            Text("UID: \(link.uid)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(link.createdAt))
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        // ⭐ Nút PIN
                        Button {
                            eventManager.togglePin(link)
                        } label: {
                            Image(systemName: link.isPinned ? "pin.fill" : "pin")
                                .foregroundColor(link.isPinned ? .orange : .gray)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(link.url) // Load ngay
                    }
                    .onLongPressGesture {
                        UIPasteboard.general.string = link.url
                        showCopied = true
                    }
                }
                .onDelete { indexSet in
                    eventManager.sharedLinks.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("Lịch sử đã xem")
            .alert("Đã copy link!", isPresented: $showCopied) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func formatDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}


// MARK: - Preview
struct AppointmentProSheet_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AppointmentProSheet(isPresented: .constant(true), sharedUserId: "demoUID")
                .environmentObject(EventManager.shared
)
        }
    }
}
