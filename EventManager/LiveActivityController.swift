//
//  LiveActivityController.swift
//  Easy Schedule (app target)
//
//  Start / update / end Live Activity "việc hiện tại" từ tiến trình app.
//  (Widget extension KHÔNG điều khiển được ActivityKit — phải do app làm.)
//
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    #if canImport(ActivityKit)
    private var activity: Activity<ScheduleActivityAttributes>?
    #endif

    /// Đồng bộ Live Activity từ snapshot mới nhất. Hiện việc đang diễn ra,
    /// hoặc việc kế tiếp nếu sắp bắt đầu trong vòng `leadTime`.
    func sync(with snapshot: ScheduleSnapshot, now: Date = Date()) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            endIfNeeded()
            return
        }

        // Tái kết nối Activity còn sống từ phiên trước (tránh tạo trùng).
        if activity == nil {
            activity = Activity<ScheduleActivityAttributes>.activities.first
        }

        let leadTime: TimeInterval = 60 * 60   // hiện sớm tối đa 1 giờ trước giờ bắt đầu
        let target: (item: ScheduleSnapshotItem, upcoming: Bool)?
        if let current = snapshot.current(at: now) {
            target = (current, false)
        } else if let next = snapshot.next(at: now),
                  next.start.timeIntervalSince(now) <= leadTime {
            target = (next, true)
        } else {
            target = nil
        }

        guard let target else { endIfNeeded(); return }

        let state = ScheduleActivityAttributes.ContentState(
            eventID: target.item.id,
            title: target.item.title,
            start: target.item.start,
            end: target.item.end,
            colorHex: target.item.colorHex,
            isUpcoming: target.upcoming
        )
        let content = ActivityContent(state: state, staleDate: target.item.end)

        if let activity {
            Task { await activity.update(content) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: ScheduleActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            } catch {
                // Lỗi (vd: quá nhiều activity) — bỏ qua, widget vẫn chạy.
            }
        }
        #endif
    }

    func endIfNeeded() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
        #endif
    }
}
