import AppKit
import SwiftUI

/// Settings → Smart → Notch layout: a zoomed picture of the notch on a
/// break where the face, its z's, the word and the time can each be dragged
/// anywhere. Below it: pick a part to nudge it a point at a time or resize
/// it, make either side wider, let it reach down below the notch, or reset.
/// Every change shows at the real notch right away.
struct IslandLayoutEditor: View {
    @ObservedObject private var breakTimer = AppSettings.breakTimer
    @State private var selected: IslandLayout.Part = .face
    /// Fixed, so the picture doesn't change identity mid-drag.
    @State private var sampleEnd = Date().addingTimeInterval(8 * 60 + 54)

    /// The sheet's content width.
    static let width: CGFloat = 300
    /// A slimmer stand-in for the camera notch, so both sides fit.
    static let cameraWidth: CGFloat = 60

    private var layout: Binding<IslandLayout> { $breakTimer.value.layout }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notch layout").font(.subheadline.weight(.semibold))
            picture
            Text("Drag the face, the z's, the word or the time. It changes at the notch right away.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                ForEach(IslandLayout.Part.allCases, id: \.self) { part in
                    Button(part.label) { selected = part }
                        .buttonStyle(ChipStyle(on: selected == part))
                }
            }

            row("Move") {
                arrow("arrow.left") { layout.wrappedValue.nudge(selected, dx: -1) }
                arrow("arrow.up") { layout.wrappedValue.nudge(selected, dy: -1) }
                arrow("arrow.down") { layout.wrappedValue.nudge(selected, dy: 1) }
                arrow("arrow.right") { layout.wrappedValue.nudge(selected, dx: 1) }
                Text(position).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            row("Size") {
                arrow("minus") { layout.wrappedValue.resize(selected, by: -0.1) }
                Text("\(Int((layout.wrappedValue[selected].size * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .frame(width: 42)
                arrow("plus") { layout.wrappedValue.resize(selected, by: 0.1) }
            }
            row("Left side") {
                amount(\.leftExtra, step: 4, clamp: IslandLayout.clampExtra)
            }
            row("Right side") {
                amount(\.rightExtra, step: 4, clamp: IslandLayout.clampExtra)
            }
            row("Reach down") {
                amount(\.drop, step: 2, clamp: IslandLayout.clampDrop)
            }

            HStack(spacing: 6) {
                Button("Show at the notch") {
                    BreakIslandController.shared.show(NoticeContent(
                        title: "Break", countdownTo: Date().addingTimeInterval(8 * 60 + 54),
                        face: .sleepy, tone: .onBreak, duration: 10))
                }
                .buttonStyle(ChipStyle())
                Button("Reset layout") { layout.wrappedValue = IslandLayout() }
                    .buttonStyle(ChipStyle())
                    .disabled(layout.wrappedValue == IslandLayout())
            }
        }
    }

    // MARK: - The picture

    private var sample: NoticeContent {
        NoticeContent(title: "Break", countdownTo: sampleEnd, face: .sleepy, tone: .onBreak, sticky: true)
    }

    private var picture: some View {
        let current = layout.wrappedValue
        let notch = IslandGeometry.Notch(middleWidth: Self.cameraWidth, height: Self.notchHeight, hasNotch: true)
        let sides = BreakIslandController.sides(for: sample, layout: current)
        let width = sides.left + notch.middleWidth + sides.right
        let height = notch.height + CGFloat(current.drop)
        let scale = min(1.6, Self.width / width)
        let palette = BreakIslandRules.palette(for: .onBreak, settings: breakTimer.value)
        let camera = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 8,
                                            bottomTrailingRadius: 8, topTrailingRadius: 0, style: .continuous)
        return ZStack(alignment: .topLeading) {
            // The menu bar it sits in.
            Rectangle().fill(Color(white: 0.1)).frame(width: width, height: notch.height)
            IslandBody(notch: notch, leftWing: sides.left, rightWing: sides.right, roomLeft: sides.left,
                       content: sample, palette: palette, layout: current,
                       editing: IslandEditing(layout: layout, selected: $selected, scale: scale))
            // The camera: whatever's moved under it is hidden, like on the Mac.
            camera.fill(Color.black)
                .frame(width: notch.middleWidth, height: notch.height)
                .offset(x: sides.left)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: max(height, notch.height), alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: width * scale, height: max(height, notch.height) * scale, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18)))
    }

    /// The notch's real height on this Mac (about 32–38 pt), 32 elsewhere.
    static var notchHeight: CGFloat {
        let height = NSScreen.screens.first { $0.notchSize.width > 0 }?.notchSize.height ?? 0
        return height > 0 ? height : 32
    }

    private var position: String {
        let spot = layout.wrappedValue[selected]
        return "x \(Int(spot.x))  y \(Int(spot.y))"
    }

    // MARK: - Controls

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
        }
    }

    /// A small button that repeats while held.
    private func arrow(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14, height: 14)
        }
        .buttonStyle(ChipStyle())
        .buttonRepeatBehavior(.enabled)
    }

    /// − value + for a width or height, in points.
    @ViewBuilder
    private func amount(_ key: WritableKeyPath<IslandLayout, Double>, step: Double,
                        clamp: @escaping (Double) -> Double) -> some View {
        arrow("minus") { layout.wrappedValue[keyPath: key] = clamp(layout.wrappedValue[keyPath: key] - step) }
        Text("+\(Int(layout.wrappedValue[keyPath: key])) pt")
            .font(.callout.monospacedDigit())
            .frame(width: 52)
        arrow("plus") { layout.wrappedValue[keyPath: key] = clamp(layout.wrappedValue[keyPath: key] + step) }
    }
}

/// A small capsule button drawn in SwiftUI (so previews can show it); lit
/// when `on`.
struct ChipStyle: ButtonStyle {
    var on = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(on ? Color.accentColor
                                  : Color.primary.opacity(configuration.isPressed ? 0.22 : 0.1))
            )
            .foregroundStyle(on ? Color.white : Color.primary)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}
