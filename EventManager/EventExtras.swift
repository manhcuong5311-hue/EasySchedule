//
//  EventExtras.swift
//  Easy Schedule
//
//  v2.4 additions to an appointment: location, per-participant response,
//  reschedule proposal and repeating series. Every field is optional on
//  `CalendarEvent`, so events written by older app versions still decode and
//  older versions simply ignore these keys.
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct EventLocation: Codable, Hashable {
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = ["name": name, "latitude": latitude, "longitude": longitude]
        if let address, !address.isEmpty { data["address"] = address }
        return data
    }

    static func from(_ value: Any?) -> EventLocation? {
        guard let map = value as? [String: Any],
              let name = map["name"] as? String,
              let lat = (map["latitude"] as? NSNumber)?.doubleValue,
              let lon = (map["longitude"] as? NSNumber)?.doubleValue
        else { return nil }
        return EventLocation(name: name, address: map["address"] as? String, latitude: lat, longitude: lon)
    }
}

struct TimeProposal: Codable, Hashable {
    var by: String
    var start: Date
    var end: Date
    /// Who agreed (the proposer counts as yes) / disagreed. Optional so cached
    /// proposals without votes still decode.
    var accepted: [String]? = nil
    var rejected: [String]? = nil

    var yes: Set<String> { Set(accepted ?? [by]) }
    var no: Set<String> { Set(rejected ?? []) }

    var firestoreData: [String: Any] {
        ["by": by,
         "start": Timestamp(date: start),
         "end": Timestamp(date: end),
         "accepted": Array(yes),
         "rejected": Array(no)]
    }

    static func from(_ value: Any?) -> TimeProposal? {
        guard let map = value as? [String: Any],
              let by = map["by"] as? String,
              let start = (map["start"] as? Timestamp)?.dateValue(),
              let end = (map["end"] as? Timestamp)?.dateValue()
        else { return nil }
        return TimeProposal(by: by, start: start, end: end,
                            accepted: map["accepted"] as? [String],
                            rejected: map["rejected"] as? [String])
    }
}

enum EventResponse: String {
    case accepted
    case declined
}

enum RepeatRule: String, CaseIterable, Identifiable {
    case none, daily, weekly, biweekly, monthly

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .none:     return "repeat_none"
        case .daily:    return "repeat_daily"
        case .weekly:   return "repeat_weekly"
        case .biweekly: return "repeat_biweekly"
        case .monthly:  return "repeat_monthly"
        }
    }

    /// Start date of every occurrence (the first one included), `count` in total.
    func occurrences(from start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard self != .none else { return [start] }
        return (0..<max(count, 1)).compactMap { i in
            switch self {
            case .none:     return start
            case .daily:    return calendar.date(byAdding: .day, value: i, to: start)
            case .weekly:   return calendar.date(byAdding: .day, value: 7 * i, to: start)
            case .biweekly: return calendar.date(byAdding: .day, value: 14 * i, to: start)
            case .monthly:  return calendar.date(byAdding: .month, value: i, to: start)
            }
        }
    }
}

// MARK: - Booking hours ("Giờ nhận lịch")

/// When other people may book the owner. Stored as the optional map
/// `publicCalendar/{uid}.bookingHours` (same schema as the web booking page):
/// `{ enabled, tz, days: { "<weekday>": { start, end } }, bufferMin, maxPerDay }`.
/// Weekday keys are `Calendar` weekday numbers ("1" = Sunday … "7" = Saturday);
/// start/end are minutes from midnight in the owner's time zone `tz`.
/// Only restricts *other* people booking the owner — never the owner's own events.
struct BookingHours: Equatable {

    struct DayRange: Equatable {
        /// Minutes from owner-local midnight, 0…1440, start < end.
        var start: Int
        var end: Int

        var isValid: Bool { start >= 0 && end <= 1440 && start < end }
    }

    var enabled: Bool
    /// Owner's `TimeZone` identifier, e.g. "Asia/Ho_Chi_Minh".
    var tz: String
    /// Calendar weekday (1 = Sunday … 7 = Saturday) → open window. Missing = closed.
    var days: [Int: DayRange]
    /// Break kept free around existing busy slots (0/10/15/30/60).
    var bufferMin: Int
    /// 0 = unlimited.
    var maxPerDay: Int

