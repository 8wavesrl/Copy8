import AppKit
import Combine
import Observation
import ServiceManagement
import SwiftUI

// MARK: - Finestra

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: Settings
    private let history: History
    private let recorder: ShortcutRecorder
    private let openTutorial: () -> Void

    init(settings: Settings, history: History, recorder: ShortcutRecorder, openTutorial: @escaping () -> Void) {
        self.settings = settings
        self.history = history
        self.recorder = recorder
        self.openTutorial = openTutorial
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, history: history, recorder: recorder,
                                                                  openTutorial: openTutorial))
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "Impostazioni"
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
        window?.bringToFront()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stop()
        history.commitClear()
    }
}

extension NSWindow {
    /// Centra la finestra nell'area visibile, sotto la barra dei menu e sopra il Dock.
    func placeInVisibleFrame() {
        guard let visible = NSScreen.main?.visibleFrame else {
            center()
            return
        }
        var frame = frame
        frame.origin.x = (visible.midX - frame.width / 2).rounded()
        frame.origin.y = max(visible.minY, (visible.minY + (visible.height - frame.height) / 2).rounded())
        setFrame(frame, display: false)
    }

    /// Porta la finestra davanti a tutte. Copy8 non ha icona nel Dock e macOS può rifiutare di renderla
    /// l'app attiva: in quel caso la finestra resterebbe dietro quella dell'app in primo piano.
    func bringToFront() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

// MARK: - Registrazione della scorciatoia

@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    @ObservationIgnored var onRecord: ((KeyCombo) -> Void)?
    @ObservationIgnored var onRecordingChange: ((Bool) -> Void)?
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard !isRecording else { return }
        isRecording = true
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.consume(event) ?? false } ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange?(false)
    }

    private func consume(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        if event.keyCode == 53 { stop(); return true } // esc annulla
        if let combo = KeyCombo(event: event) {
            onRecord?(combo)
            stop()
        }
        return true
    }
}

// MARK: - Avvio al login

enum LoginItem {
    enum Status { case on, off, needsApproval }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Contenuto

struct SettingsView: View {
    @Bindable var settings: Settings
    let history: History
    let recorder: ShortcutRecorder
    let openTutorial: () -> Void

    @State private var daysText = ""
    @State private var trusted = Paster.isTrusted
    @State private var cleared = false
    @State private var login = LoginItem.status
    @State private var loginError: String?
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var daysValid: Bool {
        guard let value = Int(daysText) else { return false }
        return Settings.dayRange.contains(value)
    }

    /// Su uno schermo basso la finestra si ferma all'altezza disponibile e il contenuto scorre.
    private static var maxHeight: CGFloat {
        max(360, (NSScreen.main?.visibleFrame.height ?? 800) - 40)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                historyGroup
                shortcutGroup
                appearanceGroup
                privacyGroup
                guideGroup
                CreditsView()
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 500)
        .frame(maxHeight: Self.maxHeight)
        .foregroundStyle(Palette.text)
        .background(Palette.window)
        .onAppear {
            daysText = String(settings.days)
            trusted = Paster.isTrusted
            login = LoginItem.status
            cleared = history.clearCutoff != nil
        }
        .onReceive(poll) { _ in
            trusted = Paster.isTrusted
            login = LoginItem.status
        }
    }

    // MARK: Cronologia

