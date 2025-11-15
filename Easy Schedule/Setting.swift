//
//  SETTING.swift
//  Easy schedule
//
//  Created by Sam Manh Cuong on 11/11/25.
//
import SwiftUI
import UserNotifications
import Combine
import FirebaseMessaging
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    @Published var notificationsEnabled = false
    @Published var leadTime: Int = 15 // phút trước khi nhắc
    @AppStorage("pushNotificationsEnabled") private var pushNotificationsEnabled = true
    
    
    
    func requestPermission() {
        UserNotifications.UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
            }
            if let error = error {
                print("❌ Lỗi xin quyền thông báo: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleNotification(title: String, message: String, date: Date) {
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        
        let triggerDate = Calendar.current.date(byAdding: .minute, value: -leadTime, to: date) ?? date
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(triggerDate.timeIntervalSinceNow, 5), repeats: false)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UserNotifications.UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - SettingsView
import SwiftUI
import FirebaseAuth
import FirebaseMessaging

struct SettingsView: View {
    // MARK: - AppStorage
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("leadTime") private var leadTime = 15
    @AppStorage("selectedLanguage") private var selectedLanguage = "vi"
    @AppStorage("proPlan") private var proPlan = "Miễn phí"
    @AppStorage("isPremiumUser") var isPremiumUser: Bool = false
    @AppStorage("pushNotificationsEnabled") private var pushNotificationsEnabled = true
    
    // MARK: - State
    @State private var showLogoutAlert = false
    @State private var showPrivacySheet = false
    
    // MARK: - Environment Objects
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var languageManager: LanguageManager
    
    // MARK: - Constants
    let leadTimeOptions = [5, 10, 15, 30, 60]
    let appVersion = "1.0.0"
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Notifications
                Section("Thông báo") {
                    Toggle("Bật thông báo sắp đến lịch", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { newValue in
                            if newValue { NotificationManager.shared.requestPermission() }
                        }
                    
                    Picker("Thời gian nhắc trước", selection: $leadTime) {
                        ForEach(leadTimeOptions, id: \.self) { value in
                            Text("\(value) phút trước").tag(value)
                        }
                    }
                    .disabled(!notificationsEnabled)
                    
                    Toggle("Thông báo khi có lịch mới", isOn: $pushNotificationsEnabled)
                        .onChange(of: pushNotificationsEnabled) { newValue in
                            if newValue {
                                Messaging.messaging().subscribe(toTopic: "admin") { error in
                                    if let error = error {
                                        print("❌ Subscribe topic lỗi: \(error.localizedDescription)")
                                    } else {
                                        print("✅ Đã bật thông báo khi có lịch mới")
                                    }
                                }
                            } else {
                                Messaging.messaging().unsubscribe(fromTopic: "admin") { error in
                                    if let error = error {
                                        print("❌ Unsubscribe topic lỗi: \(error.localizedDescription)")
                                    } else {
                                        print("✅ Đã tắt thông báo khi có lịch mới")
                                    }
                                }
                            }
                        }
                }
                
                // MARK: - Tài khoản & Bảo mật
                Section("Tài khoản & Bảo mật") {
                    NavigationLink("Nâng cấp tài khoản (\(proPlan))") {
                        UpgradeAccountView(currentPlan: $proPlan)
                    }
                    NavigationLink("Quản lý bảo mật") {
                        SecuritySettingsView()
                    }
                }
                
                // MARK: - Ngôn ngữ
                Section("Ngôn ngữ") {
                    Picker("Ngôn ngữ hiển thị", selection: $selectedLanguage) {
                        Text("Tiếng Việt").tag("vi")
                        
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedLanguage) { newValue in
                        languageManager.setLanguage(newValue)
                    }
                }
                
                // MARK: - Thông tin & Hỗ trợ
                Section("Thông tin & Hỗ trợ") {
                    Button("🧾 Privacy Policy & App Info") {
                        showPrivacySheet = true
                    }
                    Button("📞 Liên hệ hỗ trợ") {
                        contactSupport()
                    }
                }
                
                // MARK: - Đăng xuất
                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .alert("Xác nhận đăng xuất?", isPresented: $showLogoutAlert) {
                Button("Huỷ", role: .cancel) {}
                Button("Đăng xuất", role: .destructive) { performLogout() }
            } message: {
                Text("Bạn sẽ cần đăng nhập lại để tiếp tục sử dụng.")
            }
            .sheet(isPresented: $showPrivacySheet) {
                PrivacyPolicyView()
            }
        }
    }
    
    // MARK: - Hành động phụ
    private func contactSupport() {
        let supportEmail = "Manhcuong5311@gmail.com"
        let subject = "Hỗ trợ Easy Schedule".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(supportEmail)?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func performLogout() {
        do {
            try Auth.auth().signOut()
            session.currentUser = nil
            print("✅ Đăng xuất Firebase thành công (SettingsView).")
        } catch let error as NSError {
            print("❌ Lỗi khi đăng xuất: \(error.localizedDescription)")
        }
    }
}


// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("🧾 Chính sách quyền riêng tư & Thông tin ứng dụng")
                        .font(.headline)
                    Text("""
                    EasySchedule tôn trọng quyền riêng tư của bạn. Tất cả các sự kiện lịch được tạo trong ứng dụng được lưu trữ cục bộ trên thiết bị và không chia sẻ với bên thứ ba.
                    Bạn có thể chọn chia sẻ sự kiện thông qua liên kết, nhưng điều này chỉ được thực hiện khi bạn chủ động.
                    Ứng dụng không theo dõi bạn, không thu thập thông tin vị trí, danh bạ, hay dữ liệu sức khỏe.
                    Thông tin đăng ký Premium được xử lý an toàn qua hệ thống In-App Purchase của Apple.
                    Chúng tôi có thể thu thập dữ liệu crash hoặc sử dụng ẩn danh để cải thiện hiệu năng ứng dụng, nhưng dữ liệu này không liên kết với bạn.
                    Nếu có câu hỏi về quyền riêng tư, vui lòng liên hệ: [email Manhcuong5311@gmail.com].
                    
                    
                    Phiên bản: 1.0.0
                    Nhà phát triển: SamCorp.Easyschedule
                    """)
                    .font(.body)
                    Link("Website 🧾 Privacy Policy & App Info", destination: URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!)
                        
                }
                .padding()
            }
            .navigationTitle("Chính sách & Thông tin")
        }
    }
}

