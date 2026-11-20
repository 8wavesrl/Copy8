import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var model: PanelModel
    let settings: Settings
    let history: History
    let onSearchField: (NSTextField) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            HStack(spacing: 0) {
                list
                    .frame(width: settings.showPreview ? PanelMetrics.listWidth : nil)
                    .frame(maxWidth: settings.showPreview ? nil : .infinity, maxHeight: .infinity)
                if settings.showPreview {
                    VerticalHairline()
                    PreviewPane(item: model.selectedItem, terms: model.terms, history: history, days: settings.days)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            Hairline()
            footer
        }
        .frame(width: settings.showPreview ? PanelMetrics.wideWidth : PanelMetrics.narrowWidth,
               height: PanelMetrics.height)
        .foregroundStyle(Palette.text)
        .modifier(GlassHalo(amount: glossAmount))
        .background(ModalBackground(glass: settings.glass, intensity: settings.glassIntensity, radius: PanelMetrics.radius))
        .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.radius, style: .continuous))
        .overlay(WaterGloss(radius: PanelMetrics.radius, amount: glossAmount))
        .overlay(ModalBorder(glass: settings.glass, radius: PanelMetrics.radius))
    }

    // MARK: Intestazione con la ricerca

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(Palette.text2)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            SearchField(text: $model.query, onCreate: onSearchField)
                .frame(height: 26)
                .padding(.leading, 4)
            if !model.query.isEmpty {
                Text(resultCount)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
                    .fixedSize()
                IconButton(symbol: "xmark.circle", side: 28, label: "Cancella ricerca") {
                    model.query = ""
                    model.actions?.focusSearch()
                }
            }
            IconButton(symbol: "slider.horizontal.3", side: 32, label: "Impostazioni") {
                model.actions?.openSettings()
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 60)
    }

    private var glossAmount: Double {
        settings.glass ? Glass.gloss(settings.glassIntensity) : 0
    }

    private var queuePasteLabel: String {
        let verb = settings.pasteDirectly ? "Incolla" : "Copia"
        let count = model.queue.count
        return count == 1 ? "\(verb) 1 elemento" : "\(verb) \(count) in ordine"
    }

    private var resultCount: String {
        PanelText.resultCount(model.results.count)
    }

    // MARK: Elenco

    @ViewBuilder
    private var list: some View {
        if model.results.isEmpty {
            VStack(spacing: 0) {
                emptyState
                if model.showsTutorial {
                    tutorialRow.padding(.bottom, 8)
                }
            }
        } else {
            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(.vertical) {
                        // Con pochi elementi la riga del tutorial resta in fondo, al posto della nona.
                        VStack(spacing: 0) {
                            rows
                            if model.showsTutorial {
                                Spacer(minLength: 0)
                                tutorialRow.padding(.bottom, 8)
                            }
                        }
                        .frame(minHeight: geometry.size.height, alignment: .top)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: model.scrollTick) {
                        if model.scrollTarget < 0 {
                            proxy.scrollTo("top", anchor: .top)
                        } else {
                            proxy.scrollTo(PanelModel.rowID(model.scrollTarget))
                        }
                    }
                }
            }
        }
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 4).id("top")
            ForEach(model.entries) { entry in
                switch entry {
                case .header(let section):
                    SectionHeader(section: section, days: settings.days)
                        .padding(.horizontal, 20)
                        .padding(.top, section.isFirst ? 6 : 14)
                        .padding(.bottom, 4)
                case .row(let row):
                    ClipRow(item: row.item, selected: row.index == model.selection, terms: model.terms,
                            position: PanelText.position(row.index, searching: !model.query.isEmpty),
                            order: model.queueOrder(of: row.item.id)) {
                        model.actions?.togglePin(row.item)
                    }
                    .onHover { inside in if inside { model.hover(row.index) } }
                    .onTapGesture {
                        // Con ⌘ la riga entra nella coda; senza, si incolla (la coda più questa riga).
                        // Con ⇧ la finestra resta aperta, per incollare altre righe una dopo l'altra.
                        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                        model.actions?.choose(row.item, chaining: flags.contains(.command),
                                              keepOpen: flags.contains(.shift))
                    }
                    .contextMenu { rowMenu(row.item) }
                }
            }
            Color.clear.frame(height: model.showsTutorial ? 4 : 8)
        }
    }

    private var tutorialRow: some View {
        TutorialRow { model.actions?.openTutorial() }
    }

    @ViewBuilder
    private func rowMenu(_ item: ClipItem) -> some View {
        Button("Incolla") { model.actions?.paste(item, plain: false) }
        Button("Incolla come testo semplice") { model.actions?.paste(item, plain: true) }
            .disabled(item.kind == .image)
        Button("Copia") { model.actions?.copy(item) }
        Divider()
        Button(model.queueOrder(of: item.id) == nil ? "Aggiungi alla coda (⌘ clic)" : "Togli dalla coda") {
            model.actions?.toggleQueue(item)
        }
        Divider()
        Button(item.pinned ? "Togli dai fissati" : "Fissa (non viene mai cancellato)") { model.actions?.togglePin(item) }
        Divider()
        Button("Elimina", role: .destructive) { model.actions?.delete(item) }
    }

    private var emptyState: some View {
        let isEmptyHistory = model.poolCount == 0
        return VStack(spacing: 8) {
            Image(systemName: isEmptyHistory ? "doc.on.doc" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.text2)
            Text(isEmptyHistory ? "Ancora niente qui" : "Nessun risultato per «\(model.query.trimmingCharacters(in: .whitespaces))»")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(isEmptyHistory ? "Quello che copi con ⌘C compare in questo elenco."
                                : "Prova con meno parole o aumenta i giorni nelle impostazioni.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Barra inferiore

    /// La scritta "Sviluppata da 8 wave" c'è quando entra per intero; se lo spazio non basta,
    /// per esempio nella finestra stretta senza anteprima, la precedenza va ai tasti.
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerContent(credits: true)
            footerContent(credits: false)
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.text2)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 38)
    }

    private func footerContent(credits: Bool) -> some View {
        HStack(spacing: 16) {
            Text(model.queue.isEmpty ? footerSummary : PanelText.queue(model.queue.count))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(model.queue.isEmpty ? Palette.text2 : Palette.text)
            Spacer(minLength: 8)
            HStack(spacing: 16) {
                if model.queue.isEmpty {
                    KeyHint(keys: ["↩"], label: settings.pasteDirectly ? "Incolla" : "Copia")
                    if settings.showPreview {
                        KeyHint(keys: ["⌘", "P"], label: model.selectedItem?.pinned == true ? "Togli" : "Fissa")
                    }
                    KeyHint(keys: ["⌥", "↩"], label: "Testo semplice")
                    KeyHint(keys: ["esc"], label: "Chiudi")
                } else {
                    KeyHint(keys: ["↩"], label: queuePasteLabel)
                    KeyHint(keys: ["esc"], label: "Svuota la coda")
                }
            }
            if credits {
                Rectangle()
                    .fill(Palette.separator)
                    .frame(width: 0.5, height: 14)
                Text(Credits.developedBy)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var footerSummary: String {
        guard model.terms.isEmpty else {
            return PanelText.results(model.results.count, days: settings.days)
        }
        return PanelText.summary(days: settings.days, count: model.results.count - model.pinnedCount,
                                 pinned: model.pinnedCount)
    }
}

/// Testi della finestra, usati anche dalle animazioni del tutorial perché dicano le stesse cose.
enum PanelText {
    /// Tasto per scegliere la riga in base alla posizione, solo per le prime nove: "3" a ricerca vuota
    /// (il numero da solo incolla), "⌘3" mentre si cerca (i numeri sono testo, e ⌘ + numero mette in coda).
    static func position(_ index: Int, searching: Bool) -> String? {
        guard index < 9 else { return nil }
        return searching ? "⌘\(index + 1)" : "\(index + 1)"
    }

    static func queue(_ count: Int) -> String {
        "\(count) in coda · un clic senza ⌘ aggiunge l’ultimo e incolla tutto"
    }

    static func resultCount(_ count: Int) -> String {
        count == 1 ? "1 risultato" : "\(count) risultati"
    }

    static func results(_ count: Int, days: Int) -> String {
        "\(resultCount(count)) · \(period(days))"
    }

    static func summary(days: Int, count: Int, pinned: Int) -> String {
        var summary = "\(period(days).capitalizedFirst) · \(count) \(count == 1 ? "elemento" : "elementi")"
        if pinned > 0 { summary += " · \(pinned) \(pinned == 1 ? "fissato" : "fissati")" }
        return summary
    }

    private static func period(_ days: Int) -> String {
        days == 1 ? "ultimo giorno" : "ultimi \(days) giorni"
    }
}

// MARK: - Riga del tutorial

/// Riga verde chiaro al posto della nona finché la cronologia è quasi vuota: apre il tutorial.
struct TutorialRow: View {
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.tutorial)
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 28, height: 28)
            Text("Scopri come si usa Copy8")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            KeyBadge(label: "9", selected: false)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Palette.tutorialFillHover : Palette.tutorialFill)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .help("Guarda come si usa Copy8 (tasto 9)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Scopri come si usa Copy8")
        .accessibilityHint("Tasto 9")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }
}

