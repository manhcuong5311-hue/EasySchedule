//
//  TimelineHourColumn.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/1/26.
//
import SwiftUI

struct TimelineHourColumn: View {

    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let hourStride: Int = 2

    var body: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(stride(from: startHour, to: endHour, by: hourStride)),
                id: \.self
            ) { hour in
                HStack(alignment: .top, spacing: 8) {

                    Text(
                        String(
                            format: "%02d:00–%02d:00",
                            hour,
                            min(hour + hourStride, endHour)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 2)

                    Spacer()
                }
                .frame(height: CGFloat(hourStride) * hourHeight)
            }
        }
    }
}
