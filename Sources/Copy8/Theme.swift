import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

/// Il colore in evidenza (riga selezionata, coda, link, interruttori, tutorial), scelto con la tavolozza dei colori
/// di macOS. Di serie è il viola di 8 wave (8wave.it). Il riempimento è il colore scelto così com'è; il resto si
/// calcola perché si legga qualunque colore arrivi: sopra il riempimento il testo è bianco o quasi nero, e il testo
/// colorato si scurisce sui fondi chiari e si schiarisce su quelli scuri.
struct Accent: Equatable {
    static let eightWave = Accent(hex: 0x9365FF)

    let hex: UInt32
    let fill: NSColor
    /// Testo e simboli sopra il riempimento.
    let onFill: NSColor
    /// Testo colorato sui fondi della finestra: link e pulsanti senza bordo.
    let text: NSColor
    /// Il cielo della scrivania nel tutorial, appena tinto del colore scelto.
    let stageTop: NSColor

    private static let white: UInt32 = 0xFFFFFF
    private static let ink: UInt32 = 0x161A1D
    /// I fondi più chiari e più scuri su cui compare il testo colorato.
    private static let lightBackground: UInt32 = 0xF5F5F7
    private static let darkBackground: UInt32 = 0x2A2A2D

    init(hex: UInt32) {
        self.hex = hex & 0xFFFFFF
        fill = NSColor(hex: self.hex)
        // Il bianco finché si legge almeno come sul viola di 8 wave; sui colori chiari il quasi nero.
        let white = Self.contrast(Self.white, self.hex)
        onFill = NSColor(hex: white >= 3 || white >= Self.contrast(Self.ink, self.hex) ? Self.white : Self.ink)
        text = NSColor.adaptive(light: NSColor(hex: Self.readable(self.hex, on: Self.lightBackground, toward: 0x000000)),
                                dark: NSColor(hex: Self.readable(self.hex, on: Self.darkBackground, toward: Self.white)))
        stageTop = NSColor.adaptive(light: NSColor(hex: Self.mix(0xF5F5F7, self.hex, 0.14)),
                                    dark: NSColor(hex: Self.mix(0x24262B, self.hex, 0.07)))
    }

    /// Dal colore della tavolozza, in sRGB e senza trasparenza.
    init(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? NSColor(hex: Accent.eightWave.hex)
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        self.init(hex: byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent))
    }

    /// "9365FF" ↔ colore, come si salva nelle preferenze.
    init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }

    var hexString: String { String(format: "%06X", hex) }

    static func == (lhs: Accent, rhs: Accent) -> Bool { lhs.hex == rhs.hex }

    // MARK: Contrasto (WCAG 2)

    /// Spinge il colore verso il bianco o il nero quanto basta per un contrasto di 4,5 sul fondo.
    private static func readable(_ color: UInt32, on background: UInt32, toward target: UInt32) -> UInt32 {
        var amount = 0.0
        var result = color
        while contrast(result, background) < 4.5, amount < 1 {
            amount += 0.04
            result = mix(color, target, min(amount, 1))
        }
        return result
    }

    private static func mix(_ from: UInt32, _ to: UInt32, _ amount: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { result, shift in
            let a = Double((from >> shift) & 0xFF), b = Double((to >> shift) & 0xFF)
            return result | UInt32((a + (b - a) * amount).rounded()) << shift
        }
    }

    private static func luminance(_ color: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((color >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// Token del design system Copy8, aspetto chiaro e scuro.
enum Tokens {
    static let window = NSColor.adaptive(light: NSColor(hex: 0xF5F5F7), dark: NSColor(hex: 0x1E1E20))
    static let surface = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x2A2A2D))
    static let fill = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.05), dark: NSColor(hex: 0xFFFFFF, alpha: 0.08))
    static let separator = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.10), dark: NSColor(hex: 0xFFFFFF, alpha: 0.10))
    static let text = NSColor.adaptive(light: NSColor(hex: 0x1D1D1F), dark: NSColor(hex: 0xF5F5F7))
    static let text2 = NSColor.adaptive(light: NSColor(hex: 0x636368), dark: NSColor(hex: 0xAEAEB2))
    /// Calcolati dal colore scelto nelle impostazioni, così le viste SwiftUI si ridisegnano quando cambia.
    static var accent: NSColor { Settings.shared.accent.fill }
    static var accentText: NSColor { Settings.shared.accent.text }
    static var onAccent: NSColor { Settings.shared.accent.onFill }
    static let highlight = NSColor.adaptive(light: NSColor(hex: 0xFFE58A), dark: NSColor(hex: 0x74661F))
    static let danger = NSColor.adaptive(light: NSColor(hex: 0xD70015), dark: NSColor(hex: 0xFF6961))
    static let iconForeground = NSColor.adaptive(light: NSColor(hex: 0x48484D), dark: NSColor(hex: 0xD1D1D6))
    static let keyEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.14), dark: NSColor(hex: 0xFFFFFF, alpha: 0.14))
    static let field = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let fieldEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.18), dark: NSColor(hex: 0xFFFFFF, alpha: 0.16))
    static let groupEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.07), dark: NSColor(hex: 0xFFFFFF, alpha: 0.06))
    static let button = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x4A4A4E))
    static let buttonEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.16), dark: NSColor(hex: 0x000000, alpha: 0.50))
    static let hud = NSColor.adaptive(light: NSColor(hex: 0x1C1C1E, alpha: 0.86), dark: NSColor(hex: 0x3A3A3E, alpha: 0.92))
    static let modalEdge = NSColor.adaptive(light: NSColor(hex: 0x000000, alpha: 0.14), dark: NSColor(hex: 0x000000, alpha: 0.60))
    static let modalInnerEdge = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0), dark: NSColor(hex: 0xFFFFFF, alpha: 0.10))
    static let glassInnerEdge = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF, alpha: 0.55), dark: NSColor(hex: 0xFFFFFF, alpha: 0.12))
    /// Alone dietro il testo quando il vetro è trasparente: opposto al colore del testo.
    static let halo = NSColor.adaptive(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x000000))
    /// Verde chiaro della riga che apre il tutorial.
    static let tutorial = NSColor.adaptive(light: NSColor(hex: 0x2FA14C), dark: NSColor(hex: 0x2A9446))
    static let tutorialFill = NSColor.adaptive(light: NSColor(hex: 0x34C759, alpha: 0.14), dark: NSColor(hex: 0x30D158, alpha: 0.15))
    static let tutorialFillHover = NSColor.adaptive(light: NSColor(hex: 0x34C759, alpha: 0.24), dark: NSColor(hex: 0x30D158, alpha: 0.25))
    /// Sfondo delle animazioni del tutorial: una scrivania stilizzata dietro le finestre finte.
    static var stageTop: NSColor { Settings.shared.accent.stageTop }
    static let stageBottom = NSColor.adaptive(light: NSColor(hex: 0xECEFF4), dark: NSColor(hex: 0x1A1C20))
}

