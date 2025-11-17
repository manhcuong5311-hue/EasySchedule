//
//  ContentView.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
//
import SwiftUI
import Combine
import FirebaseCore
import FirebaseMessaging
import UserNotifications
// MARK: - Mô hình dữ liệu
struct CalendarEvent: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var owner: String
    var date: Date
    var startTime: Date
    var endTime: Date
    var colorHex: String = "#007AFF" // Mặc định màu xanh dương (giống accentColor)
}

final class EventManager: ObservableObject {
    
    @Published var events: [CalendarEvent] = [] {
        didSet {
            saveEvents()
            updateGroupedEvents()
        }
    }
    @Published var pastEvents: [CalendarEvent] = []
    @Published var groupedByDay: [Date: [CalendarEvent]] = [:] // ✅ thêm cache dùng cho cả 2 tab
    
    init() {
        loadEvents()
        cleanUpPastEvents()
        updateGroupedEvents()
    }
    
    
    // Lưu dữ liệu
    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: "savedEvents")
        }
    }
    
    // Tải lại dữ liệu
    private func loadEvents() {
        if let data = UserDefaults.standard.data(forKey: "savedEvents"),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.events = decoded
        }
    }
    
    // Tách sự kiện đã qua
    func cleanUpPastEvents() {
        let now = Date()
        let (past, upcoming) = events.partitioned { $0.endTime < now }
        pastEvents.append(contentsOf: past)
        events = upcoming
    }
    
    // ✅ Gom sẵn theo ngày — để CalendarView dùng
    func updateGroupedEvents() {
        groupedByDay = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
    
    // ✅ Lấy sự kiện trong 1 ngày (cho cả tab 1 và tab 2)
    func events(for date: Date) -> [CalendarEvent] {
        let day = Calendar.current.startOfDay(for: date)
        return groupedByDay[day]?.sorted(by: { $0.startTime < $1.startTime }) ?? []
    }
    
}
// MARK: - Giới hạn và xử lý logic sự kiện
extension EventManager {
    var isPremium: Bool {
        // TODO: sau này bạn gắn với StoreKit
        return UserDefaults.standard.bool(forKey: "isPremiumUser")
    }
    
    var allowDuplicateEvents: Bool {
        get { UserDefaults.standard.bool(forKey: "allowDuplicateEvents") }
        set { UserDefaults.standard.set(newValue, forKey: "allowDuplicateEvents") }
    }
    
    /// Thêm sự kiện có kiểm tra logic Premium, trùng, ngày, giới hạn số lượng
    func addEvent(title: String, owner: String, date: Date, startTime: Date, endTime: Date, colorHex: String = "007AFF") -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // 🔒 Giới hạn tổng số sự kiện khi chưa premium
        if !isPremium && events.count >= 10 {
            print("❌ Giới hạn: Chỉ được tạo tối đa 10 lịch khi chưa đăng ký Premium.")
            return false
        }
        
        // 🔒 Chỉ được tạo trong 3 ngày tới
        guard let threeDaysLater = calendar.date(byAdding: .day, value: 3, to: now),
              date <= threeDaysLater else {
            print("❌ Chỉ được tạo lịch trong 3 ngày tới.")
            return false
        }
        
        // 🔒 Tối đa 4 lịch trong 1 ngày
        let sameDayEvents = events.filter { calendar.isDate($0.date, inSameDayAs: date) }
        if sameDayEvents.count >= 4 {
            print("❌ Đã đạt giới hạn 4 lịch/ngày.")
            return false
        }
        
        // ⚙️ Cho phép trùng hay không
        if !allowDuplicateEvents {
            let hasOverlap = sameDayEvents.contains { existing in
                (startTime < existing.endTime && endTime > existing.startTime)
            }
            if hasOverlap {
                print("❌ Thời gian bị trùng với lịch khác.")
                return false
            }
        }
        
