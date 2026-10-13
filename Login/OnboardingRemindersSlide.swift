//
//  OnboardingRemindersSlide.swift
//  Easy Schedule
//
//  "Never be late": time-to-leave reminder, directions and one-tap quick
//  replies. New users are asked for notification permission HERE (in context)
//  instead of at launch — see AppDelegate / SessionStore.registerForPushIfNeeded.
//

import SwiftUI
import UIKit
import UserNotifications

struct OnboardingRemindersSlide: View {

    let onNext: () -> Void
    @Environment(\.colorScheme) private var scheme

    /// nil until the current notification settings are read.
    @State private var permission: UNAuthorizationStatus?
    @State private var isRequesting = false

    private var needsPermission: Bool { permission == .notDetermined }

    var body: some View {
        ZStack {

            LinearGradient(
                colors: scheme == .light
                    ? [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.08)
                      ]
                    : [
                        Color.onboardingDarkBackground,
                        Color.onboardingDarkBackground.opacity(0.85)
                      ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {

                Text(String(localized: "onboarding_reminders_title"))
                    .font(.system(size: 36, weight: .bold))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)

                Text(String(localized: "onboarding_reminders_subtitle"))
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 8)

                VStack(spacing: 18) {
                    LeaveReminderMockCard()

                    // Quick replies (same as the notification / Live Activity actions)
                    HStack(spacing: 10) {
                        OnboardingMockPill(
                            icon: "car.fill",
                            title: String(localized: "quick_on_my_way_button"),
                            prominent: true
                        )
                        OnboardingMockPill(
                            icon: "clock.badge.exclamationmark",
                            title: String(localized: "quick_late_button"),
                            prominent: false
                        )
                    }
                }

                Spacer(minLength: 8)

                buttons
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)       // clears the top-trailing "Skip"
            .padding(.bottom, 28)
        }
        .task { await refreshPermission() }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        if needsPermission {
            VStack(spacing: 10) {
                Button {
                    enableNotifications()
                } label: {
                    Text(String(localized: "onboarding_enable_notifications"))
                        .opacity(isRequesting ? 0 : 1)
                        .overlay {
                            if isRequesting { ProgressView().tint(.white) }
                        }
                        .onboardingCTALabel()
                }
                .disabled(isRequesting)

                Button {
                    onNext()
                } label: {
                    Text(String(localized: "onboarding_not_now"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .disabled(isRequesting)
            }
        } else {
            Button {
                onNext()
            } label: {
                Text(String(localized: "onboarding_next"))
                    .onboardingCTALabel()
            }
        }
    }

    // MARK: - Permission

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = settings.authorizationStatus
    }

    private func enableNotifications() {
        guard !isRequesting else { return }
        isRequesting = true

        NotificationManager.shared.requestPermissionIfNeeded(
            onDenied: {
                isRequesting = false
                permission = .denied
                onNext()
            },
            onGranted: {
                // Same as turning on "Notify before event" in Settings.
                UIApplication.shared.registerForRemoteNotifications()
                UserDefaults.standard.set(true, forKey: "pushNotificationsEnabled")
                PushPreferenceManager.enablePush()
                EventManager.shared.rescheduleLocalNotifications()

                isRequesting = false
                permission = .authorized
                onNext()
            }
        )
    }
}

// MARK: - Mocks

/// Notification-style "Time to leave" card with drive time and a Directions pill.
private struct LeaveReminderMockCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "leave_reminder_title"))
                        .font(.system(size: 16, weight: .semibold))

                    Text(verbatim: "\(String(localized: "onboarding_mock_event_title")) · \(OnboardingMock.time(14, 30))")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(format: String(localized: "onboarding_mock_leave_format"), OnboardingMock.time(14, 5)))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(scheme == .light ? 0.10 : 0.20))
            )

            OnboardingMockPill(
                icon: "arrow.triangle.turn.up.right.diamond.fill",
                title: String(localized: "location_directions"),
                prominent: false
            )
        }
        .padding(16)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    scheme == .light
                    ? Color.white
                    : Color.onboardingDarkCard
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            scheme == .light
                            ? Color(.systemGray4)
                            : Color.white.opacity(0.06)
                        )
                )
                .shadow(
                    color: Color.accentColor.opacity(scheme == .light ? 0.18 : 0.35),
                    radius: 14,
                    y: 8
                )
        )
    }
}

/// Small capsule used for mock actions (Directions, On my way, Running late).
struct OnboardingMockPill: View {
    @Environment(\.colorScheme) private var scheme

    let icon: String
    let title: String
    let prominent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundColor(prominent ? .white : Color.accentColor)
        .background(
            Capsule().fill(
                prominent
                ? Color.accentColor
                : (scheme == .light ? Color.white : Color.onboardingDarkCard)
            )
        )
        .overlay(
            Capsule().stroke(
                prominent ? Color.clear : Color.accentColor.opacity(0.6),
                lineWidth: 1
            )
        )
        .shadow(
            color: Color.black.opacity(scheme == .light ? 0.06 : 0.35),
            radius: 10,
            y: 5
        )
    }
}
