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

    func testRenderMenuBarIcon() throws {
        try XCTSkipIf(outputDir == nil, "PREVIEW_DIR not set")
        let icon = StatusIcon.image()
        let bar = VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: icon).renderingMode(.template).foregroundStyle(.white)
                Text("Tue 13 Oct 1:37 AM").font(.system(size: 13)).foregroundStyle(.white)
            }
            .frame(width: 260, height: 24).background(Color(white: 0.12))
            HStack(spacing: 14) {
                Image(nsImage: icon).renderingMode(.template).foregroundStyle(.black)
                Text("Tue 13 Oct 1:37 AM").font(.system(size: 13)).foregroundStyle(.black)
            }
            .frame(width: 260, height: 24).background(Color(white: 0.92))
        }
        try save(bar, as: "preview-5-menu-bar.png")
    }
}