        // ✅ Hợp lệ → thêm
        let newEvent = CalendarEvent(title: title, owner: owner, date: date, startTime: startTime, endTime: endTime, colorHex: colorHex
        )
        events.append(newEvent)
        updateGroupedEvents()
        saveEvents()
        print("✅ Thêm sự kiện thành công.")
        return true
    }
    
    /// Xóa sự kiện
    func deleteEvent(_ event: CalendarEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events.remove(at: index)
            updateGroupedEvents()
            saveEvents()
        }
    }
    
    /// Cập nhật sự kiện (ví dụ sau khi chỉnh sửa)
    func updateEvent(_ event: CalendarEvent, newTitle: String, newOwner: String, newDate: Date, newStart: Date, newEnd: Date, newColorHex: String) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index].title = newTitle
            events[index].owner = newOwner
            events[index].date = newDate
            events[index].startTime = newStart
            events[index].endTime = newEnd
            events[index].colorHex = newColorHex
            updateGroupedEvents()
            saveEvents()
        }
    }
}

extension Array {
    func partitioned(by condition: (Element) -> Bool) -> (matches: [Element], nonMatches: [Element]) {
        var matches = [Element]()
        var nonMatches = [Element]()
        for element in self {
            if condition(element) { matches.append(element) } else { nonMatches.append(element) }
        }
        return (matches, nonMatches)
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var eventManager = EventManager()
    @StateObject private var languageManager = LanguageManager.shared // ✅ thêm dòng này
    @State private var showPastEvents = false
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    var body: some View {
        TabView {
            NavigationStack {
                EventListView(showPastEvents: $showPastEvents)
            }
            .tabItem {
                Label(NSLocalizedString(" Danh sách sự kiện", comment: ""), systemImage: "list.bullet.rectangle")
            }
            
            NavigationStack {
                CustomizableCalendarView()
            }
            .tabItem {
                Label(NSLocalizedString("Lịch của tôi ", comment: ""), systemImage: "calendar")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(NSLocalizedString("Cài đặt", comment: ""), systemImage: "gearshape")
            }
        }
        .environmentObject(eventManager)
        .environmentObject(languageManager) // ✅ thêm dòng này
        .onAppear {
            NotificationManager.shared.requestPermission()
        }
    }
}

private func rememberGroupedByMonth(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
        return Calendar.current.date(from: comps)!
    }
}

private func rememberGroupedByWeek(events: [CalendarEvent]) -> [Int: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        Calendar.current.component(.weekOfMonth, from: event.date)
    }
}

private func rememberGroupedByDay(events: [CalendarEvent]) -> [Date: [CalendarEvent]] {
    Dictionary(grouping: events) { event in
        Calendar.current.startOfDay(for: event.date)
    }
}


struct EventListView: View {
    @EnvironmentObject var eventManager: EventManager
    @Binding var showPastEvents: Bool
    