    static let bufferOptions = [0, 10, 15, 30, 60]

    /// Mon–Fri 9:00–18:00, no buffer, no daily cap, device time zone.
    static var defaultHours: BookingHours {
        let nineToSix = DayRange(start: 540, end: 1080)
        return BookingHours(
            enabled: true,
            tz: TimeZone.current.identifier,
            days: [2: nineToSix, 3: nineToSix, 4: nineToSix, 5: nineToSix, 6: nineToSix],
            bufferMin: 0,
            maxPerDay: 0
        )
    }

    init(enabled: Bool, tz: String, days: [Int: DayRange], bufferMin: Int, maxPerDay: Int) {
        self.enabled = enabled
        self.tz = tz
        self.days = days
        self.bufferMin = bufferMin
        self.maxPerDay = maxPerDay
    }

    /// Parses the Firestore map. Returns nil when it isn't a booking-hours map.
    /// Invalid day entries are dropped (= closed that weekday).
    init?(from map: [String: Any]) {
        guard let enabled = map["enabled"] as? Bool else { return nil }

        func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }

        var parsedDays: [Int: DayRange] = [:]
        if let rawDays = map["days"] as? [String: Any] {
            for (key, value) in rawDays {
                guard let weekday = Int(key), (1...7).contains(weekday),
                      let range = value as? [String: Any],
                      let start = int(range["start"]),
                      let end = int(range["end"])
                else { continue }
                let day = DayRange(start: start, end: end)
                if day.isValid { parsedDays[weekday] = day }
            }
        }

        let tz = (map["tz"] as? String).flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
            ?? TimeZone.current.identifier

        self.init(
            enabled: enabled,
            tz: tz,
            days: parsedDays,
            bufferMin: max(0, int(map["bufferMin"]) ?? 0),
            maxPerDay: max(0, int(map["maxPerDay"]) ?? 0)
        )
    }

    var firestoreData: [String: Any] {
        var dayMap: [String: Any] = [:]
        for (weekday, range) in days where range.isValid {
            dayMap[String(weekday)] = ["start": range.start, "end": range.end]
        }
        return [
            "enabled": enabled,
            "tz": tz,
            "days": dayMap,
            "bufferMin": bufferMin,
            "maxPerDay": maxPerDay
        ]
    }

    // MARK: Pure checks (no Firestore)

    /// Gregorian calendar in the owner's time zone.
    var ownerCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz) ?? .current
        return c
    }

    /// Seconds since owner-local midnight of `date`.
    private func secondsIntoDay(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }

    /// [start, end) lies inside the owner's open window for that weekday and does
    /// not cross owner-local midnight. Always true when disabled.
    func allows(start: Date, end: Date) -> Bool {
        guard enabled else { return true }
        guard end > start else { return false }
        let cal = ownerCalendar
        let dayStart = cal.startOfDay(for: start)
        guard let range = days[cal.component(.weekday, from: start)],
              let nextDay = cal.date(byAdding: .day, value: 1, to: dayStart),
              end <= nextDay
        else { return false }
        let s = secondsIntoDay(start, cal)
        let e = end == nextDay ? 1440 * 60 : secondsIntoDay(end, cal)
        return s >= range.start * 60 && e <= range.end * 60
    }

    /// True when a busy slot b satisfies b.start < end + buffer && b.end > start − buffer.
    /// No buffer configured (or disabled) → false; plain overlaps are the busy check's job.
    func violatesBuffer(start: Date, end: Date, busy: [(Date, Date)]) -> Bool {
        guard enabled, bufferMin > 0 else { return false }
        let pad = TimeInterval(bufferMin * 60)
        let paddedStart = start.addingTimeInterval(-pad)
        let paddedEnd = end.addingTimeInterval(pad)
        return busy.contains { $0.0 < paddedEnd && $0.1 > paddedStart }
    }

    /// The owner-local day containing `ownerDayContaining` already has `maxPerDay`
    /// appointments (counted by start time; pass the starts of "event" busy slots).
    func isDayFull(_ ownerDayContaining: Date, eventStarts: [Date]) -> Bool {
        guard enabled, maxPerDay > 0 else { return false }
        let cal = ownerCalendar
        let count = eventStarts.reduce(0) { $0 + (cal.isDate($1, inSameDayAs: ownerDayContaining) ? 1 : 0) }
        return count >= maxPerDay
    }

    /// The owner-local weekday containing `date` is not bookable.
    func isClosed(on date: Date) -> Bool {
        guard enabled else { return false }
        return days[ownerCalendar.component(.weekday, from: date)] == nil
    }

    /// Any open window overlaps [from, to) — e.g. a whole day in the booker's own
    /// time zone, which may span two owner-local days.
    func hasOpenTime(from: Date, to: Date) -> Bool {
        guard enabled else { return true }
        guard to > from else { return false }
        let cal = ownerCalendar
        var day = cal.startOfDay(for: from)
        while day < to {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            if let range = days[cal.component(.weekday, from: day)],
               let open = cal.date(bySettingHour: range.start / 60, minute: range.start % 60, second: 0, of: day) {
                let close = range.end >= 1440
                    ? next
                    : (cal.date(bySettingHour: range.end / 60, minute: range.end % 60, second: 0, of: day) ?? next)
                if open < to && close > from { return true }
            }
            day = next
        }
        return false
    }
}

