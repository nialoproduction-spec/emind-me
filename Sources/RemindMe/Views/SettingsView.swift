import AppKit
import AVFoundation
import Speech
import SwiftUI
@preconcurrency import UserNotifications

// MARK: - The flat look

/// Settings' colours and shapes: flat black, flat red, nothing else.
enum Flat {
    static let background = Color.black
    static let sidebar = Color(white: 0.04)
    static let group = Color(white: 0.08)
    static let line = Color(white: 0.14)
    static let text = Color.white
    static let secondary = Color(white: 0.55)
    static let red = RGBColor.flatRed.color
    static let radius: CGFloat = 8
}

/// A titled group of rows on a flat dark card.
struct FlatGroup<Content: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Flat.secondary)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Flat.group)
                .clipShape(RoundedRectangle(cornerRadius: Flat.radius))
            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(Flat.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }
        }
    }
}

/// One row: a label on the left, its control on the right, a hairline under it.
struct FlatRow<Control: View>: View {
    let label: String
    var detail: String? = nil
    var last = false
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 13)).foregroundStyle(Flat.text)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Flat.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if !last { Rectangle().fill(Flat.line).frame(height: 1).padding(.leading, 12) }
        }
    }
}

/// A row that's just a switch.
struct FlatToggle: View {
    let label: String
    var detail: String? = nil
    var last = false
    @Binding var isOn: Bool

    var body: some View {
        FlatRow(label: label, detail: detail, last: last) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

/// A flat button: red filled (main action) or dark (everything else).
struct FlatButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: primary ? .semibold : .regular))
            .foregroundStyle(Flat.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(primary ? Flat.red : Flat.line)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Settings

/// Settings, one page at a time from the sidebar. Every change saves the
/// moment you make it: there's no Apply and no Cancel.
struct SettingsView: View {
    @Binding var isPresented: Bool

    enum Page: String, CaseIterable, Identifiable {
        case general, reminders, checkIns, notch, shortcuts, look, categories, davinci, health, data, items
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .reminders: return "Reminders"
            case .checkIns: return "Check-ins"
            case .notch: return "Notch"
            case .shortcuts: return "Shortcuts"
            case .look: return "Look"
            case .categories: return "Categories"
            case .davinci: return "DaVinci"
            case .health: return "Health"
            case .data: return "Backup"
            case .items: return "All items"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .reminders: return "bell"
            case .checkIns: return "checkmark.circle"
            case .notch: return "rectangle.topthird.inset.filled"
            case .shortcuts: return "keyboard"
            case .look: return "paintbrush"
            case .categories: return "tag"
            case .davinci: return "film"
            case .health: return "heart.text.square"
            case .data: return "externaldrive"
            case .items: return "list.bullet"
            }
        }
    }

    @State var page: Page = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Flat.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    SettingsPage(page: page)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Flat.background)
        .environment(\.colorScheme, .dark)
        .tint(Flat.red)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Flat.text)
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 10)
            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(item.title).font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundStyle(page == item ? Flat.text : Flat.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(page == item ? Flat.red : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 168)
        .background(Flat.sidebar)
    }

    private var header: some View {
        HStack {
            Text(page.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Flat.text)
            Spacer()
            Button("Done") { isPresented = false }
                .buttonStyle(FlatButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Flat.line).frame(height: 1) }
    }
}

/// The contents of one page. Split out so previews can draw a page without
/// the scrolling frame around it.
struct SettingsPage: View {
    let page: SettingsView.Page

    @ObservedObject private var snooze = AppSettings.snooze
    @ObservedObject private var weekly = AppSettings.weekly
    @ObservedObject private var goalNudge = AppSettings.goalNudge
    @ObservedObject private var breakTimer = AppSettings.breakTimer
    @ObservedObject private var reminderPopup = AppSettings.reminderPopup
    @ObservedObject private var face = AppSettings.face
    @ObservedObject private var smart = AppSettings.smart
    @ObservedObject private var categories = AppSettings.categories
    @ObservedObject private var login = AppSettings.login
    @ObservedObject private var renderWatch = AppSettings.renderWatch
    @ObservedObject private var deliveries = DeliveryLog.store
    @ObservedObject private var keyBindings = KeyBindings.store
    @ObservedObject private var repairs = HealthMonitor.log
    @ObservedObject private var lastCheck = HealthMonitor.lastCheck
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var endOfDay = EndOfDaySettingsStore.shared
    @ObservedObject private var escalation = EscalationSettingsStore.shared
    @ObservedObject private var placement = PlacementStore.shared
    @Environment(\.modelContext) private var modelContext