    @State private var selectedDate: Date? = nil  // dùng để mở chi tiết ngày
    @State private var searchText: String = ""    // dùng để tìm kiếm
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    
    var body: some View {
        VStack {
            // Nút chuyển giữa 2 chế độ
            Picker("", selection: $showPastEvents) {
                Text("Lịch hiện tại").tag(false)
                Text("Lịch đã qua").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Ô tìm kiếm chỉ hiện khi xem "lịch đã qua"
            if showPastEvents {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Tìm theo tên hoặc người tạo...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            if showPastEvents {
                pastEventsGroupedView
            } else {
                upcomingEventsList
            }
        }
        .navigationTitle(showPastEvents ? "Lịch đã qua" : "Lịch hiện tại")
        .onAppear {
            eventManager.cleanUpPastEvents()
        }
        // Sheet mở danh sách sự kiện trong ngày
        // Thay đoạn này:
        
        
        // ➜ Bằng đoạn này:
        .sheet(isPresented: Binding<Bool>(
            
            get: { selectedDate != nil },
            set: { if !$0 { selectedDate = nil } }
        )) {
            if let date = selectedDate {
                PastEventsByDateView(date: date)
                    .environmentObject(eventManager)
            }
        }
        .alert("Xoá sự kiện này?", isPresented: $showDeleteAlert) {
            Button("Xoá", role: .destructive) {
                if let event = eventToDelete {
                    eventManager.deleteEvent(event)
                }
                eventToDelete = nil
            }
            Button("Huỷ", role: .cancel) {
                eventToDelete = nil
            }
        } message: {
            Text("Bạn có chắc muốn xoá sự kiện “\(eventToDelete?.title ?? "")”?")
        }
    }
    private func formattedMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "MMMM yyyy" // ví dụ: "Tháng 11 2025"
        return f.string(from: date).capitalized
    }
    
    // MARK: - Lịch hiện tại
    // MARK: - Lịch hiện tại (gộp theo Tháng → Tuần → Ngày)
    // MARK: - Lịch hiện tại (TỐI ƯU HIỆU NĂNG)
    private var upcomingEventsList: some View {
        // ✅ 1. Tạo formatter dùng chung (không tạo mới mỗi lần)
        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateFormat = "MMMM yyyy"
            return f
        }()
        
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.dateStyle = .medium
            return f
        }()
        
