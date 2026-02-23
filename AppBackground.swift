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
