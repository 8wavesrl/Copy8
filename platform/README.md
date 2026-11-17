# Piattaforme

Una cartella per ogni tipo di Mac, con la sua versione di Copy8.

| Cartella | Mac | Architettura |
|---|---|---|
| `apple-silicon/` | Con chip Apple, M1 e successivi | arm64 |
| `intel/` | Con processore Intel | x86_64 |

Il codice è uno solo, in `Sources/`: cambia solo il processore per cui viene compilato, quindi una modifica vale
per tutte e due le versioni e non ci sono file da copiare tra le cartelle.

`scripts/build-app.sh` crea in ogni cartella `Copy8.app` e, con `--dmg` o `--notarize`,
`Copy8-<versione>-<piattaforma>.dmg`. Sono file generati: git li ignora e i DMG si pubblicano nella pagina
Releases. Le opzioni dello script sono nel [README principale](../README.md#compilare).

La versione Intel si apre anche sui Mac con chip Apple, con Rosetta; quella apple-silicon sui Mac Intel non si
apre.
