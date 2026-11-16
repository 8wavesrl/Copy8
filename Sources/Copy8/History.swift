import AppKit
import ImageIO

/// La cronologia in memoria, ordinata dal più recente. Ogni modifica passa anche dall'archivio.
@MainActor
final class History {
    private(set) var items: [ClipItem] = []
    /// Durante "Cancella cronologia" gli elementi fino a questa data restano nascosti finché la scelta non è definitiva.
    private(set) var clearCutoff: Date?
    var onChange: (() -> Void)?

    private let store: Store
    private let worker = DispatchQueue(label: "copy8.images", qos: .utility)
    private let thumbnails = NSCache<NSString, NSImage>()

    init(store: Store) {
        self.store = store
        items = store.loadAll()
        thumbnails.countLimit = 24
    }

    /// Gli elementi da mostrare: durante una cancellazione in sospeso restano solo i fissati e i nuovi.
    var visible: [ClipItem] {
        guard let cutoff = clearCutoff else { return items }
        return items.filter { $0.pinned || $0.copiedAt > cutoff }
    }

    // MARK: Nuovi elementi

    func add(_ capture: Capture) {
        switch capture.kind {
        case .image:
            guard let data = capture.imageData else { return }
            let directory = store.imagesDirectory
            let isPNG = capture.imageIsPNG
            worker.async { [weak self] in
                guard let rep = NSBitmapImageRep(data: data) else { return }
                let png = isPNG ? data : (rep.representation(using: .png, properties: [:]) ?? data)
                let digest = Hashing.hex(png)
                let file = digest + ".png"
                let url = directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? png.write(to: url, options: .atomic)
                }
                let width = rep.pixelsWide, height = rep.pixelsHigh, bytes = png.count
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.record(capture, text: "Immagine \(width) × \(height)", hash: "i" + digest,
                                     imageFile: file, width: width, height: height, bytes: bytes)
                    }
                }
            }
        case .file:
            record(capture, text: capture.text, hash: "f" + Hashing.hex(Data(capture.text.utf8)),
                   imageFile: nil, width: 0, height: 0, bytes: 0)
        default:
            record(capture, text: capture.text, hash: "s" + Hashing.hex(Data(capture.text.utf8)),
                   imageFile: nil, width: 0, height: 0, bytes: 0)
        }
    }

    private func record(_ capture: Capture, text: String, hash: String, imageFile: String?, width: Int, height: Int, bytes: Int) {
        let now = Date()
        guard let saved = store.upsert(kind: capture.kind, text: text, rtf: capture.rtf, html: capture.html, image: imageFile,
                                       width: width, height: height, bytes: bytes, sourceName: capture.sourceName,
                                       sourceBundle: capture.sourceBundle, date: now, hash: hash) else { return }
        items.removeAll { $0.id == saved.id || $0.hash == hash }
        items.insert(ClipItem(id: saved.id, kind: capture.kind, text: text, imageFile: imageFile, width: width, height: height,
                              byteCount: bytes, sourceName: capture.sourceName, sourceBundle: capture.sourceBundle,
                              copiedAt: now, hash: hash, pinned: saved.pinned), at: 0)
        onChange?()
    }

    // MARK: Modifiche

    /// Lo stato attuale di un elemento: le righe a schermo possono averne una copia superata.
    func current(_ item: ClipItem) -> ClipItem {
        items.first { $0.id == item.id } ?? item
    }

    /// Riporta in cima un elemento appena incollato o copiato dalla finestra.
    func touch(_ item: ClipItem) {
        let now = Date()
        let latest = current(item)
        store.touch(id: item.id, date: now)
        items.removeAll { $0.id == item.id }
        items.insert(latest.with(copiedAt: now), at: 0)
        onChange?()
    }

    /// Fissa o toglie la puntina: un elemento fissato non viene mai cancellato in automatico.
    func setPinned(_ item: ClipItem, _ pinned: Bool) {
        store.setPinned(id: item.id, pinned: pinned)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = items[index].with(pinned: pinned)
        }
        onChange?()
    }

    func delete(_ item: ClipItem) {
        removeImages(store.delete(id: item.id))
        items.removeAll { $0.id == item.id }
        onChange?()
    }

    /// Elimina definitivamente quello che è più vecchio dei giorni impostati, tranne i fissati.
    func purge(days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard items.contains(where: { !$0.pinned && $0.copiedAt < cutoff }) else { return }
        removeImages(store.deleteOlder(than: cutoff))
        items.removeAll { !$0.pinned && $0.copiedAt < cutoff }
        onChange?()
    }

    func clearAll() {
        clearCutoff = Date()
        onChange?()
    }

    func undoClear() {
        clearCutoff = nil
        onChange?()
    }

    /// Rende definitiva la cancellazione (alla chiusura delle impostazioni o all'uscita). I fissati restano.
    func commitClear() {
        guard let cutoff = clearCutoff else { return }
        removeImages(store.deleteUpTo(cutoff))
        items.removeAll { !$0.pinned && $0.copiedAt <= cutoff }
        clearCutoff = nil
        onChange?()
    }

    // MARK: Dati per incolla e anteprima

    func richData(for item: ClipItem) -> (rtf: Data?, html: Data?) {
        store.richData(id: item.id)
    }

    func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { store.imagesDirectory.appendingPathComponent($0) }
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let file = item.imageFile, let url = imageURL(for: item) else { return nil }
        if let cached = thumbnails.object(forKey: file as NSString) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 900,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        thumbnails.setObject(thumbnail, forKey: file as NSString)
        return thumbnail
    }

    private func removeImages(_ files: [String]) {
        for file in files {
            thumbnails.removeObject(forKey: file as NSString)
            try? FileManager.default.removeItem(at: store.imagesDirectory.appendingPathComponent(file))
        }
    }
}
