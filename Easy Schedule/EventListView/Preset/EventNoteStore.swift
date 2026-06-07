import Foundation

// Local-only store: maps event ID → free-text note.
// Stored in UserDefaults — never uploaded to Firestore (personal quick note).
final class EventNoteStore {
    static let shared = EventNoteStore()
    private let key = "easy_schedule_event_notes"
    private var cache: [String: String]

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func note(for eventId: String) -> String {
        cache[eventId] ?? ""
    }

    func setNote(_ note: String, for eventId: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cache.removeValue(forKey: eventId)
        } else {
            cache[eventId] = note
        }
        UserDefaults.standard.set(cache, forKey: key)
    }
}
