//
//  OfflineBannerView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 6/1/26.
//

import SwiftUI

struct OfflineBannerView: View {

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            Image(systemName: "wifi.slash")
                .foregroundColor(.red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {

                Text(String(localized: "offline_banner_title"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)

                Text(String(localized: "offline_banner_message"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
