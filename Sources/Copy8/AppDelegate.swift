import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let recorder = ShortcutRecorder()
    private var history: History!
    private var watcher: ClipboardWatcher!
    private var panel: PanelController!
    private var toast: ToastController!
    private var settingsWindow: SettingsWindowController!
    private var tutorial: TutorialWindowController!
    private var statusBar: StatusBarController!
    private var purgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyTheme()

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copy8", isDirectory: true)
        do {
            history = History(store: try Store(directory: support))
        } catch {
            let alert = NSAlert()
            alert.messageText = "Copy8 non riesce ad aprire la cronologia"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        history.purge(days: settings.days)

        toast = ToastController()
        watcher = ClipboardWatcher()
        watcher.ignoreConfidential = { [unowned self] in settings.ignoreConfidential }
        watcher.onCapture = { [unowned self] capture in
            history.add(capture)
            statusBar?.flash()
        }
        watcher.start()

        panel = PanelController(settings: settings, history: history, watcher: watcher, toast: toast)
        tutorial = TutorialWindowController(settings: settings)
        panel.onOpenSettings = { [unowned self] in openSettings() }
        panel.onOpenTutorial = { [unowned self] in tutorial.show() }
        history.onChange = { [unowned self] in
            panel.historyChanged()
            statusBar?.updateTitle()
        }

        settingsWindow = SettingsWindowController(settings: settings, history: history, recorder: recorder) { [unowned self] in
            tutorial.show()
        }
        recorder.onRecord = { [unowned self] combo in settings.hotKey = combo }
        recorder.onRecordingChange = { [unowned self] recording in
            if recording { HotKeyCenter.shared.unregister() } else { registerHotKey() }
        }

        HotKeyCenter.shared.onPress = { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        registerHotKey()
        settings.onChange = { [unowned self] change in settingsChanged(change) }

        buildMainMenu()
        statusBar = StatusBarController(settings: settings, history: history)
        statusBar.onOpenPanel = { [unowned self] in panel.show() }
        statusBar.onOpenSettings = { [unowned self] in openSettings() }
        statusBar.onPaste = { [unowned self] item in panel.paste(item, plain: false) }
        statusBar.update()

        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.history.purge(days: self.settings.days)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer

        panel.warmUp()

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "welcomed") {
            defaults.set(true, forKey: "welcomed")
            toast.show("Copy8 è attivo: \(settings.hotKey.symbols.joined()) apre la cronologia", on: NSScreen.main)
        }
        if CommandLine.arguments.contains("--show") { panel.show() }
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--tutorial") { tutorial.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        history?.commitClear()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Impostazioni

    private func settingsChanged(_ change: Settings.Change) {
        switch change {
        case .theme: applyTheme()
        case .preview: panel.applySize()
        case .hotKey: registerHotKey()
        case .menuBar: statusBar.update()
        case .days: panel.historyChanged()
        case .other: break
        }
    }

    private func applyTheme() {
        switch settings.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func registerHotKey() {
        settings.hotKeyUnavailable = !HotKeyCenter.shared.register(settings.hotKey)
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    // MARK: Menu

    /// Serve per ⌘C, ⌘V, ⌘A nei campi di testo della finestra delle impostazioni.
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Impostazioni…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Chiudi finestra", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: "Esci da Copy8", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Modifica")
        editMenu.addItem(NSMenuItem(title: "Annulla", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Ripeti", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copia", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Seleziona tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
