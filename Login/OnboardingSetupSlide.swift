//
//  OnboardingSetupSlide.swift
//  Easy Schedule
//
//  "Set up in 30 seconds": display name + memorable booking link
//  (easyschedule-ce98a.web.app/c/<handle>) + default booking hours.
//  Claims the handle exactly like BookingLinkSheet (one WriteBatch).
//  Errors show inline and never block — "Skip" always advances.
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct OnboardingSetupSlide: View {

    let onNext: () -> Void

    @EnvironmentObject private var session: SessionStore
    @Environment(\.colorScheme) private var scheme

    private enum HandleStatus: Equatable {
        case idle        // empty field / typing
        case invalid
        case checking
        case taken       // reserved or used by someone else
        case available
        case unverified  // check failed (offline / rules) — Save re-checks
        case current     // already my saved handle
    }

    private enum Field { case name, handle }

    @State private var name = ""
    /// Last value written programmatically (prefill) — anything else is a user edit.
    @State private var autoName = ""
    @State private var nameEdited = false

    @State private var handle = ""
    @State private var autoHandle = ""
    @State private var handleEdited = false
    @State private var currentHandle: String?
    @State private var status: HandleStatus = .idle
    @State private var checkTask: Task<Void, Never>?
    @State private var suggestionRetries = 0

    @State private var acceptBookings = true
    @State private var hoursSaved = false

    @State private var didLoad = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var savedURL: URL?
    @State private var copied = false

    @FocusState private var focused: Field?

    private var canSave: Bool {
        guard !isSaving, !isLoading else { return false }
        if handle.isEmpty { return true }   // name / hours only
        switch status {
        case .available, .unverified, .current: return true
        default: return false
        }
    }

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
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {

                ScrollView {
                    VStack(spacing: 18) {

                        VStack(spacing: 10) {
                            Text(String(localized: "onboarding_setup_title"))
                                .font(.system(size: 34, weight: .bold))
                                .tracking(-0.8)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.75)

                            Text(String(localized: "onboarding_setup_subtitle"))
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom, 4)

                        if let savedURL {
                            successCard(savedURL)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            formCard
                        }

                        if let errorText {
                            Label(errorText, systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)

                buttons
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .task { await loadOnce() }
        .onChange(of: session.currentUserName) { _, _ in
            prefillName()
        }
        .onChange(of: name) { _, newValue in
            if newValue != autoName { nameEdited = true }
            suggestHandleIfUntouched()
        }
        .onChange(of: handle) { _, newValue in
            let clean = BookingLink.sanitize(newValue)
            if clean != newValue {
                handle = clean      // re-enters onChange with the clean value
                return
            }
            if newValue != autoHandle { handleEdited = true }
            scheduleCheck()
        }
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Display name
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(String(localized: "display_name"), icon: "person.crop.circle")

                TextField("", text: $name, prompt: Text(String(localized: "name_placeholder")))
                    .font(.system(size: 16))
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused($focused, equals: .name)
                    .onSubmit { focused = .handle }
                    .disabled(isSaving)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(fieldBackground(border: focused == .name ? Color.accentColor.opacity(0.5) : .clear))
            }

            // Booking link
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(String(localized: "booking_link_title"), icon: "link")

                HStack(spacing: 0) {
                    Text(verbatim: BookingLink.handlePrefix)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)

                    TextField("", text: $handle, prompt: Text(verbatim: String(localized: "onboarding_mock_handle")))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused, equals: .handle)
                        .onSubmit { if canSave { Task { await save() } } }
                        .frame(minWidth: 80)
                        .disabled(isSaving)

                    if isLoading || status == .checking {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 6)
                    }
                }
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(fieldBackground(border: handleBorderColor))
                .contentShape(Rectangle())
                .onTapGesture { focused = .handle }

                statusRow
                    .animation(.easeInOut(duration: 0.15), value: status)
            }

            Divider()

            // Default booking hours
            Toggle(isOn: $acceptBookings) {
                HStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.accentColor)
                    Text(String(localized: "onboarding_booking_hours_toggle"))
                        .font(.system(size: 15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accentColor)
            .disabled(isSaving)
        }
        .padding(16)
        .background(cardBackground)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch status {
        case .idle:
            hint(String(localized: "booking_link_invalid"), icon: "info.circle", color: .secondary)
        case .invalid:
            hint(String(localized: "booking_link_invalid"), icon: "exclamationmark.circle.fill", color: .orange)
        case .taken:
            hint(String(localized: "booking_link_taken"), icon: "xmark.circle.fill", color: .red)
        case .available, .current:
            hint(String(localized: "booking_link_available"), icon: "checkmark.circle.fill", color: .green)
        case .checking, .unverified:
            hint(String(localized: "booking_link_invalid"), icon: "info.circle", color: .secondary)
                .hidden()
        }
    }

    private func hint(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(color)
    }

    private func fieldLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private var handleBorderColor: Color {
        switch status {
        case .invalid: return .orange.opacity(0.6)
        case .taken: return .red.opacity(0.6)
        case .available: return .green.opacity(0.6)
        default: return focused == .handle ? Color.accentColor.opacity(0.5) : .clear
        }
    }

    private func fieldBackground(border: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                scheme == .light
                ? Color(.secondarySystemBackground)
                : Color.white.opacity(0.06)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(
                scheme == .light
                ? Color.white
                : Color.onboardingDarkCard
            )
            .shadow(
                color: Color.black.opacity(scheme == .light ? 0.06 : 0.35),
                radius: 12,
                y: 6
            )
    }

    // MARK: - Success

    private func successCard(_ url: URL) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)

            Text(String(localized: "onboarding_setup_done"))
                .font(.system(size: 17, weight: .semibold))

            Text(verbatim: url.absoluteString)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.accentColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)

            Button {
                copy(url)
            } label: {
                Label(
                    copied ? String(localized: "copied") : String(localized: "copy"),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(Color.accentColor.opacity(scheme == .light ? 0.12 : 0.22))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if let savedURL {
                ShareLink(item: savedURL) {
                    Label(String(localized: "onboarding_share_link"), systemImage: "square.and.arrow.up")
                        .onboardingCTALabel()
                }

                Button {
                    onNext()
                } label: {
                    secondaryLabel(String(localized: "onboarding_next"))
                }
            } else {
                Button {
                    Task { await save() }
                } label: {
                    Text(String(localized: "onboarding_setup_save"))
                        .opacity(isSaving ? 0 : 1)
                        .overlay {
                            if isSaving { ProgressView().tint(.white) }
                        }
                        .onboardingCTALabel()
                        .opacity(canSave || isSaving ? 1 : 0.5)
                }
                .disabled(!canSave)

                // Always enabled: offline Firestore writes only finish once the
                // server acks them, so a pending save must never trap the user.
                Button {
                    checkTask?.cancel()
                    focused = nil
                    onNext()
                } label: {
                    secondaryLabel(String(localized: "onboarding_skip_setup"))
                }
            }
        }
    }

    private func secondaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Load / prefill

    private func loadOnce() async {
        guard !didLoad else { return }
        didLoad = true
        defer {
            isLoading = false
            scheduleCheck()
        }

        prefillName()

        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Cached handle first (instant), then confirm with Firestore.
        if let cached = BookingLink.cachedHandle {
            currentHandle = cached
            if !handleEdited { setHandle(cached) }
        } else {
            suggestHandleIfUntouched()
        }

        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument()
            if let saved = snap.data()?["handle"] as? String, BookingLink.isValid(saved) {
                BookingLink.store(handle: saved, uid: uid)
                currentHandle = saved
                if !handleEdited { setHandle(saved) }
            } else {
                currentHandle = nil
                suggestHandleIfUntouched()
            }
        } catch {
            // Offline etc. — keep the cached / suggested value.
        }
    }

    /// Fills the name from the session until the user types their own.
    private func prefillName() {
        guard !nameEdited else { return }
        let value = session.hasRealName ? session.currentUserName : ""
        guard value != name else { return }
        autoName = value
        name = value
    }

    private func setHandle(_ value: String) {
        autoHandle = value
        handle = value
    }

    /// Keeps the handle in sync with the name while the user hasn't touched it
    /// and has no saved handle yet.
    private func suggestHandleIfUntouched() {
        guard !handleEdited, currentHandle == nil, savedURL == nil else { return }
        let suggestion = Self.suggestedHandle(from: name)
        guard suggestion != handle else { return }
        suggestionRetries = 0
        setHandle(suggestion)
    }

    /// "Sâm Mạnh Cường" → "sam-manh-cuong": lowercase, no diacritics, đ→d,
    /// spaces→'-', only [a-z0-9-], 3–30 chars. Short / reserved names get digits.
    static func suggestedHandle(from name: String) -> String {
        let dashed = name.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        var s = BookingLink.sanitize(dashed)
        while s.contains("--") {
            s = s.replacingOccurrences(of: "--", with: "-")
        }
        s = trimDashes(String(trimDashes(s).prefix(30)))
        guard !s.isEmpty else { return "" }

        if s.count < 3 || BookingLink.reserved.contains(s) {
            s = trimDashes(String(s.prefix(26))) + "\(Int.random(in: 100...999))"
        }
        return BookingLink.isValid(s) ? s : ""
    }

    private static func trimDashes(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    // MARK: - Availability check (debounced, same rules as BookingLinkSheet)

    private func scheduleCheck() {
        checkTask?.cancel()
        let value = handle

        if value.isEmpty { status = .idle; return }
        if value == currentHandle { status = .current; return }
        guard BookingLink.isValid(value) else {
            // Neutral hint while typing; turn orange after the pause.
            status = .idle
            checkTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, handle == value else { return }
                status = .invalid
            }
            return
        }
        if BookingLink.reserved.contains(value) { status = .taken; return }

        status = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result: HandleStatus
            do {
                result = try await Self.isFree(value) ? .available : .taken
            } catch {
                result = .unverified
            }
            guard !Task.isCancelled, handle == value else { return }
            status = result
            if result == .taken { retrySuggestion(after: value) }
        }
    }

    /// The auto-suggested handle is taken → try "<name>-<2 digits>" (twice max).
    private func retrySuggestion(after taken: String) {
        guard !handleEdited, taken == autoHandle, currentHandle == nil,
              suggestionRetries < 2 else { return }
        suggestionRetries += 1
        let base = Self.trimDashes(String(taken.prefix(26)))
        let candidate = "\(base)-\(Int.random(in: 10...99))"
        if BookingLink.isValid(candidate) { setHandle(candidate) }
    }

    /// true when handles/{handle} does not exist or already belongs to me.
    private static func isFree(_ handle: String) async throws -> Bool {
        let snap = try await Firestore.firestore()
            .collection("handles").document(handle)
            .getDocument(source: .server)
        guard snap.exists else { return true }
        return (snap.data()?["uid"] as? String) == Auth.auth().currentUser?.uid
    }

    // MARK: - Save

    private func save() async {
        guard !isSaving else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            errorText = String(localized: "login_required")
            return
        }

        checkTask?.cancel()
        focused = nil
        errorText = nil
        isSaving = true
        defer { isSaving = false }

        var firstError: String?

        // 1) Display name (only when changed)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != session.currentUserName {
            let ok = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                session.updateUserName(trimmedName) { ok in
                    continuation.resume(returning: ok)
                }
            }
            if !ok { firstError = firstError ?? String(localized: "proposal_save_failed") }
        }

        // 2) Booking link handle
        var linkHandle: String? = nil
        let newHandle = handle
        if !newHandle.isEmpty {
            if !BookingLink.isValid(newHandle) {
                status = .invalid
                firstError = firstError ?? String(localized: "booking_link_invalid")
            } else if BookingLink.reserved.contains(newHandle) {
                status = .taken
                firstError = firstError ?? String(localized: "booking_link_taken")
            } else if newHandle == currentHandle {
                BookingLink.store(handle: newHandle, uid: uid)
                linkHandle = newHandle
            } else {
                do {
                    if try await claim(newHandle, uid: uid) {
                        linkHandle = newHandle
                    } else {
                        status = .taken
                        firstError = firstError ?? String(localized: "booking_link_taken")
                    }
                } catch {
                    firstError = firstError ?? error.localizedDescription
                }
            }
        }

        // 3) Default booking hours — never overwrite hours the user already set.
        if acceptBookings, !hoursSaved {
            do {
                if await EventManager.shared.fetchMyBookingHours() == nil {
                    let hours = BookingHours.defaultHours
                    try await EventManager.shared.saveMyBookingHours(hours)
                    AppAnalytics.log(AppAnalyticsEvent.bookingHoursSaved,
                                     ["enabled": hours.enabled,
                                      "days": hours.days.count,
                                      "buffer": hours.bufferMin,
                                      "max_per_day": hours.maxPerDay,
                                      "source": "onboarding"])
                }
                hoursSaved = true
            } catch {
                firstError = firstError ?? error.localizedDescription
            }
        }

        if let firstError {
            errorText = firstError
            return
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.25)) {
            savedURL = linkHandle.map { BookingLink.url(forHandle: $0) } ?? BookingLink.url(for: uid)
        }
    }

    /// One WriteBatch, same as BookingLinkSheet.save():
    /// create handles/{h} (unless already mine) + users/{me}.handle + delete the old handle doc.
    /// Returns false when the handle belongs to someone else.
    private func claim(_ newHandle: String, uid: String) async throws -> Bool {
        let db = Firestore.firestore()
        let newRef = db.collection("handles").document(newHandle)

        let snap = try await newRef.getDocument(source: .server)
        var alreadyMine = false
        if snap.exists {
            guard (snap.data()?["uid"] as? String) == uid else { return false }
            alreadyMine = true      // leftover doc of mine — rules forbid update, so don't rewrite it
        }

        let batch = db.batch()
        if !alreadyMine {
            batch.setData(
                ["uid": uid, "createdAt": FieldValue.serverTimestamp()],
                forDocument: newRef
            )
        }
        batch.setData(
            ["handle": newHandle],
            forDocument: db.collection("users").document(uid),
            merge: true
        )
        if let old = currentHandle, old != newHandle {
            batch.deleteDocument(db.collection("handles").document(old))
        }
        try await batch.commit()
        AppAnalytics.log(AppAnalyticsEvent.bookingLinkSet, ["source": "onboarding"])

        BookingLink.store(handle: newHandle, uid: uid)
        currentHandle = newHandle
        status = .current
        return true
    }

    private func copy(_ url: URL) {
        UIPasteboard.general.string = url.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copied = false }
        }
    }
}
