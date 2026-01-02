//
//  SlotRowPro.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import Foundation

// NOTE: dùng tên ProSlot để tránh trùng với TimeSlot
struct ProSlot: Hashable {
    let start: Date
    let end: Date
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
                Text(String(localized: "busy")).font(.caption).foregroundColor(.red)
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
        d.formatted(date: .omitted, time: .shortened)
    }

}
