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
    @Binding var isExpanded: Bool
    let onTap: (() -> Void)?
    
    
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
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded = true
            }
            onTap?()
        } label: {

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                
                Text(dayFormatter.string(from: date))
                    .foregroundColor(.primary)
                
                Text(yearFormatter.string(from: date))
                    .foregroundColor(uiAccent.color)
                
                Image(systemName: "chevron.right")
                    .foregroundColor(uiAccent.color.opacity(0.85))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))   // ⭐ xoay xuống
                    .animation(.easeInOut(duration: 0.25), value: isExpanded)

                
                Spacer()
            }
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .lineSpacing(0)
            .compositingGroup()
            .modifier(TitleShadow.primary(colorScheme))
   // ⭐ GẮN Ở ĐÂY
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)
            
        }
        .buttonStyle(.plain)
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
