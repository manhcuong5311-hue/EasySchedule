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
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.primary)
                .adaptiveTextOutline(
                    isDark: colorScheme == .dark,
                    lightOpacity: 0.25,
                    darkOpacity: 0.35
                )
                .shadow(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.15)
                        : Color.black.opacity(0.12),
                    radius: 1.5,
                    y: 1
                )


            Text(yearFormatter.string(from: date))
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(uiAccent.color)

                .adaptiveTextOutline(
                    isDark: colorScheme == .dark,
                    lightOpacity: 0.18,
                    darkOpacity: 0.3
                )
                .shadow(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.black.opacity(0.1),
                    radius: 1.5,
                    y: 1
                )



            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(uiAccent.color)
                .adaptiveTextOutline(
                    isDark: colorScheme == .dark,
                    lightOpacity: 0.15,
                    darkOpacity: 0.25
                )
                .shadow(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.1)
                        : Color.black.opacity(0.08),
                    radius: 1,
                    y: 1
                )



            Spacer()
        }
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
