//
//  HorizontalDayPickerView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct HorizontalDayPickerView: View {

    @Binding var selectedDate: Date
    @EnvironmentObject var eventManager: EventManager
    let maxSelectableDate: Date
    
    
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
                            withAnimation(.easeInOut) {
                                selectedDate = day
                            }
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
    

    
    var body: some View {
        VStack(spacing: 8) {

            Text(day.formatted(.dateTime.weekday(.short)))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(day.formatted(.dateTime.day()))
                .font(.headline.bold())
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: width, height: width)
                .background(
                    ZStack {
                        if isSelected {
                            Circle()
                                .fill(uiAccent.color)
                        } else if isOffDay {
                            Circle()
                                .fill(
                                    Color.primary.opacity(
                                        colorScheme == .dark ? 0.20 : 0.10
                                    )
                                )
                        } else if isPastDay {
                            Circle()
                                .fill(
                                    Color.primary.opacity(
                                        colorScheme == .dark ? 0.12 : 0.06
                                    )
                                )
                        }
                    }
                )
                .overlay {
                    if Calendar.current.isDateInToday(day) && !isSelected {
                        Circle()
                            .stroke(uiAccent.color, lineWidth: 1.5)
                    }
                }

                .overlay(
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
                )
                .overlay(alignment: .bottomTrailing) {
                    if isOffDay && !isSelected {
                        Image(systemName: "bed.double.fill")
                            .font(.caption)
                            .foregroundColor(uiAccent.color.opacity(0.8))
                            .offset(x: -2, y: -2)
                    }
                }


                .dayCellShadow(
                    scheme: colorScheme,
                    isSelected: isSelected
                )




            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.red)
                    .clipShape(Circle())
            } else if hasNew {
                Circle()
                    .fill(uiAccent.color)
                    .frame(width: 6, height: 6)
            }

        }
        .frame(width: width + 12)   // ⭐ tạo không gian thoáng trên iPad
        .padding(.vertical, 6)
        .opacity(
            (isPastDay || isOffDay) && !isSelected ? 0.45 : 1
        )
       
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

