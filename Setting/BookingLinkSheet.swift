//
//  BookingLinkSheet.swift
//  Easy Schedule
//
//  Memorable booking link: easyschedule-ce98a.web.app/c/<handle>
//  (the old /calendar/<uid> link keeps working).
//
//  Firestore:
//    handles/{handle} = { uid, createdAt }   — public read, create-only, owner delete
//    users/{uid}.handle = current handle
//

import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - BookingLink

enum BookingLink {

    static let host = "easyschedule-ce98a.web.app"
    /// Shown in front of the text field.
    static let handlePrefix = "easyschedule-ce98a.web.app/c/"

    private static let handleKey = "booking_handle"
    /// Owner uid of the cached handle — so a handle never leaks to another account on the same device.
    private static let ownerKey = "booking_handle_uid"

    static let reserved: Set<String> = [
        "calendar", "c", "admin", "api", "app", "login", "signin", "support",
        "help", "easyschedule", "about", "privacy", "terms", "www", "settings",
    ]

    /// Public booking URL: /c/<handle> when a handle is cached for this uid, otherwise /calendar/<uid>.
    static func url(for uid: String) -> URL {
        if let handle = cachedHandle(owner: uid),
           let url = URL(string: "https://\(host)/c/\(handle)") {
            return url
        }
        return URL(string: "https://\(host)/calendar/\(uid)")
            ?? URL(string: "https://\(host)")!
    }

    static func url(forHandle handle: String) -> URL {
        URL(string: "https://\(host)/c/\(handle)") ?? URL(string: "https://\(host)")!
    }

    /// Cached handle of the signed-in user (nil if none / other account).
    static var cachedHandle: String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return cachedHandle(owner: uid)
    }

    /// Reads users/{me}.handle once and mirrors it into UserDefaults (removes it when absent).
    /// Network / permission errors leave the cache untouched.
    static func refreshCachedHandle() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument()
            if let handle = snap.data()?["handle"] as? String, isValid(handle) {
                store(handle: handle, uid: uid)
            } else {
                clearCache()
            }
        } catch {
            // keep whatever we had
        }
    }

    // MARK: Validation

    /// ^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$
    static func isValid(_ handle: String) -> Bool {
        guard (3...30).contains(handle.count),
              handle.first != "-", handle.last != "-" else { return false }
        return handle.allSatisfy { isAllowed($0) }
    }

    /// Lowercases, folds diacritics (Cường → cuong), drops spaces / invalid characters, max 30.
    /// A pasted full link (…/c/<handle>) keeps only the handle part.
    static func sanitize(_ raw: String) -> String {
        var s = raw
        if let r = s.range(of: "/c/", options: .backwards) {
            s = String(s[r.upperBound...])
        }
        s = s.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        return String(String(s.filter { isAllowed($0) }).prefix(30))
    }

    private static func isAllowed(_ c: Character) -> Bool {
        c.isASCII && (c.isLowercase || c.isNumber || c == "-")
    }

    // MARK: Cache

    static func store(handle: String, uid: String) {
        let d = UserDefaults.standard
        d.set(handle, forKey: handleKey)
        d.set(uid, forKey: ownerKey)
    }

    static func clearCache() {
        let d = UserDefaults.standard
        d.removeObject(forKey: handleKey)
        d.removeObject(forKey: ownerKey)
    }

    private static func cachedHandle(owner uid: String) -> String? {
        let d = UserDefaults.standard
        guard d.string(forKey: ownerKey) == uid,
              let handle = d.string(forKey: handleKey),
              isValid(handle) else { return nil }
        return handle
    }
}

// MARK: - BookingLinkSheet

struct BookingLinkSheet: View {

    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private enum Status: Equatable {
        case idle        // empty field
        case invalid
        case checking
        case taken       // reserved or used by someone else
        case available
        case unverified  // check failed (offline / rules) — Save re-checks
        case current     // same as the saved handle
    }

    @State private var input = ""
    @State private var currentHandle: String?
    @State private var status: Status = .idle
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var checkTask: Task<Void, Never>?
    @State private var copied = false
    @State private var confirmRemove = false
    @State private var errorMessage: String?

    @FocusState private var fieldFocused: Bool

