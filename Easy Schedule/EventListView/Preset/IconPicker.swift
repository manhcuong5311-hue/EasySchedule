import SwiftUI

// MARK: - IconPicker

struct IconPicker: View {

    @Binding var icon: String
    @Binding var color: Color

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var premium: PremiumStoreViewModel

    @State private var selectedIcon: String = ""
    @State private var selectedColor: Color = .blue
    @State private var recentIcons: [String] =
        UserDefaults.standard.stringArray(forKey: "recentIcons") ?? []
    @State private var showHexEditor = false
    @State private var showPremiumSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    Divider().opacity(0.4)

                    ScrollView(showsIndicators: false) {
                        iconGridSection
                            .padding(.horizontal, 16)
                            .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle(String(localized: "choose_icon_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "cancel")) { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "done")) {
                        icon = selectedIcon
                        color = selectedColor
                        updateRecent(selectedIcon)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(selectedColor)
                }
            }
        }
        .onAppear {
            selectedIcon = icon
            selectedColor = color
        }
        .sheet(isPresented: $showHexEditor) {
            IconColorPickerSheet(color: $selectedColor)
                .presentationDetents([.height(280)])
        }
        .onChange(of: showHexEditor) { _, isShowing in
            if !isShowing {
                var current = EventColorPalette.colors
                let alreadyExists = current.contains {
                    $0.toHex() == selectedColor.toHex()
                }
                if !alreadyExists {
                    if current.count >= 20 { current.removeLast() }
                    current.append(selectedColor)
                    EventColorPalette.colors = current
                }
            }
        }
        .sheet(isPresented: $showPremiumSheet) {
            PremiumUpgradeSheet(preselectProductID: nil, autoPurchase: false)
                .environmentObject(premium)
        }
    }

    private func updateRecent(_ symbol: String) {
        guard !symbol.isEmpty else { return }
        if let i = recentIcons.firstIndex(of: symbol) { recentIcons.remove(at: i) }
        recentIcons.insert(symbol, at: 0)
        if recentIcons.count > 20 { recentIcons.removeLast() }
        UserDefaults.standard.set(recentIcons, forKey: "recentIcons")
    }
}

// MARK: - Header

extension IconPicker {

    var headerSection: some View {
        HStack(spacing: 20) {

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [selectedColor.opacity(0.9), selectedColor.opacity(0.55)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: selectedIcon.isEmpty ? "star.fill" : selectedIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .id(selectedIcon)
            }
            .shadow(color: selectedColor.opacity(0.35), radius: 10, y: 4)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 7),
                spacing: 10
            ) {
                ForEach(EventColorPalette.colors, id: \.self) { c in
                    ColorSwatch(color: c, isSelected: selectedColor == c) {
                        selectedColor = c
                    }
                }
                Button { showHexEditor = true } label: {
                    ZStack {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 28, height: 28)
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 16, height: 16)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .dark ? Color(.secondarySystemBackground) : .white)
                .shadow(color: .black.opacity(0.05), radius: 12, y: 3)
        )
    }
}

// MARK: - Color Swatch

struct ColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle().fill(color).frame(width: 28, height: 28)
                if isSelected {
                    Circle().stroke(.white, lineWidth: 2.5).frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Icon Grid

extension IconPicker {

    var iconGridSection: some View {
        VStack(alignment: .leading, spacing: 28) {

            if !recentIcons.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel(String(localized: "recent_section"))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recentIcons, id: \.self) { sym in
                                IconCell(symbol: sym, accentColor: selectedColor,
                                         isSelected: selectedIcon == sym) {
                                    selectIcon(sym)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            ForEach(IconCategoryCatalog.categories) { category in
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel(category.title)

                    let visible = Array(category.icons.prefix(
                        premium.visibleIconCount(total: category.icons.count)
                    ))

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(52), spacing: 10), count: 6),
                        spacing: 10
                    ) {
                        ForEach(visible) { item in
                            IconCell(symbol: item.symbol, accentColor: selectedColor,
                                     isSelected: selectedIcon == item.symbol) {
                                selectIcon(item.symbol)
                            }
                        }

                        if !premium.isPremium &&
                            category.icons.count > PremiumLimits.maxFreeIconsPerCategory {
                            Button { showPremiumSheet = true } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color.yellow.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                                        )
                                    VStack(spacing: 2) {
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.yellow)
                                        Text("+\(category.icons.count - PremiumLimits.maxFreeIconsPerCategory)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.yellow)
                                    }
                                }
                                .frame(width: 52, height: 52)
                            }
                        }
                    }
                }
            }
        }
    }

    func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    func selectIcon(_ sym: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
            selectedIcon = sym
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Icon Cell

struct IconCell: View {
    let symbol: String
    let accentColor: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected
                          ? accentColor.opacity(0.15)
                          : Color(.secondarySystemBackground))

                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accentColor.opacity(0.5), lineWidth: 1.5)
                }

                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? accentColor : .primary)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Color Picker Sheet

