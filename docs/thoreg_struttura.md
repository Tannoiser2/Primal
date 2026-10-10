# Thoreg — the Hammer

Terzo cacciatore giocabile. Il regolamento (p.84) lo descrive come un
personaggio di controllo: colpi pesanti, rimozione di struggle e supporto, al
prezzo di ridurre la propria mano con lo **strain** e di investire stamina per
amplificare le carte.

Estrazione: `python3 tools/extract_assets.py` (Thoreg e' nella lista dei set)
→ 40 immagini in `art/thoreg/`. Dati: `data/hunters.json` (24 carte azione),
`data/loadouts.json` (28 weapon, 6 mastery), `data/upgrades.json` (20
potenziamenti).

## Le 24 carte azione

Sei per colore, esattamente la composizione che chiede la sua weapon base.
Sette portano l'icona aggro; tre hanno il tratto **Impetus**, che di per se' non
fa niente ma altre carte lo contano (*Dashing Blow*, *Impulse*, *For Alborea!*).

Le carte che il motore non aveva mai visto prima:

| carta | cosa introduce |
|---|---|
| Bludgeon | **confuse** sul mostro |
| Mighty Strain, Evasive Action | **strain**: segnalini che tagliano la prossima pescata |
| Tenacity | una carta che **non conta** per il limite di mano |
| Tackle | sconta il costo a un altro giocatore e gli da' **stealth** |
| Rapid Blow | **annulla** gli effetti di una behavior appena rivelata |
| Sharp Reflexes | movimento gratuito fuori turno |
| Disruption | reagisce alla **combo di un altro giocatore** |
| Sledgehammer | costo X, giocabile **solo dopo un maneuver** |
| Leverage | pesca tante carte quanto lo struggle sul mostro |

## Le tre regole nuove

**Strain** (Glossario p.113): prendi il segnalino e lo metti sulla plancia; alla
prossima volta che riempi la mano li scarti tutti e peschi una carta in meno per
ognuno. Nel motore e' `PrimalPlayer.strain`, applicato in `_refill_hand`.

**Confuse** (p.107): metti il segnalino sul mostro e lo **giri verso il settore
che vuoi**; il prossimo effetto boost viene annullato — ma il mostro paga lo
struggle lo stesso — e il segnalino decade a inizio round. Nel motore e'
`monster_confused`. Un mostro *hardened* (Toramat, Dygorax) non puo' essere
confuso, e quel controllo c'era gia'.

**Stealth** (p.113): la carta non innesca le reazioni behavior legate al colore o
al tipo. Serve solo a *Tackle*, che la concede alla carta di un altro giocatore.

## Weapon e mastery

**Hammer** (livello 1): danno 2, composizione 6/6/6/6, e «dopo un maneuver, se
sei nel settore front, quel maneuver rimuove 1 struggle in piu'». E' la prima
weapon con una **condizione** oltre alla combo, quindi `_collect_card_triggers`
ora la verifica.

**Massive Blow** (mastery, focus 2) e' l'unica che non si focalizza con una
combo: «quando stordisci il mostro, metti un segnalino». Il motore aveva gia'
`unfocused_trigger` (Mirah lo usa con *deck_emptied*), e ora la focalizzazione
via stun passa da li'. Focalizzata da due abilita' a combo — la prima mastery
che ne ha piu' di una.

## I 20 potenziamenti

Nomi, colori, costi e testi vengono dal database; gli effetti sono scritti a
mano. **Sette su venti non hanno ancora effetto** nel motore e sono segnati come
tali: sono quasi tutti reazioni fuori turno molto specifiche (*Judgement*,
*Chase*, *Limitless Stamina*, *Adaptive Defense*, *Skull Crasher*) — la
schermata di costruzione li mostra in rosso e non li mette nel mazzo.

Due inciampi del database, entrambi gia' visti su altri cacciatori:

- **Il nome e' scritto "Thoerg"** nel foglio. Le carte dicono Thoreg, quindi la
  tabella `HUNTERS` di `build_loadouts.py` mappa lo slug allo sbaglio del
  database, come gia' fa con "Daeron".
- **Tre coppie di potenziamenti condividono lo stesso id TTS** (215700, 216100,
  216400): gli id globali di Thoreg sono quindi `5.000.000 + id×10 + posizione`,
  mentre Dareon e Mirah restano su `3/4.000.000 + id`. E la carta 216300 del
  track B2 era ambigua al colore (le due del tier sono entrambe maneuver):
  risolta guardando l'immagine — e' *Skull Crasher* — e messa in `MANUAL`.

## Verifica

`RulesTest` ha una sezione Thoreg: composizione del mazzo, strain che taglia la
pescata, Tenacity che non occupa posto, confuse che gira il mostro e decade,
Massive Blow che si focalizza a due stun, e Sledgehammer che rifiuta di essere
giocata se non segue un maneuver.

Oltre a quello, 40 partite automatiche con Thoreg in squadra — quattro mostri,
quattro livelli, con e senza forge — senza errori ne' avvisi di effetti non
implementati.

## Da fare

- I sette potenziamenti senza effetto.
- Heleren, Karah e Ljonar: stessa procedura, 24 + 20 carte ciascuno.
