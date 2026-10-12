import SwiftUI
import AppKit

struct ThemeSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var eodStore = EndOfDaySettingsStore.shared
    @ObservedObject private var escalationStore = EscalationSettingsStore.shared

    @State private var background: Color
    @State private var accent: Color
    @State private var text: Color
    @State private var opacity: Double
    @State private var fontSize: Double
    @State private var fontName: String
    @State private var cornerRadius: Double

    @State private var eodEnabled: Bool
    @State private var eodTime: Date

    @State private var maxReminders: Int
    @State private var intervalMinutes: Int

    @State private var placement: PanelPlacement

    private let availableFonts = ["System"] + (NSFontManager.shared.availableFontFamilies.sorted())

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
        let theme = ThemeStore.shared.theme
        _background = State(initialValue: theme.background)
        _accent = State(initialValue: theme.accent)
        _text = State(initialValue: theme.text)
        _opacity = State(initialValue: theme.backgroundOpacity)
        _fontSize = State(initialValue: theme.fontSize)
        _fontName = State(initialValue: theme.fontName)
        _cornerRadius = State(initialValue: theme.cornerRadius)

        let eod = EndOfDaySettingsStore.shared.settings
        _eodEnabled = State(initialValue: eod.isEnabled)
        var comps = DateComponents()
        comps.hour = eod.hour
        comps.minute = eod.minute
        _eodTime = State(initialValue: Calendar.current.date(from: comps) ?? .now)

        let escalation = EscalationSettingsStore.shared.settings
        _maxReminders = State(initialValue: escalation.maxReminders)
        _intervalMinutes = State(initialValue: escalation.intervalMinutes)

        _placement = State(initialValue: PlacementStore.shared.settings.placement)
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case smart = "Smart"
        case reminders = "Your reminders"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title3.bold())

            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .general:
                        generalContent
                    case .smart:
                        SmartSettingsView()
                    case .reminders:
                        ManageRemindersView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 440)

            if tab == .general {
                actionButtons
            } else {
                // These take effect right away (deletions once confirmed).
                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    @ViewBuilder
    private var generalContent: some View {
        appearanceSection
        Divider()
        endOfDaySection
        Divider()
        remindersSection
        Divider()
        positionSection
        Divider()
        footerNote
    }

    // MARK: - Sections (split out so the type-checker doesn't choke on one
    // giant body — a single flat VStack with this many controls can make
    // Swift time out and report bogus "cannot find in scope" errors on
    // perfectly valid @State bindings).

    @ViewBuilder
    private var appearanceSection: some View {
        Text("Panel Appearance")
            .font(.headline)

        ColorPicker("Background", selection: $background, supportsOpacity: false)
        Slider(value: $opacity, in: 0.3...1) {
            Text("Opacity")
        }
        ColorPicker("Accent", selection: $accent, supportsOpacity: false)
        ColorPicker("Text", selection: $text, supportsOpacity: false)

        Picker("Font", selection: $fontName) {
            ForEach(availableFonts, id: \.self) { Text($0).tag($0) }
        }

        HStack {
            Text("Size")
            Slider(value: $fontSize, in: 10...18, step: 1)
            Text("\(Int(fontSize))")
                .monospacedDigit()
                .frame(width: 24)
        }

        HStack {
            Text("Corners")
            Slider(value: $cornerRadius, in: 4...28, step: 1)
            Text("\(Int(cornerRadius))")
                .monospacedDigit()
                .frame(width: 24)
        }
    }

    @ViewBuilder
    private var endOfDaySection: some View {
        Text("End of Day Summary")
            .font(.headline)

        Toggle("Show a daily summary", isOn: $eodEnabled)
        if eodEnabled {
            DatePicker("At", selection: $eodTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        Text("Reminders")
            .font(.headline)

        Stepper(value: $maxReminders, in: EscalationSettings.maxRemindersRange) {
            HStack {
                Text("Pop-ups before giving up")
                Spacer()
                Text("\(maxReminders)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        Stepper(value: $intervalMinutes, in: EscalationSettings.intervalMinutesRange) {
            HStack {
                Text("Minutes between pop-ups")
                Spacer()
                Text("\(intervalMinutes)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        Text("Position")
            .font(.headline)

        Picker("Show reminders", selection: $placement) {
            ForEach(PanelPlacement.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.menu)

        Text("Drag the panel anywhere to save that spot as “Custom spot”.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerNote: some View {
        Text("Reminders only fire while your Mac is awake — nothing is scheduled to wake it.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionButtons: some View {
        HStack {
            Button("Reset to Default") {
                themeStore.reset()
                isPresented = false
            }
            Spacer()
            Button("Cancel") { isPresented = false }
            Button("Apply") {
                apply()
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func apply() {
        themeStore.theme = PanelTheme(
            backgroundHex: background.toHex(),
            backgroundOpacity: opacity,
            accentHex: accent.toHex(),
            textHex: text.toHex(),
            fontName: fontName,
            fontSize: fontSize,
            cornerRadius: cornerRadius
        )

        var settings = eodStore.settings
        let comps = Calendar.current.dateComponents([.hour, .minute], from: eodTime)
        let newHour = comps.hour ?? settings.hour
        let newMinute = comps.minute ?? settings.minute
        // Changing the time (or re-enabling) should let it fire again today
        // even if it already showed once — only a genuine same-minute match
        // counts as "already shown," not a stale guard from an old setting.
        if settings.hour != newHour || settings.minute != newMinute || (eodEnabled && !settings.isEnabled) {
            settings.lastShownDayKey = nil
        }
        settings.isEnabled = eodEnabled
        settings.hour = newHour
        settings.minute = newMinute
        eodStore.settings = settings

        escalationStore.settings = EscalationSettings(
            maxReminders: maxReminders,
            intervalMinutes: intervalMinutes
        )

        var placementSettings = PlacementStore.shared.settings
        placementSettings.placement = placement // keeps the saved custom spot
        PlacementStore.shared.settings = placementSettings
    }
}
