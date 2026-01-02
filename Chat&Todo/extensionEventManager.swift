//
//  extensionEventManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI
import FirebaseFirestore

extension EventManager {
    
    func cleanChatIfEventIsPast(_ event: CalendarEvent) {
        if event.endTime > Date() { return }

        Firestore.firestore()
            .collection("chats")
            .document(event.id)
            .updateData([
                "expired": true
            ])
    }

}

