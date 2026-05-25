import Foundation
import SwiftTerminal
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
import UIKit
#endif

enum ThemeColorRole: String, CaseIterable, Identifiable {
    case foreground
    case background
    case cursor
    case cursorAccent
    case selectionBackground
    case selectionForeground
    case selectionInactiveBackground
    case black
    case red
    case green
    case yellow
    case blue
    case magenta
    case cyan
    case white
    case brightBlack
    case brightRed
    case brightGreen
    case brightYellow
    case brightBlue
    case brightMagenta
    case brightCyan
    case brightWhite

    static let primaryRoles: [Self] = [
        .foreground,
        .background,
        .cursor,
        .cursorAccent,
        .selectionBackground,
        .selectionForeground,
        .selectionInactiveBackground,
    ]

    static let ansiRoles: [Self] = [
        .black,
        .red,
        .green,
        .yellow,
        .blue,
        .magenta,
        .cyan,
        .white,
        .brightBlack,
        .brightRed,
        .brightGreen,
        .brightYellow,
        .brightBlue,
        .brightMagenta,
        .brightCyan,
        .brightWhite,
    ]

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .foreground:
            "Foreground"
        case .background:
            "Background"
        case .cursor:
            "Cursor"
        case .cursorAccent:
            "Cursor Accent"
        case .selectionBackground:
            "Selection"
        case .selectionForeground:
            "Selection Text"
        case .selectionInactiveBackground:
            "Inactive Selection"
        case .black:
            "Black"
        case .red:
            "Red"
        case .green:
            "Green"
        case .yellow:
            "Yellow"
        case .blue:
            "Blue"
        case .magenta:
            "Magenta"
        case .cyan:
            "Cyan"
        case .white:
            "White"
        case .brightBlack:
            "Bright Black"
        case .brightRed:
            "Bright Red"
        case .brightGreen:
            "Bright Green"
        case .brightYellow:
            "Bright Yellow"
        case .brightBlue:
            "Bright Blue"
        case .brightMagenta:
            "Bright Magenta"
        case .brightCyan:
            "Bright Cyan"
        case .brightWhite:
            "Bright White"
        }
    }

    func value(in theme: SwiftTerminalTheme) -> String {
        switch self {
        case .foreground:
            theme.foreground
        case .background:
            theme.background
        case .cursor:
            theme.cursor
        case .cursorAccent:
            theme.cursorAccent
        case .selectionBackground:
            theme.selectionBackground
        case .selectionForeground:
            theme.selectionForeground
        case .selectionInactiveBackground:
            theme.selectionInactiveBackground
        case .black:
            theme.black
        case .red:
            theme.red
        case .green:
            theme.green
        case .yellow:
            theme.yellow
        case .blue:
            theme.blue
        case .magenta:
            theme.magenta
        case .cyan:
            theme.cyan
        case .white:
            theme.white
        case .brightBlack:
            theme.brightBlack
        case .brightRed:
            theme.brightRed
        case .brightGreen:
            theme.brightGreen
        case .brightYellow:
            theme.brightYellow
        case .brightBlue:
            theme.brightBlue
        case .brightMagenta:
            theme.brightMagenta
        case .brightCyan:
            theme.brightCyan
        case .brightWhite:
            theme.brightWhite
        }
    }

    func assign(_ value: String, to theme: inout SwiftTerminalTheme) {
        switch self {
        case .foreground:
            theme.foreground = value
        case .background:
            theme.background = value
        case .cursor:
            theme.cursor = value
        case .cursorAccent:
            theme.cursorAccent = value
        case .selectionBackground:
            theme.selectionBackground = value
        case .selectionForeground:
            theme.selectionForeground = value
        case .selectionInactiveBackground:
            theme.selectionInactiveBackground = value
        case .black:
            theme.black = value
        case .red:
            theme.red = value
        case .green:
            theme.green = value
        case .yellow:
            theme.yellow = value
        case .blue:
            theme.blue = value
        case .magenta:
            theme.magenta = value
        case .cyan:
            theme.cyan = value
        case .white:
            theme.white = value
        case .brightBlack:
            theme.brightBlack = value
        case .brightRed:
            theme.brightRed = value
        case .brightGreen:
            theme.brightGreen = value
        case .brightYellow:
            theme.brightYellow = value
        case .brightBlue:
            theme.brightBlue = value
        case .brightMagenta:
            theme.brightMagenta = value
        case .brightCyan:
            theme.brightCyan = value
        case .brightWhite:
            theme.brightWhite = value
        }
    }
}

