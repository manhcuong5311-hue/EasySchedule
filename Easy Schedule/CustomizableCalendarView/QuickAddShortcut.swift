//
//  QuickAddShortcut.swift
//  Easy Schedule
//
//  Siri / Shortcuts entry point: "Thêm lịch trong Easy Schedule" →
//  asks "Lịch gì, lúc nào?" → opens the app on the Add Event sheet with
//  the spoken sentence prefilled (QuickAddParser then suggests date/time).
//

import Foundation
import Combine
import AppIntents

/// Hand-off from the intent to the UI. EventListView observes `pendingText`,
/// presents AddEventView with it as the initial title, then clears it.
@MainActor
final class QuickAddRouter: ObservableObject {
    static let shared = QuickAddRouter()

    @Published var pendingText: String?

    private init() {}
}

struct QuickAddEventIntent: AppIntent {

    static let title: LocalizedStringResource = "intent_quick_add_title"

    static let openAppWhenRun: Bool = true

    @Parameter(title: "intent_param_text",
               requestValueDialog: IntentDialog("intent_ask_text"))
    var text: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            QuickAddRouter.shared.pendingText = trimmed
        }
        return .result()
    }
}

struct EasyScheduleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddEventIntent(),
            phrases: [
                "Add an event in \(.applicationName)",
                "Add event in \(.applicationName)",
                "New event in \(.applicationName)",
                "Thêm lịch trong \(.applicationName)",
                "Thêm lịch \(.applicationName)",
                "\(.applicationName) thêm lịch"
            ],
            shortTitle: "intent_quick_add_title",
            systemImageName: "calendar.badge.plus"
        )
    }
}
