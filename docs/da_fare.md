# Da fare

Elenco unico di quello che manca, in ordine di quanto pesa sul gioco.

Stato al 24 novembre 2026: **6 mostri su 6**, **6 cacciatori su 6**, tutte le 144
carte azione e i 120 potenziamenti con il loro effetto; test delle regole, 480
partite automatiche (con gli Item) e 16 partite salvate e rigiocate identiche.

## 1. Regole e dati

- Il **plateau di Toramat**: la sua Stance III dice di rimuoverlo, ma nei due
  setup Expedition di Toramat il plateau non c'è. Ora il plateau esiste (Tarragua),
  quindi la regola funziona dove serve.
- Gli **Item** non hanno immagini (nel mod non ci sono carte singole): come armor e
  helm della forge si mostrano col nome e il testo.

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
- **Slot Item**: i 18 oggetti della forge nei tre livelli, dal `primal_database.xlsm`
  (`tools/build_items.py`), con tutti gli effetti nel motore.
- Terreno delle Expedition di Tarragua e Jekoros letto dai diagrammi del Regolamento.
- Pubblicazione solo su richiesta, con controllo dei glifi e test delle regole.

## Fuori perimetro

La **modalità Campagna**: quest, crafting, progressione della forge, scenari
collegati. Il progetto è esplicitamente limitato a Expedition.