enum ThemeColorCodec {
    static func color(from string: String) -> Color {
        guard let resolvedColor = hexComponents(from: string) else {
            return Color.gray.opacity(0.7)
        }

        return Color(
            .sRGB,
            red: resolvedColor.red,
            green: resolvedColor.green,
            blue: resolvedColor.blue,
            opacity: resolvedColor.alpha
        )
    }

    static func string(from color: Color) -> String {
        #if canImport(AppKit)
        let platformColor = NSColor(color)
        guard let sRGBColor = platformColor.usingColorSpace(.sRGB) else {
            return "#000000"
        }

        return hexString(
            red: sRGBColor.redComponent,
            green: sRGBColor.greenComponent,
            blue: sRGBColor.blueComponent,
            alpha: sRGBColor.alphaComponent
        )
        #elseif canImport(UIKit)
        let platformColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard platformColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#000000"
        }

        return hexString(red: red, green: green, blue: blue, alpha: alpha)
        #else
        return "#000000"
        #endif
    }

    private static func hexComponents(
        from string: String
    ) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed

        switch digits.count {
        case 3:
            let expanded = digits.flatMap { [$0, $0] }
            return hexComponents(from: String(expanded))
        case 4:
            let expanded = digits.flatMap { [$0, $0] }
            return hexComponents(from: String(expanded))
        case 6, 8:
            guard let value = UInt64(digits, radix: 16) else {
                return nil
            }

            if digits.count == 6 {
                return (
                    red: Double((value >> 16) & 0xff) / 255,
                    green: Double((value >> 8) & 0xff) / 255,
                    blue: Double(value & 0xff) / 255,
                    alpha: 1
                )
            }

            return (
                red: Double((value >> 24) & 0xff) / 255,
                green: Double((value >> 16) & 0xff) / 255,
                blue: Double((value >> 8) & 0xff) / 255,
                alpha: Double(value & 0xff) / 255
            )
        default:
            return nil
        }
    }

    private static func hexString(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat
    ) -> String {
        let redValue = Int(round(min(max(red, 0), 1) * 255))
        let greenValue = Int(round(min(max(green, 0), 1) * 255))
        let blueValue = Int(round(min(max(blue, 0), 1) * 255))
        let alphaValue = Int(round(min(max(alpha, 0), 1) * 255))

        if alphaValue >= 255 {
            return String(format: "#%02X%02X%02X", redValue, greenValue, blueValue)
        }

        return String(
            format: "#%02X%02X%02X%02X",
            redValue,
            greenValue,
            blueValue,
            alphaValue
        )
    }
}

struct ThemeSwatchesView: View {
    let theme: SwiftTerminalTheme
    var size = CGSize(width: 18, height: 18)

    var body: some View {
        HStack(spacing: 6) {
            swatch(theme.background)
            swatch(theme.foreground)
            swatch(theme.cursor)
            swatch(theme.red)
            swatch(theme.blue)
            swatch(theme.green)
        }
    }

    private func swatch(_ value: String) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(ThemeColorCodec.color(from: value))
            .frame(width: size.width, height: size.height)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

struct ThemeBackdropView: View {
    let theme: SwiftTerminalTheme

    var body: some View {
        let background = ThemeColorCodec.color(from: theme.background)
        let selection = ThemeColorCodec.color(from: theme.selectionBackground)
        let cursor = ThemeColorCodec.color(from: theme.cursor)

        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        background,
                        selection.opacity(0.82),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(cursor.opacity(0.28))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)
                    .offset(x: 40, y: -40)
            }
    }
}

struct ThemeColorEditorRow: View {
    let role: ThemeColorRole
    @Binding var text: String
    @Binding var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role.label)
                .font(.footnote.weight(.medium))

            HStack(spacing: 10) {
                ColorPicker("", selection: $color, supportsOpacity: true)
                    .labelsHidden()

                TextField("#RRGGBB", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
    }
}
