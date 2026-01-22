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
                .shadow(
                    color: Color.primary.opacity(
                        colorScheme == .dark ? 0.25 : 0.12
                    ),
                    radius: 1.5,
                    y: 1
                )

            Text(yearFormatter.string(from: date))
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.orange)
                .shadow(
                    color: Color.primary.opacity(
                        colorScheme == .dark ? 0.18 : 0.1
                    ),
                    radius: 1.5,
                    y: 1
                )

            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.orange)
                .shadow(
                    color: Color.primary.opacity(
                        colorScheme == .dark ? 0.15 : 0.08
                    ),
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
