import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// MARK: - Finestra

@MainActor
@Observable
final class TutorialState {
    private(set) var page = 0
    /// Momento da cui parte l'animazione della pagina corrente.
    private(set) var start = Date()
    /// Falso a finestra chiusa: le animazioni si fermano.
    var isActive = false

    func go(to newPage: Int) {
        let clamped = min(max(newPage, 0), TutorialPage.allCases.count - 1)
        guard clamped != page else { return }
        page = clamped
        start = Date()
    }

    func restart() {
        page = 0
        start = Date()
    }

    /// Fa ripartire l'animazione della pagina da un certo istante.
    func seek(to time: Double) {
        start = Date().addingTimeInterval(-time)
    }
}

@MainActor
final class TutorialWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state = TutorialState()
    private let settings: Settings
    private var keyMonitor: Any?

    init(settings: Settings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let view = TutorialView(state: state, settings: settings) { [weak self] in
                self?.window?.performClose(nil)
            }
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Come si usa Copy8"
            window.styleMask = [.titled, .closable]
            window.titlebarAppearsTransparent = true
            window.backgroundColor = Tokens.window
            window.isReleasedWhenClosed = false
            window.delegate = self
            let size = host.view.fittingSize
            if size.width > 0, size.height > 0 { window.setContentSize(size) }
            window.placeInVisibleFrame()
            self.window = window
        }
        if window?.isVisible != true { state.restart() }
        state.isActive = true
        installKeyMonitor()
        window?.bringToFront()
    }

    func windowWillClose(_ notification: Notification) {
        state.isActive = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return handled ? nil : event
        }
    }

    /// ← e → cambiano pagina, esc chiude; ↩ è il pulsante Avanti.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: state.go(to: state.page - 1); return true
        case kVK_RightArrow: state.go(to: state.page + 1); return true
        case kVK_Escape: window.performClose(nil); return true
        default: return false
        }
    }
}

// MARK: - Pagine

struct SceneContext {
    let hotKey: [String]
    let days: Int
}

/// Un passaggio della spiegazione e l'istante dell'animazione in cui succede.
struct TutorialStep {
    let time: Double
    let text: String
}

enum TutorialPage: Int, CaseIterable {
    case paste, search, chain, pin

    var title: String {
        switch self {
        case .paste: return "Apri e incolla"
        case .search: return "Cerca"
        case .chain: return "Più elementi insieme"
        case .pin: return "Fissa quello che ti serve sempre"
        }
    }

    /// I passaggi iniziano negli stessi istanti in cui l'animazione li mostra (vedi `Beat`).
    func steps(_ context: SceneContext) -> [TutorialStep] {
        switch self {
        case .paste:
            return [
                TutorialStep(time: 0, text: "Mentre scrivi, in qualsiasi app, premi \(context.hotKey.joined())."),
                TutorialStep(time: Beat.Paste.open, text: "Si apre la cronologia, con le ultime cose copiate in cima."),
                TutorialStep(time: Beat.Paste.choose, text: "Premi il numero della riga, qui il 3. Oppure sceglila con ↑ ↓ e premi ↩, o fai clic."),
                TutorialStep(time: Beat.Paste.paste, text: "Copy8 la incolla dove stavi scrivendo."),
            ]
        case .search:
            return [
                TutorialStep(time: 0, text: "Con la cronologia aperta, inizia a scrivere: non serve fare clic nel campo."),
                TutorialStep(time: Beat.Search.found, text: "Copy8 cerca in tutto il testo copiato, senza badare a maiuscole e accenti, ed evidenzia dove lo trova."),
                TutorialStep(time: Beat.Search.more, text: "Con più parole trova solo gli elementi che le contengono tutte."),
                TutorialStep(time: Beat.Search.clear, text: "esc cancella la ricerca. Premuto di nuovo, chiude la finestra."),
            ]
        case .chain:
            return [
                TutorialStep(time: 0, text: "Tieni premuto ⌘."),
                TutorialStep(time: Beat.Chain.pick, text: "Fai clic sulle righe nell’ordine che vuoi: al posto dell’icona compare il loro numero."),
                TutorialStep(time: Beat.Chain.release, text: "Lascia ⌘ e fai clic sull’ultima riga."),
                TutorialStep(time: Beat.Chain.paste, text: "Copy8 le incolla tutte nell’ordine scelto, una per riga."),
            ]
        case .pin:
            let period = context.days == 1 ? "dopo 1 giorno" : "dopo \(context.days) giorni"
            return [
                TutorialStep(time: 0, text: "Porta il mouse sulla riga che ti serve sempre: compare la puntina."),
                TutorialStep(time: Beat.Pin.pin, text: "Fai clic sulla puntina, o premi ⌘P: la riga sale tra i Fissati, in cima all’elenco."),
                TutorialStep(time: Beat.Pin.days, text: "Quello che non è fissato viene cancellato \(period)."),
                TutorialStep(time: Beat.Pin.keep, text: "Gli elementi fissati restano finché non li togli, di nuovo con ⌘P."),
            ]
        }
    }

