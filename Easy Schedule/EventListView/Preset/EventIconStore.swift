import Foundation

// Local-only store: maps event ID → SF Symbol name.
// Stored in UserDefaults — never uploaded to Firestore.
final class EventIconStore {
    static let shared = EventIconStore()
    private let key = "easy_schedule_event_icons"
    private var cache: [String: String]

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func setIcon(_ symbol: String, for eventId: String) {
        guard !symbol.isEmpty else { return }
        cache[eventId] = symbol
        UserDefaults.standard.set(cache, forKey: key)
    }

    func icon(for eventId: String) -> String? {
        cache[eventId]
    }

    func clearIcon(for eventId: String) {
        cache.removeValue(forKey: eventId)
        UserDefaults.standard.set(cache, forKey: key)
    }
}
