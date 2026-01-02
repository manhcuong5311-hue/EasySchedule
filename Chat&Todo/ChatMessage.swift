
import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit

struct ChatMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var text: String = ""
    var senderId: String
    var senderName: String
    var timestamp: Date
    var seenBy: [String: Bool]?
    var latitude: Double?
    var longitude: Double?
    
    init(
        id: String? = nil,
        text: String,
        senderId: String,
        senderName: String,
        timestamp: Date = Date(),
        seenBy: [String: Bool] = [:],
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = timestamp
        self.seenBy = seenBy
        self.latitude = latitude
        self.longitude = longitude
    }
    
}

class ChatForegroundTracker {
    static let shared = ChatForegroundTracker()
    private init() {}

    // eventId đang mở chat
    var activeChatEventId: String? = nil
}



