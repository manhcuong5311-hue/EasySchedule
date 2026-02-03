//
//  DáEventsSheetView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 31/1/26.
//

import SwiftUI
import Combine


struct DayEventsSheetView: View {
    @EnvironmentObject var eventManager: EventManager
    let date: Date
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(eventManager.events(for: date)) { event in
                VStack(alignment: .leading, spacing: 4) {
                    
                    // ⭐ Tiêu đề sự kiện
                    Text(event.title)
                        .font(.headline)
                    
                    // ⭐ Thêm hiển thị tên người tạo / người được tạo
                    if event.origin == .iCreatedForOther {
                        // A tạo cho B
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)   // A
                            Text(String(localized: "arrow_right"))
                            UserNameView(uid: event.owner)       // B
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                    } else {
                        // Tự tạo hoặc người khác tạo cho tôi
                        Text(displayName(for: event, uid: event.createdBy, eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // ⭐ Thời gian sự kiện
                    Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(String(localized: "day_prefix")) \(formattedDate(date))")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "close")) { dismiss() }
                }
            }
        }
    }
    
    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }


    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

}

