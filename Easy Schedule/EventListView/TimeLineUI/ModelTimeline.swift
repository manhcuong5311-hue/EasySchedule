//
//  Model.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//

import CoreFoundation
import CoreGraphics

import SwiftUI

enum TimelineLayout {

    // MARK: - Time scale
    /// Chiều cao mỗi giờ trên timeline
    static let hourHeight: CGFloat = 64

    /// Chiều cao mỗi phút (derived)
    static let minuteHeight: CGFloat = hourHeight / 60


    // MARK: - Hour column (bên trái)
    /// Độ rộng cột hiển thị giờ (17:00, 18:00…)
    static let hourLabelWidth: CGFloat = 48


    // MARK: - Event dot
    /// Kích thước dot thời gian
    static let dotSize: CGFloat = 6

    /// Độ rộng cột dành RIÊNG cho dot
    /// Phải > dotSize để dot không bao giờ chạm card
    static let dotColumnWidth: CGFloat = 18


    // MARK: - Event card
    /// Bo góc card event
    static let blockCornerRadius: CGFloat = 12

    /// Khoảng cách từ dot column sang card
    static let contentPadding: CGFloat = 0


    // =====================================================
    // MARK: - Busy Slot (NEW)
    // =====================================================

    /// Khoảng dịch ngang của BUSY card so với event card
    /// → đảm bảo không bao giờ đè event
    static let busyCardOffsetX: CGFloat = 140

    /// Bo góc card busy (nhẹ hơn event)
    static let busyCornerRadius: CGFloat = 10

    /// Opacity nền busy slot (nhạt – không gây nhiễu)
    static let busyBackgroundOpacity: CGFloat = 0.18

    /// Opacity viền / accent busy slot
    static let busyAccentOpacity: CGFloat = 0.35
}

struct MergedBusySlot: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    
    
    
}
extension EventTimeDisplayMode {

    func primaryText(from start: Date, to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
