//
//  ScheduleSnapshot.swift
//  Easy Schedule — Shared (app + widget)
//
//  Bản chụp nhẹ của lịch người dùng, chia sẻ qua App Group cho Widget và
//  Live Activity. Cố tình tách rời khỏi `CalendarEvent` (model nặng của app)
//  để widget extension gọn nhẹ.
//
import SwiftUI

// MARK: - Item
struct ScheduleSnapshotItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var colorHex: String

    /// Màu SwiftUI suy ra từ `colorHex`.
    var color: Color { snapshotColor(from: colorHex) }
}

// MARK: - Snapshot
struct ScheduleSnapshot: Codable {
    var generatedAt: Date
    var items: [ScheduleSnapshotItem]

    init(generatedAt: Date = Date(), items: [ScheduleSnapshotItem]) {
        self.generatedAt = generatedAt
        self.items = items.sorted { $0.start < $1.start }
    }

    static let empty = ScheduleSnapshot(items: [])

    /// Việc đang diễn ra (start ≤ now < end), nếu có.
    func current(at now: Date = Date()) -> ScheduleSnapshotItem? {
        items.first { $0.start <= now && now < $0.end }
    }

    /// Việc sắp tới gần nhất chưa bắt đầu.
    func next(at now: Date = Date()) -> ScheduleSnapshotItem? {
        items.first { $0.start > now }
    }

    /// Các việc chưa kết thúc, giới hạn số lượng.
    func upcoming(at now: Date = Date(), limit: Int = 3) -> [ScheduleSnapshotItem] {
        Array(items.filter { $0.end > now }.prefix(limit))
    }

    /// Các mốc thời gian (start/end) trong tương lai — để widget hẹn refresh
    /// đúng lúc, "việc tiếp theo" luôn chính xác dù app không chạy.
    func refreshDates(after now: Date = Date()) -> [Date] {
        var dates = Set<Date>()
        for item in items {
            if item.start > now { dates.insert(item.start) }
            if item.end   > now { dates.insert(item.end) }
        }
        return dates.sorted()
    }
}

// MARK: - Hex → Color
// Internal (không phải file-private) để Live Activity dùng chung, nhưng tên
// khác `Color(hex:)` của app nên không xung đột khai báo.
func snapshotColor(from hex: String) -> Color {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&int)
    let r, g, b: UInt64
    switch cleaned.count {
    case 6: (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
    default: (r, g, b) = (0, 122, 255)   // #007AFF fallback
    }
    return Color(.sRGB,
                 red: Double(r) / 255,
                 green: Double(g) / 255,
                 blue: Double(b) / 255,
                 opacity: 1)
}
