import SwiftUI
import Combine

// MARK: - Main Container

struct DragDropTimelineDayView: View {

    let date: Date
    let events: [CalendarEvent]

    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @Environment(\.colorScheme) private var scheme

    // Persisted wake / sleep minutes
    @AppStorage("user_wake_minutes")  private var storedWake:  Int = 360   // 06:00
    @AppStorage("user_sleep_minutes") private var storedSleep: Int = 1380  // 23:00

    @State private var localEvents: [CalendarEvent] = []
    @State private var isDragging  = false
    @State private var nowMinutes  = DragDropLayoutEngine.currentMinutes()

    // System-event confirmation dialog
    @State private var showSystemDialog     = false
    @State private var pendingSystemID      = ""
    @State private var pendingSystemMinutes = 0

    // Conflict detection when moving shared events
    private struct PendingMove {
        let event:    CalendarEvent
        let newStart: Date
        let newEnd:   Date
    }
    @State private var pendingMove:     PendingMove?
    @State private var moveConflicts:   [EventMoveConflict] = []
    @State private var showConflictDialog = false

    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private let wakeID  = DragDropLayoutEngine.wakeID
    private let sleepID = DragDropLayoutEngine.sleepID

    var body: some View {
        Group {
            if localEvents.isEmpty {
                Color.clear.frame(height: 1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(localEvents.enumerated()), id: \.element.id) { i, event in
                        let isWake  = event.id == wakeID
                        let isSleep = event.id == sleepID
                        let isSys   = isWake || isSleep
                        // Use live localEvents times so constraints update dynamically during drag
                        let liveWakeMin  = localEvents.first(where: { $0.id == wakeID  })?.startMinutes ?? storedWake
                        let liveSleepMin = localEvents.first(where: { $0.id == sleepID })?.startMinutes ?? storedSleep
                        let sysRange: ClosedRange<Int>? = isWake
                            ? (0...(liveSleepMin - 120))          // ≥ 2 h gap before sleep
                            : (isSleep ? ((liveWakeMin + 120)...1440) : nil)  // ≥ 2 h after wake

                        DDDraggableEventRow(
                            event: event,
                            events: $localEvents,
                            isDragging: $isDragging,
                            canEdit: canEdit(event),
                            isToday: Calendar.current.isDateInToday(date),
                            isSystemEvent: isSys,
                            systemConstraint: sysRange,
                            onDragEnded: handleDragEnd
                        )
                        .frame(height: DragDropLayoutEngine.eventHeight(event))

                        if i < localEvents.count - 1 {
                            Color.clear.frame(
                                height: DragDropLayoutEngine.spacing(
                                    current: localEvents[i],
                                    next: localEvents[i + 1]
                                )
                            )
                        }
                    }
                }
                .background(alignment: .topLeading) {
                    DDTimelineLineView(events: localEvents, isDragging: isDragging, date: date)
                        .padding(.leading, 87)  // 58 (time col) + 4 (spacing) + 25 (icon radius)
                }
                .overlay(alignment: .topLeading) {
                    if Calendar.current.isDateInToday(date),
                       localEvents.count > 1,
                       DragDropLayoutEngine.isNowInsideTimeline(events: localEvents) {
                        DDTimeNowIndicator(time: formatTime(nowMinutes))
                            .offset(y: DragDropLayoutEngine.nowY(events: localEvents) - 9)
                    }
                }
                .transaction { t in if isDragging { t.animation = nil } }
                .animation(
                    isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                    value: localEvents.map(\.startMinutes)
                )
            }
        }
        .onAppear { loadLocal() }
        .onChange(of: events)      { _, new in loadLocal(from: new) }
        .onChange(of: storedWake)  { _, _   in if !isDragging { loadLocal() } }
        .onChange(of: storedSleep) { _, _   in if !isDragging { loadLocal() } }
        .onReceive(timer) { _ in nowMinutes = DragDropLayoutEngine.currentMinutes() }
        // ── System event confirmation dialog ──
        .confirmationDialog(
            pendingSystemID == wakeID
            ? "morning_start_title"
            : "night_sleep_title",
            isPresented: $showSystemDialog,
            titleVisibility: .visible
        ) {
            Button("apply_all_days") {
                commitSystemChange(allDays: true)
            }
            
            Button("today_only") {
                commitSystemChange(allDays: false)
            }
            
            Button("cancel", role: .cancel) {
                loadLocal()
            }
        } message: {
            Text(
                pendingSystemID == wakeID
                ? "morning_message"
                : "night_message"
            )
        }
        // ── Move conflict dialog ──
        .confirmationDialog(
            String(localized: "move_conflict_title"),
            isPresented: $showConflictDialog,
            titleVisibility: .visible
        ) {
            Button(String(localized: "move_anyway"), role: .destructive) {
                if let m = pendingMove {
                    eventManager.updateEvent(
                        m.event, newTitle: m.event.title,
                        newDate: m.newStart, newStart: m.newStart,
                        newEnd: m.newEnd, newColorHex: m.event.colorHex
                    )
                }
                pendingMove   = nil
                moveConflicts = []
            }
            Button(String(localized: "cancel"), role: .cancel) {
                pendingMove   = nil
                moveConflicts = []
                loadLocal()   // revert drag
            }
        } message: {
            Text(conflictMessage)
        }
    }

    // Builds a human-readable summary of who has a conflict and when.
    private var conflictMessage: String {
        guard !moveConflicts.isEmpty else { return "" }
        let lines = moveConflicts.prefix(3).map { c in
            let fmt = DateFormatter()
            fmt.timeStyle = .short
            let range = "\(fmt.string(from: c.conflictingStart))–\(fmt.string(from: c.conflictingEnd))"
            return "\(c.participantName): \"\(c.conflictingEventTitle)\" \(range)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func loadLocal(from source: [CalendarEvent]? = nil) {
        guard !isDragging else { return }
        let src = (source ?? events)
            .filter { $0.origin != .busySlot }
            .sorted { $0.startTime < $1.startTime }

        // Auto-expand: push wake earlier if an event starts before it,
        // push sleep later if an event ends after it.
        let effectiveWake: Int = {
            guard let earliest = src.min(by: { $0.startMinutes < $1.startMinutes }) else {
                return storedWake
            }
            // Give a 15-min buffer before the earliest event
            return min(storedWake, max(0, earliest.startMinutes - 15))
        }()

        let effectiveSleep: Int = {
            guard let latest = src.max(by: { $0.endMinutes < $1.endMinutes }) else {
                return storedSleep
            }
            // Give a 15-min buffer after the latest event end
            return max(storedSleep, min(1439, latest.endMinutes + 15))
        }()

        var result: [CalendarEvent] = []
        result.append(buildSystemEvent(id: wakeID,  label: "Morning Start",
                                       hex: "#F4A261", minutes: effectiveWake))
        result.append(contentsOf: src)
        result.append(buildSystemEvent(id: sleepID, label: "Night Sleep",
                                       hex: "#6C7AA6", minutes: effectiveSleep))
        localEvents = result
    }

    private func buildSystemEvent(id: String, label: String,
                                   hex: String, minutes: Int) -> CalendarEvent {
        let base = Calendar.current.startOfDay(for: date)
        let t    = base.addingTimeInterval(TimeInterval(minutes * 60))
        var e    = CalendarEvent(title: label, date: date,
                                 startTime: t, endTime: t.addingTimeInterval(60),
                                 owner: "", sharedUser: "", createdBy: "")
        e.id       = id
        e.colorHex = hex
        return e
    }

    private func canEdit(_ event: CalendarEvent) -> Bool {
        // System anchors are always draggable (wake/sleep time adjustment)
        if event.id == wakeID || event.id == sleepID { return true }
        // Events on past days are always read-only — no drag, no Firestore writes
        let today = Calendar.current.startOfDay(for: Date())
        guard Calendar.current.startOfDay(for: date) >= today else { return false }
        // Events that exist only in local past cache (Firestore already deleted them) are read-only
        guard !eventManager.pastOnlyEventIds.contains(event.id) else { return false }
        guard let uid = session.currentUserId else { return false }
        return event.createdBy == uid
            || event.owner == uid
            || event.admins?.contains(uid) == true
    }

    private func handleDragEnd(draggedID: String) {
        if draggedID == wakeID {
            guard let idx = localEvents.firstIndex(where: { $0.id == wakeID }) else { return }
            let newMin = localEvents[idx].startMinutes
            guard newMin != storedWake else { persistRegularChanges(); return }
            pendingSystemID      = wakeID
            pendingSystemMinutes = newMin
            showSystemDialog     = true
        } else if draggedID == sleepID {
            guard let idx = localEvents.firstIndex(where: { $0.id == sleepID }) else { return }
            let newMin = localEvents[idx].startMinutes
            guard newMin != storedSleep else { persistRegularChanges(); return }
            pendingSystemID      = sleepID
            pendingSystemMinutes = newMin
            showSystemDialog     = true
        } else {
            persistRegularChanges()
        }
    }

    private func commitSystemChange(allDays: Bool) {
        // Persist regular event moves FIRST — updating AppStorage triggers loadLocal()
        // which would reset localEvents and lose any unsaved regular event positions.
        persistRegularChanges()
        if allDays {
            if pendingSystemID == wakeID { storedWake  = pendingSystemMinutes }
            else                         { storedSleep = pendingSystemMinutes }
        }
        // "Today Only": localEvents already updated during drag, AppStorage unchanged.
    }

    private func persistRegularChanges() {
        for e in localEvents {
            guard e.id != wakeID && e.id != sleepID else { continue }
            guard let original = events.first(where: { $0.id == e.id }) else { continue }
            guard original.startTime != e.startTime || original.endTime != e.endTime else { continue }

            // For shared events, check if the new time clashes with any participant's
            // existing events before committing to Firestore.
            if e.participants.count > 1 {
                let conflicts = eventManager.moveConflicts(
                    for: original,
                    newStart: e.startTime,
                    newEnd: e.endTime
                )
                if !conflicts.isEmpty {
                    // Surface the conflict to the user; hold the move in pendingMove.
                    pendingMove   = PendingMove(event: original, newStart: e.startTime, newEnd: e.endTime)
                    moveConflicts = conflicts
                    showConflictDialog = true
                    return  // Don't persist anything yet; revert happens if user cancels
                }
            }

            eventManager.updateEvent(original, newTitle: e.title, newDate: e.date,
                                     newStart: e.startTime, newEnd: e.endTime,
                                     newColorHex: e.colorHex)
        }
    }

    private func formatTime(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Connecting Line

private struct DDTimelineLineView: View {

    let events: [CalendarEvent]
    let isDragging: Bool
    let date: Date

    var body: some View {
        GeometryReader { _ in
            if events.count > 1 {
                ZStack(alignment: .topLeading) {
                    ForEach(0..<(events.count - 1), id: \.self) { i in
                        let startY   = DragDropLayoutEngine.yPosition(for: i, in: events)
                        let endY     = DragDropLayoutEngine.yPosition(for: i + 1, in: events)
                        let gapMin   = events[i + 1].startMinutes - events[i].endMinutes
                        let style    = DragDropLayoutEngine.dashStyle(gapMinutes: gapMin, isDragging: isDragging)
                        let nowMin   = DragDropLayoutEngine.currentMinutes()
                        let segStart = events[i].startMinutes
                        let segEnd   = events[i + 1].startMinutes
                        let orange   = Color(red: 1.0, green: 0.58, blue: 0.25)

                        // Base dashed line
                        Path { p in
                            p.move(to: .init(x: 0, y: startY))
                            p.addLine(to: .init(x: 0, y: endY))
                        }
                        .stroke(
                            isDragging ? Color.blue.opacity(0.45) : Color.primary.opacity(0.13),
                            style: style
                        )

                        // Progress overlay (today only)
                        if Calendar.current.isDateInToday(date) && nowMin > segStart {
                            let paintTo: CGFloat = {
                                if nowMin >= segStart && nowMin <= segEnd {
                                    return DragDropLayoutEngine.nowY(events: events)
                                } else if nowMin > segEnd { return endY }
                                return startY
                            }()

                            if paintTo > startY {
                                Path { p in
                                    p.move(to: .init(x: 0, y: startY))
                                    p.addLine(to: .init(x: 0, y: paintTo))
                                }
                                .stroke(
                                    LinearGradient(colors: [orange.opacity(0.4), orange.opacity(0.9)],
                                                   startPoint: .top, endPoint: .bottom),
                                    style: StrokeStyle(lineWidth: isDragging ? 4 : 3,
                                                       lineCap: .round, dash: style.dash)
                                )

                                Circle()
                                    .fill(orange)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -3.5, y: paintTo + 5)
                                    .shadow(color: orange.opacity(0.6), radius: 4)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isDragging)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Draggable Event Row

struct DDDraggableEventRow: View {

    let event: CalendarEvent
    @Binding var events: [CalendarEvent]
    @Binding var isDragging: Bool
    let canEdit: Bool
    let isToday: Bool
    let isSystemEvent: Bool
    let systemConstraint: ClosedRange<Int>?
    let onDragEnded: (String) -> Void

    @EnvironmentObject var eventManager: EventManager

    @State private var isHolding      = false
    @State private var dragOffsetY: CGFloat = 0
    @State private var dragOffsetX: CGFloat = 0
    @State private var isReordering   = false
    @State private var lastSwapIndex  = -1
    @State private var lastSwapTime: Date = .distantPast
    @State private var lastHapticSnap = -1

    // Resize state
    @State private var resizeBaseDuration: Int? = nil
    @State private var durationPreview: String? = nil
    @State private var lastResizeHapticStep = -1

    // Tap → open chat / todo
    @State private var showActionSheet = false
    @State private var showDeleteConfirm = false

    @ObservedObject private var completionStore = EventCompletionStore.shared

    private let haptic = UIImpactFeedbackGenerator(style: .rigid)
    private let wakeID  = DragDropLayoutEngine.wakeID
    private let sleepID = DragDropLayoutEngine.sleepID

    private var isPersonalEvent: Bool {
        event.participants.count == 1
    }

    private func isPast() -> Bool {
        guard isToday, !isSystemEvent else { return false }
        return event.endMinutes < DragDropLayoutEngine.currentMinutes()
    }

    private func isLocked() -> Bool { !canEdit || isPast() }

    var body: some View {
        DDEventCard(
            event: event,
            isHolding: isHolding,
            isSystemEvent: isSystemEvent,
            isToday: isToday,
            nearSwap: abs(dragOffsetY) > 80 && isReordering && !isSystemEvent,
            isCompleted: completionStore.isCompleted(event.id),
            onToggleTick: { completionStore.toggle(event.id) },
            durationPreview: durationPreview,
            onResizeEnd: { translation in handleResize(translation: translation) },
            onResizeFinal: { _ in
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                durationPreview = nil
                resizeBaseDuration = nil
                lastResizeHapticStep = -1
                isDragging = false
                isHolding = false
                onDragEnded(event.id)
            }
        )
        .opacity(isDragging && !isHolding ? 0.55 : 1)
        .opacity(isPast() ? 0.5 : 1)
        .offset(x: dragOffsetX, y: dragOffsetY)
        .scaleEffect(isHolding ? 1.03 : 1)
        .shadow(color: isHolding ? .black.opacity(0.22) : .clear, radius: isHolding ? 14 : 0, y: isHolding ? 8 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isHolding)
        // Long-press to activate
        .simultaneousGesture(
            isLocked() ? nil :
            LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                haptic.prepare()
                withAnimation(.spring()) { isHolding = true }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        )
        // Drag gesture
        .gesture(
            isLocked() ? nil :
            DragGesture()
                .onChanged { value in
                    guard isHolding else { return }
                    isDragging  = true
                    dragOffsetY = value.translation.height
                    // System events don't support horizontal reorder
                    if !isSystemEvent {
                        dragOffsetX = max(0, value.translation.width)
                        if dragOffsetX > 65 { isReordering = true }
                    }

                    if isReordering {
                        handleReorder(dragY: dragOffsetY)
                    } else {
                        handleTimeChange(translation: value.translation.height)
                    }
                }
                .onEnded { _ in
                    let id       = event.id
                    dragOffsetX  = 0
                    dragOffsetY  = 0
                    isHolding    = false
                    isReordering = false
                    isDragging   = false
                    lastSwapIndex = -1
                    lastHapticSnap = -1
                    onDragEnded(id)
                }
        )
        // Tap → open chat / todo (skip system events)
        .onTapGesture {
            guard !isSystemEvent else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showActionSheet = true
        }
        .confirmationDialog(event.title, isPresented: $showActionSheet, titleVisibility: .visible) {
            if isPersonalEvent {
                Button(String(localized: "open_todo")) {
                    eventManager.openEvent(eventId: event.id)
                }
            } else {
                Button(String(localized: "open_chat")) {
                    eventManager.openChat(eventId: event.id)
                }
            }
            // Only show delete for live events (past-only local events have no Firestore doc)
            if canEdit && !eventManager.pastOnlyEventIds.contains(event.id) {
                Button(String(localized: "delete"), role: .destructive) {
                    showDeleteConfirm = true
                }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        }
        .alert(
            String(localized: "delete_event"),
            isPresented: $showDeleteConfirm
        ) {
            Button(String(localized: "delete"), role: .destructive) {
                completionStore.remove(event.id)
                withAnimation { eventManager.deleteEvent(event) }
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "delete_event_confirm"))
        }
        .sheet(item: $eventManager.selectedEventWrapper) { wrapper in
            if let event = eventManager.event(for: wrapper) {
                EventDetailView(event: event)
                    .environmentObject(eventManager)
            }
        }
    }

    // MARK: Time-change drag

    private func handleTimeChange(translation: CGFloat) {
        let delta = DragDropLayoutEngine.minuteDelta(from: translation)
        guard let idx = events.firstIndex(where: { $0.id == event.id }) else { return }

        let newStart: Int
        if isSystemEvent, let range = systemConstraint {
            newStart = DragDropLayoutEngine.newStartMinutesForSystem(
                currentMinutes: events[idx].startMinutes,
                delta: delta,
                constraint: range
            )
        } else {
            newStart = DragDropLayoutEngine.newStartMinutes(
                for: events[idx], delta: delta, in: events
            )
        }

        let step = newStart / DragDropLayoutEngine.snapStep
        if step != lastHapticSnap {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            lastHapticSnap = step
        }

        let times = DragDropLayoutEngine.updatedTimes(for: events[idx], newStartMinutes: newStart)
        events[idx].startTime = times.start
        events[idx].endTime   = times.end

        // Only autoPush for regular events
        if !isSystemEvent {
            DragDropLayoutEngine.autoPush(events: &events, movedID: event.id)
        }
    }

    // MARK: Resize drag (end-time label — regular events only)

    private func handleResize(translation: CGFloat) {
        if resizeBaseDuration == nil {
            resizeBaseDuration = event.durationMinutes
        }
        guard let base = resizeBaseDuration,
              let idx = events.firstIndex(where: { $0.id == event.id }) else { return }

        isDragging = true
        let minuteDelta = Int(translation / 12)
        let raw = base + minuteDelta
        let snapped = max(5, (raw / 5) * 5)

        let step = snapped / 5
        if step != lastResizeHapticStep {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            lastResizeHapticStep = step
        }

        let newEndMinutes = events[idx].startMinutes + snapped
        let dayStart = Calendar.current.startOfDay(for: events[idx].startTime)
        events[idx].endTime = dayStart.addingTimeInterval(TimeInterval(newEndMinutes * 60))

        let h = snapped / 60, m = snapped % 60
        if h > 0 && m > 0 { durationPreview = "\(h)h \(m)m" }
        else if h > 0     { durationPreview = "\(h)h" }
        else              { durationPreview = "\(m)m" }
    }

    // MARK: Reorder drag (horizontal — regular events only)

    private func handleReorder(dragY: CGFloat) {
        let threshold: CGFloat = 75
        let cooldown: TimeInterval = 0.15
        let now = Date()
        guard now.timeIntervalSince(lastSwapTime) > cooldown else { return }
        guard let liveIdx = events.firstIndex(where: { $0.id == event.id }) else { return }

        func swap(a: Int, b: Int) {
            // Never swap with system anchors
            guard events[a].id != wakeID, events[a].id != sleepID,
                  events[b].id != wakeID, events[b].id != sleepID else { return }

            let lo = min(events[a].startMinutes, events[b].startMinutes)
            let hi = max(events[a].startMinutes, events[b].startMinutes)
            let tA = DragDropLayoutEngine.updatedTimes(for: events[a], newStartMinutes: lo)
            let tB = DragDropLayoutEngine.updatedTimes(for: events[b], newStartMinutes: hi)

            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                events[a].startTime = tA.start; events[a].endTime = tA.end
                events[b].startTime = tB.start; events[b].endTime = tB.end
                events.sort { $0.startTime < $1.startTime }
            }
            haptic.impactOccurred()
            lastSwapTime = now
            DispatchQueue.main.asyncAfter(deadline: .now() + cooldown) { lastSwapIndex = -1 }
        }

        if dragY > threshold, liveIdx < events.count - 1 {
            let next = liveIdx + 1
            guard lastSwapIndex != next else { return }
            lastSwapIndex = next
            swap(a: liveIdx, b: next)
        }
        if dragY < -threshold, liveIdx > 0 {
            let prev = liveIdx - 1
            guard lastSwapIndex != prev else { return }
            lastSwapIndex = prev
            swap(a: prev, b: liveIdx)
        }
        if abs(dragY) < 20 { lastSwapIndex = -1 }
    }
}

// MARK: - Event Card

private struct DDEventCard: View {

    let event: CalendarEvent
    let isHolding: Bool
    let isSystemEvent: Bool
    let isToday: Bool
    let nearSwap: Bool
    var isCompleted: Bool = false
    var onToggleTick: (() -> Void)? = nil
    var durationPreview: String? = nil
    var onResizeEnd: ((CGFloat) -> Void)? = nil
    var onResizeFinal: ((CGFloat) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var eventManager: EventManager
    @EnvironmentObject var session: SessionStore
    @ObservedObject private var todoStore = LocalTodoStore.shared

    private var myUid: String? { session.currentUserId }
    private var isMyEvent: Bool { event.createdBy == event.owner }
    private var ownerUID: String {
        event.origin == .iCreatedForOther ? event.owner : event.createdBy
    }
    private var ownerLabelIcon: String {
        event.origin == .iCreatedForOther ? "arrow.right.circle.fill" : "person.fill"
    }
    private var shouldShowOwner: Bool {
        guard !isSystemEvent else { return false }
        guard let uid = myUid else { return false }
        return event.createdBy != uid || event.owner != uid
    }

    private let wakeID  = DragDropLayoutEngine.wakeID
    private let sleepID = DragDropLayoutEngine.sleepID

    private var systemIcon: String {
        event.id == wakeID ? "sunrise.fill" : "moon.stars.fill"
    }

    private var pillH: CGFloat {
        if isSystemEvent { return 50 }
        let d = event.durationMinutes
        guard d > 0 else { return 50 }
        return min(max(50 + CGFloat(d - 30) * 0.5, 50), 110)
    }

    var body: some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad

        HStack(alignment: .center, spacing: isPad ? 8 : 4) {

            // ── Time column ──
            ZStack(alignment: isSystemEvent ? .center : .topLeading) {
                Text(event.formattedStartTime)
                    .font(.system(size: isPad ? 15 : 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isSystemEvent ? event.eventColor : .primary)

                if !isSystemEvent {
                    HStack(spacing: 2) {
                        Text(durationPreview ?? event.formattedEndTime)
                            .font(.system(size: 12, weight: isHolding ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(
                                durationPreview != nil
                                    ? event.eventColor
                                    : (isHolding ? event.eventColor : Color.secondary)
                            )
                        if isHolding && durationPreview == nil {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(event.eventColor.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, isHolding ? 5 : 0)
                    .padding(.vertical, isHolding ? 2 : 0)
                    .background(
                        Capsule()
                            .fill(event.eventColor.opacity(isHolding ? 0.12 : 0))
                    )
                    .overlay(
                        Capsule()
                            .stroke(event.eventColor.opacity(isHolding ? 0.3 : 0), lineWidth: 0.8)
                    )
                    .scaleEffect(durationPreview != nil ? 1.08 : 1, anchor: .bottomLeading)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHolding)
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: durationPreview)
                    .gesture(
                        isHolding ?
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in onResizeEnd?(v.translation.height) }
                            .onEnded { v in
                                onResizeEnd?(v.translation.height)
                                onResizeFinal?(v.translation.height)
                            }
                        : nil
                    )
                }
            }
            .frame(width: isPad ? 75 : 58, height: pillH, alignment: isSystemEvent ? .center : .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)

            // ── Icon ──
            Group {
                if isSystemEvent {
                    ZStack {
                        Circle().fill(event.eventColor)
                        Image(systemName: systemIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: isPad ? 58 : 50, height: isPad ? 58 : 50)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(scheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.07))
                        if isRunning() {
                            RoundedRectangle(cornerRadius: 50).stroke(event.eventColor, lineWidth: 2.5)
                        }
                        Image(systemName: EventIconStore.shared.icon(for: event.id) ?? event.originIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(event.eventColor)
                    }
                    .frame(width: isPad ? 58 : 50, height: pillH)
                    .background(
                        RoundedRectangle(cornerRadius: 55)
                            .fill(.ultraThinMaterial)
                            .frame(width: (isPad ? 58 : 50) + 10, height: pillH + 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 50)
                            .stroke(Color.white.opacity(isHolding ? 0.25 : 0.1), lineWidth: 1)
                    )
                }
            }
            .scaleEffect(isHolding ? 1.12 : 1)
            .shadow(
                color: event.eventColor.opacity(isHolding ? 0.35 : 0.15),
                radius: isHolding ? 10 : 4,
                y: isHolding ? 5 : 2
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHolding)

            // ── Title + meta ──
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(isPad ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(isSystemEvent ? event.eventColor : .primary)
                    .lineLimit(1)

                if shouldShowOwner {
                    HStack(spacing: 4) {
                        Image(systemName: ownerLabelIcon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(event.eventColor.opacity(0.75))
                        Text(eventManager.displayName(for: ownerUID))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !isSystemEvent {
                    HStack(spacing: 6) {
                        Text(event.formattedStartTime)
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        if let preview = durationPreview {
                            Text("• \(preview)")
                                .font(.caption).monospacedDigit().foregroundStyle(event.eventColor)
                        } else if event.durationMinutes > 0 {
                            Text("• \(durationText)")
                                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }

                    if isRunning() {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 3)
                                Capsule()
                                    .fill(event.eventColor.opacity(0.65))
                                    .frame(width: geo.size.width * progressFraction, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 2)
                    }
                } else {
                    Text(event.formattedStartTime)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(event.eventColor.opacity(0.8))
                }
            }

            Spacer()

            // ── Undone todo hint (personal events only) ──
            if !isSystemEvent && event.participants.count == 1 {
                let count = todoStore.unfinishedCount(for: event.id)
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.85)))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            // ── Unread chat hint (shared events only) ──
            if !isSystemEvent && event.participants.count > 1 {
                let meta = eventManager.chatMeta(for: event.id)
                if meta.unread && !meta.lastMessage.isEmpty {
                    Text(meta.lastMessage)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }

            // ── Reorder hint (regular events only, shown while holding) ──
            if isHolding && !isSystemEvent {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(nearSwap ? 1 : 0.5)
                .transition(.opacity)
            }

            // ── Completion circle (every day, hidden while holding) ──
            if !isHolding {
                completionCircle
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func isRunning() -> Bool {
        guard !isSystemEvent else { return false }
        // Must be today — time-of-day comparison alone would match events on other days
        guard Calendar.current.isDateInToday(event.startTime) else { return false }
        let now = DragDropLayoutEngine.currentMinutes()
        return now >= event.startMinutes && now <= event.endMinutes
    }

    private var progressFraction: CGFloat {
        guard Calendar.current.isDateInToday(event.startTime) else { return 0 }
        let now = DragDropLayoutEngine.currentMinutes()
        let s = event.startMinutes, e = event.endMinutes
        guard e > s else { return 0 }
        return CGFloat(min(max(now - s, 0), e - s)) / CGFloat(e - s)
    }

    private var durationText: String {
        let h = event.durationMinutes / 60, m = event.durationMinutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    // MARK: - Completion circle

    @ViewBuilder
    private var completionCircle: some View {
        ZStack {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(event.eventColor)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .transition(.opacity)
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                onToggleTick?()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isCompleted)
    }
}

// MARK: - Now Indicator

private struct DDTimeNowIndicator: View {
    let time: String
    var body: some View {
        Text(time)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
    }
}