// MARK: - Convenience on CalendarEvent

extension CalendarEvent {

    var isShared: Bool { Set(participants + [owner]).count > 1 }

    /// Voters for a time change — same count the Firestore rules use (`participants.size()`).
    var voterCount: Int { max(Set(participants).count, 2) }

    /// "More than half" of the participants must agree to move the appointment.
    var votesNeeded: Int { voterCount / 2 + 1 }

    func canManage(_ uid: String?) -> Bool {
        guard let uid else { return false }
        return uid == owner || uid == createdBy || (admins?.contains(uid) ?? false)
    }

    func response(of uid: String) -> EventResponse? {
        responses?[uid].flatMap(EventResponse.init(rawValue:))
    }
}

// MARK: - EventManager actions

extension EventManager {

    private var eventsRef: CollectionReference { Firestore.firestore().collection("events") }

    private func mutateLocal(_ id: String, _ change: (inout CalendarEvent) -> Void) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        change(&events[idx])
    }

    // MARK: Location

    func updateLocation(_ location: EventLocation?, for event: CalendarEvent) {
        mutateLocal(event.id) { $0.location = location }
        eventsRef.document(event.id).updateData([
            "location": location?.firestoreData ?? FieldValue.delete()
        ])
    }

    // MARK: Confirm / decline

    /// Saves my answer, then tells the others in chat. Returns false if the write failed.
    @discardableResult
    func respond(_ response: EventResponse, to event: CalendarEvent) async -> Bool {
        guard let uid = currentUserId else { return false }
        if event.response(of: uid) == response { return true }   // already answered this way
        do {
            try await eventsRef.document(event.id).updateData(["responses.\(uid)": response.rawValue])
        } catch {
            print("⚠️ respond failed:", error.localizedDescription)
            return false
        }
        mutateLocal(event.id) {
            var map = $0.responses ?? [:]
            map[uid] = response.rawValue
            $0.responses = map
        }
        let key = response == .accepted ? "chat_auto_accepted" : "chat_auto_declined"
        await ChatPoster.post(String(localized: String.LocalizationValue(key)), eventId: event.id)
        return true
    }

    // MARK: Reschedule proposals (majority vote)

    @discardableResult
    func proposeTime(start: Date, end: Date, for event: CalendarEvent) async -> Bool {
        guard let uid = currentUserId else { return false }
        // Whole minutes → the Timestamps round-trip exactly, which the rules
        // compare when someone applies the accepted time.
        let s = Self.wholeMinute(start), e = Self.wholeMinute(end)
        let proposal = TimeProposal(by: uid, start: s, end: e, accepted: [uid], rejected: [])
        do {
            try await eventsRef.document(event.id).updateData(["proposal": proposal.firestoreData])
        } catch {
            print("⚠️ propose failed:", error.localizedDescription)
            return false
        }
        mutateLocal(event.id) { $0.proposal = proposal }

        let text = String(format: String(localized: "chat_auto_proposed_format"),
                          Self.proposalTimeText(start: s, end: e))
        await ChatPoster.post(text, eventId: event.id)
        AppAnalytics.log(AppAnalyticsEvent.proposalSent, ["group": event.participants.count > 2])
        return true
    }

    /// My vote on the pending proposal. When "yes" votes become more than half of the
    /// participants, the appointment moves for everyone; when "no" votes make that
    /// impossible, the proposal is dropped.
    @discardableResult
    func voteOnProposal(_ agree: Bool, for event: CalendarEvent) async -> Bool {
        guard let uid = currentUserId, let p = event.proposal else { return false }
        // Same vote again → nothing to do
        if agree && p.yes.contains(uid) && !p.no.contains(uid) { return true }
        if !agree && p.no.contains(uid) { return true }

        var yes = p.yes, no = p.no
        if agree { yes.insert(uid); no.remove(uid) } else { no.insert(uid); yes.remove(uid) }

        let total = event.voterCount
        let ref = eventsRef.document(event.id)
        let when = Self.proposalTimeText(start: p.start, end: p.end)

        do {
            if agree && yes.count * 2 > total {
                // Majority → move it for everyone
                var responses: [String: String] = [:]
                for id in yes { responses[id] = EventResponse.accepted.rawValue }
                let day = Calendar.current.startOfDay(for: p.start)
                try await ref.updateData([
                    "date": Timestamp(date: day),
                    "startTime": Timestamp(date: p.start),
                    "endTime": Timestamp(date: p.end),
                    "proposal": FieldValue.delete(),
                    "responses": responses
                ])
                var moved = event
                moved.date = day
                moved.startTime = p.start
                moved.endTime = p.end
                moved.proposal = nil
                moved.responses = responses
                mutateLocal(event.id) { $0 = moved }
                syncBusySlots(for: moved)
                await ChatPoster.post(String(format: String(localized: "chat_auto_proposal_accepted_format"), when),
                                      eventId: event.id)

            } else if !agree && no.count * 2 >= total {
                // A majority can no longer be reached → keep the original time
                try await ref.updateData(["proposal": FieldValue.delete()])
                mutateLocal(event.id) { $0.proposal = nil }
                await ChatPoster.post(String(localized: "chat_auto_proposal_rejected"), eventId: event.id)

            } else {
                try await ref.updateData([
                    "proposal.accepted": Array(yes),
                    "proposal.rejected": Array(no)
                ])
                mutateLocal(event.id) {
                    $0.proposal?.accepted = Array(yes)
                    $0.proposal?.rejected = Array(no)
                }
                let text = agree
                    ? String(format: String(localized: "chat_auto_vote_yes_format"), when, yes.count, event.votesNeeded)
                    : String(localized: "chat_auto_proposal_declined")
                await ChatPoster.post(text, eventId: event.id)
            }
        } catch {
            print("⚠️ vote failed:", error.localizedDescription)
            return false
        }
        AppAnalytics.log(AppAnalyticsEvent.proposalVoted, ["agree": agree])
        return true
    }

    /// The proposer takes the request back.
    @discardableResult
    func withdrawProposal(for event: CalendarEvent) async -> Bool {
        do {
            try await eventsRef.document(event.id).updateData(["proposal": FieldValue.delete()])
        } catch {
            return false
        }
        mutateLocal(event.id) { $0.proposal = nil }
        await ChatPoster.post(String(localized: "chat_auto_proposal_withdrawn"), eventId: event.id)
        return true
    }

    private static func wholeMinute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    static func proposalTimeText(start: Date, end: Date) -> String {
        let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(from)–\(to), \(day)"
    }

    // MARK: Repeating series

    struct SeriesResult {
        var created: Int
        var skipped: Int
    }

    /// Creates one event document per occurrence (sharing `seriesId`) in a single batch.
    /// Occurrences that are in the past, clash with an existing event or exceed the
    /// daily cap are skipped. One doc per occurrence keeps old app versions working.
    func addRecurringEvents(title: String,
                            occurrences: [(start: Date, end: Date)],
                            colorHex: String,
                            location: EventLocation?) async -> SeriesResult {
        guard let uid = currentUserId else { return SeriesResult(created: 0, skipped: occurrences.count) }

        let seriesId = UUID().uuidString
        let calendar = Calendar.current
        let now = Date()
        let premium = PremiumStoreViewModel.shared

        var pending: [CalendarEvent] = []
        for occ in occurrences {
            let day = calendar.startOfDay(for: occ.start)
            let sameDay = (events + pending).filter { calendar.isDate($0.date, inSameDayAs: day) }

            let clashes = !allowDuplicateEvents && isOverlapExceedingLimit(
                newStart: occ.start, newEnd: occ.end, limitMinutes: 5, events: sameDay)

            guard occ.end > now,
                  !clashes,
                  sameDay.count < premium.limits.maxEventsPerDay
            else { continue }

            pending.append(CalendarEvent(
                id: UUID().uuidString,
                title: title,
                date: day,
                startTime: occ.start,
                endTime: occ.end,
                owner: uid,
                sharedUser: uid,
                createdBy: uid,
                participants: [uid],
                admins: [uid],
                colorHex: colorHex,
                pendingDelete: false,
                origin: .myEvent,
                location: location,
                seriesId: seriesId
            ))
        }

        guard !pending.isEmpty else {
            return SeriesResult(created: 0, skipped: occurrences.count)
        }

        let batch = Firestore.firestore().batch()
        do {
            for ev in pending {
                try batch.setData(from: ev, forDocument: eventsRef.document(ev.id))
            }
            try await batch.commit()
        } catch {
            print("❌ Recurring batch failed:", error.localizedDescription)
            return SeriesResult(created: 0, skipped: occurrences.count)
        }

        for ev in pending {
            EventSeenStore.shared.markSeen(eventId: ev.id)
            NotificationManager.shared.scheduleNotification(for: ev)
            syncBusySlots(for: ev)
        }
        return SeriesResult(created: pending.count, skipped: occurrences.count - pending.count)
    }

    /// Deletes `event` and every later occurrence of its series.
    func deleteSeries(from event: CalendarEvent) {
        guard let seriesId = event.seriesId else {
            deleteEvent(event)
            return
        }
        let targets = events.filter { $0.seriesId == seriesId && $0.startTime >= event.startTime }
        for ev in targets { deleteEvent(ev) }
    }
}

