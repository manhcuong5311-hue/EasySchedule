import SwiftUI
import FirebaseCore
import FirebaseMessaging
import FirebaseAppCheck        // ⭐ THÊM
import UserNotifications

@main
struct Easy_scheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // ⭐ APP CHECK SETUP
    init() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(
            AppCheckDebugProviderFactory()
        )
        #else
        AppCheck.setAppCheckProviderFactory(
            DeviceCheckProviderFactory()
        )
        #endif
    }


    @StateObject private var session = SessionStore()
    @AppStorage("appTheme") private var appTheme: String = "system"

    @State private var showLaunch = true
    @AppStorage("hasSeenOnboarding")
    private var hasSeenOnboarding: Bool = false


    @StateObject var premium = PremiumStoreViewModel.shared
    @StateObject private var eventManager = EventManager.shared
    @StateObject private var lockManager = LockManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                appMainContent

                /// 🔐 FaceID Lock
                if lockManager.isLocked &&
                    UserDefaults.standard.bool(forKey: "useBiometricAuth") {

                    LockScreenView()
                        .transition(.opacity)
                }
            }
            .environmentObject(session)        // ⭐ BẮT BUỘC
                   .environmentObject(premium)        // ⭐ BẮT BUỘC
                   .environmentObject(eventManager) 
            .onAppear {
                lockManager.startTimer()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                lockManager.lock()
            }
        }
    }
}

// MARK: - MAIN CONTENT
extension Easy_scheduleApp {

    @ViewBuilder
    var appMainContent: some View {
        if showLaunch {
            LaunchView()
                .preferredColorScheme(colorScheme)
                .environmentObject(eventManager)
                .environmentObject(premium)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showLaunch = false }
                    }
                }

        } else if !hasSeenOnboarding {
            EnhancedOnboardingView()
                .preferredColorScheme(colorScheme)
                .environmentObject(eventManager)


        } else {
            RootView()
                .preferredColorScheme(colorScheme)
                .environmentObject(session)
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
    @State private var showPremiumIntro = false
    @State private var showPaywall = false

    var body: some View {
        Group {
            if session.currentUser == nil {
                LoginView()
            } else {
                ContentView()
                    .environmentObject(session)
                    .environmentObject(eventManager)
                    .onAppear {
        
                        Task { await premium.refresh() }

                        if !premium.isPremium,
                           PremiumIntroGate.shouldShowToday() {

                            showPremiumIntro = true
                            PremiumIntroGate.markShown()
                        }
                    }
            }
        }
     
        .sheet(isPresented: $showPremiumIntro) {
            PremiumIntroView(
                isPresented: $showPremiumIntro,
                onUpgrade: {
                    showPaywall = true
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PremiumUpgradeSheet()
                .environmentObject(premium)
        }
    }

}


