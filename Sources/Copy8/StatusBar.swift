import AppKit

/// L'icona di Copy8 nella barra dei menu. Il menu mostra le ultime copie, da incollare con un clic.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    var onOpenPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onPaste: ((ClipItem) -> Void)?

    private let settings: Settings
    private let history: History
    private var item: NSStatusItem?
    private var flashWork: DispatchWorkItem?

    private static let recentCount = 5
    /// Caratteri dell'ultima copia mostrati accanto all'icona.
    private static let previewLength = 10
    private static let menuTitleLength = 40

    init(settings: Settings, history: History) {
        self.settings = settings
        self.history = history
    }

    /// Crea, aggiorna o toglie l'icona secondo l'impostazione.
    func update() {
        guard settings.menuBar != .hidden else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil { item = makeItem() }
        updateTitle()
    }

    /// Il testo accanto all'icona, se l'impostazione lo prevede.
    func updateTitle() {
        guard let button = item?.button else { return }
        if settings.menuBar == .iconAndText, let last = history.visible.first {
            button.title = Self.preview(last)
        } else {
            button.title = ""
        }
    }

    /// Conferma breve che Copy8 ha registrato una copia: l'icona si riempie per un attimo.
    func flash() {
        guard let button = item?.button else { return }
        button.image = MenuBarIcon.filled
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.item?.button?.image = MenuBarIcon.outline }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = MenuBarIcon.outline
            button.imagePosition = .imageLeading
            button.font = .menuBarFont(ofSize: 0)
            button.toolTip = "Copy8"
            button.setAccessibilityTitle("Copy8")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        return item
    }

    // MARK: Menu

    /// Il menu si ricostruisce a ogni apertura, così mostra sempre le ultime copie e la scorciatoia attuale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recent = history.visible.prefix(Self.recentCount)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "Quello che copi compare qui", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            menu.addItem(.sectionHeader(title: "Ultime copie"))
            for clip in recent {
                let entry = NSMenuItem(title: Self.shorten(clip.title, to: Self.menuTitleLength),
                                       action: #selector(pasteRecent(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = clip.id
                entry.image = NSImage(systemSymbolName: clip.kind.symbol, accessibilityDescription: nil)
                entry.toolTip = settings.pasteDirectly ? "Incolla nell’app attiva" : "Copia negli appunti"
                menu.addItem(entry)
            }
        }
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Apri cronologia", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        let combo = settings.hotKey
        if combo.key.count == 1 {
            open.keyEquivalent = combo.key.lowercased()
            open.keyEquivalentModifierMask = combo.flags
        }
        menu.addItem(open)
        let preferences = NSMenuItem(title: "Impostazioni…", action: #selector(openSettings), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Esci da Copy8", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.addItem(.separator())
        let credits = NSMenuItem(title: "Copy8 \(Credits.version) · \(Credits.developedBy)", action: nil, keyEquivalent: "")
        credits.isEnabled = false
        menu.addItem(credits)
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64,
              let clip = history.visible.first(where: { $0.id == id }) else { return }
        onPaste?(clip)
    }

    @objc private func openPanel() {
        onOpenPanel?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    // MARK: Testi

    /// I primi caratteri dell'ultima copia, su una riga. Per immagini e file un nome breve al posto del contenuto.
    static func preview(_ clip: ClipItem) -> String {
        switch clip.kind {
        case .image: return "Immagine"
        default: return shorten(clip.title, to: previewLength)
        }
    }

    static func shorten(_ text: String, to length: Int) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.count > length ? line.prefix(length).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

/// L'icona della barra dei menu: una cartellina degli appunti con l'8 di Copy8. Immagine "template",
/// quindi macOS la colora come le altre icone della barra, in chiaro e in scuro.
enum MenuBarIcon {
    static let outline = make(filled: false)
    static let filled = make(filled: true)

    private static func make(filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let board = NSRect(x: 2, y: 0.75, width: 14, height: 14.25)
            if filled {
                NSBezierPath(roundedRect: board, xRadius: 2.2, yRadius: 2.2).fill()
            } else {
                let outline = NSBezierPath(roundedRect: board.insetBy(dx: 0.7, dy: 0.7), xRadius: 1.6, yRadius: 1.6)
                outline.lineWidth = 1.4
                outline.stroke()
            }
            // La molletta, staccata dal bordo da un piccolo spazio vuoto.
            let clip = NSBezierPath(roundedRect: NSRect(x: 5.5, y: 12.75, width: 7, height: 4), xRadius: 1.3, yRadius: 1.3)
            let context = NSGraphicsContext.current
            context?.compositingOperation = .destinationOut
            clip.lineWidth = 2.4
            clip.stroke()
            context?.compositingOperation = .sourceOver
            clip.fill()

            // L'8 sotto la molletta: pieno sull'icona vuota, ritagliato su quella piena.
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .heavy),
                .foregroundColor: NSColor.black,
            ]
            let digit = "8" as NSString
            let size = digit.size(withAttributes: attributes)
            let area = NSRect(x: board.minX, y: board.minY, width: board.width, height: 12)
            let origin = NSPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
            if filled { context?.compositingOperation = .destinationOut }
            digit.draw(at: origin, withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Copy8"
        return image
    }
}
