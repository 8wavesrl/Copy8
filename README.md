# Copy8

Cronologia degli appunti per macOS. Una scorciatoia (di default ⌥V) apre una finestra con tutto quello
che hai copiato negli ultimi giorni, dal più recente al più vecchio, con ricerca full text.

## Installare

Scarica `Copy8-<versione>.dmg` dalla pagina Releases, aprilo e trascina Copy8 in Applicazioni. Serve macOS 14
o successivo.

Copy8 è firmata con il certificato Developer ID di 8 wave srl e autenticata da Apple, quindi si apre senza
avvisi.

## Compilare

Servono gli strumenti da riga di comando di Xcode (`xcode-select --install`).

```bash
scripts/build-app.sh              # crea build/Copy8.app
scripts/build-app.sh --dmg        # crea anche build/Copy8-<versione>.dmg
scripts/build-app.sh --notarize   # crea il DMG e lo fa autenticare da Apple, per distribuirlo
scripts/build-app.sh --install    # la copia anche in /Applications
```

## Pubblicare una versione

Per distribuire Copy8 servono il certificato "Developer ID Application" di 8 wave srl nel portachiavi, con la
sua chiave privata, e l'autenticazione (notarization) di Apple: senza, macOS blocca l'app scaricata anche se
è firmata. `build-app.sh` usa il certificato in automatico quando lo trova, con hardened runtime e timestamp.

