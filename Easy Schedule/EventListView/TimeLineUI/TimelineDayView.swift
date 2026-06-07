import SwiftUI
import FirebaseAuth

struct TimelineDayView: View {

    let date: Date
    let events: [CalendarEvent]
    let manualBusySlots: [CalendarEvent]
    let timeDisplayMode: EventTimeDisplayMode

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var uiAccent: UIAccentStore

    @AppStorage("timeline_start_hour") private var startHour: Int = 8
    @AppStorage("timeline_end_hour")   private var endHour: Int = 22

  
    private var safeStartHour: Int {
        min(max(startHour, 0), 23)
    }

    private var safeEndHour: Int {
        min(max(endHour, safeStartHour + 1), 23)
    }

    private var timelineHeight: CGFloat {
        CGFloat(effectiveEndHour - effectiveStartHour)
        * TimelineLayout.hourHeight
    }
    private var isAutoExpanded: Bool {
        guard let r = eventHourRange else { return false }
        return r.start < safeStartHour || r.end > safeEndHour
    }

    
    @AppStorage("timeFontSize")
       private var timeFontSize: Double = 13

    var body: some View {

        let screenWidth = UIScreen.main.bounds.width
        let leadingPadding: CGFloat = 40
        let hourWidth = TimelineLayout.hourLabelWidth + 1
        let contentWidth = screenWidth - hourWidth - leadingPadding

        ScrollView {
            VStack(alignment: .leading, spacing: 6) {

                // 💡 AUTO-EXPAND HINT
                if isAutoExpanded {
                    Text(String(localized: "timeline_auto_expanded_hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, leadingPadding + 4)
                }

                HStack(alignment: .top, spacing: 0) {

                    // ⏰ HOUR COLUMN
                    TimelineHourColumn(
                        startHour: effectiveStartHour,
                        endHour: effectiveEndHour,
                        timeFontSize: timeFontSize
                    )
                    .frame(width: hourWidth)

                    // 📅 CONTENT COLUMN
                    TimelineContentColumn(
                        date: date,
                        startHour: effectiveStartHour,
                        endHour: effectiveEndHour,
                        events: events,
                        manualBusySlots: eventManager.myManualBusySlots,
                        timeDisplayMode: timeDisplayMode
                    )
                    .frame(width: contentWidth, alignment: .leading)
                }
                .padding(.leading, leadingPadding)
                .frame(height: timelineHeight)
            }
        }

        .sheet(item: $eventManager.selectedEventWrapper) { wrapper in
            if let event = eventManager.event(for: wrapper) {
                EventDetailView(event: event)
            }
        }
    }

    
    private var eventHourRange: (start: Int, end: Int)? {
        let all = events + manualBusySlots
        guard !all.isEmpty else { return nil }

        let cal = Calendar.current

        let startHours = all.map {
            cal.component(.hour, from: $0.startTime)
        }

        let endHours = all.map {
            cal.component(.hour, from: $0.endTime)
        }

        return (start: startHours.min()!, end: endHours.max()!)
    }

    private var effectiveStartHour: Int {
        guard let r = eventHourRange else { return safeStartHour }
        return min(safeStartHour, r.start)
    }

    private var effectiveEndHour: Int {
        guard let r = eventHourRange else { return safeEndHour }
        return max(safeEndHour, r.end)
    }

    
}

struct EventDetailView: View {
    let event: CalendarEvent

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) private var dismiss

    @State private var showAddMemberSheet = false
    @State private var note: String = ""
    @State private var showDeleteConfirm = false
    @FocusState private var chatFocused: Bool
    @StateObject private var chatVM: ChatViewModel

    private var myUid: String? { Auth.auth().currentUser?.uid }

    private var canManage: Bool {
        guard let uid = myUid else { return false }
        return uid == event.owner ||
               uid == event.createdBy ||
               event.admins?.contains(uid) == true
    }

    /// Chat shows only for events shared with at least one other person.
    /// Personal event = `participants.count == 1`; adding a member makes it > 1.
    private var hasChat: Bool { event.participants.count > 1 }

    init(event: CalendarEvent) {
        self.event = event
        let myId = Auth.auth().currentUser?.uid ?? ""
        let parts = event.participants.isEmpty
            ? [event.owner, event.sharedUser].filter { !$0.isEmpty }
            : event.participants
        _chatVM = StateObject(wrappedValue: ChatViewModel(
            eventId: event.id,
            participants: parts,
            myId: myId,
            myName: EventManager.shared.displayName(for: myId)
        ))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {

                    // ===== TOP ~58%: info + note (+ tasks) =====
                    ScrollView {
                        VStack(spacing: 16) {
                            headerCard
                            noteCard
                            todoCard
                            if canManage && !eventManager.pastOnlyEventIds.contains(event.id) {
                                deleteButton
                            }
                        }
                        .padding()
                    }
                    .frame(height: hasChat ? geo.size.height * 0.58 : geo.size.height)
                    .background(Color(.systemGroupedBackground))

                    // ===== BOTTOM: quick chat — shared events only =====
                    if hasChat {
                        Divider()
                        chatMessagesArea
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(String(localized: "event_navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .doneKeyboardToolbar()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                if canManage {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showAddMemberSheet = true } label: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            }
            // Quick-chat input — pinned above the keyboard (shared events only).
            .safeAreaInset(edge: .bottom) {
                if hasChat { chatInputBar }
            }
            .sheet(isPresented: $showAddMemberSheet) {
                AddMemberSheet(event: event)
                    .environmentObject(eventManager)
            }
            .onAppear { note = EventNoteStore.shared.note(for: event.id) }
            .task {
                if hasChat {
                    try? await chatVM.ensureChatExists(eventEndTime: event.endTime)
                }
            }
            .onDisappear { chatVM.stopListening() }
            .alert(String(localized: "delete_event"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "delete"), role: .destructive) { performDelete() }
                Button(String(localized: "cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "delete_event_confirm"))
            }
        }
    }

    // MARK: - Top cards (info · note · tasks)

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: event.colorHex))
                    .frame(width: 12, height: 12)
                Text(event.title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            Text(EventTimeDisplayMode.timeRange.primaryText(for: event))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Note", systemImage: "note.text")
                .font(.headline)
            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                }
                TextEditor(text: $note)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .onChange(of: note) {
                        EventNoteStore.shared.setNote(note, for: event.id)
                    }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "tasks"), systemImage: "checklist")
                .font(.headline)
            LocalTodoListView(eventId: event.id)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label(String(localized: "delete_event"), systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.12))
                )
                .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
    }

    private func performDelete() {
        let ev = event
        eventManager.selectedEventWrapper = nil   // dismiss sheet first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { eventManager.deleteEvent(ev) }
        }
    }

    // MARK: - Quick chat

    private var chatMessagesArea: some View {
        VStack(spacing: 0) {
            // Header — open full ChatView
            HStack {
                Label("Quick chat", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { openFullChat() } label: {
                    HStack(spacing: 3) {
                        Text("Open chat")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if chatVM.messages.isEmpty {
                            Text("No messages yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else {
                            ForEach(chatVM.messages) { msg in
                                quickBubble(msg).id(msg.uiId)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chatVM.messages.count) {
                    if let last = chatVM.messages.last {
                        withAnimation { proxy.scrollTo(last.uiId, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = chatVM.messages.last {
                        proxy.scrollTo(last.uiId, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
    }

    private var chatInputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                TextField("Message…", text: $chatVM.messageText, axis: .vertical)
                    .focused($chatFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color(.systemGray6)))

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(sendDisabled ? Color(.systemGray3)
                                                       : Color(hex: event.colorHex))
                }
                .disabled(sendDisabled)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var sendDisabled: Bool {
        chatVM.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func quickBubble(_ msg: ChatMessage) -> some View {
        let mine = msg.senderId == myUid
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(msg.text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    mine ? Color(hex: event.colorHex).opacity(0.9) : Color(.systemGray5),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(mine ? .white : .primary)
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func send() {
        chatVM.sendMessage(isPremium: PremiumStoreViewModel.shared.isPremium) {
            openFullChat()
        }
    }

    /// Dismiss this sheet, then open the full ChatView via the existing route.
    private func openFullChat() {
        let id = event.id
        chatFocused = false
        eventManager.selectedEventWrapper = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            eventManager.openChat(eventId: id)
        }
    }
}
