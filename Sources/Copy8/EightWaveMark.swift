import CoreGraphics

/// Il simbolo di 8 wave: due anelli uniti, un 8 coricato. Lo disegnano l'icona della barra dei menu e
/// scripts/make-icon.swift, che lo compila insieme al proprio codice per l'icona dell'app.
enum EightWaveMark {
    /// Un anello: centro, semiassi dell'ellisse esterna e di quella interna.
    private struct Ring { let cx, cy, outerX, outerY, innerX, innerY: CGFloat }

    /// Misure prese su Support/EightWaveLogo.png, in pixel del logo con la y verso il basso: l'anello di
    /// sinistra è più grande e i due si sovrappongono per lo spessore di un tratto.
    private static let rings = [
        Ring(cx: 65.65, cy: 88, outerX: 33.55, outerY: 35.5, innerX: 20.55, innerY: 22),
        Ring(cx: 114.85, cy: 88, outerX: 28.65, outerY: 29.65, innerX: 14.95, innerY: 16),
    ]
    private static let left: CGFloat = 32.1, right: CGFloat = 143.5, midY: CGFloat = 88

    /// Il simbolo largo `width` e centrato in `center`, in coordinate con la y verso l'alto.
    static func path(center: CGPoint, width: CGFloat) -> CGPath {
        let scale = width / (right - left)
        let midX = (left + right) / 2
        func ellipse(_ ring: Ring, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            let x = center.x + (ring.cx - midX) * scale
            let y = center.y - (ring.cy - midY) * scale
            return CGRect(x: x - rx * scale, y: y - ry * scale, width: rx * 2 * scale, height: ry * 2 * scale)
        }
        let union = CGMutablePath()
        for ring in rings {
            let shape = CGMutablePath()
            shape.addEllipse(in: ellipse(ring, ring.outerX, ring.outerY))
            shape.addEllipse(in: ellipse(ring, ring.innerX, ring.innerY))
            union.addPath(shape.normalized(using: .evenOdd))
        }
        return union.normalized(using: .winding)
    }
}
