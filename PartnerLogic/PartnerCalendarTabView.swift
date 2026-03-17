//
// PartnerCalendarTabView.swift
// Easy Schedule
//
// Updated for EventManager v2 (stable IDs, pendingDelete handling).
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
    // Link input
    @State private var linkText: String = ""
    @State private var parsedUID: String? = nil
    
    // Fetching state
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var fetchedEvents: [CalendarEvent] = []

    // Sheet for creating appointment
    @State private var selectedUser: SelectedUser?
    @State private var activeSheet: ActiveSheet? = nil

    // Alert
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
  
    @State private var showHelpSheet = false
    @EnvironmentObject var network: NetworkMonitor

    @EnvironmentObject var guideManager: GuideManager
    @StateObject private var accessBadgeVM = AccessBadgeViewModel()

    // Group by day for UI
    private var groupedByDay: [Date: [CalendarEvent]] {
        Dictionary(grouping: fetchedEvents) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
//NEWWWWWWW
    
    @EnvironmentObject var uiAccent: UIAccentStore

    @Environment(\.colorScheme) private var colorScheme

    let onBookPartner: () -> Void
    
    var canLoad: Bool {
        !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    @State private var didCopy = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                mainContent
            }
            .safeAreaInset(edge: .top) {
                HStack {

                    partnerHeaderView

                    Spacer()

                    floatingAddButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .background(Color(.systemBackground))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // ✅ LOAD BADGE KHI VIEW XUẤT HIỆN
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
                
            case .addPartner:     // ⭐ QUAN TRỌNG
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
    }


    private var partnerHeaderView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {

            (
                Text(String(localized: "title_partner1"))
                    .foregroundColor(uiAccent.color)
                +
                Text(" ")
                +
                Text(String(localized: "title_calendar1"))
                    .foregroundColor(.primary)
            )
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .tracking(-0.4)
            .lineLimit(1)                // ⭐ ép 1 dòng
            .minimumScaleFactor(0.75)    // ⭐ thu nhỏ nếu thiếu chỗ
            .allowsTightening(true)      // ⭐ nén ký tự nếu cần
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TitleShadow.primary(colorScheme))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var invitationCard: some View {
        
        
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Label(String(localized: "partner.invitation_title"), systemImage: "qrcode")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            if let code = eventManager.invitationCode {

                HStack {
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(uiAccent.color)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = code

                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            didCopy = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                didCopy = false
                            }
                        }

                    } label: {
                        Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                            .foregroundColor(didCopy ? .green : uiAccent.color)
                            .scaleEffect(didCopy ? 1.2 : 1.0)
                    }
                }

            } else {
                ProgressView()
            }

            Text(String(localized: "partner.invitation_subtitle"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    colorScheme == .dark
                    ? Color(.secondarySystemBackground)
                    : Color.white
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(uiAccent.color.opacity(0.15), lineWidth: 1)
        )
        .shadow(
            color: uiAccent.color.opacity(0.15),
            radius: 12,
            y: 6
        )
    }
   
    private func formattedCode(_ code: String) -> String {
        code
    }
    
    private var floatingAddButton: some View {
        Button {
            activeSheet = .addPartner
        } label: {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle()
                        .fill(uiAccent.color)
                )
                .shadow(
                    color: uiAccent.color.opacity(0.35),
                    radius: 10,
                    y: 4
                )
        }
    }
 
    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(String(localized: "access.title"))
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            manageRow(
                icon: "person.2.fill",
                title: String(localized: "access.manage"),
                badgeCount: accessBadgeVM.pendingCount
            ) {
                activeSheet = .manageAccess
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }
    
    // MARK: - Subviews
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                invitationCard
                    .padding(.horizontal, 16)

                manageSection
                    .padding(.horizontal, 16)

                SharedLinksListView { uid in
                    checkAccessAndOpen(uid: uid)
                }
                .environmentObject(eventManager)
                .padding(.horizontal, 16)
            }
            .padding(.top, 16)
        }
    }

    @ToolbarContentBuilder
    private var partnerToolbar: some ToolbarContent {

        // ➕ Add appointment — bên phải (GIỮ NGUYÊN)
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                guard !isLoading else { return }
                addAppointmentPressed()
            } label: {
                Image(systemName: "plus")
                           .font(.system(size: 20, weight: .semibold))
                           .foregroundColor(uiAccent.color)
                           .shadow(
                               color: colorScheme == .dark
                                   ? Color.white.opacity(0.18)
                                   : Color.black.opacity(0.25),
                               radius: 3,
                               y: 2
                           )
            }
            .accessibilityLabel(
                String(localized: "add_appointment")
            )

        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                TextField(String(localized: "paste_link_or_uid"), text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            HStack {
                Button(action: {
                    guard !isLoading else { return }
                    parseAndLoad()
                }) {
                    HStack {
                        if isLoading {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text(String(localized: "load_calendar"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
                .tint(
                    canLoad
                    ? uiAccent.color.opacity(0.75)
                    : uiAccent.color.opacity(0.35)
                )
                .allowsHitTesting(canLoad)


                .buttonStyle(.bordered)
                .background(uiAccent.color.opacity(0.12))
                .clipShape(Capsule())
                .shadow(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.15)
                        : Color.black.opacity(0.25),
                    radius: 8,
                    y: 5
                )
                .shadow(
                    color: colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.12),
                    radius: 3,
                    y: 2
                )
                
                Button(action: {
                    linkText = ""
                    parsedUID = nil
                    fetchedEvents.removeAll()
                    errorMessage = nil
                }) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
        .padding()
    }

    private var uidInfoArea: some View {
        Group {
            if let uid = parsedUID {
                HStack {
                    Text(String(localized: "uid_label") + ":")
                        .bold()
                    Text(uid).lineLimit(1)
                    Spacer()
                    Text(
                        Auth.auth().currentUser == nil
                        ? String(localized: "not_logged_in")
                        : String(localized: "logged_in")
                    )
                        .font(.caption)
                        .foregroundColor(Auth.auth().currentUser == nil ? .red : .green)
                }
                .padding(.horizontal)
            }
        }
    }

    private var errorArea: some View {
        Group {
            if let err = errorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var contentArea: some View {
        Group {
            if isLoading {
                Spacer()
                ProgressView(String(localized: "loading_calendar"))
                Spacer()
            } else if fetchedEvents.isEmpty {
                Spacer()
                Text(
                    parsedUID == nil
                    ? String(localized: "no_uid_yet")
                    : String(localized: "no_busy_events")
                )
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                Spacer()
            } else {
                EmptyView()
            }
        }
    }

   

    private func eventRow(_ ev: CalendarEvent) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: ev.colorHex.isEmpty ? "#007AFF" : ev.colorHex))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading) {
                Text(ev.title).font(.headline)
                Text("\(formattedTime(ev.startTime)) — \(formattedTime(ev.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                let ownerPrefix = String(localized: "owner_prefix")
                Text("\(ownerPrefix) \(eventManager.displayName(for: ev.owner))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                if Auth.auth().currentUser == nil {
                    alertMessage = String(localized: "login_required")
                    showAlert = true
                } else {
                    // ensure uid is set before opening sheet
                    if let uid = parsedUID {
                        checkAccessAndOpen(uid: uid)
                    } else {
                        alertMessage = String(localized: "uid_required")
                        showAlert = true
                    }
                }
            } label: {
                Text(String(localized: "book"))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private func checkAccessAndOpen(uid: String) {

        guard let me = Auth.auth().currentUser?.uid else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        // Owner tự book cho mình
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
                    // ⭐ FIX: TẠO REQUEST
                    let requesterName =
                        self.eventManager.userNames[me] ?? me

                    AccessService.shared.createRequest(
                        owner: uid,
                        requester: me,
                        requesterName: requesterName
                    )

                    self.alertMessage =
                        String(localized: "request_not_allowed_sent")
                    self.showAlert = true
                }
            }
        }

        
    }

    // MARK: - Actions & Helpers
    private func addAppointmentPressed() {
        let input = linkText
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        // 1️⃣ Chưa nhập gì
        guard !input.isEmpty else {
            alertMessage = String(localized: "uid_required")
            showAlert = true
            return
        }

        // 2️⃣ Parse UID
        let parsed: String
        if let url = URL(string: input),
           let last = url.pathComponents.last,
           !last.isEmpty {
            parsed = last
        } else {
            parsed = input
        }

        // 3️⃣ Check format UID (NGĂN UID RÁC)
        guard isValidUIDFormat(parsed) else {
            alertMessage = String(localized: "invalid_uid")
            showAlert = true
            return
        }

        // 4️⃣ Check đăng nhập
        guard Auth.auth().currentUser != nil else {
            alertMessage = String(localized: "login_required")
            showAlert = true
            return
        }

        // 5️⃣ Check UID tồn tại (ASYNC)
        isLoading = true
        eventManager.validateUserExists(uid: parsed) { exists in
            DispatchQueue.main.async {
                self.isLoading = false

                guard exists else {
                    self.alertMessage = String(localized: "uid_not_found")
                    self.showAlert = true
                    return
                }

                // ✅ OK → mới cho mở sheet
                self.parsedUID = parsed
                self.checkAccessAndOpen(uid: parsed)

            }
        }
    }

    private func isValidUIDFormat(_ uid: String) -> Bool {
        let regex = "^[A-Za-z0-9_-]{20,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: uid)
    }

    private func parseAndLoad() {
        errorMessage = nil
        fetchedEvents.removeAll()
        parsedUID = nil

        let input = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = String(localized: "paste_link_or_uid_first")
            return
        }

        let uid: String
        if let url = URL(string: input),
           let last = url.pathComponents.last,
           !last.isEmpty {
            uid = last
        } else {
            uid = input
        }

        // ❌ UID sai format → dừng luôn
        guard isValidUIDFormat(uid) else {
            errorMessage = String(localized: "invalid_uid")
            return
        }

        isLoading = true

        // ❌ UID không tồn tại → dừng
        eventManager.validateUserExists(uid: uid) { exists in
            DispatchQueue.main.async {
                self.isLoading = false

                guard exists else {
                    self.errorMessage = String(localized: "uid_not_found")
                    return
                }

                // ✅ UID hợp lệ → mới load
                self.parsedUID = uid
                self.loadBusySlots(uid: uid)
            }
        }
    }

    private func loadBusySlots(uid: String) {
        isLoading = true
        errorMessage = nil
        fetchedEvents.removeAll()

        eventManager.fetchBusySlots(for: uid, forceRefresh: true) { slots, tier in
            DispatchQueue.main.async {
                self.isLoading = false

                let filtered = slots.filter { slot in
                    !self.eventManager.events.contains(where: { local in
                        local.pendingDelete && local.id == slot.id
                    })
                }

                self.fetchedEvents = filtered.sorted { $0.startTime < $1.startTime }
                self.eventManager.partnerBusySlots[uid] = filtered

                // ===============================
                // MESSAGE THEO TIER (KHÔNG DÙNG BOOL)
                // ===============================
                if tier == .free {
                    self.errorMessage = String(localized: "seven_day_limit")
                } else if filtered.isEmpty {
                    self.errorMessage = String(localized: "no_busy_events_for_uid")
                }

                // ===============================
                // SHARED LINK (GIỮ NGUYÊN)
                // ===============================
                if let me = Auth.auth().currentUser?.uid {
                    self.eventManager.addSharedLink(for: me, otherUid: uid)
                    self.eventManager.addSharedLink(for: uid, otherUid: me)
                }
            }
        }
    }

    @ViewBuilder
    private func manageRow(
        icon: String,
        title: String,
        badgeCount: Int = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(uiAccent.color)
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 16, weight: .medium))

                Spacer()
                AccessRequestBadge(count: badgeCount)
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }


    private func sectionHeader(for day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }


    func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
    private var partnersIntroOverlay: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        guideManager.complete(.partnersIntro)
                    }

                VStack {
                    GuideBubble(
                        textKey: "partners_guide_intro",
                        onNext: {
                            guideManager.complete(.partnersIntro)
                        },
                        onDoNotShowAgain: {
                            guideManager.disablePermanently(.partnersIntro)
                        }
                    )
                    .frame(maxWidth: min(420, geo.size.width * 0.9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 140)
            }
        }
    }
    private func shortUID(_ uid: String) -> String {
        guard uid.count > 8 else { return uid }
        return uid.prefix(4) + "…" + uid.suffix(4)
    }

}


struct PartnerRow: View {

    let link: SharedLink
    @EnvironmentObject var eventManager: EventManager

    var body: some View {
        HStack(spacing: 12) {

            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 42, height: 42)
                .overlay(
                    Text(initial)
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {

                Text(eventManager.displayName(for: link.uid))
                    .font(.system(size: 16, weight: .medium))

                Text(shortUID(link.uid))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
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