    /// Una scorciatoia in più, sotto i passaggi.
    var tip: String {
        switch self {
        case .paste: return "La combinazione per aprire Copy8 si cambia in Impostazioni › Scorciatoia. ⌥↩ incolla come testo semplice."
        case .search: return "Cerca anche nel nome dell’app da cui hai copiato, per esempio “mail”."
        case .chain: return "Con la tastiera: ⌘ e il numero della riga la mettono in coda, il numero da solo sceglie l’ultima. esc svuota la coda."
        case .pin: return "Restano anche se cancelli la cronologia dalle impostazioni."
        }
    }

    /// Durata di un giro dell'animazione, in secondi.
    var duration: Double {
        switch self {
        case .paste: return Beat.Paste.duration
        case .search: return Beat.Search.duration
        case .chain: return Beat.Chain.duration
        case .pin: return Beat.Pin.duration
        }
    }

    /// Istante mostrato fermo quando è attivo "Riduci movimento".
    var still: Double {
        switch self {
        case .paste: return Beat.Paste.key + 0.3
        case .search: return Beat.Search.found + 1
        case .chain: return Beat.Chain.release - 0.5
        case .pin: return Beat.Pin.keep + 1
        }
    }

    func frame(at time: Double, _ context: SceneContext) -> StageFrame {
        switch self {
        case .paste: return Scenes.paste(time, context)
        case .search: return Scenes.search(time, context)
        case .chain: return Scenes.chain(time, context)
        case .pin: return Scenes.pin(time, context)
        }
    }
}

// MARK: - Vista

struct TutorialView: View {
    let state: TutorialState
    let settings: Settings
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La spiegazione ha la stessa altezza in tutte le pagine, così la finestra non cambia misura.
    private static let columnWidth: CGFloat = 340
    private static let columnHeight: CGFloat = 430

    private var page: TutorialPage { TutorialPage(rawValue: state.page) ?? .paste }
    private var context: SceneContext { SceneContext(hotKey: settings.hotKey.symbols, days: settings.days) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !state.isActive || reduceMotion)) { timeline in
                let elapsed = timeline.date.timeIntervalSince(state.start)
                let time = reduceMotion ? page.still : max(0, elapsed).truncatingRemainder(dividingBy: page.duration)
                HStack(alignment: .center, spacing: 32) {
                    explanation(active: reduceMotion ? nil : page.steps(context).lastIndex { $0.time <= time })
                        .frame(width: Self.columnWidth, height: Self.columnHeight, alignment: .topLeading)
                    TutorialStage(frame: page.frame(at: time, context), days: settings.days)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Animazione: \(page.title)")
                }
            }
            navigation
                .padding(.top, 20)
        }
        .padding(28)
        .fixedSize()
        .foregroundStyle(Palette.text)
        .background(Palette.window)
    }

    /// Titolo, passaggi numerati e un suggerimento. Il passaggio che l'animazione sta mostrando è evidenziato;
    /// un clic su un passaggio fa ripartire l'animazione da lì.
    private func explanation(active: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(page.rawValue + 1) di \(TutorialPage.allCases.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.text2)
            Text(page.title)
                .font(.system(size: 24, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(page.steps(context).enumerated()), id: \.offset) { index, step in
                    let phase: TutorialStepRow.Phase = active.map { index < $0 ? .done : index == $0 ? .active : .upcoming } ?? .done
                    TutorialStepRow(number: index + 1, text: step.text, phase: phase)
                        .onTapGesture { state.seek(to: step.time) }
                        .accessibilityAction { state.seek(to: step.time) }
                }
            }
            .padding(.top, 18)
            Spacer(minLength: 16)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lightbulb")
                    .accessibilityHidden(true)
                Text(page.tip)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text2)
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button("Indietro") { state.go(to: state.page - 1) }
                .disabled(state.page == 0)
                .frame(minWidth: 80, alignment: .leading)
            Spacer()
            HStack(spacing: 8) {
                ForEach(TutorialPage.allCases, id: \.self) { item in
                    Circle()
                        .fill(item == page ? Palette.accent : Palette.text2.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .padding(4)
                        .contentShape(Rectangle())
                        .onTapGesture { state.go(to: item.rawValue) }
                        .accessibilityElement()
                        .accessibilityLabel("Pagina \(item.rawValue + 1): \(item.title)")
                        .accessibilityAddTraits(item == page ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { state.go(to: item.rawValue) }
                }
            }
            Spacer()
            Group {
                if page == TutorialPage.allCases.last {
                    Button("Fine", action: close)
                } else {
                    Button("Avanti") { state.go(to: state.page + 1) }
                }
            }
            .keyboardShortcut(.defaultAction)
            .frame(minWidth: 80, alignment: .trailing)
        }
    }
}

