import SwiftUI
import Combine

/// Quản lý ngôn ngữ toàn app
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    // Lưu ngôn ngữ đã chọn vào UserDefaults
    @AppStorage("selectedLanguage") var selectedLanguage: String = Locale.current.language.languageCode?.identifier ?? "vi" {
        didSet {
            applyLanguage(selectedLanguage)
        }
    }
    
    // Tên ngôn ngữ hiển thị (Tiếng Việt / English)
    @Published var currentLanguageName: String = "Tiếng Việt"
    
    private init() {
        applyLanguage(selectedLanguage)
    }
    
    /// Cập nhật ngôn ngữ Bundle và currentLanguageName
    func applyLanguage(_ code: String) {
        var languageName = "Tiếng Việt"
        switch code {
        case "en":
            Bundle.setLanguage("en")
            languageName = "English"
        default:
            Bundle.setLanguage("vi")
            languageName = "Tiếng Việt"
        }
        
        DispatchQueue.main.async {
            self.currentLanguageName = languageName
            self.objectWillChange.send()
        }
    }
    
    /// Hàm tiện để SettingsView gọi khi chọn ngôn ngữ
    func setLanguage(_ code: String) {
        selectedLanguage = code
    }
}
import Foundation

private var bundleKey: UInt8 = 0

final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            return path.localizedString(forKey: key, value: value, table: tableName)
        } else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}

extension Bundle {
    class func setLanguage(_ language: String) {
        defer { object_setClass(Bundle.main, LanguageBundle.self) }
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let langBundle = Bundle(path: path)
        else { return }
        objc_setAssociatedObject(Bundle.main, &bundleKey, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
