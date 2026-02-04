//
//  NotificationManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 4/2/26.
//

import SwiftUI
import UserNotifications
import Combine
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import LocalAuthentication
import UIKit
import FirebaseFirestore
import FirebaseFunctions
import FirebaseMessaging

struct PushPreferenceManager {

    static func enablePush() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Messaging.messaging().token { token, _ in
            guard let token else { return }

            Firestore.firestore()
                .collection("users")
                .document(uid)
                .setData([
                    "notificationTokens": FieldValue.arrayUnion([token])
                ], merge: true)
        }
    }

    static func disablePush() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        Messaging.messaging().token { token, _ in
            guard let token else { return }

            Firestore.firestore()
                .collection("users")
                .document(uid)
                .updateData([
                    "notificationTokens": FieldValue.arrayRemove([token])
                ])
        }
    }
}

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var notificationsEnabled = false
    @Published var leadTime: Int = 15 // phút trước khi nhắc
 
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in

                DispatchQueue.main.async {
                    self.notificationsEnabled = granted
                    UserDefaults.standard.set(granted, forKey: "notificationsEnabled")
                    completion(granted)
                }

                if let error = error {
                    print("❌ Lỗi xin quyền thông báo: \(error.localizedDescription)")
                }
            }
    }

    
    func scheduleNotification(for event: CalendarEvent, leadTime: Int = 15) {
        let enabled = UserDefaults.standard.bool(
            forKey: "pushNotificationsEnabled"
        )
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = String(
            format: String(localized: "upcoming_event_message"),
            event.title
        )
        content.sound = .default

        let triggerDate =
            Calendar.current.date(
                byAdding: .minute,
                value: -leadTime,
                to: event.startTime
            ) ?? event.startTime

        let interval = max(triggerDate.timeIntervalSinceNow, 5)

        let request = UNNotificationRequest(
            identifier: event.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
        )

        UNUserNotificationCenter.current().add(request)
    }


}