struct TutorialStepRow: View {
    enum Phase { case done, active, upcoming }

    let number: Int
    let text: String
    let phase: Phase

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(phase == .active ? Palette.onAccent : Palette.text2)
                .frame(width: 24, height: 24)
                .background(Circle().fill(phase == .active ? Palette.accent : Palette.fill))
            Text(text)
                .font(.system(size: 15))
                .lineSpacing(2)
                .foregroundStyle(phase == .upcoming ? Palette.text2 : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(phase == .active ? Palette.accent.opacity(0.1) : Color.clear)
        )
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: phase)
        .help("Rivedi questo passaggio")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(phase == .active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Palco

/// Misure del palco. Il pannello finto ha le misure vere della finestra ed è rimpicciolito di `scale`.
enum Stage {
    static let width: CGFloat = 552
    static let sceneHeight: CGFloat = 342
    static let bandHeight: CGFloat = 46
    static let scale: CGFloat = 0.85
    static let panelWidth: CGFloat = 440
    static let header: CGFloat = 48
    static let section: CGFloat = 26
    static let row: CGFloat = 44
    static let listInset: CGFloat = 4
    static let listHeight: CGFloat = section + row * 6
    static let footer: CGFloat = 38
    static let listTop: CGFloat = header + 0.5 + listInset
    static let panelHeight: CGFloat = listTop + listHeight + listInset + 0.5 + footer
    static let panelOrigin = CGPoint(x: ((width - panelWidth * scale) / 2).rounded(), y: 8)
    static let note = CGRect(x: 16, y: 14, width: 520, height: 316)

    /// Inizio della riga `index` nell'elenco, sotto `sections` intestazioni.
    static func rowY(_ index: Int, sections: Int = 1) -> CGFloat {
        CGFloat(sections) * section + CGFloat(index) * row
    }

    /// Da coordinate dell'elenco del pannello a coordinate del palco.
    static func point(listX: CGFloat, listY: CGFloat) -> CGPoint {
        CGPoint(x: panelOrigin.x + listX * scale, y: panelOrigin.y + (listTop + listY) * scale)
    }

    /// Un punto sul testo della riga.
    static func rowPoint(_ index: Int) -> CGPoint {
        point(listX: 170, listY: rowY(index) + row / 2)
    }

    /// La puntina della riga selezionata.
    static func pinPoint(_ index: Int) -> CGPoint {
        point(listX: panelWidth - 100, listY: rowY(index) + row / 2)
    }

    /// Dove riposa il mouse: a destra del pannello, all'altezza della ricerca.
    static let restPoint = CGPoint(x: 520, y: 70)
}

struct PlacedEntry: Identifiable {
    enum Kind {
        case header(label: String, pinned: Bool)
        case row(ClipItem, index: Int)
    }

    let id: String
    let kind: Kind
    var y: CGFloat
    var opacity: Double = 1

    var isPinned: Bool {
        switch kind {
        case .header(_, let pinned): return pinned
        case .row(let item, _): return item.pinned
        }
    }
}

/// Un fotogramma: tutto quello che il palco mostra in un istante.
struct StageFrame {
    var noteTitle = "Nota"
    var noteText = ""
    var pasted = ""
    var pastedGlow = 0.0
    var caretOn = false
    var panelOpacity = 1.0
    var panelScale = 1.0
    var query = ""
    var queryCaret = false
    var entries: [PlacedEntry] = []
    var selection: Int64?
    var queue: [Int64: Int] = [:]
    var footer = ""
    var showHints = true
    var cursor: CGPoint?
    var cursorDown = false
    var cursorOpacity = 1.0
    var ring: (point: CGPoint, progress: Double)?
    var keys: [String] = []
    var keysNote: String?
    var caption: String?
    var toast: String?
    var toastOpacity = 0.0
    var fade = 1.0

    var rowCount: Int {
        entries.filter { if case .row = $0.kind { return true } else { return false } }.count
    }
}

struct TutorialStage: View {
    let frame: StageFrame
    let days: Int

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MockNote(title: frame.noteTitle, text: frame.noteText, pasted: frame.pasted,
                         glow: frame.pastedGlow, caretOn: frame.caretOn)
                    .frame(width: Stage.note.width, height: Stage.note.height)
                    .offset(x: Stage.note.minX, y: Stage.note.minY)
                MockPanel(frame: frame, days: days)
                    .scaleEffect(Stage.scale, anchor: .topLeading)
                    .frame(width: Stage.panelWidth * Stage.scale, height: Stage.panelHeight * Stage.scale,
                           alignment: .topLeading)
                    .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
                    .scaleEffect(frame.panelScale)
                    .opacity(frame.panelOpacity)
                    .offset(x: Stage.panelOrigin.x, y: Stage.panelOrigin.y)
                if let toast = frame.toast, frame.toastOpacity > 0 {
                    ToastPill(message: toast)
                        .scaleEffect(0.85)
                        .frame(width: Stage.width)
                        .offset(y: 10)
                        .opacity(frame.toastOpacity)
                }
                if let ring = frame.ring {
                    Circle()
                        .strokeBorder(Palette.accent, lineWidth: 2)
                        .frame(width: 10 + 26 * ring.progress, height: 10 + 26 * ring.progress)
                        .opacity(1 - ring.progress)
                        .position(ring.point)
                }
                if let cursor = frame.cursor, frame.cursorOpacity > 0 {
                    StageCursor(pressed: frame.cursorDown)
                        .offset(x: cursor.x - 1, y: cursor.y - 1)
                        .opacity(frame.cursorOpacity)
                }
            }
            .frame(width: Stage.width, height: Stage.sceneHeight, alignment: .topLeading)
            .clipped()
            .opacity(frame.fade)
            Hairline()
            band
                .frame(width: Stage.width, height: Stage.bandHeight)
                .opacity(frame.fade)
        }
        .background(LinearGradient(colors: [Palette.stageTop, Palette.stageBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.groupEdge, lineWidth: 0.5))
    }

    /// Sotto la scena: i tasti premuti in quel momento, o una didascalia.
    @ViewBuilder
    private var band: some View {
        HStack(spacing: 6) {
            if !frame.keys.isEmpty {
                ForEach(Array(frame.keys.enumerated()), id: \.offset) { _, key in
                    StageKey(label: key)
                }
                if let note = frame.keysNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text2)
                        .padding(.leading, 4)
                }
            } else if let caption = frame.caption {
                Label(caption, systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text2)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule().fill(Palette.fill))
            }
        }
    }
}

