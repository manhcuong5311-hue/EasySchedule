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
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var showEmptyAlert = false

    var body: some View {
        VStack(spacing: 20) {

            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(uiAccent.color.gradient)
                )
                .padding(.top, 24)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(String(localized: "name_setup_title"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(String(localized: "name_setup_message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(AppBackground.card(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                Button(action: save) {
                    ZStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(String(localized: "save"))
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                            .fill(uiAccent.color.opacity(network.isOnline ? 1 : 0.4))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!network.isOnline || isSaving)

                Button(String(localized: "name_setup_later")) {
                    dismiss()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(height: 36)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground.settings(colorScheme).ignoresSafeArea())
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
