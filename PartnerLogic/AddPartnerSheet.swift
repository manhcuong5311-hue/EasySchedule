import SwiftUI
import FirebaseAuth

struct AddPartnerSheet: View {

    @EnvironmentObject var eventManager: EventManager
    @Binding var isPresented: Bool

    @State private var input:           String  = ""
    @State private var isLoading:       Bool    = false
    @State private var errorMessage:    String? = nil
    @State private var successMessage:  String? = nil
    @State private var copiedCode:      Bool    = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    howItWorksCard
                    connectCard
                    yourCodeCard
                    Spacer(minLength: 32)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "partner.add_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: – Header

    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(String(localized: "partner.add_title"))
                    .font(.title2.weight(.bold))

                Text(String(localized: "partner.header_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    // MARK: – How it works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {

            Label(
                String(localized: "how_it_works_title"),
                systemImage: "info.circle"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

            VStack(spacing: 8) {
                howItWorksRow(
                    icon: "1.circle.fill",
                    color: Color.accentColor,
                    text: String(localized: "how_it_works_step_1")
                )
                howItWorksRow(
                    icon: "2.circle.fill",
                    color: .orange,
                    text: String(localized: "how_it_works_step_2")
                )
                howItWorksRow(
                    icon: "3.circle.fill",
                    color: .green,
                    text: String(localized: "how_it_works_step_3")
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func howItWorksRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: – Step 1: Connect card

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            stepLabel(
                number: "1",
                title: "step_add_partner",
                color: .accentColor
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "partner.enter_uid_or_link"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                HStack(spacing: 10) {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField(String(localized: "partner.paste_uid_or_link"), text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.go)
                        .onSubmit { loadPartner() }

                    if !input.isEmpty {
                        Button {
                            withAnimation { input = ""; errorMessage = nil; successMessage = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            errorMessage   != nil ? Color.red.opacity(0.50)
                          : successMessage != nil ? Color.green.opacity(0.50)
                          : Color.gray.opacity(0.15),
                            lineWidth: 1
                        )
                )
            }

            // Status messages
            if let error = errorMessage {
                statusBanner(text: error, icon: "exclamationmark.circle.fill", color: .red)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let success = successMessage {
                statusBanner(text: success, icon: "checkmark.circle.fill", color: .green)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Connect button
            Button { loadPartner() } label: {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    Text(isLoading ? String(localized: "connecting") : String(localized: "partner.load"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(isLoading || input.trimmingCharacters(in: .whitespaces).isEmpty)

            // Helper hint
            HStack(spacing: 6) {
                Image(systemName: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "partner.ask_for_uid"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .animation(.easeInOut(duration: 0.22), value: errorMessage)
        .animation(.easeInOut(duration: 0.22), value: successMessage)
    }

    // MARK: – Step 2: Your code card

    private var yourCodeCard: some View {
        VStack(alignment: .leading, spacing: 16) {

            stepLabel(
                number: "2",
                title: "share_invitation_code",
                color: .orange
            )

            Text("share_code_description")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let code = eventManager.invitationCode {
                VStack(spacing: 12) {
                    HStack(alignment: .center) {
                        Text(code)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .tracking(5)
                            .foregroundStyle(.primary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = code
                            withAnimation(.spring(response: 0.3)) { copiedCode = true }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copiedCode = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(copiedCode ? "Copied!" : "Copy")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                copiedCode
                                    ? Color.green.opacity(0.12)
                                    : Color.accentColor.opacity(0.12)
                            )
                            .foregroundStyle(copiedCode ? .green : .accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.3), value: copiedCode)
                    }

                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "partner.invitation_subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("generating_code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: – Helpers

    private func stepLabel(
        number: String,
        title: LocalizedStringKey,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color).frame(width: 26, height: 26)
                Text(number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func statusBanner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: – Logic

extension AddPartnerSheet {

    private func loadPartner() {
        errorMessage   = nil
        successMessage = nil

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "uid_required")
            return
        }

        guard let me = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "login_required")
            return
        }

        isLoading = true

        eventManager.resolveUid(from: trimmed) { resolvedUid in
            DispatchQueue.main.async {
                guard let uid = resolvedUid else {
                    self.isLoading    = false
                    self.errorMessage = String(localized: "uid_not_found")
                    return
                }

                if uid == me {
                    self.isLoading    = false
                    self.errorMessage = String(localized: "cannot_add_self")
                    return
                }

                self.eventManager.validateUserExists(uid: uid) { exists in
                    DispatchQueue.main.async {
                        guard exists else {
                            self.isLoading    = false
                            self.errorMessage = String(localized: "uid_not_found")
                            return
                        }

                        // Save connection history on both sides
                        self.eventManager.addSharedLink(for: me,  otherUid: uid)
                        self.eventManager.addSharedLink(for: uid, otherUid: me)

                        AccessService.shared.isAllowed(ownerUid: uid, otherUid: me) { allowed in
                            DispatchQueue.main.async {
                                self.isLoading = false

                                if allowed {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    self.successMessage = String(localized: "connected_success")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                        self.isPresented = false
                                    }
                                } else {
                                    let requesterName = self.eventManager.userNames[me] ?? me
                                    AccessService.shared.createRequest(
                                        owner: uid,
                                        requester: me,
                                        requesterName: requesterName
                                    )
                                    self.successMessage = String(localized: "request_not_allowed_sent")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        self.isPresented = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


// MARK: – Invitation Code Card (standalone, used on other screens)

struct InvitationCodeCard: View {

    @EnvironmentObject var eventManager: EventManager
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 8) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "partner.invitation_title"))
                    .font(.subheadline.weight(.semibold))
            }

            if let code = eventManager.invitationCode {
                HStack(alignment: .center) {
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = code
                        withAnimation(.spring(response: 0.3)) { copied = true }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(copied ? .green : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.3), value: copied)
                }

                Text(String(localized: "partner.invitation_subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("generating_short")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }
}
