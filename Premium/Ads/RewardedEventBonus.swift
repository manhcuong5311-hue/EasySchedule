//
// RewardedEventBonus.swift
//
// Extra event slots a free user unlocks for a given day by watching a rewarded ad.
//

import Foundation

enum RewardedEventBonus {

    /// Most extra events one day can get from rewarded ads.
    static let maxPerDay = 3

    private static let storeKey = "RewardedEventBonus_ByDay"

    static func count(for date: Date) -> Int {
        load()[dayKey(date)] ?? 0
    }

    static func canGrant(for date: Date) -> Bool {
        count(for: date) < maxPerDay
    }

    static func grant(for date: Date) {
        var store = load()
        let key = dayKey(date)
        store[key] = min((store[key] ?? 0) + 1, maxPerDay)

        // Bỏ các ngày đã qua cho gọn UserDefaults
        let todayKey = dayKey(Date())
        store = store.filter { $0.key >= todayKey }

        UserDefaults.standard.set(store, forKey: storeKey)
    }

    // MARK: - Private

    private static func load() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Int] ?? [:]
    }

    /// "yyyy-MM-dd" (zero-padded so string comparison == date comparison).
    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