        let timeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.timeStyle = .short
            return f
        }()
        
        // ✅ 2. Tính trước dữ liệu nhóm, tránh lặp trong body
        // Thực hiện 1 lần khi body chạy (SwiftUI sẽ diff tự động)
        let groupedByMonth = rememberGroupedByMonth(events: eventManager.events)
        let sortedMonths = groupedByMonth.keys.sorted()
        
        return List {
            if eventManager.events.isEmpty {
                Text("Chưa có lịch nào sắp tới.")
                    .foregroundColor(.secondary)
            } else {
                // ✅ 3. Vòng lặp hiển thị tháng
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    Section(header:
                                HStack {
                        Text(monthFormatter.string(from: monthDate).capitalized)
                            .font(.headline)
                        Spacer()
                        Text("\(monthEvents.count) lịch")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // ✅ 4. Gom theo tuần
                        let groupedByWeek = rememberGroupedByWeek(events: monthEvents)
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            Section(header:
                                        Text("Tuần \(week)")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                            ) {
                                // ✅ 5. Gom theo ngày
                                let groupedByDay = rememberGroupedByDay(events: weekEvents)
                                let sortedDays = groupedByDay.keys.sorted()
                                
                                ForEach(sortedDays, id: \.self) { day in
                                    let dayEvents = groupedByDay[day] ?? []
                                    Section(header:
                                                Text(dateFormatter.string(from: day))
                                        .fontWeight(.bold)
                                            
                                    ) {
                                        ForEach(dayEvents.sorted { $0.startTime < $1.startTime }) { event in
                                            HStack(alignment: .top, spacing: 8) {
                                                Circle()
                                                    .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                                                    .frame(width: 12, height: 12)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        Text(event.title)
                                                            .font(.headline)
                                                        Spacer()
                                                        Button {
                                                            showDeleteConfirmation(for: event)
                                                        } label: {
                                                            Image(systemName: "trash")
                                                                .foregroundColor(.red)
                                                                .padding(8)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                    Text(event.owner).font(.subheadline)
                                                    Text("\(timeFormatter.string(from: event.startTime)) - \(timeFormatter.string(from: event.endTime))")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }                                            .padding(.vertical, 4)
                                        }
                                        .onDelete(perform: deleteUpcomingEvent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        
    }
    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    
    // MARK: - Lịch đã qua (gộp theo ngày + tìm kiếm)
    // MARK: - Lịch đã qua (gộp theo tháng + tuần + tìm kiếm)
    private var pastEventsGroupedView: some View {
        // Lọc theo từ khóa tìm kiếm (title hoặc owner)
        let filteredEvents = eventManager.pastEvents.filter { event in
            searchText.isEmpty ||
            event.title.localizedCaseInsensitiveContains(searchText) ||
            event.owner.localizedCaseInsensitiveContains(searchText)
        }
        
        // Nhóm theo tháng (dựa trên năm + tháng)
        let groupedByMonth = Dictionary(grouping: filteredEvents) { event -> Date in
            let comps = Calendar.current.dateComponents([.year, .month], from: event.date)
            return Calendar.current.date(from: comps)!
        }
        // Sắp xếp tháng mới nhất lên trên
        let sortedMonths = groupedByMonth.keys.sorted(by: >)
        
        return List {
            if filteredEvents.isEmpty {
                Text(searchText.isEmpty ? "Chưa có lịch nào đã qua." : "Không tìm thấy kết quả phù hợp.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedMonths, id: \.self) { monthDate in
                    let monthEvents = groupedByMonth[monthDate] ?? []
                    
                    // Hiển thị tháng
                    Section(header:
                                HStack {
                        Text(formattedMonth(monthDate))
                            .font(.headline)
                        Spacer()
                        Text("\(monthEvents.count) lịch")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    ) {
                        // Nhóm trong tháng đó theo tuần
                        let groupedByWeek = Dictionary(grouping: monthEvents) { event -> Int in
                            Calendar.current.component(.weekOfMonth, from: event.date)
                        }
                        let sortedWeeks = groupedByWeek.keys.sorted()
                        
                        ForEach(sortedWeeks, id: \.self) { week in
                            let weekEvents = groupedByWeek[week] ?? []
                            
                            Button {
                                // Gộp tuần này để mở danh sách chi tiết
                                selectedDate = weekEvents.first?.date
                            } label: {
                                HStack {
                                    Text("Tuần \(week)")
                                        .font(.body)
                                    Spacer()
                                    Text("\(weekEvents.count) lịch")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    struct PastEventsByDateView: View {
        @EnvironmentObject var eventManager: EventManager
        let date: Date
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                List {
                    ForEach(eventsForDate) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.headline)
                            Text(event.owner).font(.subheadline)
                            Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .navigationTitle(formattedDate(date))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") { dismiss() }
                    }
                }
            }
        }
        
        private var eventsForDate: [CalendarEvent] {
            eventManager.pastEvents.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                .sorted { $0.startTime < $1.startTime }
        }
        
        private func formattedDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "'Ngày' d, 'tháng' M, yyyy"
            return formatter.string(from: date)
        }
        
        private func formattedTime(_ date: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "vi_VN")
            f.timeStyle = .short
            return f.string(from: date)
        }
    }
    // MARK: - Hàng hiển thị sự kiện
    private func eventRow(_ event: CalendarEvent) -> some View {
        VStack(alignment: .leading) {
            Text(event.title).font(.headline)
            Text("\(event.owner) • \(formattedDate(event.date))")
                .font(.subheadline)
            Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Xoá sự kiện hiện tại
    private func deleteUpcomingEvent(at offsets: IndexSet) {
        eventManager.events.remove(atOffsets: offsets)
    }
    
    // MARK: - Helper định dạng
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.timeStyle = .short
        return f.string(from: date)
    }
}



struct CustomizableCalendarView: View {
    @EnvironmentObject var eventManager: EventManager
    @State private var selectedDate: Date? = nil
    @State private var showAddSheet: Bool = false
    @State private var showDeleteAlert = false
    @State private var eventToDelete: CalendarEvent? = nil
    @State private var showShareSheet = false
    @State private var shareLink: URL? = nil
    
    // ✅ thêm biến quản lý ngày nghỉ
    @State private var offDays: Set<Date> = []
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // 2 = Monday bắt đầu tuần
        return cal
    }
    
    private func showDeleteConfirmation(for event: CalendarEvent) {
        eventToDelete = event
        showDeleteAlert = true
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // MARK: - Calendar grid
        CalendarGridView(
        selectedDate: $selectedDate,
        eventsByDay: eventManager.groupedByDay,
        offDays: offDays
    )
        .padding(.top, 8)
                
        // MARK: - Toggle cho phép trùng lịch
    Toggle("Cho phép trùng lịch", isOn: Binding(
        get: { eventManager.allowDuplicateEvents },
        set: { eventManager.allowDuplicateEvents = $0 }
    ))
        .padding(.horizontal)
        .padding(.bottom, 4)
                
        Divider()
                
                // MARK: - Nút chia sẻ
    Button {
        generateShareLink()
        showShareSheet = true
            } label: {
                HStack {
            Image(systemName: "square.and.arrow.up")
                Text("Chia sẻ lịch")
                    .bold()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.blue.opacity(0.2))
        .cornerRadius(10)
    }
        .padding(.horizontal)
        .sheet(isPresented: $showShareSheet) {
        if let link = shareLink {
        ActivityView(activityItems: [link])
    }
}
        // MARK: - Ngày được chọn
        if let date = selectedDate {
            VStack(spacing: 10) {
                        // ✅ Nút đặt / huỷ ngày nghỉ
                Button {
                    toggleOffDay(for: date)
                } label: {
            HStack {
                Image(systemName: isOffDay(date) ? "xmark.circle" :"bed.double.fill")
                Text(isOffDay(date) ? "Mở lại ngày này" : "Đặt ngày nghỉ")
                    .bold()
    }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isOffDay(date) ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(10)
    }
                .padding(.horizontal)
                        
                if isOffDay(date) {
                Text("Ngày này đang được đặt là *ngày nghỉ*.")
                    .foregroundColor(.red)
                    .font(.subheadline)
                    } else if eventManager.events(for: date).isEmpty {
                        Text("Không có sự kiện nào trong ngày này.")
                        .foregroundColor(.secondary)
                        .padding(.vertical, 12)
                        } else {
                List {
                    ForEach(eventManager.events(for: date)) { event in
                    HStack(alignment: .top, spacing: 8) {
                        // Circle màu sự kiện
                        Circle()
                            .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                                .frame(width: 12, height: 12)
                                        
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                                Text(event.title)
                                .font(.headline)
                        Spacer()
                    Button {
                            showDeleteConfirmation(for: event)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .padding(8)
      }                                .buttonStyle(.plain)
    }
                Text(event.owner).font(.subheadline)
                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                       .foregroundColor(.secondary)
    }
}
                        .padding(.vertical, 4)
}
                        .onDelete { indexSet in
                    for index in indexSet {
                 let event = eventManager.events(for: date)[index]
                                        eventManager.deleteEvent(event)
        }
    }
}
                .listStyle(.inset)
                .frame(maxHeight: 300)
        }
    }
        } else {
            Text("Chọn một ngày để xem sự kiện.")
                .foregroundColor(.secondary)
                .padding(.vertical, 12)
            }
            }
            .navigationTitle("Lịch của tôi")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Thêm lịch")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddEventView(prefillDate: selectedDate, offDays: offDays)
                    .environmentObject(eventManager)
            }
            .alert("Xoá sự kiện này?", isPresented: $showDeleteAlert) {
                Button("Xoá", role: .destructive) {
                    if let event = eventToDelete {
                        eventManager.deleteEvent(event)
                    }
                    eventToDelete = nil
                }
                Button("Huỷ", role: .cancel) {
                    eventToDelete = nil
                }
            } message: {
                Text("Bạn có chắc muốn xoá sự kiện “\(eventToDelete?.title ?? "")”?")
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Toggle ngày nghỉ
    private func toggleOffDay(for date: Date) {
        let key = calendar.startOfDay(for: date)
        if offDays.contains(key) {
            offDays.remove(key)
        } else {
            offDays.insert(key)
        }
    }
    
    private func isOffDay(_ date: Date) -> Bool {
        offDays.contains(calendar.startOfDay(for: date))
    }
    
    // MARK: - Share link tạm
    private func generateShareLink() {
        shareLink = URL(string: "https://example.com/share-calendar")
    }
    
    // MARK: - Format giờ
    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.timeStyle = .short
        return f.string(from: date)
    }
}


struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}


struct AddEventView: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColor: Color = .blue // ✅ màu mặc định
    // Pre-fill date if user selected a date in calendar
    let prefillDate: Date?
    let offDays: Set<Date>        // ✅ THÊM MỚI — danh sách ngày nghỉ truyền từ ngoài vào
    @State private var selectedDate: Date = Date()
    @State private var selectedSlot: TimeSlot?
    
    @State private var title: String = ""
    @State private var owner: String = ""
    @State private var date: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endTime: Date = Date().addingTimeInterval(1800) // default +1h
    
    // ✅ THÊM MỚI — biến trạng thái popup
    @State private var showOffDayAlert = false
    @State private var offDayMessage = ""
    
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thông tin")) {
                    TextField("Tiêu đề", text: $title)
                    TextField("Người tạo", text: $owner)
                }
                Section(header: Text("Ngày & giờ")) {
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    NavigationLink {
                        TimeSlotPickerGridView(selectedDate: selectedDate) { slot in
                            selectedSlot = slot
                            startTime = slot.startTime   // ✅ cập nhật DatePicker
                            endTime = slot.endTime
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Chọn khung giờ")
                                    .font(.headline)
                                if let slot = selectedSlot {
                                    Text("\(slot.startTime.formatted(date: .omitted, time: .shortened)) - \(slot.endTime.formatted(date: .omitted, time: .shortened))")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Chưa chọn")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    DatePicker("Bắt đầu", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Kết thúc", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section(header: Text("Màu sự kiện")) {
                    ColorPicker("Chọn màu", selection: $selectedColor, supportsOpacity: false)
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
            .navigationTitle("Thêm lịch")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        // ✅ THÊM MỚI: kiểm tra ngày nghỉ trước khi lưu
                        let calendar = Calendar.current
                        if offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) }) {
                            offDayMessage = " \(formattedDate(date)) là ngày nghỉ, bạn không thể đặt lịch vào ngày này."
                            showOffDayAlert = true
                            return
                        }
                        
                        // Basic validation
                        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        // ensure start <= end (if not, swap)
                        var s = combine(date: date, time: startTime)
                        var e = combine(date: date, time: endTime)
                        if e < s { swap(&s, &e) }
                        
                        let safeOwner = owner.isEmpty ? "Bạn" : owner
                        
                        _ = eventManager.addEvent(
                            title: title,
                            owner: safeOwner,
                            date: date,
                            startTime: s,
                            endTime: e,
                            colorHex: selectedColor.toHex() ?? "#FFFFFF" // ví dụ giá trị mặc định
                        )
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            // ✅ THÊM MỚI — popup cảnh báo
            .alert("Không thể đặt lịch", isPresented: $showOffDayAlert) {
                Button("Đóng", role: .cancel) { }
            } message: {
                Text(offDayMessage)
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
    
    // ✅ THÊM MỚI — định dạng ngày hiển thị trong popup
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
    }
    
}



struct CalendarGridView: View {
    @Binding var selectedDate: Date?
    let eventsByDay: [Date: [CalendarEvent]]
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    let offDays: Set<Date>
    
    // Alert trạng thái chung, riêng cho CalendarGridView
    @State private var showOffDayAlert = false
    
    var body: some View {
        VStack(spacing: 8) {
            // MARK: - Header tháng
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(formattedMonth(currentMonth))
                    .font(.headline)
                Spacer()
                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)
            
            // MARK: - Tên thứ trong tuần
            HStack {
                let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols[1...6]) + [calendar.veryShortStandaloneWeekdaySymbols[0]]
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.secondary)
                }
            }
            
            // MARK: - Lưới ngày
            LazyVGrid(columns: columns, spacing: 12) {
                let allDays = daysInMonth(for: currentMonth)
                    .map { calendar.startOfDay(for: $0) }

                if let firstDay = allDays.first {
                    let weekday = calendar.component(.weekday, from: firstDay)
                    let emptySlots = weekday - calendar.firstWeekday
                    if emptySlots > 0 {
                        ForEach(0..<emptySlots, id: \.self) { idx in
                            Text("")
                                .id("empty_\(currentMonth)_\(idx)") // ép ID duy nhất
                        }
                    }
                }
                
                // Hiển thị các ngày trong tháng
                ForEach(allDays.indices, id: \.self) { index in
                    let date = allDays[index]

                    let day = calendar.component(.day, from: date)
                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                    let isToday = calendar.isDateInToday(date)
                    let isOffDay = offDays.contains(where: { calendar.isDate($0, inSameDayAs: date) })

                    VStack(spacing: 4) {
                        Text("\(day)")
                            .font(.body)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(
                                    isSelected ? Color.accentColor :
                                        (isOffDay ? Color.gray.opacity(0.4) :
                                            (isToday ? Color.green.opacity(0.3) : Color.clear)
                                        )
                                )
                            )
                            .foregroundColor(isSelected ? .white : .primary)

                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundColor(
                                (eventsByDay[calendar.startOfDay(for: date)]?.isEmpty == false)
                                ? Color(hex: eventsByDay[calendar.startOfDay(for: date)]!.first!.colorHex)
                                : .clear
                            )

                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOffDay {
                            showOffDayAlert = true
                        } else {
                            selectedDate = date
                        }
                    }
                }

            }
            .padding(.horizontal)
        }
        // ✅ Alert riêng cho CalendarGridView (ngày nghỉ)
        .alert("Không thể đặt lịch", isPresented: $showOffDayAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Ngày này là ngày nghỉ, bạn không thể đặt lịch vào ngày này.")
        }
    }
    
    // MARK: - Month navigation
    @State private var currentMonth: Date = Date()
    private func changeMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    // MARK: - Ngày trong tháng
    private func daysInMonth(for date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: [Date] = []
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }
    
    // MARK: - Định dạng tháng
    private func formattedMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
    }
}


