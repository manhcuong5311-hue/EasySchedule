//
//  AddEventView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

struct AddEventView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color = .blue // ✅ màu mặc định
    // Pre-fill date if user selected a date in calendar
    let prefillDate: Date?
    let offDays: Set<Date>        // ✅ THÊM MỚI — danh sách ngày nghỉ truyền từ ngoài vào
    let busyHours: [(Date, Date)]
    @State private var selectedDate: Date = Date()
   
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800) // default +1h
    // ✅ THÊM MỚI — biến trạng thái popup
    @State private var showOffDayAlert = false
    @State private var offDayMessage = ""
    @EnvironmentObject var premium: PremiumStoreViewModel
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false
    @EnvironmentObject var session: SessionStore
    @State private var showBusyInfo = false
    @State private var busyInfoEvent: CalendarEvent? = nil
    @State private var hasSelectedSlot = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "info_section"))) {
                    TextField(String(localized: "title_placeholder"), text: $title)
                }

                Section(header: Text(String(localized: "date_time_section"))) {
                    DatePicker(
                        String(localized: "date_label"),
                        selection: $date,
                        displayedComponents: .date
                    )
                    .onChange(of: date) { _, _ in
                        hasSelectedSlot = false
                    }

                    Section(String(localized: "select_time_section")) {
                        let hours = Array(0..<24)
                        let eventsToday = eventManager.events(for: date)

                        // Kiểm tra ngày nghỉ
                        let isOffDay = offDays.contains {
                            Calendar.current.isDate($0, inSameDayAs: date)
                        }


                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {

                            ForEach(hours, id: \.self) { hour in

                                let slotStart = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
                                let slotEnd   = slotStart.addingTimeInterval(3600)
                                // ✅ CHECK SLOT ĐÃ QUA (CHỈ ÁP DỤNG CHO HÔM NAY)
                                let isToday = Calendar.current.isDateInToday(date)
                                let now = Date()

                                let isPastSlot =
                                    isToday &&
                                    slotEnd <= now

                                // Check giờ bận
                                // 1️⃣ Busy do EVENT
                                let busyEvent = eventsToday.first {
                                    $0.startTime < slotEnd && $0.endTime > slotStart
                                }

                                // 2️⃣ Busy do BUSY HOURS
                                let busyHour = busyHours.first {
                                    $0.0 < slotEnd && $0.1 > slotStart
                                }

                                // 3️⃣ Tổng hợp
                                let isBusy =
                                    (busyEvent != nil) ||
                                    (busyHour != nil) ||
                                    isOffDay ||
                                    isPastSlot



                                // Check giờ được chọn
                                let selectedHour = Calendar.current.component(.hour, from: startTime)
                                let isSelected = hasSelectedSlot && (hour == selectedHour)

                                // Màu nền
                                let bgColor: Color = {
                                    if isSelected {
                                        return .blue.opacity(0.7)
                                    }
                                    if isPastSlot {
                                        return .gray.opacity(0.25)
                                    }
                                    if isBusy {
                                        return .red.opacity(0.40)
                                    }
                                    return .gray.opacity(0.15)
                                }()



                                Text(String(format: "%02d:00", hour))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(bgColor)
                                    .foregroundColor(isBusy ? .white : .primary)
                                    .cornerRadius(8)
                                    .contentShape(Rectangle())

                                    // TAP để chọn giờ
                                    .onTapGesture {
                                        if !isBusy {
                                            hasSelectedSlot = true
                                            startTime = slotStart
                                            endTime = slotStart.addingTimeInterval(1800)
                                        }
                                    }


                                    // LONG PRESS để xem giờ bận
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.4)
                                            .onEnded { _ in
                                                if let ev = busyEvent {
                                                    busyInfoEvent = ev
                                                    showBusyInfo = true

                                                } else if busyHour != nil {
                                                    alertMessage = String(localized: "busy_hours")
                                                    showAlert = true

                                                } else if isOffDay {
                                                    alertMessage = String(localized: "off_day")
                                                    showAlert = true
                                                }
                                            }

                                    )
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    DatePicker( String(localized: "start_label"), selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker( String(localized: "end_label"), selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text(String(localized: "event_color_section"))) {
 
                    ColorPicker(String(localized: "pick_color"), selection: $selectedColor, supportsOpacity: false)
                }
               

            }
            .onAppear {
                if let d = prefillDate {
                    date = d
                    selectedDate = d                  // <- QUAN TRỌNG: đồng bộ
                    // set startTime/endTime to that day same hour as current
                    let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
                    if let dayStart = Calendar.current.date(from: comps) {
                        // keep times (only change date portion)
                        startTime = combine(date: dayStart, time: startTime)
                        endTime = combine(date: dayStart, time: endTime)
                    }
                }
            }

            .navigationTitle(String(localized: "add_event_title"))

            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) {

                        guard !isSaving else { return }
                        isSaving = true

                        let calendar = Calendar.current
                        let now = Date()

                        // 1️⃣ OFF DAY
                        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                            let template = String(localized: "off_day_full_message")
                            offDayMessage = template
                                .replacingOccurrences(of: "{date}", with: formattedDate(date))
                            showOffDayAlert = true
                            isSaving = false
                            return
                        }

                        // 2️⃣ EMPTY TITLE
                        if title.trimmingCharacters(in: .whitespaces).isEmpty {
                            alertMessage = String(localized: "empty_title")
                            showAlert = true
                            isSaving = false
                            return
                        }

                        // 3️⃣ TIME
                        let s = combine(date: date, time: startTime)
                        var e = combine(date: date, time: endTime)

                        if e <= s {
                            e = s.addingTimeInterval(1800)
                        }

                        if !calendar.isDate(e, inSameDayAs: s) {
                            e = calendar.date(
                                bySettingHour: 23,
                                minute: 59,
                                second: 0,
                                of: s
                            )!
                        }

                        // 4️⃣ LIMIT
                        let tier = premium.tier
                        let limits = PremiumLimits.limits(for: tier)

                        if let maxDate = calendar.date(byAdding: .day,
                                                       value: limits.maxBookingDaysAhead,
                                                       to: now),
                           date > maxDate {

                            alertMessage = {
                                switch tier {
                                case .free: return String(localized: "limit_7_days")
                                case .premium: return String(localized: "limit_90_days")
                                case .pro: return String(localized: "limit_270_days")
                                }
                            }()

                            showAlert = true
                            isSaving = false
                            return
                        }
                        // 4️⃣b LIMIT SỐ EVENT / NGÀY
                        let sameDayEvents = eventManager.events.filter {
                            calendar.isDate($0.date, inSameDayAs: date)
                        }

                        if sameDayEvents.count >= limits.maxEventsPerDay {
                            alertMessage = String(localized: "event_limit_reached")
                            showAlert = true
                            isSaving = false
                            return
                        }

                        // 5️⃣ ADD EVENT
                        let success = eventManager.addEvent(
                            title: title,
                            ownerName: session.currentUserName,
                            date: date,
                            startTime: s,
                            endTime: e,
                            colorHex: selectedColor.toHex() ?? "#007AFF"
                        )

                        if success {
                            isSaving = false
                            dismiss()          // ✔️ feedback thành công
                        } else {
                            alertMessage = String(localized: "cannot_create_event")
                            showAlert = true  // ✔️ feedback thất bại
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)   // ⭐ CỰC KỲ QUAN TRỌNG CHO APPLE
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            // OFFDAY popup
            .alert(String(localized: "cannot_book"), isPresented: $showOffDayAlert) {
                Button(String(localized: "close"), role: .cancel) { }
            } message: {
                Text(offDayMessage)
            }

            // PREMIUM popup
            .alert(alertMessage, isPresented: $showAlert) {
                Button(String(localized:"ok"), role: .cancel) {}
            }
            .alert(
                String(localized: "busy_time"),
                isPresented: $showBusyInfo
            ) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                if let ev = busyInfoEvent {
                    Text("\(ev.title)\n\(formattedTime(ev.startTime)) – \(formattedTime(ev.endTime))")
                }
            }

        }
    }
    
    // Helper: combine date portion of `date` with time portion of `time`
    private func combine(date: Date, time: Date) -> Date {
        let cal = Calendar.current
        let dComp = cal.dateComponents([.year, .month, .day], from: date)
        let tComp = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = dComp.year
        comps.month = dComp.month
        comps.day = dComp.day
        comps.hour = tComp.hour
        comps.minute = tComp.minute
        comps.second = tComp.second ?? 0
        return cal.date(from: comps) ?? date
    }
  
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    // ✅ THÊM MỚI — định dạng ngày hiển thị trong popup
    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    
}
