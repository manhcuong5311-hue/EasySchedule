import Foundation
import Combine

/// Local-only store that maps event ID → user-ticked completion.
/// Stored in UserDefaults — never uploaded to Firestore.
final class EventCompletionStore: ObservableObject {

    static let shared = EventCompletionStore()
    private let key = "easy_schedule_event_completion_v1"

    /// Set of event IDs the user has manually ticked as done.
    @Published private(set) var completedIds: Set<String>

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        completedIds = Set(saved)
    }

    func isCompleted(_ eventId: String) -> Bool {
        completedIds.contains(eventId)
    }

    func toggle(_ eventId: String) {
        if completedIds.contains(eventId) {
            completedIds.remove(eventId)
        } else {
            completedIds.insert(eventId)
        }
        persist()
    }

    /// Call when an event is permanently deleted so we don't leak orphan entries.
    func remove(_ eventId: String) {
        guard completedIds.contains(eventId) else { return }
        completedIds.remove(eventId)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(completedIds), forKey: key)
    }
}
