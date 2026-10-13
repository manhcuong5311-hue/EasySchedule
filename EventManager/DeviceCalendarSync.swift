//
//  DeviceCalendarSync.swift
//  Easy Schedule
//
//  Reads busy times from the iPhone Calendar (incl. Google / Outlook accounts
//  added to iOS) and publishes them — times only, never titles — as
//  `source: "ical"` busy slots in publicCalendar/{uid}, so nobody books over
//  them. Older app versions and the web page already render any non-"manual"
//  slot as a plain busy block.
//

import Foundation
import EventKit
import Combine
import FirebaseFirestore

@MainActor
final class DeviceCalendarSync: ObservableObject {

    static let shared = DeviceCalendarSync()
    static let enabledKey = "syncDeviceCalendarBusy"
    static let slotSource = "ical"

    /// Merged busy intervals from the device calendar (local display + conflict checks).
    @Published private(set) var busyIntervals: [DateInterval] = []

    private let store = EKEventStore()
    private var lastSync: Date?
    private var changeObserver: NSObjectProtocol?

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - On / off (Settings toggle)

    /// Turns the sync on (asks for calendar access) or off (removes published slots).
    /// Returns the resulting state.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        guard on else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            stopObserving()
            busyIntervals = []
            await publish([])
            return false
        }

        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        UserDefaults.standard.set(granted, forKey: Self.enabledKey)
        if granted {
            startObserving()
            await sync()
        }
        return granted
    }

    /// Called when the app becomes active.
    func syncIfNeeded() async {
        guard isEnabled else { return }
        guard hasAccess else {
            // Access revoked in iOS Settings → stop sharing stale busy times.
            await setEnabled(false)
            return
        }
        startObserving()
        if let lastSync, Date().timeIntervalSince(lastSync) < 10 * 60 { return }
        await sync()
    }

    // MARK: - Queries used by the UI

    /// Busy intervals overlapping `day` (local calendar day).
    func intervals(on day: Date) -> [(Date, Date)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return busyIntervals
            .filter { $0.start < end && $0.end > start }
            .map { ($0.start, $0.end) }
    }

    func isBusy(from start: Date, to end: Date) -> Bool {
        busyIntervals.contains { $0.start < end && $0.end > start }
    }

    // MARK: - Sync

    func sync() async {
        guard isEnabled, hasAccess else { return }
        lastSync = Date()

        let now = Date()
        // People can book me as far ahead as my plan allows (free 7 / premium 90 / pro 270).
        let tierDays = PremiumLimits.limits(for: PremiumStoreViewModel.shared.tier).maxBookingDaysAhead
        let days = max(14, min(tierDays, 90))
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: now) else { return }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let raw = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .filter { $0.availability != .free }
            .filter { $0.status != .canceled }
            .filter { $0.url?.scheme != "easyschedule" }      // added by us via "Add to Calendar"
            .compactMap { ev -> DateInterval? in
                guard let s = ev.startDate, let e = ev.endDate, e > s, e > now else { return nil }
                return DateInterval(start: max(s, now), end: e)
            }

        let merged = Self.merge(raw)
        busyIntervals = merged
        await publish(merged)
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    // MARK: - Firestore

    /// Replaces every `source == "ical"` slot in my public calendar with `intervals`.
    private func publish(_ intervals: [DateInterval]) async {
        guard let uid = EventManager.shared.currentUserId else { return }

        let newSlots: [[String: Any]] = intervals.map {
            [
                "id": "ical-\(Int($0.start.timeIntervalSince1970))-\(Int($0.end.timeIntervalSince1970))",
                "source": Self.slotSource,
                "owner": uid,
                "start": $0.start.timeIntervalSince1970,
                "end": $0.end.timeIntervalSince1970
            ]
        }

        let db = Firestore.firestore()
        let ref = db.collection("publicCalendar").document(uid)

        do {
            _ = try await db.runTransaction { transaction, errorPointer -> Any? in
                let snap: DocumentSnapshot
                do {
                    snap = try transaction.getDocument(ref)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }
                var slots = snap.data()?["busySlots"] as? [[String: Any]] ?? []
                slots.removeAll { ($0["source"] as? String) == DeviceCalendarSync.slotSource }
                slots.append(contentsOf: newSlots)
                transaction.setData(["busySlots": slots], forDocument: ref, merge: true)
                return nil
            }
        } catch {
            print("⚠️ Calendar busy publish failed:", error.localizedDescription)
        }
    }

    // MARK: - Calendar change notifications

    private func startObserving() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
    }

    private func stopObserving() {
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
    }
}