    private var historyGroup: some View {
        SettingsGroup(title: "Cronologia") {
            SettingsRow(label: "Conserva gli elementi per") {
                HStack(spacing: 8) {
                    TextField("", text: $daysText)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13).monospacedDigit())
                        .frame(width: 36)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.field))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(daysValid ? Palette.fieldEdge : Palette.danger, lineWidth: 1)
                        )
                        .accessibilityLabel("Giorni di cronologia")
                        .onChange(of: daysText) { _, newValue in
                            let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(3))
                            if digits != newValue { daysText = digits; return }
                            if let value = Int(digits), Settings.dayRange.contains(value), value != settings.days {
                                settings.days = value
                            }
                        }
                    Text("giorni").foregroundStyle(Palette.text2)
                }
            }
            SettingsRow(label: "Incolla direttamente nell’app attiva", divider: false) {
                Toggle("", isOn: $settings.pasteDirectly).labelsHidden().toggleStyle(.switch)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(daysValid
                     ? "La finestra mostra quello che hai copiato \(settings.days == 1 ? "nell’ultimo giorno" : "negli ultimi \(settings.days) giorni"). Gli elementi fissati con la puntina (⌘P) restano finché non li togli."
                     : "Inserisci un numero di giorni tra 1 e 365.")
                    .foregroundStyle(daysValid ? Palette.text2 : Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.pasteDirectly && !trusted {
                    HStack(spacing: 4) {
                        Text("Per incollare serve il permesso Accessibilità.")
                            .foregroundStyle(Palette.text2)
                        Button("Apri Impostazioni di Sistema") {
                            Paster.requestTrust()
                            Paster.openAccessibilitySettings()
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(Palette.accentText)
                    }
                }
            }
        }
    }

    // MARK: Scorciatoia

    private var shortcutGroup: some View {
        SettingsGroup(title: "Scorciatoia") {
            SettingsRow(label: "Apri la cronologia") {
                ShortcutButton(combo: settings.hotKey, recorder: recorder)
            }
            SettingsRow(label: "Avvia al login", divider: false) {
                Toggle("", isOn: Binding(
                    get: { login != .off },
                    set: { enabled in
                        do {
                            try LoginItem.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = "Non riesco a cambiare l’avvio al login. Sposta Copy8 in Applicazioni e riprova."
                        }
                        login = LoginItem.status
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if settings.hotKeyUnavailable {
                    Text("Questa combinazione è già usata da un’altra app. Scegline un’altra.")
                        .foregroundStyle(Palette.danger)
                }
                if login == .needsApproval {
                    HStack(spacing: 4) {
                        Text("Approva Copy8 negli elementi di login.")
                            .foregroundStyle(Palette.text2)
                        Button("Apri Impostazioni di Sistema") { SMAppService.openSystemSettingsLoginItems() }
                            .buttonStyle(.link)
                            .foregroundStyle(Palette.accentText)
                    }
                }
                if let loginError {
                    Text(loginError).foregroundStyle(Palette.danger)
                }
            }
        }
    }

    // MARK: Aspetto

    private var appearanceGroup: some View {
        SettingsGroup(title: "Aspetto") {
            SettingsRow(label: "Tema") {
                Picker("Tema", selection: $settings.theme) {
                    ForEach(ThemePreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(label: "Nella barra dei menu") {
                Picker("Nella barra dei menu", selection: $settings.menuBar) {
                    ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(label: "Mostra anteprima") {
                Toggle("", isOn: $settings.showPreview).labelsHidden().toggleStyle(.switch)
            }
            SettingsRow(label: "Effetto vetro", divider: settings.glass) {
                Toggle("", isOn: $settings.glass).labelsHidden().toggleStyle(.switch)
            }
            if settings.glass {
                SettingsRow(label: "Intensità") {
                    HStack(spacing: 12) {
                        Slider(value: Binding(
                            get: { settings.glassIntensity },
                            set: { settings.glassIntensity = $0.rounded() }
                        ), in: 1...100)
                        .frame(width: 200)
                        .accessibilityLabel("Intensità del vetro")
                        .accessibilityValue("\(Int(settings.glassIntensity))")
                        Text("\(Int(settings.glassIntensity))")
                            .font(.system(size: 13).monospacedDigit())
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                GlassSample(intensity: settings.glassIntensity)
            }
        } footer: {
            switch settings.menuBar {
            case .icon:
                EmptyView()
            case .iconAndText:
                Text("Accanto all’icona compaiono i primi caratteri dell’ultima copia: si vedono anche quando condividi lo schermo.")
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            case .hidden:
                Text("Senza icona, le impostazioni si aprono con \(settings.hotKey.symbols.joined()) e poi ⌘, oppure riaprendo Copy8 da Applicazioni.")
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Privacy

    private var privacyGroup: some View {
        SettingsGroup(title: "Privacy") {
            SettingsRow(label: "Ignora password e contenuti riservati") {
                Toggle("", isOn: $settings.ignoreConfidential).labelsHidden().toggleStyle(.switch)
            }
            HStack(spacing: 16) {
                Text(cleared ? "Cronologia cancellata" : "Cronologia")
                    .font(.system(size: 13))
                    .foregroundStyle(cleared ? Palette.text2 : Palette.text)
                Spacer(minLength: 16)
                if cleared {
                    Button("Annulla") {
                        history.undoClear()
                        cleared = false
                    }
                } else {
                    Button("Cancella cronologia…") {
                        history.clearAll()
                        cleared = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(minHeight: 44)
        } footer: {
            if cleared {
                Text("Diventa definitivo quando chiudi questa finestra. Gli elementi fissati restano.")
                    .foregroundStyle(Palette.text2)
            }
        }
    }

    // MARK: Guida

    private var guideGroup: some View {
        SettingsGroup(title: "Guida") {
            SettingsRow(label: "Come si usa Copy8", divider: false) {
                Button("Guarda il tutorial", action: openTutorial)
            }
        } footer: {
            Text("Quattro brevi animazioni: incollare, cercare, incollare più elementi insieme, fissare con la puntina.")
                .foregroundStyle(Palette.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Componenti delle impostazioni

/// In fondo alle impostazioni: il logo di 8 wave e la versione.
struct CreditsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Sviluppata da")
                .font(.system(size: 11))
                .foregroundStyle(Palette.text2)
            if let logo = Credits.logo {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
                    .foregroundStyle(Palette.text)
                    // Centratura ottica: il logo è centrato al pixel, ma l'occhio legge il cerchio come un simbolo
                    // a parte e centra la scritta, che sta tutta a destra. Uno spostamento di circa il 3,5% lo bilancia.
                    .offset(x: -3)
                    .accessibilityLabel("8 wave")
            } else {
                Text("8 wave").font(.system(size: 15, weight: .semibold))
            }
            if !Credits.version.isEmpty {
                Text("Copy8 \(Credits.version)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsGroup<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.groupEdge, lineWidth: 0.5))
            footer
                .font(.system(size: 11))
                .padding(.leading, 4)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let label: String
    var divider = true
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 16) {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 16)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            if divider { Hairline() }
        }
    }
}

struct ShortcutButton: View {
    let combo: KeyCombo
    let recorder: ShortcutRecorder

    var body: some View {
        Button {
            recorder.isRecording ? recorder.stop() : recorder.start()
        } label: {
            HStack(spacing: 4) {
                if recorder.isRecording {
                    Text("Premi i tasti…").foregroundStyle(Palette.text2)
                } else {
                    ForEach(Array(combo.symbols.enumerated()), id: \.offset) { _, symbol in
                        Kbd(label: symbol)
                    }
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .frame(minWidth: 92, minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.button))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recorder.isRecording ? Palette.accent : Palette.buttonEdge,
                                  lineWidth: recorder.isRecording ? 2 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recorder.isRecording
                            ? "Premi la nuova combinazione di tasti"
                            : "Scorciatoia attuale: \(combo.spokenDescription). Premi per cambiarla")
    }
}

/// Anteprima dal vivo dell'effetto vetro su quello che sta dietro la finestra.
struct GlassSample: View {
    let intensity: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.iconForeground)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fill))
            Text("Anteprima del vetro")
                .font(.system(size: 13))
            Spacer()
            Text(DayFormat.time.string(from: Date()))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Palette.text2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 44)
        .modifier(GlassHalo(amount: Glass.gloss(intensity)))
        .background(ModalBackground(glass: true, intensity: intensity, radius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(WaterGloss(radius: 8, amount: Glass.gloss(intensity)))
        .overlay(ModalBorder(glass: true, radius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}
