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
    @StateObject private var network = NetworkMonitor.shared


    @StateObject var premium = PremiumStoreViewModel.shared
    @StateObject private var eventManager = EventManager.shared
    @StateObject private var lockManager = LockManager.shared
    @StateObject private var guideManager = GuideManager()
    @Environment(\.scenePhase) private var scenePhase

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
                   .environmentObject(network)
                   .environmentObject(guideManager)
                   .onAppear {
                       lockManager.startTimer()

                       if UserDefaults.standard.bool(forKey: "useBiometricAuth") {
                           lockManager.lock()   // ⭐ DÒNG QUAN TRỌNG NHẤT
                       }
                   }

            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willResignActiveNotification
                )
            ) { _ in
                lockManager.lock()
            }
            .onChange(of: scenePhase) { _, phase in
                // Giữ widget + Live Activity luôn mới khi app vào/ra nền.
                if phase == .active || phase == .background {
                    EventManager.shared.refreshSharedSnapshot()
                }
                if phase == .active {
                    Task { await DeviceCalendarSync.shared.syncIfNeeded() }
                }
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
            
        } else {
            
            if session.currentUser == nil {
                
                // 🔐 LOGIN TRƯỚC
                LoginView()
                    .preferredColorScheme(colorScheme)
                
            } else if !hasSeenOnboarding {
                
                // 🎯 ONBOARDING SAU KHI LOGIN
                OnboardingContainerView()
                    .preferredColorScheme(colorScheme)
                
            } else {
                
                // ✅ APP CHÍNH
                RootView()
                    .preferredColorScheme(colorScheme)
            }
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

    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var guideManager: GuideManager

    @StateObject private var uiAccent = UIAccentStore()
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Group {
            if session.currentUser == nil {
                LoginView()
            } else {
                ContentView()
                    
                    .onAppear {
                        guideManager.startIfNeeded()
                        AdsManager.shared.activate()

                        if let uid = session.currentUserId {
                            eventManager.configureForUser(uid: uid)
                            eventManager.preloadUsersIfNeeded()
                        }

                        Task { await premium.refresh() }

                        ReviewManager.shared.tryRequestReview(requestReview)
                    }
            }
        }
        // ⭐⭐⭐ INJECT Ở ĐÂY — NGOÀI GROUP ⭐⭐⭐
        .environmentObject(session)
        .environmentObject(eventManager)
        .environmentObject(network)
        .environmentObject(uiAccent)
        .tint(uiAccent.color)
    }
}

struct OnboardingContainerView: View {

    @AppStorage("hasSeenOnboarding")
    private var hasSeenOnboarding = false

    @State private var step: OnboardingStep = .hero

    /// When set (e.g. previewing from Settings) a close button is shown so the
    /// already-onboarded user can dismiss without going through the paywall flow.
    var onClose: (() -> Void)? = nil

    var body: some View {
        // ZStack (not .overlay on the TabView) so the top bar stays inside the
        // safe area while the pages extend edge to edge.
        ZStack(alignment: .topTrailing) {
            TabView(selection: $step) {

                // 1️⃣ HERO
                OnboardingHeroSlide(
                    onNext: { go(.webBooking) }
                )
                .tag(OnboardingStep.hero)

                // 2️⃣ BOOKING LINK (+ booking hours)
                OnboardingWebBookingSlide(
                    onNext: { go(.agree) }
                )
                .tag(OnboardingStep.webBooking)

                // 3️⃣ AGREE ON A TIME (proposal + vote + chat)
                OnboardingAgreeSlide(
                    onNext: { go(.reminders) }
                )
                .tag(OnboardingStep.agree)

                // 4️⃣ NEVER BE LATE (asks notification permission in context)
                OnboardingRemindersSlide(
                    onNext: { go(.setup) }
                )
                .tag(OnboardingStep.reminders)

                // 5️⃣ SETUP: name + booking link + booking hours
                OnboardingSetupSlide(
                    onNext: { go(.cta) }
                )
                .tag(OnboardingStep.setup)

                // 6️⃣ CTA
                FinalOnboardingCTASlide(
                    onFinish: finish
                )
                .tag(OnboardingStep.cta)
            }
            .tabViewStyle(.page)
            .ignoresSafeArea()

            topBar
        }
    }

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 12) {
            // Skip the feature tour → setup step (not straight into the app)
            if step.isFeatureSlide {
                Button {
                    go(.setup)
                } label: {
                    Text(String(localized: "onboarding_skip"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .transition(.opacity)
            }

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .padding(.top, 6)
        .padding(.trailing, 16)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func go(_ next: OnboardingStep) {
        withAnimation { step = next }
    }

    /// Leaves onboarding. In the Settings preview the flag is already true, so
    /// this just closes the preview.
    private func finish() {
        hasSeenOnboarding = true
        onClose?()
    }
}
