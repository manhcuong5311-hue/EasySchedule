//
//  EventSeenStore.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//

import Foundation

final class EventSeenStore {

    static let shared = EventSeenStore()

    private let key = "es_seen_event_ids_v1"
    private var seenIds: Set<String>

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.seenIds = decoded
        } else {
            self.seenIds = []
        }
    }

    // MARK: - Public API

    func isSeen(eventId: String) -> Bool {
        seenIds.contains(eventId)
    }

    func markSeen(eventId: String) {
        guard !seenIds.contains(eventId) else { return }
        seenIds.insert(eventId)
        persist()
    }

    func markSeen(eventIds: [String]) {
        var changed = false
        for id in eventIds where !seenIds.contains(id) {
            seenIds.insert(id)
            changed = true
        }
        if changed {
            persist()
        }
    }

    func reset() {
        seenIds.removeAll()
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(seenIds) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
