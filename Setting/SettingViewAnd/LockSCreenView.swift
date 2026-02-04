//
//  LockSCreenView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 4/2/26.
//
import SwiftUI

// MARK: - Lock Screen View
struct LockScreenView: View {
    @ObservedObject var lockManager = LockManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text(String(localized: "app_locked"))
                .font(.title3)
                .bold()

            Button(String(localized: "unlock_button")) {
                lockManager.unlock()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea()   // 👈 BẮT BUỘC
    }
}
