import SwiftUI

/// Settings → Smart: snooze lengths, the weekly summary, holding reminders
/// while you're away, suggestions, keyboard shortcuts and categories.
/// Changes apply right away.
struct SmartSettingsView: View {
    @ObservedObject private var snooze = AppSettings.snooze
    @ObservedObject private var weekly = AppSettings.weekly
    @ObservedObject private var goalNudge = AppSettings.goalNudge
    @ObservedObject private var breakTimer = AppSettings.breakTimer
    @ObservedObject private var reminderPopup = AppSettings.reminderPopup
    @ObservedObject private var face = AppSettings.face
    @ObservedObject private var smart = AppSettings.smart
    @ObservedObject private var categories = AppSettings.categories
    @State private var newCategory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            reminderPopupSection
            Divider()
            faceSection
            Divider()
            snoozeSection
            Divider()
            goalSection
            Divider()
            breakTimerSection
            Divider()
            weeklySection
            Divider()
            awaySection
            Divider()
            suggestionsSection
            Divider()
            shortcutsSection
            Divider()
            categoriesSection
        }
        // Everything wraps to the sheet's width; nothing runs off the edges.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Menu bar face

    @ViewBuilder
    private var faceSection: some View {
        Text("Menu bar face").font(.headline)
        Toggle("Wakes up and watches the pointer", isOn: $face.value.followPointer)
        Text("Bring the pointer near it: it opens its eyes and follows you around.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Reminder popup

    @ViewBuilder
    private var reminderPopupSection: some View {
        Text("Reminder popup").font(.headline)
        HStack {
            Picker("Stays for", selection: $reminderPopup.value.seconds) {
                ForEach(ReminderPopupSettings.choices, id: \.self) { seconds in
                    Text(ReminderPopupSettings.label(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Button("Try it") {
                NoticePillController.shared.show(
                    ReminderScheduler.popupContent(title: "Drink water",
                                                   quote: ReminderQuotes.quote(for: "Drink water", pick: Int.random(in: 0..<100)),
                                                   settings: reminderPopup.value)
                )
            }
            .controlSize(.small)
        }
        Picker("Send off with", selection: $reminderPopup.value.dismiss) {
            ForEach(ReminderPopupSettings.Dismiss.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        Text("For reminders (no buttons). It says its last words, then \"Sayonara.\", and dissolves.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Snooze

    @ViewBuilder
    private var snoozeSection: some View {
        Text("Snooze lengths").font(.headline)
        FlowLayout(spacing: 6) {
            ForEach(SnoozeSettings.choices, id: \.self) { minutes in
                let on = snooze.value.presets.contains(minutes)
                Toggle(SnoozeSettings.label(minutes), isOn: Binding(
                    get: { on },
                    set: { wanted in
                        var presets = Set(snooze.value.presets)
                        if wanted { presets.insert(minutes) } else if presets.count > 1 { presets.remove(minutes) }
                        snooze.value.presets = presets.sorted()
                    }
                ))
                .toggleStyle(.button)
                .controlSize(.small)
            }
        }
        Text("A habit's Snooze button uses the shortest (also \(GlobalHotkeys.label(for: .snooze)) and the S key). Right-click Snooze for the others.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Break timer

    @ViewBuilder
    private var breakTimerSection: some View {
        Text("Break timer").font(.headline)
        Toggle("Keep the work countdown at the notch", isOn: $breakTimer.value.keepWorkCountdown)
        Text("Off: it shows when work starts, with 10 minutes left and for the last 10 seconds. Breaks always show. Click it at the notch to hide it.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Text("Notch colours").font(.subheadline.weight(.semibold))
        colorRow("Working", $breakTimer.value.workColor)
        colorRow("Break", $breakTimer.value.breakColor)
        colorRow("Time away", $breakTimer.value.awayColor)
        Text("Time away counts up after a break if you're not back yet.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Button("Reset colours") {
            breakTimer.value.workColor = .black
            breakTimer.value.breakColor = .breakBlue
            breakTimer.value.awayColor = .awayRed
        }
        .controlSize(.small)
    }

    /// Quick colour picks, plus the system picker for anything else. The
    /// label sits above the swatches so the row fits the sheet.
    private func colorRow(_ label: String, _ value: Binding<RGBColor>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 2) {
                swatches(value)
            }
        }
    }

    @ViewBuilder
    private func swatches(_ value: Binding<RGBColor>) -> some View {
            ForEach(RGBColor.swatches, id: \.self) { swatch in
                Button { value.wrappedValue = swatch } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .padding(-3)
                                .opacity(value.wrappedValue == swatch ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .padding(3)
            }
            ColorPicker("", selection: Binding(
                get: { value.wrappedValue.color },
                set: { value.wrappedValue = RGBColor($0) }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Any colour")
    }

    // MARK: - Goal check-in

    @ViewBuilder
    private var goalSection: some View {
        Text("Goal check-in").font(.headline)
        Toggle("Ask about my goals every day", isOn: $goalNudge.value.isEnabled)
        if goalNudge.value.isEnabled {
            DatePicker("At", selection: goalTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
        }
        Text("Each goal gets Done or Not today, so you can see how often you hit it.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var goalTime: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = goalNudge.value.hour
                comps.minute = goalNudge.value.minute
                return Calendar.current.date(from: comps) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                goalNudge.value.hour = parts.hour ?? 20
                goalNudge.value.minute = parts.minute ?? 0
                // A later time can still ask today.
                goalNudge.value.lastShownDayKey = nil
            }
        )
    }

    // MARK: - Weekly summary

    @ViewBuilder
    private var weeklySection: some View {
        Text("Weekly summary").font(.headline)
        Toggle("Show a summary of my week", isOn: $weekly.value.isEnabled)
        if weekly.value.isEnabled {
            Picker("On", selection: $weekly.value.weekday) {
                ForEach(1...7, id: \.self) { day in
                    Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                }
            }
            DatePicker("At", selection: weeklyTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
        }
        Text("Also any time from the chart button in the panel, or right-click the menu bar icon.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var weeklyTime: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = weekly.value.hour
                comps.minute = weekly.value.minute
                return Calendar.current.date(from: comps) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                weekly.value.hour = parts.hour ?? 19
                weekly.value.minute = parts.minute ?? 0
                // A new time can show it again this week.
                weekly.value.lastShownWeekKey = nil
            }
        )
    }

    // MARK: - Away

    @ViewBuilder
    private var awaySection: some View {
        Text("When I'm away").font(.headline)
        Toggle("Hold reminders until I'm back", isOn: $smart.value.holdWhileAway)
        if smart.value.holdWhileAway {
            Stepper(value: $smart.value.awayMinutes, in: 1...30) {
                HStack {
                    Text("Away after no activity for")
                    Spacer()
                    Text("\(smart.value.awayMinutes) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        Text("Reminders wait instead of nagging an empty room, and don't use up their pop-ups while you're gone.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionsSection: some View {
        Text("Suggestions").font(.headline)
        Toggle("Suggest better times", isOn: $smart.value.suggestionsEnabled)
        Text("For example, when you keep doing something later than it's set for, or keep snoozing it. Worked out on this Mac only.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if !smart.value.dismissedSuggestions.isEmpty {
            Button("Bring back dismissed suggestions") {
                smart.value.dismissedSuggestions = []
            }
            .controlSize(.small)
        }
    }

    // MARK: - Shortcuts

    @ViewBuilder
    private var shortcutsSection: some View {
        Text("Keyboard shortcuts").font(.headline)
        Toggle("Answer reminders from any app", isOn: $smart.value.globalShortcuts)
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
            shortcutRow(.done, "Done")
            shortcutRow(.snooze, "Snooze")
            shortcutRow(.skip, "Skip")
        }
        .font(.callout)
        .foregroundStyle(smart.value.globalShortcuts ? Color.primary : Color.secondary)
        Text("Only active while a reminder is on screen. When the reminder has focus, Return, S and K work too.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcutRow(_ action: ReminderScheduler.ShortcutAction, _ label: String) -> some View {
        GridRow {
            Text(GlobalHotkeys.label(for: action))
                .font(.system(.callout, design: .monospaced))
            Text(label)
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesSection: some View {
        Text("Categories").font(.headline)
        FlowLayout(spacing: 6) {
            ForEach(categories.value.names, id: \.self) { name in
                HStack(spacing: 4) {
                    Circle().fill(CategoryStyle.color(for: name)).frame(width: 7, height: 7)
                    Text(name).font(.callout)
                    Button {
                        categories.value.names.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from the list (reminders keep their tag)")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        HStack {
            TextField("New category", text: $newCategory)
                .onSubmit(addCategory)
            Button("Add", action: addCategory)
                .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        Text("Tag a reminder by typing #work, #health… when adding it, or pick one when editing.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !categories.value.names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            categories.value.names.append(name)
        }
        newCategory = ""
    }
}