/// La finestra di Copy8, con i componenti veri dell'elenco.
struct MockPanel: View {
    let frame: StageFrame
    let days: Int

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ZStack(alignment: .topLeading) {
                ForEach(frame.entries) { entry in
                    entryView(entry)
                        .offset(y: entry.y)
                        .opacity(entry.opacity)
                        // La riga selezionata passa sopra le altre quando si spostano.
                        .zIndex(entry.id == "r-\(frame.selection ?? -1)" ? 1 : 0)
                }
            }
            .frame(width: Stage.panelWidth, height: Stage.listHeight, alignment: .topLeading)
            .padding(.vertical, Stage.listInset)
            .clipped()
            Hairline()
            footer
        }
        .frame(width: Stage.panelWidth, height: Stage.panelHeight)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radius, style: .continuous))
        .overlay(ModalBorder(glass: false, radius: PanelMetrics.radius))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(Palette.text2)
                .frame(width: 20, height: 20)
            Group {
                if frame.query.isEmpty {
                    Text("Cerca negli appunti, o premi 1–9").foregroundStyle(Palette.text2)
                } else {
                    Text(frame.query) + Text("|").foregroundStyle(frame.queryCaret ? Palette.accent : Color.clear)
                }
            }
            .font(.system(size: 20))
            .lineLimit(1)
            .padding(.leading, 4)
            Spacer(minLength: 8)
            if !frame.query.isEmpty {
                Text(PanelText.resultCount(frame.rowCount))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text2)
                    .frame(width: 28, height: 28)
            }
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(Palette.text2)
                .frame(width: 32, height: 32)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: Stage.header)
    }

    @ViewBuilder
    private func entryView(_ entry: PlacedEntry) -> some View {
        switch entry.kind {
        case .header(let label, let pinned):
            SectionHeader(section: PanelModel.Section(day: .distantFuture, label: label, isPinned: pinned, isFirst: false),
                          days: days)
                .padding(.horizontal, 20)
                .padding(.bottom, 5)
                .frame(width: Stage.panelWidth, height: Stage.section, alignment: .bottom)
        case .row(let item, let index):
            ClipRow(item: item, selected: item.id == frame.selection, terms: Search.terms(frame.query),
                    position: PanelText.position(index, searching: !frame.query.isEmpty),
                    order: frame.queue[item.id]) {}
                .frame(width: Stage.panelWidth)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(frame.footer)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(frame.queue.isEmpty ? Palette.text2 : Palette.text)
            Spacer(minLength: 8)
            if frame.showHints {
                KeyHint(keys: ["↩"], label: "Incolla")
                KeyHint(keys: ["esc"], label: "Chiudi")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.text2)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: Stage.footer)
    }
}