// MARK: - Intestazione di sezione

struct SectionHeader: View {
    let section: PanelModel.Section
    let days: Int

    var body: some View {
        HStack(spacing: 5) {
            if section.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(section.label)
                .font(.system(size: 11, weight: .semibold))
            Spacer(minLength: 8)
            if section.isPinned {
                // Spiegazione breve, visibile solo quando c'è almeno un elemento fissato.
                Text(days == 1 ? "Restano anche dopo 1 giorno" : "Restano anche dopo i \(days) giorni")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(Palette.text2)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Riga

struct ClipRow: View {
    let item: ClipItem
    let selected: Bool
    let terms: [String]
    /// Tasto per posizione: "3" a ricerca vuota, "⌘3" mentre si cerca.
    let position: String?
    /// Posizione nella coda degli elementi da incollare insieme (1, 2, 3…), se la riga è in coda.
    let order: Int?
    let onTogglePin: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TypeIcon(item: item, selected: selected, order: order)
            Text(Highlight.make(item.title, terms: terms, selected: selected, monospaced: item.kind.isMonospaced))
                .font(item.kind.isMonospaced ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if selected || item.pinned || position != nil {
                HStack(spacing: 6) {
                    if selected || item.pinned {
                        // Un tocco sulla puntina ha la precedenza su quello della riga, che incollerebbe.
                        Image(systemName: item.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selected ? Palette.onAccent : Palette.text2)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onTogglePin)
                            .help(item.pinned ? "Togli dai fissati (⌘P)" : "Fissa: resta in cima e non viene mai cancellato (⌘P)")
                    }
                    if let position {
                        KeyBadge(label: position, selected: selected)
                    }
                }
            }
            Text(DayFormat.time.string(from: item.copiedAt))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(selected ? Palette.onAccent : Palette.text2)
        }
        .foregroundStyle(selected ? Palette.onAccent : Palette.text)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Palette.accent : (order == nil ? Color.clear : Palette.accent.opacity(0.14)))
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue([item.pinned ? "Fissato" : nil, order.map { "In coda, posizione \($0)" }]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(position.map { "Tasto \($0)" } ?? "")
        .accessibilityAction(named: item.pinned ? "Togli dai fissati" : "Fissa", onTogglePin)
    }
}

/// Etichetta del tasto che sceglie la riga in base alla posizione.
struct KeyBadge: View {
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(selected ? Palette.onAccent : Palette.text2)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected ? Palette.onAccent.opacity(0.2) : Palette.fill)
            )
            .accessibilityHidden(true)
    }
}

