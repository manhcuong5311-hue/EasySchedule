//
//  Model.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 21/11/25.
//

import Foundation

import FirebaseFirestore
import Combine

struct EventModel: Identifiable, Codable {
    @DocumentID var id: String? = UUID().uuidString
    var title: String
    var owner: String?
    var startTime: Date
    var endTime: Date
    var colorHex: String?

    // For decoding generic JSON that may have timestamp strings or nested formats
    init(id: String? = nil, title: String, owner: String? = nil, startTime: Date, endTime: Date, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.owner = owner
        self.startTime = startTime
        self.endTime = endTime
        self.colorHex = colorHex
    }

    // Create from Firestore document data
    static func fromFirestoreData(_ data: [String: Any]) -> EventModel? {
        guard let title = (data["title"] as? String) ?? (data["name"] as? String) else { return nil }
 

        // parse startTime / endTime flexibly
        func parseDate(_ any: Any?) -> Date? {
            if let ts = any as? Timestamp {
                return ts.dateValue()
            }
            if let s = any as? String {
                // try ISO first
                let isoFormatter = ISO8601DateFormatter()
                if let d = isoFormatter.date(from: s) { return d }
                // fallback to DateFormatter common formats
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let d = df.date(from: s) { return d }
                // last resort parse using Date initializer
                return Date(timeIntervalSince1970: TimeInterval(s) ?? 0)
            }
            if let d = any as? Date { return d }
            return nil
        }

        guard let start = parseDate(data["startTime"] ?? data["datetime"] ?? data["date"]),
              let end = parseDate(data["endTime"] ?? data["end"]) else {
            return nil
        }

        let owner = data["owner"] as? String
        let color = data["colorHex"] as? String

        return EventModel(id: data["id"] as? String, title: title, owner: owner, startTime: start, endTime: end, colorHex: color)
    }
}

struct Partner: Identifiable, Codable {
    var id: String
    var name: String
    var sourceURL: String? = nil
    var events: [EventModel] = []
}
