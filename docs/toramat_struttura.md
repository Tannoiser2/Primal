# Toramat — struttura rilevata

Quarto mostro, e il piu' irregolare: e' l'unico con carte che stanno **fuori dal
mazzo**, con **carte attrition proprie** e con un secondo tracciato oltre
all'hardening.

Estrazione: `python3 tools/extract_monster.py Toramat`
→ 100 immagini in `art/monsters/toramat/`. Dati: `data/toramat.json`.

## Cosa c'e' nella bag

Sei mazzi, non quattro: **4 mazzi behavior da 9**, un mazzo da 2 (le peril,
fronte e retro) e un mazzo da 2 copie della stessa **carta attrition speciale**.
Piu' sette carte sciolte: quattro Stance I (con Stance II e III come *States*),
l'objective *Crash on the Rocks* e le due behavior speciali *Out of Control* e
*Crashing Charge*.

Le 36 carte dei mazzi sono **18 distinte**: nove nomi in due versioni.

## L'ordine dei mazzi non e' quello del file

Il salvataggio elenca i mazzi come 1, 3, 4, 6 e quell'ordine non e' il livello di
aggression. L'ho ricavato dalle **sovrapposizioni**, come fa gia'
`extract_assets.py` per Vyraxen: con la finestra scorrevole del regolamento due
livelli adiacenti condividono 6 carte, a distanza 2 ne condividono 3, a distanza
3 nessuna. Le sovrapposizioni misurate danno una sola catena possibile,
**g3 – g1 – g4 – g6**, e il verso lo decidono i testi, che si induriscono:

| | livello 0 (g3) | livello 3 (g6) |
|---|---|---|
| Ancient Fury | guadagna struggle | ... e il giocatore attivo diventa threatened |
| Smash | *se* c'e' un rock lo rimuove, e si **rivela** un dodge | rimuove il rock e si **scarta** un dodge |
| Stone Wall | il danno e' nel boost | il danno e' nell'abilita' base |

## Le 18 behavior

| nome | refresh | reazione | cambia fra le versioni |
|------|---------|----------|------------------------|
| Pawing the Ground | 7 | turn_start_front | solo l'icona |
| Tail Strike | 1 | turn_start_rear / **any_turn_start_rear** | dal giocatore attivo a tutto il rear |
| Raging Havoc | 3 | rampage | da 1 dodge a 2 |
| Stone Wall | 5 | turn_start_flank | il danno passa dal boost alla base |
| Tail Swipe | 4 | **monster_turned** | da rivelare a scartare, piu' un boost che semina dust |
| Smash | 4 | **monster_turned** | come sopra |
| Hardening | 9 | end_of_round | dal solo giocatore aggro a tutti |
| Skull Bash | 8 | turn_start_front | colpisce tutto il settore front e toglie piu' acceleration |
| Ancient Fury | 6 | **aggro_played** | aggiunge threatened |

Due reazioni sono nuove: la **rotazione del mostro** (due frecce in cerchio) e la
**carta aggro giocata** — quest'ultima e' lo stesso glifo a corna che le carte
azione portano nell'angolo, verificato confrontandolo con l'intestazione di
*Engage* di Dareon.

## Le due behavior fuori dal mazzo