enum Palette {
    static let window = Color(nsColor: Tokens.window)
    static let surface = Color(nsColor: Tokens.surface)
    static let fill = Color(nsColor: Tokens.fill)
    static let separator = Color(nsColor: Tokens.separator)
    static let text = Color(nsColor: Tokens.text)
    static let text2 = Color(nsColor: Tokens.text2)
    static var accent: Color { Color(nsColor: Tokens.accent) }
    static var accentText: Color { Color(nsColor: Tokens.accentText) }
    static var onAccent: Color { Color(nsColor: Tokens.onAccent) }
    static let highlight = Color(nsColor: Tokens.highlight)
    static let danger = Color(nsColor: Tokens.danger)
    static let iconForeground = Color(nsColor: Tokens.iconForeground)
    static let keyEdge = Color(nsColor: Tokens.keyEdge)
    static let field = Color(nsColor: Tokens.field)
    static let fieldEdge = Color(nsColor: Tokens.fieldEdge)
    static let groupEdge = Color(nsColor: Tokens.groupEdge)
    static let button = Color(nsColor: Tokens.button)
    static let buttonEdge = Color(nsColor: Tokens.buttonEdge)
    static let hud = Color(nsColor: Tokens.hud)
    static let modalEdge = Color(nsColor: Tokens.modalEdge)
    static let modalInnerEdge = Color(nsColor: Tokens.modalInnerEdge)
    static let glassInnerEdge = Color(nsColor: Tokens.glassInnerEdge)
    static let halo = Color(nsColor: Tokens.halo)
    static let tutorial = Color(nsColor: Tokens.tutorial)
    static let tutorialFill = Color(nsColor: Tokens.tutorialFill)
    static let tutorialFillHover = Color(nsColor: Tokens.tutorialFillHover)
    static var stageTop: Color { Color(nsColor: Tokens.stageTop) }
    static let stageBottom = Color(nsColor: Tokens.stageBottom)
}

/// Effetto vetro: un solo valore (1–100) va dalla superficie quasi piena al vetro lucido.
/// Strati: brina (sfocatura) e tinta sotto il contenuto, riflessi sopra.
enum Glass {
    /// L'intensità 100 corrisponde al 75 della scala precedente: oltre, il vetro diventava troppo trasparente.
    private static let maxProgress = 74.0 / 99.0

    private static func progress(_ intensity: Double) -> Double {
        (min(max(intensity, 1), 100) - 1) / 99 * maxProgress
    }

    private static func smoothstep(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let u = min(1, max(0, (x - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    /// Opacità della tinta di superficie: 94% a intensità 1, circa 24% a intensità 100.
    static func tint(_ intensity: Double) -> Double {
        0.94 * (1 - progress(intensity))
    }

    /// Quanto resta della sfocatura: piena fino a circa 40, circa 30% a intensità 100.
    static func frost(_ intensity: Double) -> Double {
        1 - smoothstep(0.3, 1, progress(intensity))
    }

    /// Forza di riflessi e alone del testo: compaiono da circa 54, circa 62% a intensità 100.
    static func gloss(_ intensity: Double) -> Double {
        smoothstep(0.4, 1, progress(intensity))
    }
}

enum PanelMetrics {
    static let wideWidth: CGFloat = 780
    static let narrowWidth: CGFloat = 520
    static let height: CGFloat = 540
    static let listWidth: CGFloat = 340
    static let radius: CGFloat = 18
}
