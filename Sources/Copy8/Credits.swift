import AppKit

/// Chi sviluppa Copy8: il logo nelle impostazioni, una scritta in fondo alla finestra e nel menu dell'icona.
enum Credits {
    static let developedBy = "Sviluppata da 8 wave"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Il logo di 8 wave, nero su trasparente. È un'immagine "template": si colora come il testo,
    /// quindi va bene sia in chiaro sia in scuro. Nil fuori dal pacchetto dell'app (per esempio nei test).
    static let logo: NSImage? = {
        guard let image = NSImage(named: "EightWaveLogo") else { return nil }
        image.isTemplate = true
        return image
    }()
}
