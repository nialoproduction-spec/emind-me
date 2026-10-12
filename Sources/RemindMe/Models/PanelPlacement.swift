import Foundation
import CoreGraphics

/// Where the floating panel (reminders, the pill, the list) appears.
enum PanelPlacement: String, Codable, CaseIterable, Identifiable {
    case topRight, topLeft, bottomRight, bottomLeft
    /// Wherever it was last dragged to.
    case custom
    /// Drops down right under the menu bar icon, like a menu.
    case menuBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        case .custom: return "Custom spot"
        case .menuBar: return "Under the menu bar icon"
        }
    }
}

struct PlacementSettings: Codable, Equatable {
    var placement: PanelPlacement = .topRight
    /// Top-left corner of the panel's custom spot, in screen coordinates.
    /// Set by dragging the panel.
    var customTopLeft: CGPoint?

    static let `default` = PlacementSettings()
}

@MainActor
final class PlacementStore: ObservableObject {
    static let shared = PlacementStore()

    private static let defaultsKey = "panelPlacement.v1"
    private static let legacyOriginKey = "panel.origin.v1"

    @Published var settings: PlacementSettings {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(PlacementSettings.self, from: data) {
            settings = decoded
        } else {
            // New default is top right. If the panel had been dragged before
            // this setting existed, keep that spot available as "Custom".
            var initial = PlacementSettings.default
            if let legacy = UserDefaults.standard.dictionary(forKey: Self.legacyOriginKey),
               let x = legacy["x"] as? Double, let y = legacy["y"] as? Double {
                initial.customTopLeft = CGPoint(x: x, y: y + 56)
            }
            settings = initial
        }
    }

    /// The panel was dragged: that spot becomes the custom placement.
    func pinCustom(topLeft: CGPoint) {
        var updated = settings
        updated.placement = .custom
        updated.customTopLeft = topLeft
        if updated != settings { settings = updated }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// The geometry, as a pure function so it's testable without any windows.
/// All rects are in screen coordinates (origin bottom-left, y up).
enum PanelPlacementMath {
    static let margin: CGFloat = 12
    /// Gap between the bottom of the menu bar icon and the panel.
    static let menuBarGap: CGFloat = 6

    /// Where a panel of `size` goes for `placement`. Resizing just calls this
    /// again with the new size, so the chosen corner stays put while the
    /// panel grows or shrinks (bottom placements grow upwards, right ones
    /// leftwards, the menu bar one stays centred under the icon).
    static func frame(
        for placement: PanelPlacement,
        size: CGSize,
        visibleFrame screen: CGRect,
        customTopLeft: CGPoint?,
        statusItemFrame: CGRect?
    ) -> CGRect {
        let m = margin
        let origin: CGPoint
        switch placement {
        case .topRight:
            origin = CGPoint(x: screen.maxX - size.width - m, y: screen.maxY - size.height - m)
        case .topLeft:
            origin = CGPoint(x: screen.minX + m, y: screen.maxY - size.height - m)
        case .bottomRight:
            origin = CGPoint(x: screen.maxX - size.width - m, y: screen.minY + m)
        case .bottomLeft:
            origin = CGPoint(x: screen.minX + m, y: screen.minY + m)
        case .custom:
            guard let topLeft = customTopLeft else {
                // Never dragged yet: behave like the default.
                return frame(for: .topRight, size: size, visibleFrame: screen,
                             customTopLeft: nil, statusItemFrame: statusItemFrame)
            }
            origin = CGPoint(x: topLeft.x, y: topLeft.y - size.height)
        case .menuBar:
            guard let icon = statusItemFrame, icon.width > 0 else {
                // Icon position unknown (e.g. menu bar hidden): fall back.
                return frame(for: .topRight, size: size, visibleFrame: screen,
                             customTopLeft: nil, statusItemFrame: nil)
            }
            origin = CGPoint(x: icon.midX - size.width / 2, y: icon.minY - size.height - menuBarGap)
        }
        return clamp(CGRect(origin: origin, size: size), to: screen)
    }

    /// Keeps the panel fully on screen.
    static func clamp(_ frame: CGRect, to screen: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(result.origin.x, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(result.origin.y, screen.minY), screen.maxY - result.height)
        return result
    }
}