// MARK: - Upgrade Account View
struct UpgradeAccountView: View {
    @Binding var currentPlan: String
    @Environment(\.dismiss) var dismiss
    let plans = ["Miễn phí", "1 tháng", "1 năm", "Trọn đời"]
    
    var body: some View {
        List(plans, id: \.self) { plan in
            Button {
                currentPlan = plan
                dismiss()
            } label: {
                HStack {
                    Text(plan)
                    Spacer()
                    if currentPlan == plan {
                        Image(systemName: "checkmark").foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle("Nâng cấp tài khoản")
    }
}

// MARK: - Security View
import SwiftUI
import LocalAuthentication

struct SecuritySettingsView: View {
    // MARK: - AppStorage để lưu trạng thái
    @AppStorage("useBiometricAuth") private var useBiometricAuth = false
    @AppStorage("autoLockEnabled") private var autoLockEnabled = false
    
    // MARK: - State
    @State private var showAuthError = false
    @ObservedObject private var lockManager = LockManager.shared
    
    var body: some View {
        ZStack {
            Form {
                Section("Bảo mật tài khoản") {
                    // Face ID / Touch ID Toggle
                    Toggle("Xác thực Face ID / Touch ID", isOn: Binding(
                        get: { useBiometricAuth },
                        set: { newValue in
                            if newValue {
                                authenticateUser()
                            } else {
                                useBiometricAuth = false
                            }
                        }
                    ))
                    .alert("Xác thực thất bại", isPresented: $showAuthError) {
                        Button("OK", role: .cancel) {}
                    }
                    
                    // Auto Lock Toggle
                    Toggle("Tự động khoá khi không hoạt động", isOn: $autoLockEnabled)
                }
            }
            .navigationTitle("Bảo mật")
            .onTapGesture {
                lockManager.userDidInteract()
            }
            
            // Overlay màn hình khóa nếu bị khóa
            if lockManager.isLocked {
                LockScreenView()
            }
        }
        .onAppear {
            lockManager.startTimer()
        }
    }
    
    // MARK: - Face ID / Touch ID xác thực
    private func authenticateUser() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Xác thực để bật Face ID / Touch ID"
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        useBiometricAuth = true
                    } else {
                        showAuthError = true
                    }
                }
            }
        } else {
            showAuthError = true
        }
    }
}

// MARK: - Lock Manager
class LockManager: ObservableObject {
    static let shared = LockManager()
    
    @Published var isLocked = false
    private var lastInteractionTime = Date()
    private var timer: Timer?
    
    private init() { }
    
    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            self.checkForInactivity()
        }
    }
    
    func userDidInteract() {
        lastInteractionTime = Date()
    }
    
    private func checkForInactivity() {
        let timeout: TimeInterval = 60 // thời gian tự động khóa (giây)
        if Date().timeIntervalSince(lastInteractionTime) > timeout,
           UserDefaults.standard.bool(forKey: "autoLockEnabled") {
            DispatchQueue.main.async {
                self.lock()
            }
        }
    }
    
    func lock() {
        if UserDefaults.standard.bool(forKey: "useBiometricAuth") {
            isLocked = true
        }
    }
    
    func unlock() {
        let context = LAContext()
        let reason = "Xác thực để mở khóa"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.isLocked = false
                    self.lastInteractionTime = Date()
                }
            }
        }
    }
}

// MARK: - Lock Screen View
struct LockScreenView: View {
    @ObservedObject var lockManager = LockManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            Text("Ứng dụng đã bị khóa")
                .font(.title3)
                .bold()
            Button("Mở khóa bằng Face ID / Touch ID") {
                lockManager.unlock()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        SecuritySettingsView()
    }
}


import SwiftUI
import FirebaseCore
import UserNotifications



class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        FirebaseApp.configure()
        
        // 1️⃣ Set delegate
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        
        // 2️⃣ Xin quyền notification
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async {
                    // 3️⃣ Đăng ký APNs token
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("❌ Xin quyền notification lỗi: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    // 4️⃣ Khi APNs token được cấp
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Set APNs token cho FCM
        Messaging.messaging().apnsToken = deviceToken
    }
    
    // 5️⃣ Nhận notification khi app foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
        
        func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
            print("FCM token: \(fcmToken ?? "")")
        }
        func application(_ app: UIApplication, open url: URL,
                           options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
              return GIDSignIn.sharedInstance.handle(url)
          }
        
    }
}

