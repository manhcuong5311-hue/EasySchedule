//
//  QuickReplyIntent.swift
//  Easy Schedule
//
//  "Tôi đang tới" / "Trễ 10 phút" buttons on the Live Activity.
//  Compiled into BOTH the app and the widget: the widget only builds the
//  button, `perform()` always runs in the app process (LiveActivityIntent),
//  where the app installs `QuickReplyCenter.handler` at launch. The widget
//  doesn't link Firebase, so nothing here may import it.
//

import Foundation
import AppIntents

enum QuickReplyKind: String, Sendable {
    case onMyWay
    case runningLate
}

/// Set by the app (AppDelegate) to actually post the chat message.
enum QuickReplyCenter {
    nonisolated(unsafe) static var handler: (@Sendable (_ eventId: String, _ kind: QuickReplyKind) async -> Void)?
}

struct QuickReplyIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "Quick reply"
    static let isDiscoverable = false

    @Parameter(title: "Event")
    var eventId: String

    @Parameter(title: "Reply")
    var kind: String

    init() {}

    init(eventId: String, kind: QuickReplyKind) {
        self.eventId = eventId
        self.kind = kind.rawValue
    }

    func perform() async throws -> some IntentResult {
        if let reply = QuickReplyKind(rawValue: kind) {
            await QuickReplyCenter.handler?(eventId, reply)
        }
        return .result()
    }
}