/// L'app in cui si sta scrivendo, dietro la finestra di Copy8.
struct MockNote: View {
    let title: String
    let text: String
    let pasted: String
    let glow: Double
    let caretOn: Bool

    private static let lights = [Color(red: 1, green: 0.37, blue: 0.34),
                                 Color(red: 1, green: 0.74, blue: 0.18),
                                 Color(red: 0.16, green: 0.78, blue: 0.25)]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 7) {
                    ForEach(Self.lights, id: \.self) { Circle().fill($0).frame(width: 11, height: 11) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text2)
            }
            .frame(height: 30)
            Hairline()
            content
                .font(.system(size: 14))
                .lineSpacing(5)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.groupEdge, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    private var content: Text {
        var added = AttributedString(pasted)
        added.swiftUI.backgroundColor = Palette.highlight.opacity(glow)
        return Text(text) + Text(added) + Text("|").foregroundStyle(caretOn ? Palette.accent : Color.clear)
    }
}

struct StageKey: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.accent))
            .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
    }
}

struct StageCursor: View {
    let pressed: Bool

    var body: some View {
        ArrowShape()
            .fill(Color.black)
            .overlay(ArrowShape().stroke(Color.white, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)))
            .frame(width: 13, height: 20)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .scaleEffect(pressed ? 0.86 : 1, anchor: .topLeading)
    }
}

/// La freccia del mouse, con la punta nell'angolo in alto a sinistra.
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [(0, 0), (0, 16.5), (4, 12.8), (6.6, 18.6), (9, 17.5), (6.5, 11.8), (11.6, 11.8)]
        let sx = rect.width / 12, sy = rect.height / 19
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * sx, y: rect.minY + point.1 * sy)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Scene

/// Esempi di cose copiate, inventati.
enum Sample {
    static let base = Date()

    private static func item(_ id: Int64, _ kind: ClipKind, _ text: String, minutesAgo: Double, from source: String,
                             pinned: Bool = false) -> ClipItem {
        ClipItem(id: id, kind: kind, text: text, imageFile: nil, width: 0, height: 0, byteCount: text.utf8.count,
                 sourceName: source, sourceBundle: nil, copiedAt: base.addingTimeInterval(-minutesAgo * 60),
                 hash: "tutorial-\(id)", pinned: pinned)
    }

    static let meeting = item(1, .text, "Ci vediamo lunedì alle 10 in sala riunioni", minutesAgo: 2, from: "Mail")
    static let push = item(2, .code, "git push origin main", minutesAgo: 6, from: "Terminale")
    static let link = item(3, .link, "https://meet.example.com/riunione-lunedi", minutesAgo: 11, from: "Calendario")
    static let color = item(4, .color, "#9365FF", minutesAgo: 19, from: "Anteprima")
    static let invoice = item(5, .text, "Fattura 2026-118 · 1.250,00 €", minutesAgo: 26, from: "Numbers")
    static let call = item(6, .text, "Chiamare Giulia per il preventivo", minutesAgo: 34, from: "Promemoria")
    static let sent = item(7, .text, "Ho mandato la fattura a Giulia stamattina", minutesAgo: 8, from: "Messaggi")
    static let sheet = item(8, .file, "/Users/me/Documenti/Fatture ottobre.xlsx", minutesAgo: 15, from: "Finder")
    static let iban = item(9, .text, "IT60 X054 2811 1010 0000 0123 456", minutesAgo: 9, from: "Safari")
}

/// Percorso del mouse: punti da raggiungere a certi istanti, con un'accelerazione morbida tra l'uno e l'altro.
struct Track {
    let keys: [(time: Double, point: CGPoint)]