// MARK: - My booking hours

extension EventManager {

    enum BookingHoursError: LocalizedError {
        case notSignedIn
        var errorDescription: String? { String(localized: "login_required") }
    }

    private var myPublicCalendarRef: DocumentReference? {
        guard let uid = currentUserId ?? Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().collection("publicCalendar").document(uid)
    }

    /// Writes (or removes, when nil) `publicCalendar/{me}.bookingHours`.
    /// `mergeFields` replaces the whole map — a plain `merge: true` would deep-merge
    /// and keep weekdays the user has just closed.
    func saveMyBookingHours(_ hours: BookingHours?) async throws {
        guard let ref = myPublicCalendarRef else { throw BookingHoursError.notSignedIn }
        try await ref.setData([
            "bookingHours": hours?.firestoreData ?? FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ], mergeFields: ["bookingHours", "updatedAt"])
    }

    /// My current booking hours, or nil when never set / unreadable.
    func fetchMyBookingHours() async -> BookingHours? {
        guard let ref = myPublicCalendarRef else { return nil }
        do {
            let snap = try await ref.getDocument()
            guard let map = snap.data()?["bookingHours"] as? [String: Any] else { return nil }
            return BookingHours(from: map)
        } catch {
            print("⚠️ fetchMyBookingHours failed:", error.localizedDescription)
            return nil
        }
    }
}
