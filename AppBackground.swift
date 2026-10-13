import SwiftUI

enum AppBackground {

    /// Background chính cho Settings / EventList (Structured style)
    static func settings(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 245/255, green: 246/255, blue: 247/255) // xám lạnh
        case .dark:
            return Color(red: 18/255, green: 18/255, blue: 20/255)
        @unknown default:
            return Color(.systemGroupedBackground)
        }
    }


    /// Surface trắng cho panel / card lớn
    static func card(_ scheme: ColorScheme) -> Color {
        switch scheme {

        case .light:
            // Trắng hơi xám → không chói
            return Color(
                red: 255 / 255,
                green: 255 / 255,
                blue: 255 / 255
            )

        case .dark:
            // Dark surface – nhô lên nền graphite
            return Color(
                red: 32 / 255,
                green: 32 / 255,
                blue: 36 / 255
            )

        @unknown default:
            return Color(.secondarySystemGroupedBackground)
        }
    }

    /// Shadow CHUẨN cho panel (không dùng cho button)
    static func panelShadow(_ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.45 : 0.14)
    }
}

/// Bo góc dùng chung — thay cho ~19 giá trị rải rác trước đây.
enum AppRadius {
    /// Thẻ / nhóm nội dung (card)
    static let card: CGFloat = 16
    /// Panel lớn (form Thêm lịch)
    static let panel: CGFloat = 20
    /// Ô nhập, nút lớn
    static let control: CGFloat = 12
    /// Chip, ô giờ, nút nhỏ
    static let chip: CGFloat = 10
}
