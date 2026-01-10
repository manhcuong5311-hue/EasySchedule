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

        // ✅ CHỈ LOG / cache nếu cần
        print("🔥 FCM TOKEN:", token)

        // ❌ TUYỆT ĐỐI KHÔNG:
        // - set UserDefaults
        // - enablePush()
        // - disablePush()
        // - mutate state UI
    }




    // Show banner in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let type = userInfo["type"] as? String else {
            completionHandler()
            return
        }

        DispatchQueue.main.async {

            switch type {

            case "chat", "event":
                if let eventId = userInfo["eventId"] as? String {
                    NotificationRouter.shared.handle(type: type, eventId: eventId)
                }

            case "calendar_access_request":
                NotificationRouter.shared.handleAccessRequest()

            default:
                break
            }
        }

        completionHandler()
    }


}
