//
//  ChatButtonWithBadge.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//

import SwiftUI



struct ChatButtonWithBadge: View {
    let event: CalendarEvent
    let otherUserId: String
   
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var eventManager: EventManager

    @State private var metaVM: ChatMetaViewModel?
    @State private var didBindMeta = false

    private var resolvedOtherName: String {
        event.participantNames?[otherUserId]
        ?? String(localized: "generic_user")
    }
          
    
    var body: some View {
        ZStack(alignment: .topTrailing) {

            NavigationLink {
                ChatView(
                    eventId: event.id,
                    otherUserId: otherUserId,
                    otherName: resolvedOtherName,
                    eventEndTime: event.endTime,
                    eventInfo: event,
                    myId: session.currentUserId!,
                    myName: session.currentUserName
                )
            } label: {
                Image(systemName: "bubble.right.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundColor((metaVM?.unread ?? false) ? .red : .blue)
                    .font(.system(size: 20))
            }

            if metaVM?.unread == true {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .offset(x: 6, y: -4)
            }
        }
        .onAppear {
            guard !didBindMeta else { return }
            didBindMeta = true
            metaVM = eventManager.chatMeta(for: event.id)
        }
    }
}


