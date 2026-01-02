//
//  NotificationHelper.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 14/12/25.
//

import UserNotifications

func pushLocalChatNotification(
    title: String,
    body: String,
    identifier: String
) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: nil
    )

    UNUserNotificationCenter.current().add(request)
}
