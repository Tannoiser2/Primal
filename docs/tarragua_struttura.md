# Tarragua — struttura rilevata

Quinto mostro. Dati in `data/tarragua.json`, scritti da
`tools/build_tarragua_jekoros.py`: la trascrizione delle carte sta lì, in forma
di dati, e rifare il file è rilanciare lo script.

## I quattro mazzi behavior

Le 36 carte dei quattro mazzi sono **16 distinte** (Hammer Tail e Aggressive
Posture compaiono in due copie nello stesso mazzo). Le copie identiche si
riconoscono per immagine: differenza media dei pixel zero.

Il livello di ogni mazzo lo dice il **glifo aggression** in alto a sinistra di
ogni carta, ordine `≢ ⊕ Ψ 8 M V` (A…F). Ogni glifo compare tre volte per mazzo e la
finestra scorrevole di p.60 è univoca:

| gruppo estratto | glifi | livello |
|---|---|---|
| 5 | ≢ ⊕ Ψ | 0 |
| 2 | ⊕ Ψ 8 | 1 |
| 4 | Ψ 8 M | 2 |
| 3 | 8 M V | 3 |

Reazione e refresh stanno sul **retro**: icona al centro, refresh in basso a
sinistra.

| carta | reazione | refresh | versioni |
|---|---|---|---|
| Metal Skin / Arkeum Skin | inizio turno nel front | 7 | shield +1 / +4 fino a fine turno |
| Spidery Grasp | inizio turno nel front | 4 | salta il movimento se nessuno vicino scarta un'offensive; la versione 8 aggiunge *dazed*; boost 1 |
| Rumbling Stomp | dodge giocato | 1 | PP-1 struggle e DMG+1 / threatened, 1PP struggle e DMG+3 |
| Rampaging Horns | attack giocato | 5 | si gira e ti lascia muovere / DMG se non ti muovi, movimento +1 |
| Crushing Horns | inizio turno nei flank | 5 | se ha subito danni: front e flank / tutti rivelano 2 dodge; boost: scarta 3 attrition |
| Indomitable Charge | fine round | 4 | front DMG (x2 nella versione 8) se non rivela 2 dodge; chi li rivela si sposta gratis |
| Aggressive Posture | rampage | 6 | 1 struggle per giocatore nel front / PP-1 |
| Hammer Tail | rotazione del mostro | 3 | rear e flank threatened, con i +1 nella versione M |

Nota: il testo di Spidery Grasp chiede di scartare una carta **offensive** (il
glifo senza colore), non una parry come diceva la trascrizione precedente.

## Stance

Resistant e Shield sulle Stance I e II; Stance III solo Shield. Le Stance II (e la
III del livello 3) danno 1 acceleration quando vengono rivelate. Lati esposti letti
con `tools/check_exposure.py` e controllati a occhio: di solito flank e rear, solo i
flank nelle Stance II dal livello 1 e nella Stance III del livello 3.

| liv | St.I | St.II | St.III |
|---|---|---|---|
| 0 | 2 / prog 6 / dmg 1 / shield 1 | 3 / prog 3 / dmg 1 / shield 1 | 4 / dmg 2 / shield 2 |
| 1 | 6 / 6 / 1 / 1 | 7 / 3 / 1 / 1 | 8 / 2 / 2 |
| 2 | 10 / 6 / 2 / 2 | 14 / 3 / 3 / 2 | 18 / 4 / 3 |
| 3 | 16 / 6 / 3 / 3 | 18 / 3 / 4 / 3 | 22 / 5 / 4 |

Al livello 3 la Stance I toglie dal gioco una carta attrition di valore 0 a inizio
round 1.

## Peril e objective

- **Wailing Roar** (Stance I, permanente): quando il mazzo attrition si esaurisce,
  1 struggle per giocatore; al livello 3 anche *unstoppable* fino a fine round.
- **Unscratchable** (Stance III): con almeno 1 struggle per giocatore le weapon sono
  blank; al livello 3 lo shield sale anche a 6.
- **Slash to the Throat** (objective, Stance II, permanente): quando si rivela una
  behavior con la reazione del front, il giocatore attivo può scartare un **attack**
  per annullarla (e infliggere vulnerable, ai livelli 0-2).

## Expedition

Pezzi dal Regolamento: Expedition 1 plateau, 2 rock, baethanis; Expedition 2
plateau, 2 rock, 2 fog. Caselle lette dal diagramma del Regolamento (p.78).
