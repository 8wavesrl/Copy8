import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Pannello senza bordi che riceve la tastiera senza attivare Copy8:
/// l'app in cui stai lavorando resta in primo piano e riceve l'incolla.
final class ClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate, PanelActions {
    let model: PanelModel
    var onOpenSettings: (() -> Void)?
    var onOpenTutorial: (() -> Void)?
    private(set) var isShown = false

    private let panel: ClipPanel
    private let settings: Settings
    private let history: History
    private let watcher: ClipboardWatcher
    private let toast: ToastController
    private weak var searchField: NSTextField?
    private var keyMonitor: Any?
    private var askedForTrust = false
    /// Vero mentre la finestra si toglie di mezzo per un incolla con ⇧ clic: non va chiusa.
    private var steppingAside = false
    /// Elementi incollati con ⇧ clic: tornano in cima alla cronologia solo alla chiusura,
    /// così l'elenco non si riordina mentre si incolla una riga dopo l'altra.
    private var pendingTouches: [ClipItem] = []

    init(settings: Settings, history: History, watcher: ClipboardWatcher, toast: ToastController) {
        self.settings = settings
        self.history = history
        self.watcher = watcher
        self.toast = toast
        model = PanelModel(history: history, settings: settings)
        panel = ClipPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.wideWidth, height: PanelMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        model.actions = self
        let root = PanelView(model: model, settings: settings, history: history) { [weak self] field in
            self?.searchField = field
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.cornerRadius = PanelMetrics.radius
        host.layer?.cornerCurve = .continuous
        host.layer?.masksToBounds = true
        panel.contentView = host
        applySize()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    // MARK: Mostra e nascondi

    func toggle() {
        isShown ? hide() : show()
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        model.prepareForShow()
        position()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if let searchField { panel.makeFirstResponder(searchField) }
        // Disegna subito lo stato aggiornato, senza aspettare il prossimo evento.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.08 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        if !reduceMotion { animateScaleIn() }
        panel.invalidateShadow()
    }

    /// Scala 0,98 → 1 in 120 ms con Core Animation: gira nel compositore di sistema anche se Copy8
    /// non è l'app attiva, e lo stato finale resta sempre al 100%.
    private func animateScaleIn() {
        guard let layer = panel.contentView?.layer else { return }
        let scale: CGFloat = 0.98
        let bounds = layer.bounds
        // Il layer ha l'ancora nell'angolo: la traslazione tiene fermo il centro.
        let start = CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeTranslation(bounds.width * (1 - scale) / 2, bounds.height * (1 - scale) / 2, 0)
        )
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: start)
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = 0.12
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "appear")
    }

    func hide(animated: Bool = true) {
        guard isShown else { return }
        isShown = false
        if !model.queue.isEmpty { model.queue = [] }
        for item in pendingTouches { history.touch(item) }
        pendingTouches = []
        guard animated else {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        })
    }

    /// Disegna il pannello una volta all'avvio, fuori schermo, così la prima apertura è immediata.
    func warmUp() {
        model.refresh()
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShown else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    func applySize() {
        let size = NSSize(width: settings.showPreview ? PanelMetrics.wideWidth : PanelMetrics.narrowWidth,
                          height: PanelMetrics.height)
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: isShown)
        panel.invalidateShadow()
    }

    func historyChanged() {
        if isShown { model.refresh() }
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let top = visible.maxY - visible.height * 0.16
        let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(),
                             y: max(visible.minY + 16, top - size.height).rounded())
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        if !steppingAside { hide() }
    }

    // MARK: Azioni

    func paste(_ item: ClipItem, plain: Bool) {
        paste([item], plain: plain, keepOpen: false)
    }

    func choose(_ item: ClipItem, chaining: Bool, keepOpen: Bool) {
        if chaining {
            toggleQueue(item)
        } else {
            pasteChain(model.chain(endingWith: item.id), keepOpen: keepOpen)
        }
    }

    func toggleQueue(_ item: ClipItem) {
        model.toggleQueue(item.id)
    }

    /// Incolla insieme più elementi, nell'ordine in cui sono stati scelti.
    private func pasteChain(_ ids: [Int64], keepOpen: Bool) {
        let available = history.visible
        let items = ids.compactMap { id in available.first { $0.id == id } }
        if items.isEmpty {
            model.queue = []
        } else {
            paste(items, plain: false, keepOpen: keepOpen)
        }
    }

    /// Mette gli elementi negli appunti e li incolla nell'app attiva. Con `keepOpen` la finestra resta aperta
    /// per incollarne altri, ma solo se Copy8 può incollare da sé: se serve il tuo ⌘V, si chiude come sempre.
    private func paste(_ items: [ClipItem], plain: Bool, keepOpen: Bool) {
        guard let first = items.first else { return }
        let screen = panel.screen
        watcher.ignoredChangeCount = items.count == 1
            ? Paster.write(first, plain: plain, history: history)
            : Paster.write(items, history: history)
        let pasted = items.count > 1 ? "Incollati \(items.count) elementi in ordine"
            : plain ? "Incollato come testo semplice" : "Incollato nell’app attiva"
        if keepOpen, isShown, settings.pasteDirectly, Paster.isTrusted {
            model.queue = []
            pendingTouches += items
            pasteBehindPanel()
            toast.show(pasted, on: screen)
            return
        }
        hide(animated: false)
        for item in items { history.touch(item) }
        deliver(pasted: pasted,
                copied: items.count > 1 ? "Copiati \(items.count) elementi: premi ⌘V per incollare"
                                        : "Copiato: premi ⌘V per incollare",
                on: screen)
    }

    /// ⌘V arriva alla finestra che ha la tastiera, quindi per incollare nell'app sotto la finestra
    /// si toglie di mezzo per un attimo e poi torna com'era: stessa ricerca, stessa selezione.
    private func pasteBehindPanel() {
        steppingAside = true
        panel.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.sendPaste() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.steppingAside = false
                // Se nel frattempo è stata chiusa (per esempio con la scorciatoia) resta chiusa.
                if self.isShown { self.panel.makeKeyAndOrderFront(nil) }
            }
        }
    }

    /// Dopo aver scritto negli appunti: incolla nell'app attiva se può, altrimenti avvisa che è solo copiato.
    private func deliver(pasted: String, copied: String, on screen: NSScreen?) {
        guard settings.pasteDirectly else {
            toast.show(copied, on: screen)
            return
        }
        if Paster.isTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.sendPaste() }
            toast.show(pasted, on: screen)
        } else {
            if !askedForTrust {
                askedForTrust = true
                Paster.requestTrust()
            }
            toast.show(copied, on: screen)
        }
    }

    func copy(_ item: ClipItem) {
        let screen = panel.screen
        watcher.ignoredChangeCount = Paster.write(item, plain: false, history: history)
        history.touch(item)
        hide(animated: false)
        toast.show("Copiato negli appunti", on: screen)
    }

    func delete(_ item: ClipItem) {
        history.delete(item)
    }

    func togglePin(_ item: ClipItem) {
        let latest = history.current(item)
        history.setPinned(latest, !latest.pinned)
        model.select(id: item.id)
    }

    func openSettings() {
        hide(animated: false)
        onOpenSettings?()
    }

    func openTutorial() {
        hide(animated: false)
        onOpenTutorial?()
    }

    func focusSearch() {
        if let searchField { panel.makeFirstResponder(searchField) }
    }

    // MARK: Tastiera

    private func handleKey(_ event: NSEvent) -> Bool {
        guard isShown, event.window === panel else { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch Int(event.keyCode) {
        case kVK_DownArrow: model.move(by: 1); return true
        case kVK_UpArrow: model.move(by: -1); return true
        case kVK_PageDown: model.move(by: 8); return true
        case kVK_PageUp: model.move(by: -8); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if mods == .command {
                // ⌘↩ mette in coda la riga selezionata, come ⌘ clic.
                if let item = model.selectedItem { toggleQueue(item) }
            } else if !model.queue.isEmpty {
                pasteChain(model.queue, keepOpen: false)
            } else if let item = model.selectedItem {
                paste(item, plain: mods.contains(.option))
            }
            return true
        case kVK_Escape:
            if !model.queue.isEmpty {
                model.queue = []
            } else if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        default:
            break
        }

        if choosesRow(event) { return true }

        guard mods == .command else { return false }
        if Int(event.keyCode) == kVK_Delete {
            if let item = model.selectedItem { delete(item) }
            return true
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let digit = Int(key), (1...9).contains(digit) {
            // ⌘ + numero mette in coda la riga in quella posizione, come ⌘ clic.
            if digit <= model.results.count { toggleQueue(model.results[digit - 1]) }
            return true
        }
        switch key {
        case ",": openSettings(); return true
        case "w": hide(); return true
        case "p":
            if let item = model.selectedItem { togglePin(item) }
            return true
        case "a": return send(#selector(NSText.selectAll(_:)))
        case "x": return send(#selector(NSText.cut(_:)))
        case "v": return send(#selector(NSText.paste(_:)))
        case "z": return send(Selector(("undo:")))
        case "c":
            if let editor = panel.firstResponder as? NSTextView, editor.selectedRange().length > 0 {
                return send(#selector(NSText.copy(_:)))
            }
            if let item = model.selectedItem { copy(item) }
            return true
        default:
            return false
        }
    }

    /// A ricerca vuota un numero da 1 a 9 sceglie la riga corrispondente, come un clic senza ⌘:
    /// la incolla, insieme alla coda se ce n'è una. Il 9 apre il tutorial finché la sua riga è al nono posto.
    /// Appena si scrive qualcosa i numeri tornano testo.
    private func choosesRow(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.isEmpty, !event.isARepeat, model.query.isEmpty,
              let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) else { return false }
        if digit <= model.results.count {
            choose(model.results[digit - 1], chaining: false, keepOpen: false)
            return true
        }
        if digit == 9, model.showsTutorial {
            openTutorial()
            return true
        }
        return false
    }

    private func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: nil)
        return true
    }
}
