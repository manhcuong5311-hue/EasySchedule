import SwiftUI

struct MonthHeaderPositionKey: PreferenceKey {
    static var defaultValue: [Date: CGFloat] = [:]

    static func reduce(
        value: inout [Date: CGFloat],
        nextValue: () -> [Date: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct BigDateHeaderView: View {
    let date: Date
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var uiAccent: UIAccentStore
    
    
    
    
    
    
    private var dayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "d MMMM"
        return f
    }

    private var yearFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {

            Text(dayFormatter.string(from: date))
                .foregroundColor(.primary)

            Text(yearFormatter.string(from: date))
                .foregroundColor(uiAccent.color)

            Image(systemName: "chevron.right")
                .foregroundColor(uiAccent.color.opacity(0.85))

            Spacer()
        }
        .font(.system(size: 36, weight: .bold, design: .rounded))
        .modifier(TitleShadow.primary(colorScheme))   // ⭐ GẮN Ở ĐÂY
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)

    }
}

extension View {
    func adaptiveTextOutline(
        isDark: Bool,
        lightOpacity: Double,
        darkOpacity: Double
    ) -> some View {
        self
            .overlay(
                self
                    .foregroundColor(
                        isDark
                            ? Color.white.opacity(darkOpacity)
                            : Color.black.opacity(lightOpacity)
                    )
                    .blur(radius: 0.6)
            )
    }
}
