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

    
    var body: some View {
        GeometryReader { geo in
            let config = LayoutConfig(availableWidth: geo.size.width)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: config.spacing) {
                    ForEach(config.days(around: selectedDate), id: \.self) { day in
                        DayCell(
                            day: day,
                            isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                            unreadCount: eventManager.unreadCount(for: day),
                            hasNew: eventManager.hasNewEvent(for: day),
                            width: config.cellWidth
                        )

                        .onTapGesture {
                            withAnimation(.easeInOut) {
                                selectedDate = day
                            }

                            if eventManager.hasNewEvent(for: day) {
                                let ids = eventManager.events(for: day).map { $0.id }
                                EventSeenStore.shared.markSeen(eventIds: ids)
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
        let half = visibleCount / 2
        let calendar = Calendar.current

        return (-half...half).compactMap {
            calendar.date(byAdding: .day, value: $0, to: center)
        }
    }
}


struct DayCell: View {
    let day: Date
      let isSelected: Bool
      let unreadCount: Int
      let hasNew: Bool
      let width: CGFloat

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
                                .fill(Color.orange)
                                .shadow(
                                    color: Color.black.opacity(0.25),
                                    radius: 6,
                                    y: 4
                                )
                                .shadow(
                                    color: Color.black.opacity(0.08),
                                    radius: 2,
                                    y: 1
                                )
                        } else {
                            Circle()
                                .fill(Color.clear)
                        }
                    }
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
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

        }
        .frame(width: width + 12)   // ⭐ tạo không gian thoáng trên iPad
        .padding(.vertical, 6)
    }
}

struct DayStatusBadgeView: View {

    let unreadCount: Int
    let hasNew: Bool

    private var text: String {
        if unreadCount > 0 && hasNew {
            return "NEW · \(unreadCount)"
        }
        if unreadCount > 0 {
            return "\(unreadCount)"
        }
        return "NEW"
    }

    private var backgroundColor: Color {
        unreadCount > 0 ? .red : .orange
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