struct DayEventsSheetView: View {
    @EnvironmentObject var eventManager: EventManager
    let date: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(eventManager.events(for: date)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.headline)
                    Text(event.owner).font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Ngày \(formattedDate(date))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateStyle = .medium
        return f.string(from: date)
    }
}


struct AddOrEditEventView: View {
    enum Mode {
        case add
        case edit(CalendarEvent)
    }
    
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showLimitAlert = false
    @AppStorage("isPremiumUser") private var isPremiumUser: Bool = false
    
    private func showAlertLimit(title: String, message: String) {
        alertMessage = message
        showLimitAlert = true
    }
    
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var selectedDate: Date
    var allowOverlap: Bool
    @Binding var existingEvents: [CalendarEvent]
    
    @State private var title = ""
    @State private var owner = ""
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(3600)
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @State private var activeAlert: AlertMessage? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin sự kiện") {
                    TextField("Tên sự kiện", text: $title)
                    TextField("Người tạo / tham gia", text: $owner)
                    DatePicker("Ngày", selection: $date, displayedComponents: .date)
                    DatePicker("Giờ bắt đầu", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Giờ kết thúc", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                
                if case .edit(let event) = mode {
                    Section {
                        Button(role: .destructive) {
                            deleteEvent(event)
                        } label: {
                            Label("Xoá lịch này", systemImage: "trash")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Lưu") { handleSave() }
                }
            }
            // ✅ Alert chung cho mọi lỗi
            .alert(alertMessage, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            }
            // ✅ Alert giới hạn premium
            .alert(alertMessage, isPresented: $showLimitAlert) {
                Button("OK", role: .cancel) {}
            }
            .onAppear {
                // Khởi tạo form
                date = selectedDate
                if case .edit(let event) = mode {
                    title = event.title
                    owner = event.owner
                    date = event.date
                    startTime = event.startTime
                    endTime = event.endTime
                } else {
                    let now = Date()
                    if Calendar.current.isDate(selectedDate, inSameDayAs: now) {
                        startTime = now
                    } else {
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
                        comps.hour = 9
                        comps.minute = 0
                        startTime = Calendar.current.date(from: comps) ?? now
                    }
                    endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime.addingTimeInterval(3600)
                }
            }
            .alert(item: $activeAlert) { alert in
                Alert(title: Text(alert.title),
                      message: Text(alert.message),
                      dismissButton: .default(Text("OK")))
            }

        }
    }
    
