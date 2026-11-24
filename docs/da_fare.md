# Da fare

Elenco unico di quello che manca, in ordine di quanto pesa sul gioco.

Stato al 24 novembre 2026: **6 mostri su 6**, **6 cacciatori su 6**, tutte le 144
carte azione e i 120 potenziamenti con il loro effetto; test delle regole, 480
partite automatiche e 16 partite salvate e rigiocate identiche.

## 1. Regole e dati

- **Lo slot Item**: il regolamento prevede di scegliere anche un Item fra gli
  accessori forgiabili. Mancano i dati: le righe degli Item stanno nel
  `primal_database.xlsm`, che non è nel repository. Con quel file
  `tools/build_loadouts.py` può estrarle come fa con weapon, armor e helm.
- **Le caselle del terreno di Tarragua e Jekoros** sono provvisorie: i pezzi sono
  quelli del Regolamento (p.69-70), le posizioni vanno lette dai diagrammi.
- Il **plateau di Toramat**: la sua Stance III dice di rimuoverlo, ma nei due
  setup Expedition di Toramat il plateau non c'è. Ora il plateau esiste (Tarragua),
  quindi la regola funziona dove serve.

## 2. Interfaccia

- **I tracciati sono sulla plancia mostro, non sul tavolo 3D**: salute,
  hardening, acceleration e charge si leggono nel pannello di sinistra e nella
  barra in alto.
- **Hotseat**: le scelte che toccano a un altro giocatore compaiono nello stesso
  schermo. La rete serve al salvataggio, non al gioco a più dispositivi.

## 3. Fatto il 24 novembre 2026

- Tema grafico nuovo (font Teko e Barlow Semi Condensed, palette inchiostro e
  ruggine), schermata iniziale a pieno schermo, plancia su un tavolo con luce
  morbida, controlli al tocco per iPad, mano che si legge col dito.
- **Tarragua** e **Jekoros**: trascritti carta per carta, vedi
  `docs/tarragua_struttura.md` e `docs/jekoros_struttura.md`.
- **Brush** (turno in pausa) e **plateau** (riding check).
- Peril e objective **permanenti** restano in gioco quando la stance avanza.
- `why_not_playable` non conta più la carta che stai giocando fra le fonti di stamina.
- Salvataggio su Firebase e ripresa con un codice.
- Pubblicazione solo su richiesta, con controllo dei glifi e test delle regole.

## Fuori perimetro

La **modalità Campagna**: quest, crafting, progressione della forge, scenari
collegati. Il progetto è esplicitamente limitato a Expedition.
