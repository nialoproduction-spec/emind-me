import XCTest
import SwiftUI
import AppKit
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

    private func card(popCount: Int, reaction: FaceMood? = nil, title: String = "Drink water") -> some View {
        let item = Item(title: title, kind: .repeatingRoutine, intervalSeconds: 40 * 60)
        let occurrence = Occurrence(item: item, scheduledFireDate: .now)
        occurrence.remindersSentCount = popCount
        return ZStack {
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .fill(theme.background.opacity(theme.backgroundOpacity))
            LiveReminderView(occurrence: occurrence, theme: theme, initialReaction: reaction)
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
}
