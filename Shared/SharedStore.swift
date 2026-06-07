//
//  SharedStore.swift
//  Easy Schedule — Shared (app + widget)
//
//  Cầu nối app ↔ widget/Live Activity qua App Group container.
//
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum SharedStore {
    /// ⚠️ Phải trùng App Group bật trong Signing & Capabilities của CẢ 2 target.
    static let appGroupID = "group.com.SamCorp.EasySchedule"
    private static let snapshotKey = "schedule_snapshot_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func writeSnapshot(_ snapshot: ScheduleSnapshot) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    static func readSnapshot() -> ScheduleSnapshot {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
