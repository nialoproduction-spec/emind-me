import SwiftUI

/// Edit a routine or goal in place: its name, category, and when it reminds
/// you — every so often, at a time on chosen days, or not at all (a goal).
/// Saving re-works out the next reminder from now.
struct EditItemView: View {
    let item: Item
    let theme: PanelTheme
    let onDone: () -> Void

    @ObservedObject private var categories = AppSettings.categories

    private enum Mode: String, CaseIterable, Identifiable {
        case every = "Every…"
        case atTime = "At a time"
        case goal = "Goal"
        var id: String { rawValue }
    }

    private enum IntervalUnit: Double, CaseIterable, Identifiable {
        case minutes = 60, hours = 3600, days = 86400
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .minutes: return "minutes"
            case .hours: return "hours"
            case .days: return "days"
            }
        }
    }

    @State private var title: String
    @State private var category: String?
    @State private var newCategory = ""
    @State private var mode: Mode
    @State private var intervalValue: Int
    @State private var intervalUnit: IntervalUnit
    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var hasTarget: Bool
    @State private var targetDate: Date
    @FocusState private var titleFocused: Bool

    init(item: Item, theme: PanelTheme, onDone: @escaping () -> Void) {
        self.item = item
        self.theme = theme
        self.onDone = onDone
        _title = State(initialValue: item.title)
        _category = State(initialValue: item.category)
        switch item.kind {
        case .repeatingRoutine: _mode = State(initialValue: .every)
        case .scheduledRoutine: _mode = State(initialValue: .atTime)
        case .goal: _mode = State(initialValue: .goal)
        }
        let seconds = item.intervalSeconds ?? 3600
        let unit: IntervalUnit = seconds.truncatingRemainder(dividingBy: 86400) == 0 ? .days
            : seconds.truncatingRemainder(dividingBy: 3600) == 0 ? .hours : .minutes
        _intervalUnit = State(initialValue: unit)
        _intervalValue = State(initialValue: max(1, Int((seconds / unit.rawValue).rounded())))
        var comps = DateComponents()
        comps.hour = item.hour ?? 9
        comps.minute = item.minute ?? 0
        _time = State(initialValue: Calendar.current.date(from: comps) ?? .now)
        _weekdays = State(initialValue: Set(item.weekdaysRaw ?? []))
        _hasTarget = State(initialValue: item.targetDate != nil)
        _targetDate = State(initialValue: item.targetDate ?? Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
    }

    private var edit: ItemActions.Edit {
        var edit = ItemActions.Edit(of: item)
        edit.title = title
        edit.category = category
        switch mode {
        case .every:
            edit.kind = .repeatingRoutine
            edit.intervalSeconds = Double(intervalValue) * intervalUnit.rawValue
        case .atTime:
            edit.kind = .scheduledRoutine
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            edit.hour = parts.hour ?? 9
            edit.minute = parts.minute ?? 0
            edit.weekdays = weekdays.sorted()
        case .goal:
            edit.kind = .goal
            edit.targetDate = hasTarget ? targetDate : nil
        }
        return edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: item.kind == .goal ? "Edit goal" : "Edit reminder", theme: theme, onBack: onDone) {
                Button("Save", action: save)
                    .buttonStyle(.plain)
                    .font(theme.font.weight(.semibold))
                    .foregroundStyle(edit.isValid ? theme.accent : theme.text.opacity(0.3))
                    .disabled(!edit.isValid)
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("Name", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($titleFocused)
                    }
                    field("Category") { categoryPicker }
                    field("Reminds you") {
                        Picker("Reminds you", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    scheduleFields
                }
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: title) { ReminderPanelController.shared.noteActivity() }
    }

    // MARK: - Pieces

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: theme.fontSize - 2, weight: .semibold))
                .foregroundStyle(theme.text.opacity(0.6))
            content()
        }
    }

    private var categoryNames: [String] {
        var names = categories.value.names
        if let category, !names.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) {
            names.append(category)
        }
        return names
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 5) {
                chip("None", selected: category == nil, color: theme.text.opacity(0.6)) { category = nil }
                ForEach(categoryNames, id: \.self) { name in
                    chip(name, selected: category?.caseInsensitiveCompare(name) == .orderedSame,
                         color: CategoryStyle.color(for: name)) { category = name }
                }
            }
            HStack(spacing: 6) {
                TextField("New category", text: $newCategory)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCategory)
                Button("Add", action: addCategory)
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: theme.fontSize - 1))
        }
    }

    private func chip(_ label: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: theme.fontSize - 2, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? color : theme.text.opacity(0.7))
                .background(selected ? color.opacity(0.2) : theme.text.opacity(0.06))
                .overlay(Capsule().strokeBorder(selected ? color.opacity(0.6) : .clear, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var scheduleFields: some View {
        switch mode {
        case .every:
            field("Every") {
                HStack(spacing: 8) {
                    TextField("", value: $intervalValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                    Stepper("", value: $intervalValue, in: 1...999)
                        .labelsHidden()
                    Picker("", selection: $intervalUnit) {
                        ForEach(IntervalUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if Double(intervalValue) * intervalUnit.rawValue < 60 {
                Text("At least a minute apart.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .atTime:
            field("At") {
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }
            field("On") {
                HStack(spacing: 4) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        let on = weekdays.contains(day)
                        Button {
                            if on { weekdays.remove(day) } else { weekdays.insert(day) }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                .font(.system(size: theme.fontSize - 2, weight: .semibold))
                                .frame(width: 26, height: 24)
                                .foregroundStyle(on ? theme.background : theme.text.opacity(0.7))
                                .background(on ? theme.accent : theme.text.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text(weekdays.isEmpty || weekdays.count == 7 ? "Every day" : "Only on the highlighted days")
                .font(.caption)
                .foregroundStyle(theme.text.opacity(0.5))
        case .goal:
            Toggle("Target date", isOn: $hasTarget)
                .foregroundStyle(theme.text)
            if hasTarget {
                DatePicker("By", selection: $targetDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .foregroundStyle(theme.text)
            }
            Text("Goals never pop up — they're kept on your list until you tick them off.")
                .font(.caption)
                .foregroundStyle(theme.text.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Weekdays in the Mac's order (Monday first where that's the custom).
    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    // MARK: - Actions

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !categories.value.names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            categories.value.names.append(name)
        }
        category = categories.value.names.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
        newCategory = ""
    }

    private func save() {
        guard edit.isValid else { return }
        ItemActions.apply(edit, to: item)
        onDone()
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
