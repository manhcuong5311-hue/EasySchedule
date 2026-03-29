//
// PartnerCalendarTabView.swift
// Easy Schedule
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SelectedUser: Identifiable {
    let id: String
}

struct PartnerCalendarTabView: View {
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var network: NetworkMonitor
    @EnvironmentObject var guideManager: GuideManager
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme

    // Link input (legacy, kept for addAppointmentPressed)
    @State private var linkText: String = ""
    @State private var parsedUID: String? = nil

    // Fetching state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var fetchedEvents: [CalendarEvent] = []

    // Sheets
    @State private var selectedUser: SelectedUser?
    @State private var activeSheet: ActiveSheet? = nil

    // Alert
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    @State private var didCopy = false
    @StateObject private var accessBadgeVM = AccessBadgeViewModel()

    let onBookPartner: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
            }
            .safeAreaInset(edge: .top) {
                HStack(alignment: .center) {
                    partnerHeaderView
                    Spacer()
                    floatingAddButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(
                    Color(.systemBackground)
                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 3)
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard let uid = Auth.auth().currentUser?.uid else { return }
            accessBadgeVM.load(ownerUid: uid)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .history:
                NavigationStack {
                    HistoryLinksView { uid in
                        activeSheet = nil
                        checkAccessAndOpen(uid: uid)
                    }
                    .environmentObject(eventManager)
                }
            case .manageAccess:
                NavigationStack {
                    AccessManagementView()
                        .environmentObject(eventManager)
                        .environmentObject(session)
                }
            case .addPartner:
                AddPartnerSheet(
                    isPresented: Binding(
                        get: { activeSheet == .addPartner },
                        set: { if !$0 { activeSheet = nil } }
                    )
                )
                .environmentObject(eventManager)
            }
        }
        .sheet(item: $selectedUser) { user in
            AppointmentProSheet(
                isPresented: Binding(
                    get: { selectedUser != nil },
                    set: { if !$0 { selectedUser = nil } }
                ),
                sharedUserId: user.id,
                sharedUserName: eventManager.userNames[user.id]
            )
            .environmentObject(eventManager)
            .environmentObject(session)
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button(String(localized: "ok"), role: .cancel) {}
        }
    }

    // MARK: – Header

    private var partnerHeaderView: some View {
        (
            Text(String(localized: "title_partner1"))
                .foregroundColor(uiAccent.color)
            +
            Text(" ")
            +
            Text(String(localized: "title_calendar1"))
                .foregroundColor(.primary)
        )
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .tracking(-0.4)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .allowsTightening(true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TitleShadow.primary(colorScheme))
    }

    // MARK: – Floating Add Button

    private var floatingAddButton: some View {
        Button { activeSheet = .addPartner } label: {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [uiAccent.color, uiAccent.color.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: uiAccent.color.opacity(0.40), radius: 10, y: 4)
        }
    }

    // MARK: – Main scroll content

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Invitation card ──────────────────────────────────────
                invitationCard
                    .padding(.horizontal, 16)

                // ── Access management ────────────────────────────────────
                manageSection
                    .padding(.horizontal, 16)

                // ── Partners list ────────────────────────────────────────
                partnersSection
                    .padding(.horizontal, 16)
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: – Invitation Card

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.subheadline)
                    .foregroundStyle(uiAccent.color)
                Text(String(localized: "partner.invitation_title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if let code = eventManager.invitationCode {
                HStack(alignment: .center, spacing: 12) {
                    Text(code)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundColor(uiAccent.color)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = code
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { didCopy = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(didCopy ? "Copied!" : "Copy")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(didCopy
                                    ? Color.green.opacity(0.12)
                                    : uiAccent.color.opacity(0.10))
                        )
                        .foregroundStyle(didCopy ? .green : uiAccent.color)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.3), value: didCopy)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.85)
                    Text("generating_short")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            }

            Divider()

            Text(String(localized: "partner.invitation_subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark
                    ? Color(.secondarySystemBackground)
                    : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(uiAccent.color.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: uiAccent.color.opacity(0.10), radius: 12, y: 5)
    }

    // MARK: – Manage Access Section

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            sectionHeader(
                icon: "lock.shield",
                title: String(localized: "access.title"),
                hint: "Control who can view your calendar and book time with you."
            )

            manageRow(
                icon: "person.2.fill",
                title: String(localized: "access.manage"),
                subtitle: pendingAccessHint,
                badgeCount: accessBadgeVM.pendingCount
            ) {
                activeSheet = .manageAccess
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    private var pendingAccessHint: String {
        let n = accessBadgeVM.pendingCount
        return n > 0
            ? "\(n) pending request\(n == 1 ? "" : "s") waiting"
            : "Approve or deny access requests"
    }

    // MARK: – Partners Section

    private var partnersSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            sectionHeader(
                icon: "person.2",
                title: partnersHeaderTitle,
                hint: "Tap a connected partner to book an appointment on their calendar."
            )

            SharedLinksListView { uid in
                checkAccessAndOpen(uid: uid)
            }
            .environmentObject(eventManager)
        }
    }

    private var partnersHeaderTitle: String {
        let count = eventManager.sharedLinks.count
        return count > 0 ? "Partners (\(count))" : "Partners"
    }

    // MARK: – Section Header Helper

    private func sectionHeader(icon: String, title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(uiAccent.color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 4)
    }

    // MARK: – Manage Row

    @ViewBuilder
    private func manageRow(
        icon: String,
        title: String,
        subtitle: String,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(uiAccent.color.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(uiAccent.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                AccessRequestBadge(count: badgeCount)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }

    // MARK: – Access check & open sheet

    private func checkAccessAndOpen(uid: String) {
        guard let me = Auth.auth().currentUser?.uid else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        if uid == me {
            selectedUser = SelectedUser(id: uid)
            return
        }

        isLoading = true

        AccessService.shared.isAllowed(ownerUid: uid, otherUid: me) { allowed in
            DispatchQueue.main.async {
                self.isLoading = false

                if allowed {
                    self.selectedUser = SelectedUser(id: uid)
                } else {
                    let requesterName = self.eventManager.userNames[me] ?? me
                    AccessService.shared.createRequest(
                        owner: uid,
                        requester: me,
                        requesterName: requesterName
                    )
                    self.alertMessage = String(localized: "request_not_allowed_sent")
                    self.showAlert = true
                }
            }
        }
    }

    // MARK: – Legacy helpers (kept for addAppointmentPressed)

    private func addAppointmentPressed() {
        let input = linkText
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard !input.isEmpty else {
            alertMessage = String(localized: "uid_required")
            showAlert = true
            return
        }

        let parsed: String
        if let url = URL(string: input),
           let last = url.pathComponents.last, !last.isEmpty {
            parsed = last
        } else {
            parsed = input
        }

        guard isValidUIDFormat(parsed) else {
            alertMessage = String(localized: "invalid_uid")
            showAlert = true
            return
        }

        guard Auth.auth().currentUser != nil else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        isLoading = true
        eventManager.validateUserExists(uid: parsed) { exists in
            DispatchQueue.main.async {
                self.isLoading = false
                guard exists else {
                    self.alertMessage = String(localized: "uid_not_found")
                    self.showAlert = true
                    return
                }
                self.parsedUID = parsed
                self.checkAccessAndOpen(uid: parsed)
            }
        }
    }

    private func isValidUIDFormat(_ uid: String) -> Bool {
        NSPredicate(format: "SELF MATCHES %@", "^[A-Za-z0-9_-]{20,}$").evaluate(with: uid)
    }

    private func shortUID(_ uid: String) -> String {
        guard uid.count > 8 else { return uid }
        return uid.prefix(4) + "…" + uid.suffix(4)
    }

    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}


// MARK: – PartnerRow (standalone, used elsewhere)

struct PartnerRow: View {
    let link: SharedLink
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(uiAccent.color.opacity(0.12))
                    .frame(width: 42, height: 42)
                Text(initial)
                    .font(.headline)
                    .foregroundStyle(uiAccent.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(eventManager.displayName(for: link.uid))
                    .font(.system(size: 16, weight: .medium))
                Text(shortUID(link.uid))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var initial: String {
        eventManager.displayName(for: link.uid).prefix(1).uppercased()
    }

    private func shortUID(_ uid: String) -> String {
        guard uid.count > 8 else { return uid }
        return uid.prefix(4) + "…" + uid.suffix(4)
    }
}
