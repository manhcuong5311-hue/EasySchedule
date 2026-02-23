//
//  AddEventView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
enum SaveEventAlert: Identifiable {
    case offDay(Date)
    case emptyTitle
    case pastTime
    case busyHours
    case conflict
    case overBookingDays(Int)
    case overEventsPerDay
    case cannotCreate

    var id: String {
        String(describing: self)
    }
}

enum SlotInfoAlert: Identifiable {
    case event(CalendarEvent)
    case busyHours
    case offDay

    var id: String {
        String(describing: self)
    }
}
enum AddEventAlert: Identifiable {
    case save(SaveEventAlert)
    case slot(SlotInfoAlert)

    var id: String {
        switch self {
        case .save(let alert):
            return "save-\(alert.id)"
        case .slot(let alert):
            return "slot-\(alert.id)"
        }
    }
}


struct AddEventView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color = .blue // ✅ màu mặc định
    // Pre-fill date if user selected a date in calendar
    let prefillDate: Date?
    let offDays: Set<Date>        // ✅ THÊM MỚI — danh sách ngày nghỉ truyền từ ngoài vào
    let busyHours: [(Date, Date)]
   
    
    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800) // default +1h
    // ✅ THÊM MỚI — biến trạng thái popup
    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var session: SessionStore
    @State private var hasSelectedSlot = false
    @State private var isSaving = false
    
    @State private var activeAlert: AddEventAlert?

    @State private var showUpgradeSheet = false
    @State private var showPremiumIntro = false
    
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
                                                // 🔑 RESET TRƯỚC
                                                activeAlert = nil

                                                DispatchQueue.main.async {
                                                    if let ev = busyEvent {
                                                        activeAlert = .slot(.event(ev))

                                                    } else if busyHour != nil {
                                                        activeAlert = .slot(.busyHours)

                                                    } else if isOffDay {
                                                        activeAlert = .slot(.offDay)
                                                    }
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
                        
                        if let error = validateBeforeSave() {

                            switch error {

                            case .overBookingDays,
                                 .overEventsPerDay:

                                if PremiumIntroGate.shouldShowToday() {
                                    PremiumIntroGate.markShown()
                                    showPremiumIntro = true
                                } else {
                                    activeAlert = .save(error)
                                }

                            default:
                                activeAlert = .save(error)
                            }

                            isSaving = false
                            return
                        }
                        
                        let start = combine(date: date, time: startTime)
                        let end   = combine(date: date, time: endTime)
                        
                        let success = eventManager.addEvent(
                            title: title,
                            ownerName: session.currentUserName,
                            date: date,
                            startTime: start,
                            endTime: end,
                            colorHex: selectedColor.toHex() ?? "#007AFF"
                        )
                        
                        if success {
                            dismiss()
                        } else {
                            activeAlert = nil
                            DispatchQueue.main.async {
                                activeAlert = .save(.cannotCreate)
                            }
                        }

                        
                        isSaving = false
                    }
                    .disabled(isSaving)   // ⭐ CỰC KỲ QUAN TRỌNG CHO APPLE
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cancel")) { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            // OFFDAY popup
            .alert(item: $activeAlert) { alert in
                buildAlert(alert)
            }
            .fullScreenCover(isPresented: $showPremiumIntro) {
                PremiumIntroView(isPresented: $showPremiumIntro) {
                    showUpgradeSheet = true
                }
            }
            .sheet(isPresented: $showUpgradeSheet) {
                PremiumUpgradeSheet(
                    preselectProductID: nil,
                    autoPurchase: false
                )
                .environmentObject(premium)
            }

            
        }
    }
    private func validateBeforeSave() -> SaveEventAlert? {

        let calendar = Calendar.current
        let now = Date()

        // 1️⃣ EMPTY TITLE
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyTitle
        }

        let start = combine(date: date, time: startTime)
        let end   = combine(date: date, time: endTime)

        // 2️⃣ PAST TIME
        if Calendar.current.isDateInToday(date) && start < now {
            return .pastTime
        }


        // 3️⃣ OFF DAY
        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
            return .offDay(date)
        }

        // 4️⃣ BUSY HOURS (manual)
        let busyHourConflict = busyHours.contains {
            $0.0 < end && $0.1 > start
        }
        if busyHourConflict {
            return .busyHours
        }

        // 5️⃣ EVENT CONFLICT
        let eventConflict = eventManager.events.contains {
            calendar.isDate($0.date, inSameDayAs: date) &&
            $0.startTime < end &&
            $0.endTime > start
        }
        if eventConflict {
            return .conflict
        }

        // 6️⃣ LIMIT DAYS AHEAD
        let limits = PremiumLimits.limits(for: premium.tier)
        if let maxDate = calendar.date(
            byAdding: .day,
            value: limits.maxBookingDaysAhead,
            to: now
        ), date > maxDate {
            return .overBookingDays(limits.maxBookingDaysAhead)
        }

        // 7️⃣ LIMIT EVENTS PER DAY
        let sameDayEvents = eventManager.events.filter {
            calendar.isDate($0.date, inSameDayAs: date)
        }
        if sameDayEvents.count >= limits.maxEventsPerDay {
            return .overEventsPerDay
        }

        return nil
    }
    
    private func buildAlert(_ alert: AddEventAlert) -> Alert {
        switch alert {

        case .save(let save):
            return buildSaveAlert(save)

        case .slot(let slot):
            return buildSlotAlert(slot)
        }
    }
    private func buildSaveAlert(_ alert: SaveEventAlert) -> Alert {
        switch alert {

        case .emptyTitle:
            return Alert(
                title: Text(String(localized: "missing_info")),
                message: Text(String(localized: "empty_title")),
                dismissButton: okDismiss
            )

        case .pastTime:
            return Alert(
                title: Text(String(localized: "invalid_time")),
                message: Text(String(localized: "cannot_book_in_past")),
                dismissButton: okDismiss
            )

        case .offDay(let date):
            return Alert(
                title: Text(String(localized: "cannot_book")),
                message: Text(
                    String(
                        format: String(localized: "off_day_full_message"),
                        formattedDate(date)
                    )
                ),
                dismissButton: okDismiss
            )

        case .busyHours:
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text(String(localized: "busy_hours")),
                dismissButton: okDismiss
            )

        case .conflict:
            return Alert(
                title: Text(String(localized: "time_conflict")),
                message: Text(String(localized: "event_conflict")),
                dismissButton: okDismiss
            )

        case .overBookingDays(let days):
            return Alert(
                title: Text(String(localized: "limit_reached")),
                message: Text(
                    String(
                        format: String(localized: "limit_days_format"),
                        days
                    )
                ),
                dismissButton: okDismiss
            )

        case .overEventsPerDay:
            return Alert(
                title: Text(String(localized: "limit_reached")),
                message: Text(String(localized: "event_limit_reached")),
                dismissButton: okDismiss
            )

        case .cannotCreate:
            return Alert(
                title: Text(String(localized: "error")),
                message: Text(String(localized: "cannot_create_event")),
                dismissButton: okDismiss
            )
        }
    }
    
    private func buildSlotAlert(_ alert: SlotInfoAlert) -> Alert {
        switch alert {

        case .event(let ev):
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text(
                    "\(ev.title)\n\(formattedTime(ev.startTime)) – \(formattedTime(ev.endTime))"
                ),
                dismissButton: okDismiss
            )

        case .busyHours:
            return Alert(
                title: Text(String(localized: "busy_time")),
                message: Text(String(localized: "busy_hours")),
                dismissButton: okDismiss
            )

        case .offDay:
            return Alert(
                title: Text(String(localized: "cannot_book")),
                message: Text(String(localized: "off_day")),
                dismissButton: okDismiss
            )
        }
    }

    private var okDismiss: Alert.Button {
        .default(Text(String(localized: "ok"))) {
            activeAlert = nil
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