    func at(_ t: Double) -> CGPoint {
        guard var previous = keys.first else { return .zero }
        for key in keys.dropFirst() {
            if t < key.time {
                let u = Scenes.ramp(t, previous.time, key.time)
                return CGPoint(x: previous.point.x + (key.point.x - previous.point.x) * u,
                               y: previous.point.y + (key.point.y - previous.point.y) * u)
            }
            previous = key
        }
        return previous.point
    }
}

/// Istanti chiave di ogni animazione, in secondi. I passaggi della spiegazione partono dagli stessi istanti,
/// e ognuno resta acceso almeno un paio di secondi, il tempo di leggerlo.
enum Beat {
    enum Paste {
        static let typed = 1.8      // finisce di scrivere nella nota
        static let keys = 2.1       // preme la scorciatoia
        static let open = 2.8       // passaggio 2: si apre la cronologia
        static let choose = 5.2     // passaggio 3: il più lungo, spiega tre modi di scegliere
        static let key = 5.8        // preme 3
        static let paste = 9.8      // passaggio 4: incolla
        static let duration = 13.8
    }

    enum Search {
        static let type = 1.0       // scrive "fatt"
        static let found = 2.2      // passaggio 2
        static let more = 5.2       // passaggio 3: scrive " ott" poco dopo
        static let clear = 8.4      // passaggio 4: esc poco dopo
        static let duration = 11.4
    }

    enum Chain {
        static let command = 0.8    // preme ⌘
        static let pick = 2.4       // passaggio 2
        static let clicks = [3.0, 4.1, 5.2]
        static let release = 6.4    // passaggio 3: lascia ⌘
        static let last = 8.7       // clic sull'ultima riga
        static let paste = 8.8      // passaggio 4
        static let duration = 13.0
    }

    enum Pin {
        static let pin = 3.2        // passaggio 2: clic sulla puntina
        static let days = 6.0       // passaggio 3: passano i giorni
        static let expire = 6.8     // gli altri elementi spariscono
        static let keep = 8.4       // passaggio 4
        static let duration = 11.8
    }
}

enum Scenes {
    // MARK: Apri e incolla

    static func paste(_ t: Double, _ context: SceneContext) -> StageFrame {
        typealias B = Beat.Paste
        var frame = StageFrame()
        let items = [Sample.meeting, Sample.push, Sample.link, Sample.color, Sample.invoice, Sample.call]
        // Si sta scrivendo nella nota.
        let note = "Ciao Marco,\nti mando il link per la riunione di lunedì:\n"
        let typed = min(1, max(0, (t - 0.3) / (B.typed - 0.3)))
        frame.noteText = String(note.prefix(Int(Double(note.count) * typed)))
        frame.caretOn = t < B.typed || blink(t)
        if t >= B.keys, t < B.open + 0.3 { frame.keys = context.hotKey }

        let appear = ramp(t, B.open, B.open + 0.12)
        frame.panelOpacity = appear * (1 - ramp(t, B.paste - 0.08, B.paste))
        frame.panelScale = 0.98 + 0.02 * appear
        frame.entries = layout([("Oggi", false, items)])
        frame.selection = t >= B.key ? Sample.link.id : Sample.meeting.id
        frame.footer = PanelText.summary(days: context.days, count: items.count, pinned: 0)
        if t >= B.key, t < B.key + 1.2 { frame.keys = ["3"] }

        if t >= B.paste {
            frame.pasted = Sample.link.text
            frame.pastedGlow = 1 - ramp(t, B.paste + 1.6, B.paste + 2.8)
        }
        frame.toast = "Incollato nell’app attiva"
        frame.toastOpacity = ramp(t, B.paste + 0.05, B.paste + 0.17) * (1 - ramp(t, B.paste + 1.8, B.paste + 2.05))
        frame.fade = loopFade(t, B.duration)
        return frame
    }

    // MARK: Cerca

    static func search(_ t: Double, _ context: SceneContext) -> StageFrame {
        typealias B = Beat.Search
        var frame = StageFrame()
        let items = [Sample.meeting, Sample.invoice, Sample.link, Sample.sent, Sample.color, Sample.sheet]
        let words: [(start: Double, text: String)] = [(B.type, "fatt"), (B.more + 0.4, " ott")]
        let typing = words.flatMap { word in
            word.text.enumerated().map { (time: word.start + Double($0.offset) * 0.2, key: String($0.element)) }
        }
        let escAt = B.clear + 0.5
        frame.query = t < escAt ? typing.filter { $0.time <= t }.map(\.key).joined() : ""
        frame.queryCaret = blink(t)
        let needles = Search.terms(frame.query).map { Array($0.utf8) }
        let results = items.filter { item in needles.allSatisfy(item.matches) }
        frame.entries = layout([("Oggi", false, results)])
        frame.selection = results.first?.id
        frame.footer = needles.isEmpty
            ? PanelText.summary(days: context.days, count: items.count, pinned: 0)
            : PanelText.results(results.count, days: context.days)
        if let typed = typing.last(where: { t >= $0.time && t < $0.time + 0.24 }) {
            frame.keys = [typed.key == " " ? "spazio" : typed.key.uppercased()]
        }
        if t >= escAt, t < escAt + 0.35 { frame.keys = ["esc"] }
        frame.fade = loopFade(t, B.duration)
        return frame
    }

