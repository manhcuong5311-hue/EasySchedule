import Foundation

struct TimeSlot: Identifiable, Hashable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    
    /// Slot đã qua thời điểm hiện tại?
    var isPast: Bool {
        endTime < Date()
    }
    
    /// Ghép string cho UI hiển thị nhanh
    var label: String {
        "\(startTime.formatted(date: .omitted, time: .shortened)) - \(endTime.formatted(date: .omitted, time: .shortened))"
    }
}

import Foundation
import Combine

final class TimeSlotManager: ObservableObject {
    @Published var slots: [TimeSlot] = []
    
    /// Những slot đã được đặt (dùng để disable)
    @Published var bookedSlots: [TimeSlot] = []
    
    /// Tạo danh sách slot trong ngày
    func generateSlots(for date: Date,
                       startHour: Int = 9,
                       endHour: Int = 17,
                       durationMinutes: Int = 30,
                       bufferMinutes: Int = 0) {
        
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date)!
        let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date)!
        
        var result: [TimeSlot] = []
        var current = start
        
        while current.addingTimeInterval(Double(durationMinutes * 60)) <= end {
            let next = current.addingTimeInterval(Double(durationMinutes * 60))
            result.append(TimeSlot(startTime: current, endTime: next))
            current = next.addingTimeInterval(Double(bufferMinutes * 60))
        }
        
        self.slots = result
    }
    
    /// Kiểm tra slot đã được đặt chưa
    func isBooked(_ slot: TimeSlot) -> Bool {
        bookedSlots.contains { $0.startTime == slot.startTime }
    }
}

import SwiftUI

struct TimeSlotPickerGridView: View {
    @StateObject private var manager = TimeSlotManager()
    @Environment(\.dismiss) private var dismiss
    
    let selectedDate: Date
    var booked: [TimeSlot] = []       // slot đã đặt (từ Firebase)
    var onSelect: (TimeSlot) -> Void  // trả slot
    
    @State private var selectedSlot: TimeSlot?
    
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(manager.slots) { slot in
                    
                    let isBooked = manager.isBooked(slot)
                    let isPast = slot.isPast
                    
                    Button {
                        if !isBooked && !isPast {
                            selectedSlot = slot
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(slot.startTime.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                            Text(slot.endTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 55)
                        .padding(6)
                        .background(backgroundColor(slot: slot, isBooked: isBooked, isPast: isPast))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(borderColor(slot: slot, isBooked: isBooked, isPast: isPast), lineWidth: 2)
                        )
                    }
                    .disabled(isBooked || isPast)
                }
            }
            .padding()
        }
        .navigationTitle("Chọn khung giờ")
        .toolbar {
            Button("Xong") {
                if let slot = selectedSlot {
                    onSelect(slot)
                }
                dismiss()
            }
            .disabled(selectedSlot == nil)
        }
        .onAppear {
            manager.bookedSlots = booked
            manager.generateSlots(
                for: selectedDate,
                startHour: 5,
                endHour: 23,
                durationMinutes: 55,
                bufferMinutes: 5
            )
        }
    }
    
    // MARK: - UI Helpers
    
    private func backgroundColor(slot: TimeSlot, isBooked: Bool, isPast: Bool) -> Color {
        if isBooked { return Color.red.opacity(0.2) }
        if isPast { return Color.gray.opacity(0.2) }
        if selectedSlot == slot { return Color.blue.opacity(0.2) }
        return Color(.systemGray6)
    }
    
    private func borderColor(slot: TimeSlot, isBooked: Bool, isPast: Bool) -> Color {
        if isBooked { return Color.red }
        if isPast { return Color.gray }
        return selectedSlot == slot ? .blue : Color.gray.opacity(0.3)
    }
}
