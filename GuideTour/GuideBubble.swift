//
//  Untitled.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 7/1/26.
//

import SwiftUI
struct GuideBubble: View {

    let textKey: LocalizedStringKey
    let onNext: () -> Void
    let onDoNotShowAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text(textKey)
                .font(.callout)
                .multilineTextAlignment(.leading)

            HStack {
                Button(String(localized: "guide_do_not_show_again")) {
                    onDoNotShowAgain()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()

                Button(String(localized: "guide_got_it")) {
                    onNext()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }
}