    // MARK: Più elementi insieme

    static func chain(_ t: Double, _ context: SceneContext) -> StageFrame {
        typealias B = Beat.Chain
        var frame = StageFrame()
        let items = [Sample.meeting, Sample.push, Sample.link, Sample.color, Sample.invoice, Sample.call]
        frame.entries = layout([("Oggi", false, items)])
        // Clic sulle righe 1, 5 e 3 con ⌘, poi sulla 6 senza.
        let picks = [(row: 0, item: Sample.meeting), (row: 4, item: Sample.invoice), (row: 2, item: Sample.link)]
        let rest = Stage.restPoint
        var keys: [(time: Double, point: CGPoint)] = [(0, rest), (B.pick, rest)]
        for (index, pick) in picks.enumerated() {
            let click = B.clicks[index]
            let leave = index == picks.count - 1 ? B.release + 0.5 : click + 0.3
            keys += [(click - 0.1, Stage.rowPoint(pick.row)), (leave, Stage.rowPoint(pick.row))]
        }
        keys.append((B.last - 0.4, Stage.rowPoint(5)))
        let track = Track(keys: keys)
        let clicks = B.clicks + [B.last]
        let cursor = track.at(t)
        frame.cursor = cursor
        frame.cursorDown = pressed(t, clicks)
        frame.cursorOpacity = 1 - ramp(t, B.paste + 0.6, B.paste + 1.0)
        frame.ring = ring(t, clicks, track)

        var queue: [Int64: Int] = [:]
        for (index, pick) in picks.enumerated() where t >= B.clicks[index] && t < B.paste {
            queue[pick.item.id] = index + 1
        }
        frame.queue = queue
        // Come nella finestra vera, la riga sotto il mouse è quella selezionata.
        frame.selection = hovered(cursor, in: frame.entries) ?? Sample.meeting.id
        frame.footer = queue.isEmpty
            ? PanelText.summary(days: context.days, count: items.count, pinned: 0)
            : PanelText.queue(queue.count)
        frame.showHints = queue.isEmpty
        if t >= B.command, t < B.release {
            frame.keys = ["⌘"]
            frame.keysNote = "tenuto premuto"
        }

        frame.panelOpacity = 1 - ramp(t, B.paste, B.paste + 0.08)
        frame.noteText = "Da fare oggi:\n"
        frame.caretOn = blink(t)
        if t >= B.paste + 0.1 {
            frame.pasted = (picks.map(\.item) + [Sample.call]).map(\.text).joined(separator: "\n")
            frame.pastedGlow = 1 - ramp(t, B.paste + 1.6, B.paste + 2.8)
        }
        frame.toast = "Incollati 4 elementi in ordine"
        frame.toastOpacity = ramp(t, B.paste + 0.15, B.paste + 0.27) * (1 - ramp(t, B.paste + 1.9, B.paste + 2.15))
        frame.fade = loopFade(t, B.duration)
        return frame
    }

    // MARK: Puntina

