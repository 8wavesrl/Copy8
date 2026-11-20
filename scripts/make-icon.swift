// Disegna l'icona di Copy8 in tutte le misure di un .iconset: il simbolo "copia" con i colori di 8 wave, su
// fondo viola #9365FF. La scheda dietro è un contorno bianco, quella davanti è nera con il simbolo di 8 wave.
// Uso (il simbolo viene da Sources/Copy8/EightWaveMark.swift):
//   swiftc -parse-as-library Sources/Copy8/EightWaveMark.swift scripts/make-icon.swift -o build/make-icon
//   build/make-icon build/AppIcon.iconset
import AppKit

@main
enum MakeIcon {
    static let sizes: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    // I colori di 8wave.it: il viola e il quasi nero.
    static let purple = NSColor(srgbRed: 0x93 / 255, green: 0x65 / 255, blue: 0xFF / 255, alpha: 1).cgColor
    static let ink = NSColor(srgbRed: 0x16 / 255, green: 0x1A / 255, blue: 0x1D / 255, alpha: 1).cgColor

    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            print("Uso: make-icon <cartella.iconset>")
            exit(1)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, pixels) in sizes {
            try render(pixels).write(to: output.appendingPathComponent(name + ".png"))
        }
    }

    static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func render(_ pixels: Int) -> Data {
        let side = CGFloat(pixels)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext

        // Corpo dell'icona secondo la griglia macOS: 824/1024 con raggio continuo.
        let inset = side * 100 / 1024
        let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.03, color: NSColor(white: 0, alpha: 0.28).cgColor)
        ctx.addPath(rounded(body, body.width * 0.225))
        ctx.setFillColor(purple)
        ctx.fillPath()
        ctx.restoreGState()

        // Il simbolo "copia": due schede quadrate, quella dietro in alto a sinistra e quella davanti in basso a destra.
        let box = body.width * 0.8
        let card = box * 0.78
        let shift = box - card
        let line = box * 0.065
        let radius = card * 0.2
        let origin = CGPoint(x: body.midX - box / 2, y: body.midY - box / 2)
        let back = CGRect(x: origin.x, y: origin.y + shift, width: card, height: card)
        let front = CGRect(x: origin.x + shift, y: origin.y, width: card, height: card)

        ctx.addPath(rounded(back.insetBy(dx: line / 2, dy: line / 2), radius - line / 2))
        ctx.setStrokeColor(.white)
        ctx.setLineWidth(line)
        ctx.strokePath()

        // Uno stacco del colore del fondo tra il contorno dietro e la scheda davanti.
        let gap = line * 0.9
        ctx.addPath(rounded(front.insetBy(dx: -gap, dy: -gap), radius + gap))
        ctx.setFillColor(purple)
        ctx.fillPath()
        ctx.addPath(rounded(front, radius))
        ctx.setFillColor(ink)
        ctx.fillPath()

        ctx.addPath(EightWaveMark.path(center: CGPoint(x: front.midX, y: front.midY), width: card * 0.72))
        ctx.setFillColor(.white)
        ctx.fillPath()

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
