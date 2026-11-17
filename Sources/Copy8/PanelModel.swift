import AppKit
import Observation

@MainActor
protocol PanelActions: AnyObject {
    func paste(_ item: ClipItem, plain: Bool)
    func copy(_ item: ClipItem)
    func delete(_ item: ClipItem)
    func togglePin(_ item: ClipItem)
    /// Una riga è stata scelta: con `chaining` (⌘ premuto) entra nella coda, altrimenti si incolla.
    func choose(_ item: ClipItem, chaining: Bool)
    func toggleQueue(_ item: ClipItem)
    func openSettings()
    func openTutorial()
    func focusSearch()
}

/// Stato della finestra: ricerca, risultati raggruppati per giorno, selezione.
@MainActor
@Observable
final class PanelModel {
    struct Row: Identifiable {
        let index: Int
        let item: ClipItem
        var id: Int64 { item.id }
    }

    struct Section {
        let day: Date
        let label: String
        let isPinned: Bool
        let isFirst: Bool
    }

    /// L'elenco è una sola sequenza piatta di intestazioni e righe: una riga non cambia mai contenitore
    /// quando viene fissata o tolta dai fissati, così non restano a schermo copie vecchie.
    enum Entry: Identifiable {
        case header(Section)
        case row(Row)

        var id: String {
            switch self {
            case .header(let section): return section.isPinned ? "h-fissati" : "h-\(Int(section.day.timeIntervalSince1970))"
            case .row(let row): return "r-\(row.item.id)"
            }
        }
    }

    static func rowID(_ id: Int64) -> String { "r-\(id)" }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            refresh()
            selection = 0
            requestScrollToTop()
        }
    }
    var selection = 0
    private(set) var results: [ClipItem] = []
    private(set) var entries: [Entry] = []
    private(set) var terms: [String] = []
    private(set) var poolCount = 0
    private(set) var pinnedCount = 0
    /// Coda degli elementi da incollare insieme, nell'ordine in cui sono stati scelti con ⌘.
    var queue: [Int64] = []
    /// Id della riga da rendere visibile; -1 significa "torna in cima".
    private(set) var scrollTarget: Int64 = -1
    private(set) var scrollTick = 0

    @ObservationIgnored weak var actions: PanelActions?
    @ObservationIgnored private let history: History
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private var lastMouse = NSPoint(x: -1, y: -1)

    init(history: History, settings: Settings) {
        self.history = history
        self.settings = settings
    }

    var selectedItem: ClipItem? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// La riga del tutorial occupa il posto della nona, quindi c'è solo a ricerca vuota.
    var showsTutorial: Bool {
        settings.showsTutorialRow && query.isEmpty
    }

    func refresh() {
        let cutoff = Date().addingTimeInterval(-Double(settings.days) * 86_400)
        // I fissati restano sempre, anche oltre i giorni impostati.
        let pool = history.visible.filter { $0.pinned || $0.copiedAt >= cutoff }
        poolCount = pool.count
        // La nona copia prende il posto della riga del tutorial, per sempre.
        if pool.count >= 9, settings.showsTutorialRow { settings.showsTutorialRow = false }
        terms = Search.terms(query)
        let needles = terms.map { Array($0.utf8) }
        let matching = needles.isEmpty ? pool : pool.filter { item in needles.allSatisfy(item.matches) }
        let pinned = matching.filter(\.pinned)
        results = pinned + matching.filter { !$0.pinned }
        pinnedCount = pinned.count

        var built: [Entry] = []
        var currentHeader: String?
        for (index, item) in results.enumerated() {
            let section = item.pinned
                ? Section(day: .distantFuture, label: "Fissati", isPinned: true, isFirst: built.isEmpty)
                : Section(day: DayFormat.dayKey(item.copiedAt), label: DayFormat.dayLabel(item.copiedAt), isPinned: false, isFirst: built.isEmpty)
            let header = Entry.header(section)
            if header.id != currentHeader {
                built.append(header)
                currentHeader = header.id
            }
            built.append(.row(Row(index: index, item: item)))
        }
        entries = built
        if selection >= results.count { selection = max(0, results.count - 1) }
    }

    /// Seleziona di nuovo un elemento dopo che ha cambiato posizione (per esempio quando viene fissato).
    func select(id: Int64) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        selection = index
        scrollTarget = id
        scrollTick += 1
    }

    /// Posizione di un elemento nella coda, a partire da 1.
    func queueOrder(of id: Int64) -> Int? {
        queue.firstIndex(of: id).map { $0 + 1 }
    }

    /// Aggiunge l'elemento in fondo alla coda, o lo toglie se c'era già.
    func toggleQueue(_ id: Int64) {
        if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
        } else {
            queue.append(id)
        }
    }

    /// La catena da incollare quando si sceglie l'ultima riga senza ⌘: la coda più quella riga in fondo.
    func chain(endingWith id: Int64) -> [Int64] {
        queue.contains(id) ? queue : queue + [id]
    }

    func prepareForShow() {
        queue = []
        if query.isEmpty { refresh() } else { query = "" }
        selection = 0
        lastMouse = NSEvent.mouseLocation
        requestScrollToTop()
    }

    func move(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
        scrollTarget = results[selection].id
        scrollTick += 1
    }

    /// Il passaggio del mouse seleziona solo se il mouse si è mosso davvero,
    /// non quando è la lista a scorrere sotto un puntatore fermo.
    func hover(_ index: Int) {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse else { return }
        lastMouse = mouse
        if selection != index { selection = index }
    }

    private func requestScrollToTop() {
        scrollTarget = -1
        scrollTick += 1
    }
}