struct TypeIcon: View {
    let item: ClipItem
    let selected: Bool
    /// Se la riga è in coda, al posto dell'icona c'è il suo numero d'ordine.
    var order: Int?

    var body: some View {
        ZStack {
            if let order {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Palette.onAccent : Palette.accent)
                Text("\(order)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Palette.accent : Palette.onAccent)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Palette.onAccent.opacity(0.2) : Palette.fill)
            }
            if order != nil {
                EmptyView()
            } else if item.kind == .color, let swatch = item.swatch {
                Circle()
                    .fill(swatch)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
                    .overlay(Circle().strokeBorder(selected ? Palette.onAccent : Color.clear, lineWidth: 1.5).padding(-1.5))
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Palette.onAccent : Palette.iconForeground)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: - Anteprima

struct PreviewPane: View {
    let item: ClipItem?
    let terms: [String]
    let history: History
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let item {
                ScrollView(.vertical) {
                    content(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                metadata(item)
            } else {
                Spacer()
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            Text(Highlight.make(item.previewText, terms: terms, selected: false, monospaced: false))
                .font(.system(size: 13))
                .lineSpacing(4)
        case .code:
            Text(Highlight.make(item.previewText, terms: terms, selected: false, monospaced: true))
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(5)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fill))
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Text(item.linkHost)
                    .font(.system(size: 17, weight: .semibold))
                Text(Highlight.make(item.text, terms: terms, selected: false, monospaced: false))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accentText)
            }
        case .color:
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.swatch ?? .clear)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                    .frame(height: 150)
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 20, design: .monospaced))
            }
        case .image:
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.fill)
                    if let image = history.thumbnail(for: item) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    } else {
                        Text("Immagine non più disponibile")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.text2)
                    }
                }
                .frame(height: 190)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
            }
        case .file:
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(item.fileURLs.prefix(20).enumerated()), id: \.offset) { _, url in
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                            Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.text2)
                        }
                    }
                }
            }
        }
    }

    private func metadata(_ item: ClipItem) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(item.metadata(days: days).enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(Palette.text2)
                        .frame(width: 96, alignment: .leading)
                    Text(row.1)
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Piccoli componenti

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 0.5)
    }
}

