import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
struct Easy_scheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var session = SessionStore()
    @AppStorage("appTheme") private var appTheme: String = "system"

    @State private var showLaunch = true
    @State private var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    @StateObject var premium = PremiumStoreViewModel.shared
    @StateObject private var eventManager = EventManager.shared
    
    @StateObject private var lockManager = LockManager.shared   // ← dùng class của bạn

    var body: some Scene {
        WindowGroup {
            ZStack {
                appMainContent

                /// 🔐 Nếu bật FaceID + app đang khóa → hiện Lock Screen
                if lockManager.isLocked &&
                    UserDefaults.standard.bool(forKey: "useBiometricAuth") {

                    LockScreenView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                // bắt đầu đếm thời gian không hoạt động
                lockManager.startTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                // ứng dụng bị ẩn → khóa nếu bật FaceID
                lockManager.lock()
            }
        }
    }
}

extension Easy_scheduleApp {

    @ViewBuilder
    var appMainContent: some View {
        if showLaunch {
            LaunchView()
                .preferredColorScheme(colorScheme)
                .environmentObject(eventManager)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showLaunch = false }
                    }
                }

        } else if showOnboarding {
            EnhancedOnboardingView(showOnboarding: $showOnboarding)
                .preferredColorScheme(colorScheme)
                .environmentObject(eventManager)

        } else {
            RootView()
                .preferredColorScheme(colorScheme)
                .environmentObject(session)
                .environmentObject(premium)
                .environmentObject(eventManager)
        }
    }

    private var colorScheme: ColorScheme? {
        appTheme == "light" ? .light :
        appTheme == "dark" ? .dark : nil
    }
}


// MARK: - ROOT VIEW
struct RootView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var premium: PremiumStoreViewModel
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        if session.currentUser == nil {
            LoginView()
                .environmentObject(eventManager)

        } else {
            ContentView()
                .environmentObject(session)
                .environmentObject(premium)
                .environmentObject(eventManager)
        }
    }
}