struct IconColorPickerSheet: View {
    @Binding var color: Color
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)

                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .shadow(color: color.opacity(0.4), radius: 10, y: 4)

                ColorPicker(String(localized: "pick_color"), selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.6)
                    .padding(.vertical, 8)

                Button(String(localized: "done")) { dismiss() }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(color, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

// MARK: - Color Palette

struct EventColorPalette {
    static let defaultColors: [Color] = [
        .blue, .green, .purple, .pink, .orange, .red,
        .teal, .indigo, .mint, .yellow, .cyan, .brown, .gray
    ]

    static var colors: [Color] {
        get {
            if let hexes = UserDefaults.standard.stringArray(forKey: "presetColors") {
                return hexes.map { Color(hex: $0) }
            }
            return defaultColors
        }
        set {
            UserDefaults.standard.set(newValue.compactMap { $0.toHex() }, forKey: "presetColors")
        }
    }
}

// MARK: - Icon Catalog

struct EventIcon: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let name: String
}

struct IconCategory: Identifiable {
    let id = UUID()
    let title: String
    let icons: [EventIcon]
}

struct IconCategoryCatalog {
    static let categories: [IconCategory] = [

        IconCategory(title: String(localized: "icon_category_work"), icons: [
            EventIcon(symbol: "briefcase.fill",                    name: "Work"),
            EventIcon(symbol: "calendar",                          name: "Schedule"),
            EventIcon(symbol: "doc.text.fill",                     name: "Document"),
            EventIcon(symbol: "folder.fill",                       name: "Files"),
            EventIcon(symbol: "tray.full.fill",                    name: "Inbox"),
            EventIcon(symbol: "paperplane.fill",                   name: "Send"),
            EventIcon(symbol: "envelope.fill",                     name: "Email"),
            EventIcon(symbol: "clock.fill",                        name: "Deadline"),
            EventIcon(symbol: "checkmark.circle.fill",             name: "Done"),
            EventIcon(symbol: "flag.fill",                         name: "Priority"),
            EventIcon(symbol: "chart.bar.fill",                    name: "Analytics"),
            EventIcon(symbol: "chart.pie.fill",                    name: "Report"),
            EventIcon(symbol: "chart.line.uptrend.xyaxis",         name: "Growth"),
            EventIcon(symbol: "person.3.fill",                     name: "Team"),
            EventIcon(symbol: "video.fill",                        name: "Meeting"),
            EventIcon(symbol: "mic.fill",                          name: "Presentation"),
            EventIcon(symbol: "megaphone.fill",                    name: "Announce"),
            EventIcon(symbol: "rectangle.and.pencil.and.ellipsis", name: "Edit"),
            EventIcon(symbol: "building.2.fill",                   name: "Office"),
            EventIcon(symbol: "phone.fill",                        name: "Call"),
            EventIcon(symbol: "dollarsign.circle.fill",            name: "Finance"),
            EventIcon(symbol: "creditcard.fill",                   name: "Payment"),
            EventIcon(symbol: "signature",                         name: "Contract"),
            EventIcon(symbol: "list.clipboard.fill",               name: "Checklist")
        ]),

        IconCategory(title: String(localized: "icon_category_study"), icons: [
            EventIcon(symbol: "book.fill",                         name: "Study"),
            EventIcon(symbol: "books.vertical.fill",               name: "Library"),
            EventIcon(symbol: "graduationcap.fill",                name: "Learning"),
            EventIcon(symbol: "pencil",                            name: "Writing"),
            EventIcon(symbol: "highlighter",                       name: "Highlight"),
            EventIcon(symbol: "brain.head.profile",                name: "Thinking"),
            EventIcon(symbol: "lightbulb.fill",                    name: "Idea"),
            EventIcon(symbol: "bookmark.fill",                     name: "Bookmark"),
            EventIcon(symbol: "text.book.closed.fill",             name: "Reading"),
            EventIcon(symbol: "magnifyingglass",                   name: "Search"),
            EventIcon(symbol: "note.text",                         name: "Notes"),
            EventIcon(symbol: "pencil.and.outline",                name: "Edit"),
            EventIcon(symbol: "square.and.pencil",                 name: "Write"),
            EventIcon(symbol: "abc",                               name: "Language"),
            EventIcon(symbol: "function",                          name: "Math"),
            EventIcon(symbol: "x.squareroot",                      name: "Science"),
            EventIcon(symbol: "globe",                             name: "History"),
            EventIcon(symbol: "music.note",                        name: "Music Theory"),
            EventIcon(symbol: "paintbrush.fill",                   name: "Art"),
            EventIcon(symbol: "keyboard",                          name: "Typing"),
            EventIcon(symbol: "clock.arrow.circlepath",            name: "Review"),
            EventIcon(symbol: "trophy.fill",                       name: "Goal"),
            EventIcon(symbol: "star.fill",                         name: "Achievement"),
            EventIcon(symbol: "flame.fill",                        name: "Streak")
        ]),

        IconCategory(title: String(localized: "icon_category_health_fitness"), icons: [
            EventIcon(symbol: "heart.fill",                        name: "Health"),
            EventIcon(symbol: "figure.walk",                       name: "Walk"),
            EventIcon(symbol: "figure.run",                        name: "Run"),
            EventIcon(symbol: "figure.strengthtraining.traditional", name: "Gym"),
            EventIcon(symbol: "dumbbell.fill",                     name: "Workout"),
            EventIcon(symbol: "figure.yoga",                       name: "Yoga"),
            EventIcon(symbol: "figure.mind.and.body",              name: "Mindfulness"),
            EventIcon(symbol: "figure.cooldown",                   name: "Stretch"),
            EventIcon(symbol: "figure.hiking",                     name: "Hike"),
            EventIcon(symbol: "figure.pool.swim",                  name: "Swim"),
            EventIcon(symbol: "figure.outdoor.cycle",              name: "Cycle"),
            EventIcon(symbol: "figure.dance",                      name: "Dance"),
            EventIcon(symbol: "bed.double.fill",                   name: "Sleep"),
            EventIcon(symbol: "leaf.fill",                         name: "Meditation"),
            EventIcon(symbol: "lungs.fill",                        name: "Breathing"),
            EventIcon(symbol: "drop.fill",                         name: "Water"),
            EventIcon(symbol: "fork.knife.circle.fill",            name: "Diet"),
            EventIcon(symbol: "pill.fill",                         name: "Medicine"),
            EventIcon(symbol: "cross.case.fill",                   name: "Medical"),
            EventIcon(symbol: "stethoscope",                       name: "Doctor"),
            EventIcon(symbol: "waveform.path.ecg",                 name: "HeartRate"),
            EventIcon(symbol: "bandage.fill",                      name: "Recovery"),
            EventIcon(symbol: "scalemass.fill",                    name: "Weight"),
            EventIcon(symbol: "allergens.fill",                    name: "Nutrition")
        ]),

        IconCategory(title: String(localized: "icon_category_life"), icons: [
            EventIcon(symbol: "house.fill",                        name: "Home"),
            EventIcon(symbol: "cup.and.saucer.fill",               name: "Coffee"),
            EventIcon(symbol: "fork.knife",                        name: "Food"),
            EventIcon(symbol: "cart.fill",                         name: "Shopping"),
            EventIcon(symbol: "bag.fill",                          name: "Errands"),
            EventIcon(symbol: "gift.fill",                         name: "Gift"),
            EventIcon(symbol: "birthday.cake.fill",                name: "Birthday"),
            EventIcon(symbol: "sparkles",                          name: "Special"),
            EventIcon(symbol: "person.fill",                       name: "Personal"),
            EventIcon(symbol: "person.2.fill",                     name: "Friends"),
            EventIcon(symbol: "heart.circle.fill",                 name: "Self-care"),
            EventIcon(symbol: "face.smiling.fill",                 name: "Joy"),
            EventIcon(symbol: "bubble.left.and.bubble.right.fill", name: "Social"),
            EventIcon(symbol: "house.and.flag.fill",               name: "Family"),
            EventIcon(symbol: "pawprint.fill",                     name: "Pet"),
            EventIcon(symbol: "paintbrush.pointed.fill",           name: "Creative"),
            EventIcon(symbol: "scissors",                          name: "Haircut"),
            EventIcon(symbol: "washer.fill",                       name: "Chores"),
            EventIcon(symbol: "hammer.fill",                       name: "Repair"),
            EventIcon(symbol: "trash.fill",                        name: "Clean"),
            EventIcon(symbol: "sofa.fill",                         name: "Relax"),
            EventIcon(symbol: "tv.fill",                           name: "Watch"),
            EventIcon(symbol: "newspaper.fill",                    name: "Read"),
            EventIcon(symbol: "dollarsign.arrow.circlepath",       name: "Budget")
        ]),

        IconCategory(title: String(localized: "icon_category_creative"), icons: [
            EventIcon(symbol: "paintpalette.fill",                 name: "Art"),
            EventIcon(symbol: "camera.fill",                       name: "Photo"),
            EventIcon(symbol: "video.fill",                        name: "Video"),
            EventIcon(symbol: "music.note",                        name: "Music"),
            EventIcon(symbol: "waveform",                          name: "Podcast"),
            EventIcon(symbol: "headphones",                        name: "Listen"),
            EventIcon(symbol: "guitars.fill",                      name: "Guitar"),
            EventIcon(symbol: "pianokeys.inverse",                 name: "Piano"),
            EventIcon(symbol: "mic.circle.fill",                   name: "Record"),
            EventIcon(symbol: "film.fill",                         name: "Film"),
            EventIcon(symbol: "photo.artframe",                    name: "Gallery"),
            EventIcon(symbol: "pencil.tip.crop.circle.fill",       name: "Sketch"),
            EventIcon(symbol: "scribble.variable",                 name: "Doodle"),
            EventIcon(symbol: "theatermasks.fill",                 name: "Theater"),
            EventIcon(symbol: "building.columns.fill",             name: "Museum"),
            EventIcon(symbol: "books.vertical",                    name: "Writing"),
            EventIcon(symbol: "gamecontroller.fill",               name: "Gaming"),
            EventIcon(symbol: "puzzlepiece.fill",                  name: "Puzzle"),
            EventIcon(symbol: "dice.fill",                         name: "Game"),
            EventIcon(symbol: "party.popper.fill",                 name: "Celebrate")
        ]),

        IconCategory(title: String(localized: "icon_category_tech"), icons: [
            EventIcon(symbol: "laptopcomputer",                    name: "Laptop"),
            EventIcon(symbol: "desktopcomputer",                   name: "Desktop"),
            EventIcon(symbol: "iphone",                            name: "Phone"),
            EventIcon(symbol: "ipad",                              name: "Tablet"),
            EventIcon(symbol: "applewatch",                        name: "Watch"),
            EventIcon(symbol: "airpodspro",                        name: "Audio"),
            EventIcon(symbol: "wifi",                              name: "Internet"),
            EventIcon(symbol: "gearshape.fill",                    name: "Settings"),
            EventIcon(symbol: "gearshape.2.fill",                  name: "System"),
            EventIcon(symbol: "cpu.fill",                          name: "CPU"),
            EventIcon(symbol: "externaldrive.fill",                name: "Storage"),
            EventIcon(symbol: "icloud.fill",                       name: "Cloud"),
            EventIcon(symbol: "bolt.fill",                         name: "Power"),
            EventIcon(symbol: "terminal.fill",                     name: "Terminal"),
            EventIcon(symbol: "chevron.left.slash.chevron.right",  name: "Code"),
            EventIcon(symbol: "app.badge.fill",                    name: "App"),
            EventIcon(symbol: "network",                           name: "Network"),
            EventIcon(symbol: "server.rack",                       name: "Server"),
            EventIcon(symbol: "lock.shield.fill",                  name: "Security"),
            EventIcon(symbol: "antenna.radiowaves.left.and.right", name: "Signal"),
            EventIcon(symbol: "visionpro",                         name: "XR"),
            EventIcon(symbol: "printer.fill",                      name: "Print"),
            EventIcon(symbol: "scanner.fill",                      name: "Scan"),
            EventIcon(symbol: "memorychip.fill",                   name: "AI")
        ]),

        IconCategory(title: String(localized: "icon_category_travel"), icons: [
            EventIcon(symbol: "airplane",                          name: "Flight"),
            EventIcon(symbol: "car.fill",                          name: "Drive"),
            EventIcon(symbol: "tram.fill",                         name: "Transit"),
            EventIcon(symbol: "bus.fill",                          name: "Bus"),
            EventIcon(symbol: "bicycle",                           name: "Bike"),
            EventIcon(symbol: "scooter",                           name: "Scooter"),
            EventIcon(symbol: "ferry.fill",                        name: "Boat"),
            EventIcon(symbol: "map.fill",                          name: "Map"),
            EventIcon(symbol: "location.fill",                     name: "Location"),
            EventIcon(symbol: "mappin.and.ellipse",                name: "Pin"),
            EventIcon(symbol: "suitcase.fill",                     name: "Trip"),
            EventIcon(symbol: "tent.fill",                         name: "Camping"),
            EventIcon(symbol: "binoculars.fill",                   name: "Explore"),
            EventIcon(symbol: "camera.aperture",                   name: "Sightseeing"),
            EventIcon(symbol: "beach.umbrella.fill",               name: "Beach"),
            EventIcon(symbol: "mountain.2.fill",                   name: "Mountain"),
            EventIcon(symbol: "fuelpump.fill",                     name: "Fuel"),
            EventIcon(symbol: "parkingsign.circle.fill",           name: "Parking"),
            EventIcon(symbol: "key.fill",                          name: "Hotel"),
            EventIcon(symbol: "fork.knife",                        name: "Restaurant")
        ]),

        IconCategory(title: String(localized: "icon_category_mindset_goals"), icons: [
            EventIcon(symbol: "target",                            name: "Target"),
            EventIcon(symbol: "trophy.fill",                       name: "Win"),
            EventIcon(symbol: "medal.fill",                        name: "Medal"),
            EventIcon(symbol: "rosette",                           name: "Badge"),
            EventIcon(symbol: "flame.fill",                        name: "Motivation"),
            EventIcon(symbol: "bolt.circle.fill",                  name: "Energy"),
            EventIcon(symbol: "star.circle.fill",                  name: "Dream"),
            EventIcon(symbol: "arrow.up.circle.fill",              name: "Progress"),
            EventIcon(symbol: "checkmark.seal.fill",               name: "Certified"),
            EventIcon(symbol: "crown.fill",                        name: "Excellence"),
            EventIcon(symbol: "infinity",                          name: "Consistency"),
            EventIcon(symbol: "chart.line.uptrend.xyaxis.circle.fill", name: "Improve"),
            EventIcon(symbol: "hand.raised.fill",                  name: "Discipline"),
            EventIcon(symbol: "eyes",                              name: "Focus"),
            EventIcon(symbol: "brain",                             name: "Growth"),
            EventIcon(symbol: "figure.stand",                      name: "Confidence"),
            EventIcon(symbol: "sun.max.fill",                      name: "Positivity"),
            EventIcon(symbol: "moon.zzz.fill",                     name: "Rest"),
            EventIcon(symbol: "heart.circle.fill",                 name: "Gratitude"),
            EventIcon(symbol: "leaf.circle.fill",                  name: "Balance")
        ]),

        IconCategory(title: String(localized: "icon_category_finance"), icons: [
            EventIcon(symbol: "dollarsign.circle.fill",            name: "Money"),
            EventIcon(symbol: "creditcard.fill",                   name: "Card"),
            EventIcon(symbol: "banknote.fill",                     name: "Cash"),
            EventIcon(symbol: "chart.bar.xaxis",                   name: "Budget"),
            EventIcon(symbol: "arrow.up.arrow.down.circle.fill",   name: "Transfer"),
            EventIcon(symbol: "cart.badge.plus",                   name: "Purchase"),
            EventIcon(symbol: "bag.badge.minus",                   name: "Expense"),
            EventIcon(symbol: "building.columns.fill",             name: "Bank"),
            EventIcon(symbol: "percent",                           name: "Tax"),
            EventIcon(symbol: "doc.text.magnifyingglass",          name: "Invoice"),
            EventIcon(symbol: "lock.rotation",                     name: "Subscription"),
            EventIcon(symbol: "arrow.clockwise.circle.fill",       name: "Recurring"),
            EventIcon(symbol: "gift.circle.fill",                  name: "Bonus"),
            EventIcon(symbol: "wonsign.circle.fill",               name: "Savings"),
            EventIcon(symbol: "chart.xyaxis.line",                 name: "Invest")
        ])
    ]
}