    private var canSave: Bool {
        !isLoading && !isSaving && (status == .available || status == .unverified)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    editorCard

                    if let handle = currentHandle {
                        linkCard(handle)
                        removeButton
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground.settings(colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "booking_link_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task { await load() }
            .onChange(of: input) { _, newValue in
                let clean = BookingLink.sanitize(newValue)
                if clean != newValue {
                    input = clean   // re-enters onChange with the clean value
                    return
                }
                scheduleCheck()
            }
            .onDisappear { checkTask?.cancel() }
            .confirmationDialog(
                String(localized: "booking_link_remove"),
                isPresented: $confirmRemove,
                titleVisibility: .hidden
            ) {
                Button(String(localized: "booking_link_remove"), role: .destructive) {
                    Task { await removeHandle() }
                }
                Button(String(localized: "cancel"), role: .cancel) {}
            }
            .alert(
                String(localized: "error_title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(String(localized: "ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(uiAccent.color)
    }

    // MARK: - Editor

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "share_calendar_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Text(verbatim: BookingLink.handlePrefix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                TextField("", text: $input, prompt: Text(String(localized: "booking_link_placeholder")))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit { if canSave { Task { await save() } } }
                    .frame(minWidth: 90)
                    .disabled(isLoading || isSaving)

                if isLoading || status == .checking {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 6)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(AppBackground.settings(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .stroke(fieldBorderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = true }

            statusRow
                .animation(.easeInOut(duration: 0.15), value: status)

            Button {
                Task { await save() }
            } label: {
                ZStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(String(localized: "save"))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(uiAccent.color.opacity(canSave || isSaving ? 1 : 0.4))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
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
        case .available:
            hint(String(localized: "booking_link_available"), icon: "checkmark.circle.fill", color: .green)
        case .checking, .unverified, .current:
            hint(String(localized: "booking_link_invalid"), icon: "info.circle", color: .secondary)
                .hidden()
        }
    }

    private func hint(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
    }

    private var fieldBorderColor: Color {
        switch status {
        case .invalid: return .orange.opacity(0.6)
        case .taken: return .red.opacity(0.6)
        case .available: return .green.opacity(0.6)
        default: return fieldFocused ? uiAccent.color.opacity(0.5) : .clear
        }
    }

    // MARK: - Current link

    private func linkCard(_ handle: String) -> some View {
        let url = BookingLink.url(forHandle: handle)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                        .fill(uiAccent.color.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "link")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(uiAccent.color)
                }
                Text(verbatim: url.absoluteString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    copy(url)
                } label: {
                    actionLabel(
                        copied ? String(localized: "copied") : String(localized: "copy"),
                        icon: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: url) {
                    actionLabel(String(localized: "partner.share_code_short"), icon: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(uiAccent.color)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .fill(uiAccent.color.opacity(0.12))
            )
            .contentShape(Rectangle())
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            confirmRemove = true
        } label: {
            Label(String(localized: "booking_link_remove"), systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(cardBackground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(AppBackground.card(colorScheme))
    }

    // MARK: - Actions

    private func load() async {
        defer { isLoading = false }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Show the cached value instantly, then confirm with Firestore.
        if let cached = BookingLink.cachedHandle {
            currentHandle = cached
            if input.isEmpty { input = cached }
        }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument()
            if let handle = snap.data()?["handle"] as? String, BookingLink.isValid(handle) {
                BookingLink.store(handle: handle, uid: uid)
                let editedByUser = !input.isEmpty && input != currentHandle
                currentHandle = handle
                if !editedByUser { input = handle }
            } else {
                BookingLink.clearCache()
                if input == currentHandle { input = "" }
                currentHandle = nil
            }
            scheduleCheck()
        } catch {
            // Offline etc. — keep the cached state silently.
        }
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        let handle = input

        if handle.isEmpty { status = .idle; return }
        if handle == currentHandle { status = .current; return }
        guard BookingLink.isValid(handle) else {
            // Neutral hint while typing ("my-" → "my-name"); turn orange after the pause.
            status = .idle
            checkTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, input == handle else { return }
                status = .invalid
            }
            return
        }
        if BookingLink.reserved.contains(handle) { status = .taken; return }

        status = .checking
        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let result: Status
            do {
                result = try await isFree(handle) ? .available : .taken
            } catch {
                result = .unverified
            }
            guard !Task.isCancelled, input == handle else { return }
            status = result
        }
    }

    /// true when handles/{handle} does not exist or already belongs to me.
    private func isFree(_ handle: String) async throws -> Bool {
        let snap = try await Firestore.firestore()
            .collection("handles").document(handle)
            .getDocument(source: .server)
        guard snap.exists else { return true }
        return (snap.data()?["uid"] as? String) == Auth.auth().currentUser?.uid
    }

    private func save() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let newHandle = input
        guard BookingLink.isValid(newHandle), newHandle != currentHandle else { return }
        guard !BookingLink.reserved.contains(newHandle) else { status = .taken; return }

        checkTask?.cancel()
        fieldFocused = false
        isSaving = true
        defer { isSaving = false }

        let db = Firestore.firestore()
        let newRef = db.collection("handles").document(newHandle)
        do {
            let snap = try await newRef.getDocument(source: .server)
            var alreadyMine = false
            if snap.exists {
                if (snap.data()?["uid"] as? String) == uid {
                    alreadyMine = true      // leftover doc of mine — rules forbid update, so don't rewrite it
                } else {
                    status = .taken
                    return
                }
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
            AppAnalytics.log(AppAnalyticsEvent.bookingLinkSet)

            BookingLink.store(handle: newHandle, uid: uid)
            currentHandle = newHandle
            if input == newHandle { status = .current }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeHandle() async {
        guard let uid = Auth.auth().currentUser?.uid,
              let old = currentHandle else { return }
        isSaving = true
        defer { isSaving = false }

        let db = Firestore.firestore()
        let batch = db.batch()
        batch.deleteDocument(db.collection("handles").document(old))
        batch.setData(
            ["handle": FieldValue.delete()],
            forDocument: db.collection("users").document(uid),
            merge: true
        )
        do {
            try await batch.commit()
            BookingLink.clearCache()
            currentHandle = nil
            input = ""
            status = .idle
        } catch {
            errorMessage = error.localizedDescription
        }
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
