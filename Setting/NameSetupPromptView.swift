//
//  NameSetupPromptView.swift
//  Easy Schedule
//
//  One-time nudge shown when a freshly-created account has no display name yet.
//  Without a name, partners see the "No name" placeholder (or a raw UID) when
//  scheduling together — this lets the user set a real name in one tap.
//

import SwiftUI

struct NameSetupPromptView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var showEmptyAlert = false

    var body: some View {
        VStack(spacing: 20) {

            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(uiAccent.color.gradient)
                .padding(.top, 28)

            VStack(spacing: 8) {
                Text(String(localized: "name_setup_title"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(String(localized: "name_setup_message"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            if !network.isOnline {
                OfflineBannerView()
                    .padding(.horizontal, 24)
            }

            TextField(String(localized: "display_name"), text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button(action: save) {
                    Text(String(localized: "save"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(uiAccent.color)
                .disabled(!network.isOnline || isSaving)

                Button(String(localized: "name_setup_later")) {
                    dismiss()
                }
                .font(.subheadline)
                .tint(.secondary)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .alert(
            String(localized: "invalid_name"),
            isPresented: $showEmptyAlert
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "name_cannot_be_empty"))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showEmptyAlert = true
            return
        }
        guard network.isOnline, !isSaving else { return }

        isSaving = true
        session.updateUserName(trimmed) { ok in
            isSaving = false
            if ok { dismiss() }
        }
    }
}
