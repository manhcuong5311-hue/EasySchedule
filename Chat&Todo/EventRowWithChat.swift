//
//  EventRowWithChat.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit


struct EventRowWithChat: View {
    let event: CalendarEvent
    let timeFontSize: Int
    let timeColorHex: String
    let showOwnerLabel: Bool

    @EnvironmentObject var eventManager: EventManager
    
    // ⭐ giữ VM optional
    @State private var metaVM: ChatMetaViewModel? = nil

    // ⭐ computed → luôn trả về instance hợp lệ
    private var chatMeta: ChatMetaViewModel {
        metaVM!
    }


    // ❗ init KHÔNG được động chạm vào environmentObject
    init(event: CalendarEvent,
         timeFontSize: Int = 14,
         timeColorHex: String = "#333333",
         showOwnerLabel: Bool = true)
    {
        self.event = event
        self.timeFontSize = timeFontSize
        self.timeColorHex = timeColorHex
        self.showOwnerLabel = showOwnerLabel
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {

            Circle()
                .fill(Color(hex: event.colorHex.isEmpty ? "#FF0000" : event.colorHex))
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {

                Text(event.title).font(.headline)

                if showOwnerLabel {
                    Text(originLabel(for: event))
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                if showOwnerLabel {
                    if event.origin == .iCreatedForOther {
                        HStack(spacing: 4) {
                            UserNameView(uid: event.createdBy)
                            Text("→")
                            UserNameView(uid: event.owner)
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    } else {
                        Text(displayName(for: event,
                                         uid: event.createdBy,
                                         eventManager: eventManager))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(formattedTime(event.startTime)) - \(formattedTime(event.endTime))")
                    .font(.system(size: CGFloat(timeFontSize), weight: .regular))
                    .foregroundColor(Color(hex: timeColorHex))

                // ⭐ Chat preview
                HStack(spacing: 6) {

                    if !chatMeta.lastMessage.isEmpty {
                        Text(chatMeta.lastMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    if chatMeta.unread {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onAppear {
            if metaVM == nil {
                metaVM = eventManager.chatMeta(for: event.id)
            }
        

        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    
    private func originLabel(for ev: CalendarEvent) -> String {
        let ownerPrefix = String(localized: "owner_prefix")
        return "\(ownerPrefix) \(ev.owner)"
    }
}

