//
//  DailyRhythmNotificationManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 29/1/26.
//

import UserNotifications

enum DailyRhythmNotificationManager {

    static func rescheduleIfNeeded() {
        let defaults = UserDefaults.standard

        let startHour = defaults.integer(forKey: "timeline_start_hour")
        let endHour   = defaults.integer(forKey: "timeline_end_hour")

        let morningEnabled = defaults.bool(forKey: "daily_morning_reminder_enabled")
        let eveningEnabled = defaults.bool(forKey: "daily_evening_reminder_enabled")

        let center = UNUserNotificationCenter.current()

        center.removePendingNotificationRequests(
            withIdentifiers: [
                "daily_morning_reminder",
                "daily_evening_reminder"
            ]
        )

        if morningEnabled {
            schedule(
                id: "daily_morning_reminder",
                hour: startHour,
                titleKey: "morning_reminder_title",
                bodyKey: "morning_reminder_body"
            )
        }

        if eveningEnabled {
            schedule(
                id: "daily_evening_reminder",
                hour: endHour,
                titleKey: "evening_reminder_title",
                bodyKey: "evening_reminder_body"
            )
        }
    }

    private static func schedule(
        id: String,
        hour: Int,
        titleKey: String.LocalizationValue,
        bodyKey: String.LocalizationValue
    ) {
        var comp = DateComponents()
        comp.hour = hour
        comp.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: comp,
            repeats: true
        )

        let content = UNMutableNotificationContent()
        content.title = String(localized: titleKey)
        content.body  = String(localized: bodyKey)
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: id,
                content: content,
                trigger: trigger
            )
        )
    }
}
