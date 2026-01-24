//
//  EmptyState.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 24/1/26.
//
import SwiftUI

struct OffDayEmptyStateView: View {

    let date: Date

    var body: some View {
        VStack(spacing: 16) {

            Image(systemName: "bed.double.fill")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text(String(localized: "off_day_title1"))
                .font(.title3.weight(.semibold))

            Text(String(localized: "off_day_description"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }
}
