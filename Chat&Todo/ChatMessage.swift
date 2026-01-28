
import SwiftUI
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import MapKit

struct ChatMessage: Identifiable, Codable {

    var id: String                 // ID dùng cho SwiftUI
    let clientId: String           // Local ID (offline)

    var text: String
    var senderId: String
    var senderName: String?
    var timestamp: Date
    var seenBy: [String: Bool]?
    var latitude: Double?
    var longitude: Double?
    var sendStatus: MessageSendStatus = .sent

    // SwiftUI luôn dùng id này
    var uiId: String { id }

    init(
        id: String? = nil,
        clientId: String = UUID().uuidString,
        text: String,
        senderId: String,
        senderName: String?,
        timestamp: Date = Date(),
        seenBy: [String: Bool] = [:],
        latitude: Double? = nil,
        longitude: Double? = nil,
        sendStatus: MessageSendStatus = .sent
    ) {
        let resolvedId = id ?? clientId   // ⭐ QUYẾT ĐỊNH
        self.id = resolvedId
        self.clientId = clientId
        self.text = text
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = timestamp
        self.seenBy = seenBy
        self.latitude = latitude
        self.longitude = longitude
        self.sendStatus = sendStatus
    }
}




class ChatForegroundTracker {
    static let shared = ChatForegroundTracker()
    private init() {}

    // eventId đang mở chat
    var activeChatEventId: String? = nil
}



