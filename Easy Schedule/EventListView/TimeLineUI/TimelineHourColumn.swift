//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
import SwiftUI

struct TimelineHourColumn: View {

    let startHour: Int
    let endHour: Int
    let timeFontSize: Double   // ⭐ ADD

    private var hourFontSize: CGFloat {
        CGFloat(max(10, timeFontSize - 2)) // ⭐ clamp an toàn
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(spacing: 6) {

                    // ⏱ TIME LABEL
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: timeFontSize, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(
                            width: TimelineLayout.hourLabelWidth,
                            alignment: .trailing
                        )

                    // │ SPINE
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                }
                // ⭐ CĂN TRÁI TUYỆT ĐỐI
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: TimelineLayout.hourHeight)
            }
        }
    }
}
