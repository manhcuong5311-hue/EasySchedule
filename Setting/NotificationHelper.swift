import UserNotifications

enum InAppNotificationType {
    case event
    case eventRemoved
    case accessRequest
}

func pushLocalNotification(
    title: String,
    body: String,
    identifier: String = UUID().uuidString
) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: nil // 👉 IMMEDIATE (foreground)
    )

    UNUserNotificationCenter.current().add(request)
}

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

    // Dùng userInfo để router (nếu user tap)
    content.userInfo = [
        "type": "chat",
        "eventId": identifier.replacingOccurrences(of: "chat-", with: "")
    ]

    let trigger = UNTimeIntervalNotificationTrigger(
        timeInterval: 0.5,
        repeats: false
    )

    let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: trigger
    )

    UNUserNotificationCenter.current().add(request)
}
