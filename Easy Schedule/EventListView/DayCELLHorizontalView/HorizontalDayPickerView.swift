//
//  HorizontalDayPickerView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct DayCardHintBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HorizontalDayPickerView: View {

    @Binding var selectedDate: Date
    let maxSelectableDate: Date
    let onUserSelectDay: (Date) -> Void

    @EnvironmentObject var eventManager: EventManager
  
    
    
    var body: some View {
        GeometryReader { geo in
            let config = LayoutConfig(availableWidth: geo.size.width)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: config.spacing) {

                    ForEach(config.days(around: selectedDate), id: \.self) { day in
                        let key = Calendar.current.startOfDay(for: day)
                        let dayStart = Calendar.current.startOfDay(for: day)
                        let today = Calendar.current.startOfDay(for: Date())

                        let isPast = dayStart < today
                        let isOutOfRange = dayStart > maxSelectableDate
                        let isLocked = isPast || isOutOfRange

                        DayCell(
                            day: day,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),

                            isPastDay: isPast,
                            isOffDay: eventManager.isOffDay(day),
                            isLocked: isLocked,

                            unreadCount: eventManager.unreadCountByDay[key] ?? 0,
                            hasNew: eventManager.hasNewByDay[key] ?? false,
                            width: config.cellWidth
                        )

                        .opacity(isLocked ? 0.35 : 1)
                        .allowsHitTesting(!isLocked)
                        .onTapGesture {
                                                   guard !isLocked else { return }

                                                   withAnimation(.easeInOut) {
                                                       selectedDate = day
                                                   }

                                                   // 🔥 PHÁT INTENT DUY NHẤT
                                                   onUserSelectDay(day)
                                               }

                    }

                }
                .padding(.horizontal, config.horizontalPadding)
            }
        }
        .frame(height: 92)
    }

}


private struct LayoutConfig {

    let availableWidth: CGFloat

    let spacing: CGFloat = 14
    let horizontalPadding: CGFloat = 16

    var cellWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 64 : 44
    }

    private var cellTotalWidth: CGFloat {
        cellWidth + spacing
    }

    private var visibleCount: Int {
        max(7, Int((availableWidth - horizontalPadding * 2) / cellTotalWidth))
    }

    func days(around center: Date) -> [Date] {
        let calendar = Calendar.current
        let total = visibleCount

        let today = calendar.startOfDay(for: Date())
        let centerDay = calendar.startOfDay(for: center)

        // 🔑 Nếu user đang ở quá khứ → cân bằng hơn
        let isPastMode = centerDay < today

        let pastCount: Int
        if isPastMode {
            pastCount = total / 2        // cân bằng khi ở quá khứ
        } else {
            pastCount = 1                // GIỮ NGUYÊN hành vi hiện tại
        }

        let futureCount = total - pastCount - 1   // -1 cho center

        return (-pastCount...futureCount).compactMap {
            calendar.date(byAdding: .day, value: $0, to: center)
        }
    }


    
}


struct DayCell: View {

    let day: Date
    let isSelected: Bool
    let isPastDay: Bool
    let isOffDay: Bool
    let isLocked: Bool

    let unreadCount: Int
    let hasNew: Bool
    let width: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var uiAccent: UIAccentStore

    // MARK: - Layout constants
        private let hintSlotHeight: CGFloat = 10   // chỗ “ảo” cho hint

    var body: some View {
        VStack(spacing: 6) {

            weekdayLabel

            dayCircle

            // slot cố định cho hint (KHÔNG đẩy layout)
            Color.clear
                .frame(height: 10)
        }
        .frame(width: width + 12)
        .opacity(contentOpacity)
    }

    
   
    
}

private extension DayCell {
    var weekdayLabel: some View {
        Text(day.formatted(.dateTime.weekday(.short)))
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

private extension DayCell {

    var dayCircle: some View {
        ZStack {
            // ===== MAIN DAY CIRCLE =====
            Text(day.formatted(.dateTime.day()))
                .font(.headline.bold())
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: width, height: width)
                .background(circleBackground)
                .overlay(todayRing)
                .overlay(darkSelectedRing)
                .overlay(offDayIcon, alignment: .bottomTrailing)
                .dayCellShadow(
                    scheme: colorScheme,
                    isSelected: isSelected
                )
                // ⭐ NEO HINT Ở ĐÂY – KHÔNG DÙNG ZSTACK BÊN NGOÀI
                .overlay(alignment: .bottomTrailing) {
                    hintStack
                }
        }
    }
    
    @ViewBuilder
    var hintStack: some View {
        if unreadCount > 0 || hasNew {
            HStack(spacing: 0) {

                // ⬅️ UNREAD – BÊN TRÁI
                if unreadCount > 0 {
                    unreadBadge
                }

                Spacer(minLength: 0)

                // ➡️ NEW EVENT – BÊN PHẢI
                if hasNew {
                    newEventBadge
                }
            }
            .frame(width: width - 8)   // 👈 ép đúng bề rộng day
            .offset(y: 6)              // 👈 neo sát đáy circle
        }
    }


}

private extension DayCell {

    var unreadBadge: some View {
        Text("\(unreadCount)")
            .font(.caption2.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red,
                                Color.red.opacity(0.85)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            )
    }


    var newEventBadge: some View {
        Image(systemName: "sparkles")
            .font(.caption2)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        uiAccent.color,
                        uiAccent.color.opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .padding(4)
            .background(
                Circle()
                    .fill(uiAccent.color.opacity(0.18))
                    .shadow(color: uiAccent.color.opacity(0.4), radius: 4)
            )
    }

}


private extension DayCell {
    var circleBackground: some View {
        Group {
            if isSelected {
                Circle().fill(uiAccent.color)
            } else if isOffDay {
                Circle().fill(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10))
            } else if isPastDay {
                Circle().fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            }
        }
    }
}

private extension DayCell {
    var todayRing: some View {
        Group {
            if Calendar.current.isDateInToday(day) && !isSelected {
                Circle()
                    .stroke(uiAccent.color, lineWidth: 1.5)
            }
        }
    }
}

private extension DayCell {
    var darkSelectedRing: some View {
        Group {
            if isSelected && colorScheme == .dark {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
        }
    }
}

private extension DayCell {
    var offDayIcon: some View {
        Group {
            if isOffDay && !isSelected {
                Image(systemName: "bed.double.fill")
                    .font(.caption)
                    .foregroundColor(uiAccent.color.opacity(0.8))
                    .offset(x: -2, y: -2)
            }
        }
    }
}


private extension DayCell {
    var contentOpacity: Double {
        (isPastDay || isOffDay) && !isSelected ? 0.45 : 1
    }
}





struct DayStatusBadgeView: View {

    let unreadCount: Int
    let hasNew: Bool
    @EnvironmentObject var uiAccent: UIAccentStore
    
    
    private var text: String {
        if unreadCount > 0 && hasNew {
            return String(
                format: String(localized: "day_badge_new_with_count"),
                unreadCount
            )
        }
        if unreadCount > 0 {
            return "\(unreadCount)"
        }
        return String(localized: "day_badge_new")
    }


    private var backgroundColor: Color {
        unreadCount > 0 ? .red : uiAccent.color
    }


    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}