Una volta sola, salva nel portachiavi le credenziali per l'autenticazione. Serve un Apple ID del team
8 wave srl e una password per app, da creare su [account.apple.com](https://account.apple.com) › Accesso e
sicurezza › Password per le app:

```bash
xcrun notarytool store-credentials "Copy8" --apple-id <Apple ID> --team-id GCQB48ZS4W
```

Poi, per ogni versione: aggiorna `CFBundleShortVersionString` e `CFBundleVersion` in `Support/Info.plist` e
lancia `scripts/build-app.sh --notarize`. Lo script firma app e DMG, invia il DMG ad Apple, aspetta l'esito
(di solito pochi minuti), aggancia il ticket al DMG e controlla che Gatekeeper lo accetti. Se Apple rifiuta,
stampa il log con il motivo. Il file da pubblicare è `build/Copy8-<versione>.dmg`.

L'app vive nella barra dei menu e non compare nel Dock. La sua icona è una cartellina con un 8, che si riempie
per un attimo quando Copy8 registra una copia. Il menu dell'icona mostra le ultime 5 copie, che si incollano
con un clic, e porta alle impostazioni; ci si arriva anche con ⌘, a finestra aperta.

## Permesso Accessibilità

Per incollare direttamente nell'app attiva Copy8 simula ⌘V, e macOS lo consente solo con il permesso
in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità. Senza permesso l'elemento viene copiato
negli appunti e basta premere ⌘V.

macOS lega i permessi alla firma dell'app. Con il certificato Developer ID i permessi restano validi a ogni
ricompilazione. Se compili da solo senza quel certificato, crea una volta un certificato autofirmato con
`scripts/make-signing-cert.sh`: `build-app.sh` lo usa in automatico, con lo stesso effetto ma solo sul tuo
Mac. Senza certificato la firma è ad-hoc e cambia ogni volta.

Quando la firma cambia, anche passando dalla versione del DMG a una tua build o viceversa, macOS non
riconosce più il permesso e l'incolla smette di funzionare: togli Copy8 dall'elenco Accessibilità con il
tasto − e aggiungilo di nuovo.

## Nella finestra

| Tasti | Azione |
|---|---|
| ↑ ↓, Pagina su/giù | Scegli l'elemento |
| ↩ | Incolla nell'app attiva |
| ⌥↩ | Incolla come testo semplice |
| ⇧ clic | Incolla la riga e lascia la finestra aperta, per incollare altre righe una dopo l'altra (serve il permesso Accessibilità: senza, la finestra si chiude come con il clic) |
| 1 … 9 | A ricerca vuota, incolla l'elemento in quella posizione (il numero è sulla riga); il 9 apre il tutorial finché la sua riga c'è |
| ⌘ clic, ⌘1 … ⌘9, ⌘↩ | Mette la riga in coda, per incollare più elementi insieme (vedi sotto) |
| ⌘C | Copia senza incollare (se nel campo di ricerca non c'è testo selezionato) |
| ⌘P | Fissa l'elemento con la puntina, o lo toglie dai fissati |
| ⌘⌫ | Elimina l'elemento |
| ⌘, | Impostazioni |
| esc | Svuota la coda, poi la ricerca, poi chiude |

La ricerca ignora maiuscole e accenti e richiede tutte le parole scritte, in qualunque punto del testo o
nel nome dell'app di origine. A ricerca vuota i tasti 1–9 scelgono una riga: per cercare un testo che
inizia con un numero, scrivi prima uno spazio. Clic destro su una riga per incollare, copiare, fissare o eliminare.

### Incollare più elementi insieme

Tieni premuto ⌘ e scegli le righe una dopo l'altra, con un clic o con il loro numero: entrano in coda
nell'ordine in cui le scegli, e al posto dell'icona compare il numero d'ordine. Poi scegli l'ultima senza ⌘,
con un clic o con il numero: Copy8 incolla tutto in quell'ordine. Per esempio ⌘ clic sulle righe 1, 6 e 3,
poi clic sulla 8, incolla 1, 6, 3, 8.

- ↩ incolla la coda così com'è; esc la svuota; ⌘ clic su una riga già in coda la toglie.
- La coda resta mentre cerchi, quindi puoi cercare, aggiungere e cercare ancora.
- Se gli elementi sono tutti testo vengono incollati come un testo solo, una riga per elemento e senza
  formattazione. Se ci sono immagini o file ogni elemento resta separato negli appunti, e dipende dall'app
  di destinazione se li incolla tutti o solo il primo.

### Elementi fissati

Un elemento fissato con la puntina (⌘P, il clic sulla puntina della riga selezionata o il menu con il tasto
destro) sta nella sezione "Fissati" in cima all'elenco e non viene mai cancellato in automatico: né dopo i
giorni impostati né con "Cancella cronologia". Si elimina solo a mano. Nell'anteprima la riga
"Conservazione" dice fino a quando resta un elemento non fissato.

### Tutorial

Finché la cronologia ha meno di nove elementi, al posto della nona riga c'è una riga verde chiaro,
"Scopri come si usa Copy8": si apre con un clic o con il tasto 9. Alla nona copia la riga sparisce per sempre
e il tutorial resta in Impostazioni › Guida. Sono quattro animazioni (incollare, cercare, più elementi
insieme, puntina) fatte con gli stessi componenti della finestra, quindi seguono tema e grafica dell'app.
Con "Riduci movimento" attivo nelle impostazioni di sistema mostrano un'immagine ferma. ← e → cambiano
pagina, esc chiude.

## Impostazioni

- **Conserva gli elementi per**: numero di giorni (1–365, default 7). Quello che è più vecchio viene eliminato,
  tranne gli elementi fissati.
- **Incolla direttamente nell'app attiva**: se spento, Copy8 copia soltanto.
- **Apri la cronologia**: clicca e premi la nuova combinazione (serve ⌘, ⌃ o ⌥).
- **Avvia al login**.
- **Tema**: Sistema, Chiaro, Scuro.
- **Nella barra dei menu**: Icona (predefinita), Icona e ultima copia (i primi 10 caratteri accanto
  all'icona, visibili anche quando condividi lo schermo), Nascosta. Senza icona le impostazioni si aprono dalla
  finestra con ⌘, oppure riaprendo Copy8 da Applicazioni.
- **Mostra anteprima**: pannello di destra con il contenuto completo e i dettagli.
- **Effetto vetro** e **Intensità** (1–100), con anteprima dal vivo. A 1 la superficie è quasi piena, a 100
  la finestra è vetro lucido e molto trasparente. La sfocatura resta piena fino a circa 40 e a 100 ne resta
  circa un terzo; la tinta della superficie scende dal 94% a circa il 24%; da metà scala in su compaiono i
  riflessi (filo di luce sul bordo, riflesso in alto, bordo inferiore più scuro) e un alone dietro il testo
  che lo tiene leggibile su qualsiasi sfondo.
- **Ignora password e contenuti riservati**: salta quello che i password manager marcano come riservato.
- **Cancella cronologia…**: si può annullare finché la finestra delle impostazioni è aperta. Gli elementi
  fissati restano.
- **Come si usa Copy8**: apre il tutorial.

## Dati

Tutto resta sul Mac, in `~/Library/Application Support/Copy8/`: `history.sqlite` per testi, link e
percorsi, la cartella `Images/` per le immagini. Copy8 riconosce testo, link, codice, colori (`#RRGGBB`,
`rgb()`), immagini e file. Il testo formattato (RTF, HTML) viene conservato e incollato così com'era.
Copy8 ignora un testo più lungo di un milione di caratteri e un'immagine più grande di 40 MB.

## Struttura

| File | Ruolo |
|---|---|
| `AppDelegate.swift` | Avvio, menu, collegamenti tra le parti |
| `ClipboardWatcher.swift` | Controlla gli appunti ogni 0,4 s e riconosce il tipo di contenuto |
| `Store.swift`, `History.swift` | Archivio SQLite e cronologia in memoria |
| `PanelController.swift`, `PanelModel.swift`, `PanelView.swift` | La finestra: tastiera, ricerca, elenco, anteprima |
| `Paster.swift` | Scrive negli appunti e simula ⌘V |
| `HotKey.swift` | Scorciatoia globale (Carbon, non richiede permessi) |
| `StatusBar.swift` | Icona e menu nella barra dei menu |
| `Credits.swift` | "Sviluppata da 8 wave": logo nelle impostazioni, scritta nella finestra e nel menu |
| `SettingsView.swift`, `Settings.swift` | Impostazioni e loro salvataggio |
| `Theme.swift` | Token del design system, chiaro e scuro |
| `Toast.swift` | Conferma dopo l'incolla |
| `Tutorial.swift` | Finestra del tutorial e le sue animazioni |

La finestra viene creata e disegnata una volta all'avvio e poi solo mostrata, così si apre al frame
successivo alla scorciatoia.
