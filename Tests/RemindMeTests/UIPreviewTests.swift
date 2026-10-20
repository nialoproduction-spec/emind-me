import XCTest
import SwiftUI
import AppKit
import SwiftData
@testable import RemindMe

/// Renders the real SwiftUI views to PNG files so they can be looked at
/// without running the app (CI attaches them to the GitHub Release).
/// Only runs when PREVIEW_DIR is set; otherwise it's a no-op.
@MainActor
final class UIPreviewTests: XCTestCase {

    private var outputDir: URL? {
        guard let path = ProcessInfo.processInfo.environment["PREVIEW_DIR"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func save<V: View>(_ view: V, as name: String) throws {
        guard let dir = outputDir else { return }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "render failed: \(name)")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: dir.appendingPathComponent(name))
    }

    private let theme = PanelTheme.default

    private func card(popCount: Int, reaction: FaceMood? = nil, title: String = "Drink water",
                      choosingSnooze: Bool = false) -> some View {
        let item = Item(title: title, kind: .repeatingRoutine, intervalSeconds: 40 * 60)
        let occurrence = Occurrence(item: item, scheduledFireDate: .now)
        occurrence.remindersSentCount = popCount
        return ZStack {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.background.opacity(theme.backgroundOpacity))
            LiveReminderView(occurrence: occurrence, theme: theme, initialReaction: reaction,
                             choosingSnooze: choosingSnooze)
        }
        .frame(width: ReminderPanelController.liveReminderSize.width,
               height: ReminderPanelController.liveReminderSize.height)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .padding(10)
        .background(Color(white: 0.5))
    }

    func testRenderReminderCards() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let cards = HStack(spacing: 0) {
            card(popCount: 1)
            card(popCount: 2)
            card(popCount: 3)
        }
        try save(cards, as: "preview-1-pops-gentle-nudge-urgent.png")
        let reactions = HStack(spacing: 0) {
            card(popCount: 1, reaction: .done)
            card(popCount: 1, reaction: .snoozed)
            card(popCount: 1, reaction: .skipped, title: "Stretch your back and refill the water bottle")
        }
        try save(reactions, as: "preview-2-reactions-done-snooze-skip.png")
    }

    func testRenderAllFaces() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let grid = Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<8, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let face = Face(rawValue: row * 3 + col + 1)!
                        VStack(spacing: 2) {
                            FaceView(face: face, color: .white).frame(width: 150, height: 78)
                            Text("\(face.rawValue) \(String(describing: face))")
                                .font(.system(size: 9)).foregroundStyle(.gray)
                        }
                        .padding(4)
                        .background(Color(white: 0.11))
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black)
        try save(grid, as: "preview-3-all-faces.png")
    }

    func testRenderAnimationFilmstrips() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let moods: [(FaceMood, String)] = [(.gentle, "gentle"), (.nudge, "nudge"), (.urgent, "urgent"),
                                            (.done, "done"), (.snoozed, "snoozed"), (.skipped, "skipped")]
        let times: [Double] = [0, 0.1, 0.2, 0.3, 0.45, 0.6, 0.8, 1.0, 1.5, 2.25]
        let strips = VStack(alignment: .leading, spacing: 4) {
            ForEach(moods.indices, id: \.self) { index in
                let mood = moods[index].0
                let label = moods[index].1
                HStack(spacing: 4) {
                    Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 56, alignment: .leading)
                    ForEach(times, id: \.self) { t in
                        let frame = FaceScript.frame(for: mood, at: t)
                        VStack(spacing: 1) {
                            FaceView(face: frame.face, color: .white)
                                .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .bottom)
                                .rotationEffect(.degrees(frame.rotation))
                                .offset(x: frame.dx, y: frame.dy)
                                .frame(width: 84, height: 44)
                            Text(String(format: "%.2fs", t)).font(.system(size: 8)).foregroundStyle(.gray)
                        }
                        .padding(3)
                        .background(Color(white: 0.11))
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black)
        try save(strips, as: "preview-4-animation-filmstrips.png")
    }

    private func icon(_ image: NSImage, _ color: Color) -> some View {
        Image(nsImage: image).renderingMode(.template).foregroundStyle(color)
    }

    func testRenderMenuBarIcon() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let reactions = HoverReaction.allCases
        let times: [Double] = [0.05, 0.3, 0.6, 2.0]
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach([true, false], id: \.self) { dark in
                let fg: Color = dark ? .white : .black
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("idle").font(.system(size: 10)).foregroundStyle(fg).frame(width: 64, alignment: .leading)
                        self.icon(MenuBarFace.logoImage(), fg)
                        Text("Tue 13 Oct 1:37 AM").font(.system(size: 13)).foregroundStyle(fg)
                    }
                    ForEach(reactions.indices, id: \.self) { i in
                        let reaction = reactions[i]
                        let span = MenuBarFace.span(of: reaction.beats.map { $0.face })
                        HStack(spacing: 10) {
                            Text("hover: \(reaction.rawValue)").font(.system(size: 10)).foregroundStyle(fg)
                                .frame(width: 64, alignment: .leading)
                            ForEach(times, id: \.self) { t in
                                self.icon(MenuBarFace.faceImage(reaction.face(at: t), span: span, offset: reaction.motion(at: t)), fg)
                            }
                        }
                    }
                    ForEach([FaceMood.gentle, .nudge, .urgent], id: \.self) { mood in
                        let faces = FaceScript.beats(for: mood).map { $0.face }
                        let span = MenuBarFace.span(of: faces)
                        HStack(spacing: 10) {
                            Text("due: \(String(describing: mood))").font(.system(size: 10)).foregroundStyle(fg)
                                .frame(width: 64, alignment: .leading)
                            ForEach(Array(Set(faces)).sorted { $0.rawValue < $1.rawValue }.prefix(5), id: \.self) { face in
                                self.icon(MenuBarFace.faceImage(face, span: span, offset: .zero), fg)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(width: 330, alignment: .leading)
                .background(dark ? Color(white: 0.12) : Color(white: 0.92))
            }
        }
        try save(sheet, as: "preview-5-menu-bar.png")
    }

    func testRenderPlacements() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        // A scaled-down 1440 × 900 screen for each placement.
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let icon = CGRect(x: 1180, y: 875, width: 38, height: 25)
        let scale: CGFloat = 0.15
        let sheet = HStack(spacing: 10) {
            ForEach(PanelPlacement.allCases) { placement in
                let f = PanelPlacementMath.frame(
                    for: placement, size: ReminderPanelController.liveReminderSize, visibleFrame: screen,
                    customTopLeft: CGPoint(x: 520, y: 600), statusItemFrame: icon)
                VStack(spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color(white: 0.25)).frame(width: 1440 * scale, height: 900 * scale)
                        Rectangle().fill(Color(white: 0.4)).frame(width: 1440 * scale, height: 25 * scale)
                        Rectangle().fill(Color.white).frame(width: icon.width * scale, height: 3)
                            .offset(x: icon.minX * scale, y: 1)
                        RoundedRectangle(cornerRadius: 3).fill(Color.blue)
                            .frame(width: f.width * scale, height: f.height * scale)
                            .offset(x: f.minX * scale, y: (900 - f.maxY) * scale)
                    }
                    .frame(width: 1440 * scale, height: 900 * scale)
                    Text(placement.label).font(.system(size: 10)).foregroundStyle(.white)
                }
            }
        }
        .padding(10)
        .background(Color.black)
        try save(sheet, as: "preview-6-placements.png")
    }

    func testRenderManageReminders() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let container = try ModelContainer(
            for: Item.self, Occurrence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        for text in ["drink water every 40 minutes", "walk at 4am every day", "read a book at 7am",
                     "go to Godavari", "pay rent by friday", "stretch every hour"] {
            context.insert(Item(from: ItemParser.parse(text)))
        }
        let paused = Item(from: ItemParser.parse("meditate at 6am"))
        paused.isActive = false
        context.insert(paused)
        try context.save()

        let view = ManageRemindersView()
            .modelContainer(container)
            .padding(20)
            .frame(width: 340)
            .background(Color(nsColor: .windowBackgroundColor))
        try save(view, as: "preview-7-your-reminders.png")
    }

    // MARK: - New screens

    /// A dark panel-coloured backdrop of a given size.
    private func panel<V: View>(width: CGFloat, height: CGFloat? = nil, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: width, height: height, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(theme.background.opacity(theme.backgroundOpacity))
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .padding(10)
            .background(Color(white: 0.5))
    }

    /// Sample routines with two weeks of history.
    private func sampleData() throws -> (ModelContainer, [Item], [Occurrence]) {
        let container = try ModelContainer(
            for: Item.self, Occurrence.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let water = Item(from: ItemParser.parse("drink water every 40 minutes #health"))
        let walk = Item(from: ItemParser.parse("walk at 4pm every day #health"))
        let standup = Item(from: ItemParser.parse("standup notes at 9:30am on weekdays #work"))
        let goal = Item(from: ItemParser.parse("go to Godavari #travel"))
        let paused = Item(from: ItemParser.parse("meditate at 6am"))
        paused.isActive = false
        paused.pausedUntil = Calendar.current.date(byAdding: .day, value: 1, to: .now)
        [water, walk, standup, goal, paused].forEach { context.insert($0) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let walkAt = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: day)!
            let walked = Occurrence(item: walk, scheduledFireDate: walkAt)
            walked.status = offset == 9 ? .skipped : (offset == 0 ? .pending : .done)
            walked.resolvedAt = walkAt.addingTimeInterval(35 * 60)
            context.insert(walked)
            for hour in [9, 10, 11, 14] {
                let at = calendar.date(bySettingHour: hour, minute: 20, second: 0, of: day)!
                guard at < .now else { continue }
                let sip = Occurrence(item: water, scheduledFireDate: at)
                sip.status = (offset + hour) % 5 == 0 ? .unfinished : ((offset + hour) % 4 == 0 ? .skipped : .done)
                if hour == 14 { sip.snoozedMinutes = 15 }
                context.insert(sip)
            }
        }
        try context.save()
        let items = try context.fetch(FetchDescriptor<Item>())
        let occurrences = try context.fetch(FetchDescriptor<Occurrence>())
        return (container, items, occurrences)
    }

    func testRenderNewCardsAndRows() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let (container, items, occurrences) = try sampleData()
        _ = container
        let cards = HStack(spacing: 0) {
            card(popCount: 1)
            card(popCount: 1, choosingSnooze: true)
        }
        try save(cards, as: "preview-8-card-shortcuts-and-snooze-lengths.png")

        func find(_ prefix: String) -> Item { items.first { $0.title.hasPrefix(prefix) }! }
        let today = occurrences.filter { $0.dayKey == Occurrence.dayKey(for: .now) }
            .sorted { $0.scheduledFireDate < $1.scheduledFireDate }
        let rows = panel(width: 340) {
            VStack(alignment: .leading, spacing: 8) {
                Text("GOALS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.gray)
                ReminderRowView(item: find("Go"), theme: theme, onToggle: {})
                Text("REMINDERS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.gray)
                ReminderRowView(item: find("Walk"), theme: theme, streak: 4, onToggle: {})
                ReminderRowView(item: find("Meditate"), theme: theme, onToggle: {})
                Text("TODAY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.gray)
                ForEach(today.prefix(4)) { ChecklistRowView(occurrence: $0, theme: self.theme) }
                SuggestionBar(
                    suggestion: Insights.Suggestion(
                        id: "x", itemID: find("Walk").persistentModelID,
                        message: "You usually do “Walk” around 4:35 PM. Move it there?",
                        actionLabel: "Move to 4:35 PM", action: .moveTime(hour: 16, minute: 35)),
                    theme: theme, onApply: {}, onDismiss: {}
                )
            }
            .padding(14)
        }
        try save(rows, as: "preview-9-list-rows.png")
    }

    func testRenderHistoryAndWeekly() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let (container, items, occurrences) = try sampleData()
        _ = container
        let walk = try XCTUnwrap(items.first { $0.title.hasPrefix("Walk") })
        let water = try XCTUnwrap(items.first { $0.title.hasPrefix("Drink") })
        let sheet = HStack(alignment: .top, spacing: 0) {
            panel(width: 340) {
                ItemHistoryContent(item: walk, occurrences: occurrences, theme: theme, now: .now).padding(14)
            }
            panel(width: 340) {
                ItemHistoryContent(item: water, occurrences: occurrences, theme: theme, now: .now).padding(14)
            }
            panel(width: 340) {
                WeeklySummaryContent(
                    summary: Insights.weeklySummary(items: items, occurrences: occurrences, now: .now),
                    theme: theme
                )
                .padding(14)
            }
        }
        try save(sheet, as: "preview-10-history-and-weekly.png")
    }

    func testRenderEditScreen() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let (container, items, _) = try sampleData()
        _ = container
        let walk = try XCTUnwrap(items.first { $0.title.hasPrefix("Walk") })
        let water = try XCTUnwrap(items.first { $0.title.hasPrefix("Drink") })
        let sheet = HStack(alignment: .top, spacing: 0) {
            panel(width: 340, height: 480) { EditItemView(item: walk, theme: theme, scrolls: false, onDone: {}) }
            panel(width: 340, height: 480) { EditItemView(item: water, theme: theme, scrolls: false, onDone: {}) }
            panel(width: 340, height: 480) { SmartSettingsView().padding(14).environment(\.colorScheme, .dark) }
        }
        try save(sheet, as: "preview-11-edit-and-smart-settings.png")
    }

    // MARK: - Notch island, type picker, reminder popup

    /// One island state on a dark "menu bar" with a stand-in for the camera
    /// notch, the way it looks on a MacBook.
    private func island(_ content: NoticeContent, settings: BreakTimerSettings = BreakTimerSettings()) -> some View {
        let model = IslandModel()
        // A 16-inch MacBook Pro's notch.
        model.notch = IslandGeometry.notch(CGSize(width: 200, height: 37))
        model.content = content
        model.palette = BreakIslandRules.palette(for: content.tone ?? .work, settings: settings)
        let sides = BreakIslandController.sides(for: content)
        model.leftWing = sides.left
        model.rightWing = sides.right
        model.roomLeft = sides.left
        model.isOpen = true
        let width = sides.left + model.notch.middleWidth + sides.right
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.22), Color(red: 0.05, green: 0.05, blue: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            IslandView(model: model)
                .frame(width: width, height: 37)
                .offset(x: (sides.left - sides.right) / 2)
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 9, bottomTrailingRadius: 9,
                                   topTrailingRadius: 0, style: .continuous)
                .fill(Color.black)
                .frame(width: model.notch.middleWidth, height: 37)
        }
        .frame(width: 560, height: 60)
    }

    func testRenderNotchIsland() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let now = Date()
        let states = VStack(spacing: 0) {
            // Between moments: face and time only.
            island(NoticeContent(title: "", countdownTo: now.addingTimeInterval(38 * 60 + 12),
                                 face: .smug, tone: .work, sticky: true))
            island(NoticeContent(title: "", countdownTo: now.addingTimeInterval(8 * 60 + 54),
                                 face: .sleepy, tone: .onBreak, sticky: true))
            // The moments, with words.
            island(NoticeContent(title: "Working", countdownTo: now.addingTimeInterval(38 * 60 + 12),
                                 face: .smug, tone: .work, sticky: true))
            island(NoticeContent(title: "Break", countdownTo: now.addingTimeInterval(8 * 60 + 54),
                                 face: .sleepy, tone: .onBreak, sticky: true))
            island(NoticeContent(title: "Break", countdownTo: now.addingTimeInterval(8 * 60 + 54),
                                 face: .sleepy, tone: .onBreak, sticky: true),
                   settings: { var s = BreakTimerSettings(); s.breakColor = .awayRed; return s }())
            island(NoticeContent(title: "Come back!", countUpFrom: now.addingTimeInterval(-192),
                                 face: .furious, tone: .away, sticky: true))
        }
        try save(states, as: "preview-notch-island.png")
    }

    /// The whole Smart settings tab at the sheet's real width (340 with 20
    /// padding), at full length, to catch anything running off the edges.
    func testRenderSmartSettingsFull() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let view = SmartSettingsView()
            .frame(width: 300)
            .padding(20)
            .frame(width: 340)
            .background(Color(white: 0.16))
            .environment(\.colorScheme, .dark)
        try save(view, as: "preview-12-smart-settings-full.png")
    }

    /// The menu bar face awake, looking at the pointer in different places.
    func testRenderWatchingFace() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let looks: [(String, CGVector, Bool, Bool)] = [
            ("wow", CGVector(dx: 0, dy: 1), false, true),
            ("down", CGVector(dx: 0, dy: 1), false, false),
            ("left", CGVector(dx: -1, dy: 0.3), false, false),
            ("right", CGVector(dx: 1, dy: 0.3), false, false),
            ("down-left", CGVector(dx: -0.7, dy: 0.7), false, false),
            ("blink", .zero, true, false),
        ]
        let row = HStack(spacing: 14) {
            ForEach(looks, id: \.0) { name, look, blink, wow in
                VStack(spacing: 4) {
                    Image(nsImage: MenuBarFace.watchImage(look: look, blink: blink, wow: wow))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 38 * 3, height: 20 * 3)
                        .foregroundStyle(.white)
                    Text(name).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background(Color.black)
        try save(row, as: "preview-14-watching-face.png")
    }

    func testRenderTypePicker() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        func row(_ text: String, chosen: ItemType? = nil) -> some View {
            var parsed: ParsedItem? = text.isEmpty ? nil : ItemParser.parse(text)
            parsed?.chosen = chosen
            return HStack(spacing: 8) {
                Text(text.isEmpty ? "Drink water every 40 min" : text)
                    .font(theme.font)
                    .foregroundStyle(theme.text.opacity(text.isEmpty ? 0.35 : 1))
                Spacer()
                TypePicker(preview: parsed, theme: theme)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(parsed == nil ? theme.text.opacity(0.25) : ReminderRowView.onColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: ReminderPanelController.expandedSize.width)
            .background(theme.background.opacity(theme.backgroundOpacity))
        }
        let rows = VStack(spacing: 6) {
            row("")
            row("drink water every 1 minute")
            row("drink water every 1 minute", chosen: .habit)
            row("finish the Sharma teaser")
            row("work 40 min rest 10 min")
        }
        .padding(10)
        .background(Color(white: 0.5))
        try save(rows, as: "preview-type-picker.png")
    }

    func testRenderReminderPopup() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let size = NoticePillController.size
        let popup = HStack(spacing: 10) {
            NoticePillView(content: NoticeContent(title: "Drink water", detail: "Stay hydrated, stay sharp."),
                           life: PopupLife())
                .frame(width: size.width, height: size.height)
            // Mid-dissolve: the dead face, its last words, the bits flying off.
            ZStack {
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(theme.background.opacity(theme.backgroundOpacity))
                    .opacity(0.35)
                VStack(spacing: 6) {
                    KaomojiView(face: Kaomoji(eyes: .cross, mouth: .wavy, extra: .tears), color: theme.text)
                        .frame(width: 128, height: 64)
                    Text("Tell my family I loved them.")
                        .font(.system(size: theme.fontSize - 2, weight: .semibold).italic())
                        .foregroundStyle(theme.text.opacity(0.9))
                }
                .opacity(0.5)
                .blur(radius: 3)
                DissolveField(bits: DissolveBit.burst(count: 46), progress: 0.45,
                              colors: [theme.text, theme.text.opacity(0.6), theme.accent, theme.background])
            }
            .frame(width: size.width, height: size.height)
            // The end: "Sayonara.", accepting its fate.
            ZStack {
                RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                    .fill(theme.background.opacity(theme.backgroundOpacity))
                VStack(spacing: 6) {
                    KaomojiView(face: Kaomoji(eyes: .content, mouth: .smile, extra: .tears), color: theme.text)
                        .frame(width: 128, height: 64)
                    Text("Drink water").font(theme.titleFont).foregroundStyle(theme.text)
                    Text("Sayonara.")
                        .font(.system(size: theme.fontSize - 2, weight: .semibold).italic())
                        .foregroundStyle(theme.text.opacity(0.9))
                    Text("accepts fate")
                        .font(.system(size: theme.fontSize - 3).italic())
                        .foregroundStyle(theme.text.opacity(0.5))
                }
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: size.width, height: size.height)
        }
        .padding(10)
        .background(Color(white: 0.5))
        try save(popup, as: "preview-reminder-popup.png")
    }

    /// The face kit: every eye, every mouth, every extra, then a row of
    /// random faces for each mood.
    func testRenderFaceKit() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        func cell(_ face: Kaomoji) -> some View {
            KaomojiView(face: face, color: .white).frame(width: 84, height: 44)
        }
        var rng = SystemRandomNumberGenerator()
        let moods: [(String, Kaomoji.Mood)] = [("happy", .happy), ("calm", .calm), ("love", .love),
                                                ("shocked", .shocked), ("sad", .sad), ("angry", .angry),
                                                ("dead", .dead), ("cool", .cool), ("silly", .silly),
                                                ("pleading", .pleading), ("nervous", .nervous)]
        let sheet = VStack(alignment: .leading, spacing: 10) {
            Text("Eyes").foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88)), count: 9), spacing: 6) {
                ForEach(Kaomoji.Eyes.allCases, id: \.self) { cell(Kaomoji(eyes: $0, mouth: .cat, extra: .none)) }
            }
            Text("Mouths").foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88)), count: 9), spacing: 6) {
                ForEach(Kaomoji.Mouth.allCases, id: \.self) { cell(Kaomoji(eyes: .dot, mouth: $0, extra: .none)) }
            }
            Text("Extras").foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88)), count: 9), spacing: 6) {
                ForEach(Kaomoji.Extra.allCases, id: \.self) { cell(Kaomoji(eyes: .bead, mouth: .smile, extra: $0)) }
            }
            ForEach(moods, id: \.0) { name, mood in
                Text(name).foregroundStyle(.white)
                HStack(spacing: 4) {
                    ForEach(0..<9, id: \.self) { _ in cell(Kaomoji.random(mood, using: &rng)) }
                }
            }
        }
        .padding(16)
        .background(Color(white: 0.14))
        try save(sheet, as: "preview-13-face-kit.png")
    }
}
