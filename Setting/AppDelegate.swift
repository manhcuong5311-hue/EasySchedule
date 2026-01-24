//
//  AppDelegate.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
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


class AppDelegate: NSObject,
                   UIApplicationDelegate,
                   UNUserNotificationCenterDelegate,
                   MessagingDelegate {


    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Firebase
        FirebaseApp.configure()
        // Firebase Messaging
        Messaging.messaging().delegate = self

        // Register for remote notifications (APNs)
        application.registerForRemoteNotifications()

        // Firestore offline cache
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings

        // Load users cache
        EventManager.shared.preloadUsersIfNeeded()

        // Notifications (LOCAL ONLY)
        UNUserNotificationCenter.current().delegate = self

        // Xin quyền thông báo
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if let error = error {
                            print("❌ Notification permission error:", error.localizedDescription)
                        }
                    }
            }
        }


        return true
    }
    func applicationDidEnterBackground(_ application: UIApplication) {
        ChatForegroundTracker.shared.activeChatEventId = nil
    }
    // APNs device token → Firebase
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Nhận FCM token
    func messaging(_ messaging: Messaging,
                   didReceiveRegistrationToken fcmToken: String?) {

        guard let token = fcmToken else { return }

        print("🔥 FCM TOKEN:", token)

        saveTokenToFirestore(token)
    }


    private func saveTokenToFirestore(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            // ❗ user chưa login → token sẽ được lưu sau
            return
        }

        Firestore.firestore()
            .collection("users")
            .document(uid)
            .updateData([
                "notificationTokens": FieldValue.arrayUnion([token]),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    print("❌ Save FCM token error:", error.localizedDescription)
                } else {
                    print("✅ FCM token saved to Firestore")
                }
            }
    }



    // Show banner in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        guard let type = userInfo["type"] as? String else {
            completionHandler([.banner, .sound])
            return
        }

        switch type {

        case "chat":
            // ✅ Chat vẫn dùng banner hệ thống
            completionHandler([.banner, .sound])

        case "event":
            completionHandler([]) // ❌ chặn banner iOS
            pushLocalNotification(
                title: "New event",
                body: "A new event has been added to your calendar"
            )

        case "event_removed":
            completionHandler([])
            pushLocalNotification(
                title: "Event removed",
                body: "An event was removed"
            )

        case "calendar_access_request":
            completionHandler([])
            pushLocalNotification(
                title: "Calendar access request",
                body: "Someone wants to access your calendar"
            )

        default:
            completionHandler([])
        }
    }


}