struct VerticalHairline: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(width: 0.5)
    }
}

struct Kbd: View {
    let label: String
    var side: CGFloat = 18

    var body: some View {
        Text(label)
            .font(.system(size: side <= 18 ? 10 : 11, weight: .medium))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 4)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .background(RoundedRectangle(cornerRadius: side <= 18 ? 4 : 5, style: .continuous).fill(Palette.fill))
            .overlay(RoundedRectangle(cornerRadius: side <= 18 ? 4 : 5, style: .continuous).strokeBorder(Palette.keyEdge, lineWidth: 0.5))
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Kbd(label: $0) }
            }
            Text(label)
        }
        .fixedSize()
    }
}

struct IconButton: View {
    let symbol: String
    let side: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Palette.text2)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Sfondo e bordo della modale

struct ModalBackground: View {
    let glass: Bool
    let intensity: Double
    let radius: CGFloat

    var body: some View {
        if glass {
            ZStack {
                if Glass.frost(intensity) > 0.01 {
                    VisualEffectBlur(radius: radius)
                        .opacity(Glass.frost(intensity))
                }
                Palette.surface.opacity(Glass.tint(intensity))
            }
        } else {
            Palette.surface
        }
    }
}

/// Riflessi di una goccia d'acqua, sopra il contenuto: filo di luce sul bordo, riflesso in alto,
/// spessore più scuro in basso e una caustica morbida. Non intercetta i clic.
struct WaterGloss: View {
    let radius: CGFloat
    let amount: Double

    var body: some View {
        if amount > 0.01 {
            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .black.opacity(0.22)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 12)
                        .blur(radius: 9)
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: width * 0.3))
                        .frame(width: width * 0.62, height: height * 0.3)
                        .position(x: width * 0.32, y: height * 0.06)
                        .blur(radius: 10)
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.16), .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: width * 0.25))
                        .frame(width: width * 0.5, height: height * 0.14)
                        .position(x: width * 0.62, y: height * 0.98)
                        .blur(radius: 10)
                    shape
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.18), .white.opacity(0.5)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                }
                .clipShape(shape)
                .opacity(amount)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Alone dietro testo e icone quando il vetro diventa trasparente, per leggerli su qualsiasi sfondo.
struct GlassHalo: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        if amount > 0.01 {
            content
                .shadow(color: Palette.halo.opacity(0.75 * amount), radius: 1)
                .shadow(color: Palette.halo.opacity(0.45 * amount), radius: 3)
        } else {
            content
        }
    }
}

struct ModalBorder: View {
    let glass: Bool
    let radius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.modalEdge, lineWidth: 0.5)
            RoundedRectangle(cornerRadius: radius - 0.5, style: .continuous)
                .strokeBorder(glass ? Palette.glassInnerEdge : Palette.modalInnerEdge, lineWidth: 0.5)
                .padding(0.5)
        }
        .allowsHitTesting(false)
    }
}

/// Sfocatura di ciò che sta dietro la finestra (materiale di sistema).
struct VisualEffectBlur: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: radius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: - Campo di ricerca

final class SearchTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = Tokens.accent
        }
        return accepted
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let onCreate: (NSTextField) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.textColor = Tokens.text
        field.placeholderAttributedString = NSAttributedString(string: "Cerca negli appunti, o premi 1–9", attributes: [
            .foregroundColor: Tokens.text2,
            .font: NSFont.systemFont(ofSize: 20),
            .kern: -0.2,
        ])
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Cerca negli appunti")
        onCreate(field)
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

// MARK: - Evidenziazione delle corrispondenze

enum Highlight {
    static func make(_ value: String, terms: [String], selected: Bool, monospaced: Bool, size: CGFloat = 13) -> AttributedString {
        var result = AttributedString(value)
        guard !terms.isEmpty, !value.isEmpty else { return result }
        let string = value as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        for term in terms {
            var location = 0
            var found = 0
            while location < string.length, found < 300 {
                let range = string.range(of: term, options: options, range: NSRange(location: location, length: string.length - location))
                guard range.location != NSNotFound, range.length > 0 else { break }
                if let target = Range(range, in: result) {
                    if selected {
                        result[target].swiftUI.font = .system(size: size, weight: .semibold, design: monospaced ? .monospaced : .default)
                        result[target].swiftUI.underlineStyle = .single
                    } else {
                        result[target].swiftUI.backgroundColor = Palette.highlight
                    }
                }
                location = range.location + range.length
                found += 1
            }
        }
        return result
    }
}