    // Merge date + time
    private func combine(date day: Date, time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute, .second], from: time)
        var comps = DateComponents()
        comps.year = d.year; comps.month = d.month; comps.day = d.day
        comps.hour = t.hour ?? 0; comps.minute = t.minute ?? 0; comps.second = t.second ?? 0
        return cal.date(from: comps) ?? day
    }
    
    private func handleSave() {
        let startDT = combine(date: date, time: startTime)
        let endDT = combine(date: date, time: endTime)
        let now = Date()
        
      
        // 2️⃣ Tạo sự kiện mới
        let newEvent = CalendarEvent(
            title: title,
            owner: owner,
            date: Calendar.current.startOfDay(for: date),
            startTime: startDT,
            endTime: endDT
        )
        
        let calendar = Calendar.current
        
        // 3️⃣ Kiểm tra giới hạn user chưa premium
        // Kiểm tra trùng slot
        if !allowOverlap {
            let overlap = existingEvents.contains { ev in
                calendar.isDate(ev.date, inSameDayAs: newEvent.date) &&
                ((startDT >= ev.startTime && startDT < ev.endTime) ||
                 (endDT > ev.startTime && endDT <= ev.endTime) ||
                 (startDT <= ev.startTime && endDT >= ev.endTime))
            }
            if overlap {
                activeAlert = AlertMessage(title: "Trùng lịch", message: "Khung giờ này đã có lịch khác.")
                return
            }
        }

        // Kiểm tra giới hạn Premium
        if !isPremiumUser {
            if let maxDate = calendar.date(byAdding: .day, value: 3, to: now),
               newEvent.date > maxDate {
                activeAlert = AlertMessage(title: "Vượt giới hạn ngày", message: "Chỉ được thêm lịch trong 3 ngày tới.")
                return
            }

            let sameDayEvents = existingEvents.filter {
                calendar.isDate($0.date, inSameDayAs: newEvent.date)
            }
            if sameDayEvents.count >= 4 {
                activeAlert = AlertMessage(title: "Vượt giới hạn", message: "Chỉ được thêm tối đa 4 lịch/ngày.")
                return
            }
        }

        
        // 5️⃣ Lưu sự kiện
        switch mode {
        case .add:
            existingEvents.append(newEvent)
        case .edit(let old):
            if let idx = existingEvents.firstIndex(where: { $0.id == old.id }) {
                existingEvents[idx] = newEvent
            }
        }
        
        // 6️⃣ Gửi thông báo nếu bật
        if NotificationManager.shared.notificationsEnabled {
            NotificationManager.shared.scheduleNotification(
                title: "📅 \(title)",
                message: "Sắp đến giờ cho lịch: \(title) của \(owner)",
                date: startDT
            )
        }
        
        DispatchQueue.main.async { dismiss() }
    }
    
    private func deleteEvent(_ event: CalendarEvent) {
        existingEvents.removeAll { $0.id == event.id }
        DispatchQueue.main.async { dismiss() }
    }
    
}
