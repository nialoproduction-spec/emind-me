import SwiftUI
import AppKit

/// Everything about the panel's appearance the user can customize.
/// Stored as JSON in UserDefaults — simple, local, no account needed.
struct PanelTheme: Codable, Equatable {
    var backgroundHex: String
    var backgroundOpacity: Double
    var accentHex: String
    var textHex: String
    var fontName: String
    var fontSize: Double
    var cornerRadius: Double

    static let `default` = PanelTheme(
        backgroundHex: "#1C1C1E",
        backgroundOpacity: 0.92,
        accentHex: "#0A84FF",
        textHex: "#FFFFFF",
        fontName: "System",
        fontSize: 13,
        cornerRadius: 16
    )

    var background: Color { Color(hex: backgroundHex) }
    var accent: Color { Color(hex: accentHex) }
    var text: Color { Color(hex: textHex) }

    var font: Font {
        if fontName == "System" {
            return .system(size: fontSize)
        }
        return .custom(fontName, size: fontSize)
    }

    var titleFont: Font {
        if fontName == "System" {
            return .system(size: fontSize + 2, weight: .semibold)
        }
        return .custom(fontName, size: fontSize + 2)
    }
}

/// Publishes theme changes to every panel view and persists them locally.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private static let defaultsKey = "panelTheme.v1"

    @Published var theme: PanelTheme {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(PanelTheme.self, from: data) {
            theme = decoded
        } else {
            theme = .default
        }
    }

    func reset() {
        theme = .default
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA"; falls back to opaque black on bad input.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized.removeAll { $0 == "#" }
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let r, g, b, a: Double
        switch sanitized.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Round-trips to "#RRGGBB" (alpha dropped — PanelTheme carries opacity separately).
    func toHex() -> String {
        let resolved = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