    static func pin(_ t: Double, _ context: SceneContext) -> StageFrame {
        typealias B = Beat.Pin
        var frame = StageFrame()
        let items = [Sample.meeting, Sample.push, Sample.iban, Sample.link, Sample.color]
        let others = items.filter { $0.id != Sample.iban.id }
        let before = layout([("Oggi", false, items)])
        let after = layout([("Fissati", true, [Sample.iban.with(pinned: true)]), ("Oggi", false, others)])
        var entries = t < B.pin ? before : blend(before, after, ramp(t, B.pin + 0.05, B.pin + 0.45))
        // Passano i giorni: resta solo quello che è fissato.
        let expire = ramp(t, B.expire, B.expire + 0.8)
        for index in entries.indices where !entries[index].isPinned {
            entries[index].opacity *= 1 - expire
        }
        frame.entries = entries

        let rest = Stage.restPoint
        // Dopo il clic il mouse esce dal pannello di lato, senza passare sulle altre righe.
        let exit = CGPoint(x: 525, y: Stage.pinPoint(2).y)
        let track = Track(keys: [(0, rest), (0.8, rest), (1.6, Stage.rowPoint(2)), (2.4, Stage.rowPoint(2)),
                                 (B.pin - 0.2, Stage.pinPoint(2)), (B.pin + 0.4, Stage.pinPoint(2)),
                                 (B.pin + 1.1, exit)])
        let cursor = track.at(t)
        frame.cursor = cursor
        frame.cursorDown = pressed(t, [B.pin])
        frame.ring = ring(t, [B.pin], track)
        frame.selection = t < B.pin ? (hovered(cursor, in: before) ?? Sample.meeting.id) : Sample.iban.id

        if t < B.pin {
            frame.footer = PanelText.summary(days: context.days, count: items.count, pinned: 0)
        } else {
            frame.footer = PanelText.summary(days: context.days, count: expire < 0.5 ? others.count : 0, pinned: 1)
        }
        if t >= B.days, t < B.duration - 0.4 {
            frame.caption = context.days == 1 ? "Passa 1 giorno" : "Passano \(context.days) giorni"
        }
        frame.fade = loopFade(t, B.duration)
        return frame
    }

    // MARK: Strumenti

    /// Da 0 a 1 tra `from` e `to`, con partenza e arrivo morbidi.
    static func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double {
        let u = min(1, max(0, (t - from) / (to - from)))
        return u * u * (3 - 2 * u)
    }

    private static func blink(_ t: Double) -> Bool {
        Int(t / 0.53) % 2 == 0
    }

    /// Dissolvenza all'inizio e alla fine di ogni giro.
    private static func loopFade(_ t: Double, _ duration: Double) -> Double {
        min(1, max(0, t / 0.25)) * min(1, max(0, (duration - t) / 0.35))
    }

    private static func pressed(_ t: Double, _ clicks: [Double]) -> Bool {
        clicks.contains { t >= $0 - 0.06 && t < $0 + 0.12 }
    }

    private static func ring(_ t: Double, _ clicks: [Double], _ track: Track) -> (point: CGPoint, progress: Double)? {
        guard let click = clicks.last(where: { t >= $0 && t < $0 + 0.45 }) else { return nil }
        return (track.at(click), (t - click) / 0.45)
    }

    /// Intestazioni e righe una sotto l'altra, come nell'elenco vero.
    private static func layout(_ sections: [(label: String, pinned: Bool, items: [ClipItem])]) -> [PlacedEntry] {
        var entries: [PlacedEntry] = []
        var y: CGFloat = 0
        var index = 0
        for section in sections where !section.items.isEmpty {
            entries.append(PlacedEntry(id: "h-\(section.label)", kind: .header(label: section.label, pinned: section.pinned), y: y))
            y += Stage.section
            for item in section.items.sorted(by: { $0.copiedAt > $1.copiedAt }) {
                entries.append(PlacedEntry(id: "r-\(item.id)", kind: .row(item, index: index), y: y))
                y += Stage.row
                index += 1
            }
        }
        return entries
    }

    /// Passaggio da una disposizione all'altra: chi c'è in entrambe scivola, chi c'è in una sola sfuma.
    private static func blend(_ from: [PlacedEntry], _ to: [PlacedEntry], _ u: Double) -> [PlacedEntry] {
        var result: [PlacedEntry] = []
        for entry in to {
            var moved = entry
            if let old = from.first(where: { $0.id == entry.id }) {
                moved.y = old.y + (entry.y - old.y) * u
            } else {
                moved.opacity = entry.opacity * u
            }
            result.append(moved)
        }
        for entry in from where !to.contains(where: { $0.id == entry.id }) {
            var faded = entry
            faded.opacity = entry.opacity * (1 - u)
            result.append(faded)
        }
        return result
    }

    /// La riga sotto il mouse, se il mouse è sull'elenco.
    private static func hovered(_ point: CGPoint, in entries: [PlacedEntry]) -> Int64? {
        let x = (point.x - Stage.panelOrigin.x) / Stage.scale
        let y = (point.y - Stage.panelOrigin.y) / Stage.scale - Stage.listTop
        guard x >= 8, x <= Stage.panelWidth - 8, y >= 0, y < Stage.listHeight else { return nil }
        for entry in entries {
            if case .row(let item, _) = entry.kind, y >= entry.y, y < entry.y + Stage.row { return item.id }
        }
        return nil
    }
}