Il setup dello scenario dice di lasciare *Crashing Charge* e *Out of Control*
fuori dal mazzo: sono fuori dal gioco finche' una carta non le chiama. Entrambe
hanno la reazione **"appena entra in gioco"**, si risolvono prima di ogni altra e
si scartano a vicenda ("scarta ogni altra behavior in gioco con la reazione
aggro").

- **Out of Control** la mette in cima al mazzo la **Stance III**.
- **Crashing Charge** la mette in cima l'objective, quando si completa. E' anche
  l'unico modo che i cacciatori hanno di far crollare l'hardening: se il
  giocatore attivo rimuove un rock dal settore front, Toramat perde tutta
  l'acceleration, l'hardening torna a 1 e incassa una ferita.

## Le stance

| liv | St.I | St.II | St.III |
|-----|------|-------|--------|
| 0 | 2 / prog 7 / dmg 1 | 3 / prog 4 / dmg 1 | 3 / dmg 2 |
| 1 | 4 / prog 7 / dmg 1 | 6 / prog 4 / dmg 2 | 9 / dmg 2 |
| 2 | 10 / prog 7 / dmg 2 | 16 / prog 4 / dmg 3 | 20 / dmg 4 |
| 3 | 18 / prog 7 / dmg 3 | 25 / prog 4 / dmg 4 | 30 / dmg 6 |

Lati esposti (letti campionando i pixel, come per Dygorax): Stance I sempre
flank+rear; le altre flank+rear tranne al livello 0, dove la Stance II e la III
lasciano esposti solo i flank, e al livello 1-3 dove la Stance III fa lo stesso.
Il fronte non e' mai esposto: Toramat va colpita di lato o da dietro.

## Peril, objective, attrition

**Solo due peril**, non tre: *Granite Skin* (Stance I) e *Rising Fury* (Stance
II). La Stance III non ne ha — nel mazzo ci sono due carte e nessuna porta il
numero III. I retri sono le varianti di livello 3: Granite Skin passa da «se ha
1 struggle per giocatore» a «se ha 1 struggle», cioe' scatta quasi sempre.

**Crash on the Rocks**: a inizio turno puoi rivelare 2 carte aggro per mettere un
segnalino; a tanti segnalini quanti i giocatori l'objective esce dal gioco e
arriva Crashing Charge.

**Carte attrition speciali** (Regolamento p.98): il setup toglie dal mazzo
attrition due carte di valore 1 e mette le due di Toramat, che chiedono un
**dodge specifico** invece di una difensiva qualsiasi. Il motore ora costruisce
il mazzo attrition per partita, non piu' dal solo `common.json`.

## Acceleration

Il secondo tracciato: ogni segnalino da' a Toramat **1 struggle in piu' durante
l'upkeep**, e il tetto e' 1 per giocatore. Lo alza la Stance II ai livelli alti e
la peril *Rising Fury* a ogni escalation (cioe' ogni volta che il mazzo behavior
finisce e viene rimescolato); lo abbassano *Skull Bash*, se riveli dei dodge, e
Crashing Charge.

## Cosa e' stato aggiunto al motore

Stato: `acceleration`, `attrition_cards` (il mazzo attrition della partita).
Reazioni: `aggro_played`, `monster_turned`, `on_enter_play`.
Trigger peril: `escalation`. Trigger objective: `turn_start` con richiesta di
rivelare. Condizioni: `struggle_per_player`, `struggle_at_least_1`.
Op: `acceleration`, `place_behavior_on_top`, `discard_behaviors_with_reaction`,
`remove_terrain`, `remove_terrain_or_suffer`; `hardening` accetta ora `set` e
`unless_discard`; `place_terrain` accetta `count` e i settori `remembered` /
`adjacent_to_remembered`; `suffer` accetta un danno fisso; `suffer_unless_reveal`
esegue effetti per ogni giocatore che rivela; `monster_turn_to` conosce
`most_aggro_in_hand`.
Bersagli: `target`, `players_in_rear_or_flank`, `players_in_remembered`.

## Le due letture incerte

1. **L'icona di Tail Strike.** «The active player discards a ⧨ from their hand»:
   il glifo bianco non e' nessuno dei quattro colori delle carte azione ne' il
   simbolo generico di offensive/defensive. La forma — un corpo a triangolo
   rovesciato con una fascia e un collo — legge come una **fiala**, quindi e'
   stata trascritta come pozione. E' l'unico punto di questo mostro dove ho
   scelto fra due letture invece di verificarne una.
2. **Il plateau che non c'e'.** La Stance III dice «rimuovi il terreno plateau
   dalla plancia», ma nei due setup Expedition di Toramat il plateau **non e'
   previsto**: ci sono rock, sand, wildmaw e baethanis. Letto dai diagrammi del
   regolamento (p.69-70), non dedotto. In Expedition quella riga quindi non
   trova niente da rimuovere e la carta ripiega sul settore front; il plateau
   arrivera' dagli scenari di campagna.

## Da fare

- Le regole generali dei terreni (Regolamento, sezione Terreni): i pezzi ora
  stanno sul tavolo e le carte che li nominano funzionano, ma il terreno di per
  se' non ha ancora effetti.
- La UI non mostra i tracciati (hardening, acceleration) ne' il dust: stanno nel
  registro, non sul tavolo. La miniatura 3D e' un GLB Meshy.

## I lati esposti erano sbagliati

Tre carte stance su dodici: le Stance II e III del livello 0 sono flank+rear e
non solo flank, e la Stance II del livello 3 è solo flank e non flank+rear.
Stesso errore di Kharja e stesso rimedio — `tools/check_exposure.py --sheet` —
descritto in `docs/kharja_struttura.md`.

## Il modello guardava dalla parte sbagliata

Ogni miniatura GLB e' scolpita rivolta da una parte diversa, e l'angolo di
correzione sta nei dati (`art.model_yaw`). Per **tre mostri su quattro** era
sbagliato: Toramat e Dygorax avevano 0 invece di 180, Kharja 270 invece di 90.
Il motore girava il mostro nel settore giusto e il registro lo scriveva giusto,
ma il modello guardava altrove — cosi' sembrava che il mostro si voltasse verso
un settore vuoto.

Non se n'era accorto nessuno perche' Vyraxen, l'unico mostro per settimane, era
l'unico con il valore corretto.

Si controlla con `--shot-facing --facing=N --monster=<id>`: gira il mostro verso
quel settore e basta guardare dove punta la testa (0 in alto, 1 a destra, 2 in
basso, 3 a sinistra).
