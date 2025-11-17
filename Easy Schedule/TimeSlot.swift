//
//  TIMESLOT.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
//

import Foundation
import Combine
struct TimeSlot: Identifiable, Hashable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
}

import Foundation

final class TimeSlotManager: ObservableObject {
    @Published var slots: [TimeSlot] = []
    
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
            current = next.addingTimeInterval(Double(bufferMinutes * 60)) // buffer sau mỗi slot
        }
        
        self.slots = result
    }
}

import SwiftUI

struct TimeSlotPickerGridView: View {
    @StateObject private var manager = TimeSlotManager()
    @Environment(\.dismiss) private var dismiss
    
    let selectedDate: Date
    var onSelect: (TimeSlot) -> Void
    
    @State private var selectedSlot: TimeSlot?
    
    // ✅ Cấu hình lưới: 3 cột (có thể chỉnh 2 hoặc 4 tuỳ ý)
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(manager.slots) { slot in
                    Button {
                        selectedSlot = slot
                    } label: {
                        VStack {
                            Text(slot.startTime.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                            Text(slot.endTime.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedSlot == slot ? Color.blue.opacity(0.2) : Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedSlot == slot ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                    }
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
            manager.generateSlots(for: selectedDate,
                                  startHour: 8,
                                  endHour: 20,
                                  durationMinutes: 30,
                                  bufferMinutes: 5)
        }
    }
}