    @State private var newCategory = ""
    @State private var restoreResult: String?
    @State private var shortcutNote: String?
    @State private var notificationsAllowed: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch page {
            case .general: general
            case .reminders: reminders
            case .checkIns: checkIns
            case .notch: notch
            case .shortcuts: shortcuts
            case .look: look
            case .categories: categoryPage
            case .davinci: davinci
            case .health: health
            case .data: data
            case .items: ManageRemindersView()
            }
        }
    }

    // MARK: General

    @ViewBuilder private var general: some View {
        FlatGroup(title: "Startup") {
            FlatToggle(label: "Open at login", detail: "So reminders keep firing after a restart.", last: true,
                       isOn: Binding(get: { login.value.openAtLogin }, set: { on in
                           LoginItem.set(on)
                           login.value.openAtLogin = LoginItem.isOn
                       }))
        }
        if login.value.openAtLogin, LoginItem.needsApproval {
            FlatGroup(title: "Needs a yes from macOS") {
                FlatRow(label: "Turn Remind Me on in Login Items", last: true) {
                    Button("Open") { LoginItem.openSystemSettings() }.buttonStyle(FlatButtonStyle(primary: true))
                }
            }
        }
        FlatGroup(title: "Panel") {
            FlatRow(label: "Show reminders", detail: "Drag the panel anywhere to save a custom spot.", last: true) {
                Picker("", selection: $placement.settings.placement) {
                    ForEach(PanelPlacement.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        FlatGroup(title: "When I'm away", note: "Reminders wait instead of nagging an empty room.") {
            FlatToggle(label: "Hold reminders until I'm back", last: !smart.value.holdWhileAway,
                       isOn: $smart.value.holdWhileAway)
            if smart.value.holdWhileAway {
                FlatRow(label: "Away after no activity for", last: true) {
                    stepper($smart.value.awayMinutes, in: 1...30, unit: "min")
                }
            }
        }
        FlatGroup(title: "Menu bar face") {
            FlatToggle(label: "Wakes up and watches the pointer", last: true, isOn: $face.value.followPointer)
        }
    }

    // MARK: Reminders

    @ViewBuilder private var reminders: some View {
        FlatGroup(title: "Popup", note: "Reminders have no buttons. Ignore one while you type and it leaves angry.") {
            FlatRow(label: "Stays for") {
                HStack(spacing: 8) {
                    Picker("", selection: $reminderPopup.value.seconds) {
                        ForEach(ReminderPopupSettings.choices, id: \.self) { Text(ReminderPopupSettings.label($0)).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    Button("Try it") {
                        NoticePillController.shared.show(ReminderScheduler.popupContent(
                            title: "Drink water",
                            quote: ReminderQuotes.quote(for: "Drink water", pick: Int.random(in: 0..<100)),
                            settings: reminderPopup.value))
                    }
                    .buttonStyle(FlatButtonStyle())
                }
            }
            FlatRow(label: "Send off with", last: true) {
                Picker("", selection: $reminderPopup.value.dismiss) {
                    ForEach(ReminderPopupSettings.Dismiss.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        FlatGroup(title: "Habits that aren't answered") {
            FlatRow(label: "Pop-ups before giving up") {
                stepper($escalation.settings.maxReminders, in: EscalationSettings.maxRemindersRange, unit: "")
            }
            FlatRow(label: "Minutes between pop-ups", last: true) {
                stepper($escalation.settings.intervalMinutes, in: EscalationSettings.intervalMinutesRange, unit: "min")
            }
        }
        FlatGroup(title: "Snooze lengths",
                  note: "Snooze uses the shortest (\(GlobalHotkeys.label(for: .snooze))). Right-click Snooze for the others.") {
            FlowLayout(spacing: 6) {
                ForEach(SnoozeSettings.choices, id: \.self) { minutes in
                    let on = snooze.value.presets.contains(minutes)
                    Button(SnoozeSettings.label(minutes)) {
                        var presets = Set(snooze.value.presets)
                        if on { if presets.count > 1 { presets.remove(minutes) } } else { presets.insert(minutes) }
                        snooze.value.presets = presets.sorted()
                    }
                    .buttonStyle(FlatButtonStyle(primary: on))
                }
            }
            .padding(12)
        }
        FlatGroup(title: "Suggestions", note: "Worked out on this Mac only.") {
            FlatToggle(label: "Suggest better times", detail: "When you keep doing something later, or keep snoozing it.",
                       last: smart.value.dismissedSuggestions.isEmpty, isOn: $smart.value.suggestionsEnabled)
            if !smart.value.dismissedSuggestions.isEmpty {
                FlatRow(label: "Dismissed suggestions", last: true) {
                    Button("Bring back") { smart.value.dismissedSuggestions = [] }.buttonStyle(FlatButtonStyle())
                }
            }
        }
    }

    // MARK: Check-ins

    @ViewBuilder private var checkIns: some View {
        FlatGroup(title: "Goals", note: "Each goal gets Done or Not today.") {
            FlatToggle(label: "Ask about my goals every day", last: !goalNudge.value.isEnabled,
                       isOn: $goalNudge.value.isEnabled)
            if goalNudge.value.isEnabled {
                FlatRow(label: "At", last: true) {
                    timePicker(hour: goalNudge.value.hour, minute: goalNudge.value.minute) { h, m in
                        goalNudge.value.hour = h
                        goalNudge.value.minute = m
                        goalNudge.value.lastShownDayKey = nil
                    }
                }
            }
        }
        FlatGroup(title: "End of day") {
            FlatToggle(label: "Show a summary of my day", last: !endOfDay.settings.isEnabled,
                       isOn: Binding(get: { endOfDay.settings.isEnabled }, set: { on in
                           if on, !endOfDay.settings.isEnabled { endOfDay.settings.lastShownDayKey = nil }
                           endOfDay.settings.isEnabled = on
                       }))
            if endOfDay.settings.isEnabled {
                FlatRow(label: "At", last: true) {
                    timePicker(hour: endOfDay.settings.hour, minute: endOfDay.settings.minute) { h, m in
                        endOfDay.settings.hour = h
                        endOfDay.settings.minute = m
                        endOfDay.settings.lastShownDayKey = nil
                    }
                }
            }
        }
        FlatGroup(title: "Week", note: "Also from the chart button in the panel, or right-click the menu bar icon.") {
            FlatToggle(label: "Show a summary of my week", last: !weekly.value.isEnabled, isOn: $weekly.value.isEnabled)
            if weekly.value.isEnabled {
                FlatRow(label: "On") {
                    Picker("", selection: $weekly.value.weekday) {
                        ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                }
                FlatRow(label: "At", last: true) {
                    timePicker(hour: weekly.value.hour, minute: weekly.value.minute) { h, m in
                        weekly.value.hour = h
                        weekly.value.minute = m
                        weekly.value.lastShownWeekKey = nil
                    }
                }
            }
        }
    }

    // MARK: Notch

    @ViewBuilder private var notch: some View {
        FlatGroup(title: "Break timer") {
            FlatToggle(label: "Work countdown always counting",
                       detail: "Off: it shows at the start, with 10 minutes left and for the last 10 seconds.",
                       isOn: $breakTimer.value.workCountdownStays)
            FlatToggle(label: "\"Working\" / \"Break\" always shown", detail: "Off: just the face and the time.",
                       last: true, isOn: $breakTimer.value.wordsStay)
        }
        FlatGroup(title: "Colours", note: "Time away counts up in this colour after a break, and a task timer turns it when its time is up.") {
            colourRow("Working", $breakTimer.value.workColor)
            colourRow("Break", $breakTimer.value.breakColor)
            colourRow("Time away / time's up", $breakTimer.value.awayColor, last: true)
        }
        HStack {
            Button("Flat black and red") {
                breakTimer.value.workColor = .black
                breakTimer.value.breakColor = .black
                breakTimer.value.awayColor = .flatRed
            }
            .buttonStyle(FlatButtonStyle())
        }
        FlatGroup(title: "Layout") {
            IslandLayoutEditor().padding(12)
        }
    }

    private func colourRow(_ label: String, _ value: Binding<RGBColor>, last: Bool = false) -> some View {
        FlatRow(label: label, last: last) {
            HStack(spacing: 4) {
                ForEach(RGBColor.swatches, id: \.self) { swatch in
                    Button { value.wrappedValue = swatch } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatch.color)
                            .frame(width: 16, height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(value.wrappedValue == swatch ? Flat.text : Flat.line,
                                              lineWidth: value.wrappedValue == swatch ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(get: { value.wrappedValue.color },
                                                   set: { value.wrappedValue = RGBColor($0) }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .help("Any colour")
            }
        }
    }

    // MARK: Shortcuts

    @ViewBuilder private var shortcuts: some View {
        FlatGroup(title: "From any app") {
            FlatToggle(label: "Use these shortcuts everywhere", last: true, isOn: $smart.value.globalShortcuts)
        }
        FlatGroup(title: "Keys", note: "Click a shortcut, then press the new keys. Done, Snooze and Skip work while a reminder is on screen; Undo works any time.") {
            ForEach(KeyBindings.Action.allCases) { action in
                FlatRow(label: action.title) {
                    ShortcutRecorder(binding: keyBindings.value[action]) { binding in
                        changeShortcut(action, to: binding)
                    }
                }
            }
            FlatRow(label: "Hold to talk", detail: "Hold it on its own to speak a reminder.", last: true) {
                Picker("", selection: $keyBindings.value.talk) {
                    ForEach(TalkKey.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
        .opacity(smart.value.globalShortcuts ? 1 : 0.5)
        if let shortcutNote {
            Text(shortcutNote).font(.system(size: 12)).foregroundStyle(Flat.red)
        }
    }

    private func changeShortcut(_ action: KeyBindings.Action, to binding: KeyBinding) {
        if let other = keyBindings.value.conflict(for: binding, except: action) {
            shortcutNote = "\(binding.display) is already used by \(other.title)."
            return
        }
        shortcutNote = nil
        keyBindings.value[action] = binding
    }

    // MARK: Look

    @MainActor private static let fonts = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()

    @ViewBuilder private var look: some View {
        FlatGroup(title: "Panel colours") {
            FlatRow(label: "Background") { colourWell(\.backgroundHex) }
            FlatRow(label: "Opacity") {
                slider($themeStore.theme.backgroundOpacity, in: 0.3...1, label: "\(Int(themeStore.theme.backgroundOpacity * 100))%")
            }
            FlatRow(label: "Accent") { colourWell(\.accentHex) }
            FlatRow(label: "Text", last: true) { colourWell(\.textHex) }
        }
        FlatGroup(title: "Text and shape") {
            FlatRow(label: "Font") {
                Picker("", selection: $themeStore.theme.fontName) {
                    ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 180)
            }
            FlatRow(label: "Size") {
                slider($themeStore.theme.fontSize, in: 10...18, step: 1, label: "\(Int(themeStore.theme.fontSize))")
            }
            FlatRow(label: "Corners", last: true) {
                slider($themeStore.theme.cornerRadius, in: 0...28, step: 1, label: "\(Int(themeStore.theme.cornerRadius))")
            }
        }
        HStack(spacing: 8) {
            Button("Flat black and red") { themeStore.theme = .flat }.buttonStyle(FlatButtonStyle(primary: true))
            Button("Original look") { themeStore.reset() }.buttonStyle(FlatButtonStyle())
        }
    }

    private func colourWell(_ key: WritableKeyPath<PanelTheme, String>) -> some View {
        ColorPicker("", selection: Binding(get: { Color(hex: themeStore.theme[keyPath: key]) },
                                           set: { themeStore.theme[keyPath: key] = $0.toHex() }),
                    supportsOpacity: false)
            .labelsHidden()
    }

    // MARK: Categories

    @ViewBuilder private var categoryPage: some View {
        FlatGroup(title: "Your categories", note: "Tag a reminder by typing #work, #health… when adding it.") {
            FlowLayout(spacing: 6) {
                ForEach(categories.value.names, id: \.self) { name in
                    HStack(spacing: 5) {
                        Circle().fill(CategoryStyle.color(for: name)).frame(width: 7, height: 7)
                        Text(name).font(.system(size: 12)).foregroundStyle(Flat.text)
                        Button { categories.value.names.removeAll { $0 == name } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Flat.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from the list (reminders keep their tag)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Flat.line)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(12)
            Rectangle().fill(Flat.line).frame(height: 1)
            HStack {
                TextField("New category", text: $newCategory)
                    .textFieldStyle(.plain)
                    .onSubmit(addCategory)
                Button("Add", action: addCategory)
                    .buttonStyle(FlatButtonStyle(primary: true))
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
        }
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !categories.value.names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            categories.value.names.append(name)
        }
        newCategory = ""
    }

    // MARK: DaVinci

    @ViewBuilder private var davinci: some View {
        FlatGroup(title: "Render done ping",
                  note: "When a new video in these folders stops growing while DaVinci Resolve is open, it says \"Render done\".") {
            FlatToggle(label: "Tell me when a render finishes", last: !renderWatch.value.isEnabled,
                       isOn: Binding(get: { renderWatch.value.isEnabled }, set: { on in
                           renderWatch.value.isEnabled = on
                           if on, renderWatch.value.folders.isEmpty {
                               let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path
                               renderWatch.value.folders = [movies ?? NSHomeDirectory() + "/Movies"]
                           }
                       }))
            if renderWatch.value.isEnabled {
                ForEach(renderWatch.value.folders, id: \.self) { folder in
                    FlatRow(label: (folder as NSString).abbreviatingWithTildeInPath) {
                        Button("Remove") { renderWatch.value.folders.removeAll { $0 == folder } }
                            .buttonStyle(FlatButtonStyle())
                    }
                }
                FlatRow(label: "Add a folder", last: true) {
                    Button("Choose…", action: addRenderFolder).buttonStyle(FlatButtonStyle(primary: true))
                }
            }
        }
    }

    private func addRenderFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !renderWatch.value.folders.contains(url.path) { renderWatch.value.folders.append(url.path) }
    }

    // MARK: Health

    @ViewBuilder private var health: some View {
        FlatGroup(title: "Permissions") {
            statusRow("Notifications", ok: notificationsAllowed,
                      fix: "x-apple.systempreferences:com.apple.preference.notifications")
            statusRow("Open at login", ok: login.value.openAtLogin ? !LoginItem.needsApproval : false, fixAction: {
                if login.value.openAtLogin { LoginItem.openSystemSettings() } else {
                    LoginItem.set(true)
                    login.value.openAtLogin = LoginItem.isOn
                }
            })
            statusRow("Microphone (hold to talk)", ok: microphoneOK,
                      fix: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            statusRow("Speech recognition", ok: speechOK,
                      fix: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition", last: true)
        }
        .task { await loadNotificationStatus() }
        FlatGroup(title: "Self-check", note: "Every minute it checks each habit has its notification and the timer is running, and repairs what's missing.") {
            FlatRow(label: "Last check", detail: lastCheck.value.map { Self.when($0) } ?? "Not yet", last: true) {
                Button("Check now") { HealthMonitor.shared.check() }.buttonStyle(FlatButtonStyle(primary: true))
            }
        }
        FlatGroup(title: "Repairs") {
            logList(repairs.value.entries.prefix(15).map { ($0.id, $0.at, "Fixed", $0.text) },
                    empty: "Nothing needed fixing.")
        }
        FlatGroup(title: "Recent deliveries") {
            logList(deliveries.value.entries.prefix(20).map { ($0.id, $0.at, $0.step.label, $0.title + ($0.detail.map { " · \($0)" } ?? "")) },
                    empty: "Each reminder shows up here as it comes due, is shown, answered or missed.")
        }
        if !deliveries.value.entries.isEmpty || !repairs.value.entries.isEmpty {
            Button("Clear both logs") {
                deliveries.value.entries = []
                repairs.value.entries = []
            }
            .buttonStyle(FlatButtonStyle())
        }
    }

    private var microphoneOK: Bool? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return nil
        default: return false
        }
    }

    private var speechOK: Bool? {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return nil
        default: return false
        }
    }

    /// Only inside the real app: the notification centre crashes elsewhere.
    private func loadNotificationStatus() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// A status: green-free on purpose (flat): "On" in white, "Off" in red with a fix button.
    private func statusRow(_ label: String, ok: Bool?, fix: String? = nil, fixAction: (() -> Void)? = nil,
                           last: Bool = false) -> some View {
        FlatRow(label: label, last: last) {
            HStack(spacing: 8) {
                Text(ok == true ? "On" : ok == false ? "Off" : "Not asked yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ok == false ? Flat.red : (ok == true ? Flat.text : Flat.secondary))
                if ok != true {
                    Button("Fix") {
                        if let fixAction { fixAction() } else if let fix, let url = URL(string: fix) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(FlatButtonStyle(primary: true))
                }
            }
        }
    }

    private func logList(_ rows: [(UUID, Date, String, String)], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text(empty)
                    .font(.system(size: 12))
                    .foregroundStyle(Flat.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Self.when(row.1))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Flat.secondary)
                            .frame(width: 92, alignment: .leading)
                        Text(row.2)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(row.2 == "Missed" ? Flat.red : Flat.text)
                            .frame(width: 70, alignment: .leading)
                        Text(row.3)
                            .font(.system(size: 12))
                            .foregroundStyle(Flat.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    if index < rows.count - 1 {
                        Rectangle().fill(Flat.line).frame(height: 1).padding(.leading, 12)
                    }
                }
            }
        }
    }

    private static let whenFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd jmm")
        return formatter
    }()

    static func when(_ date: Date) -> String { whenFormatter.string(from: date) }

    // MARK: Backup

    @ViewBuilder private var data: some View {
        FlatGroup(title: "Backup", note: "One file with every reminder, habit, goal and deadline and their history. A copy is also saved every day (the last 7 are kept). Restoring only adds what's missing; it never deletes.") {
            FlatRow(label: "Save a backup file") {
                Button("Back up…") { Backup.exportWithPanel(from: modelContext) }.buttonStyle(FlatButtonStyle(primary: true))
            }
            FlatRow(label: "Bring back from a file", detail: restoreResult) {
                Button("Restore…") {
                    if let result = Backup.importWithPanel(into: modelContext) {
                        restoreResult = result.items == 0 && result.entries == 0
                            ? "Nothing new: everything in that file is already here."
                            : "Brought back \(result.items) item\(result.items == 1 ? "" : "s") and \(result.entries) history entr\(result.entries == 1 ? "y" : "ies")."
                    }
                }
                .buttonStyle(FlatButtonStyle())
            }
            FlatRow(label: "Daily copies", last: true) {
                Button("Show") {
                    try? FileManager.default.createDirectory(at: Backup.folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Backup.folder)
                }
                .buttonStyle(FlatButtonStyle())
            }
        }
    }

    // MARK: Small controls

    private func stepper(_ value: Binding<Int>, in range: ClosedRange<Int>, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(unit.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(unit)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Flat.text)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }

    private func slider(_ value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil,
                        label: String) -> some View {
        HStack(spacing: 8) {
            Group {
                if let step { Slider(value: value, in: range, step: step) } else { Slider(value: value, in: range) }
            }
            .frame(width: 140)
            Text(label)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Flat.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func timePicker(hour: Int, minute: Int, set: @escaping (Int, Int) -> Void) -> some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(parts.hour ?? hour, parts.minute ?? minute)
            }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.field)
    }
}
