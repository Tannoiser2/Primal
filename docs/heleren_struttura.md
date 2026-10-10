# Heleren — the Gunbow

Sesto e ultimo cacciatore, **completo**: 24 carte azione, 28 weapon, 6 mastery,
20 potenziamenti, miniatura. Le carte sono trascritte dalle immagini in
`art/heleren/` e questo documento e' la lettura da cui vengono.

## Il vocabolario

Dalla sua Player Reference (`art/heleren/heleren_aid_back.jpg`). Tre parole su
quattro sono sue e non esistono per nessun altro:

- **Bullet**: una risorsa personale, contata su un **tracciato sulla sua plancia
  che arriva a 3** (le caselle sono 1, 2, 3). Non e' stamina: si spende solo dove
  la carta lo dice.
- **Ignite [Abilita']**: l'abilita' scatta **quando spendi bullet**, di qualunque
  quantita', e scatta **una volta sola** anche se ne spendi piu' d'uno.
- **Reload X**: recuperi X bullet.
- **Defense token**: segnalino che conta come una carta difensiva nella sequenza
  per il **prossimo** check di attrition, poi si scarta. Non e' di Heleren: sta
  nel Glossario a p.108 e serve anche a *Spinning* di Karah. Il disrupt del dust
  lo cancella, e non conta per i requisiti di colore delle carte attrition
  speciali.

## Le 24 carte

Sei per colore, come chiede la Gunbow. Gli id sono quelli TTS e non collidono con
gli altri cacciatori (verificato: nessuna sovrapposizione con gli id azione gia'
in uso).

| id | nome | tipo | costo | stamina | aggro | testo |
|---|---|---|---|---|---|---|
| 213400 | Bombardment | maneuver | 1 | 1 | | Puoi spendere un bullet: se lo fai, confondi il mostro **oppure** questo maneuver rimuove 2 struggle in piu'. |
| 213600 | Cover Fire | attack | 0 | 1 | | Assist. Quando un altro giocatore subirebbe danno da attrition, puoi scartarla dalla mano per prevenirlo. |
| 213800 | Exertion | parry | 0 | 1 | | Assist. Quando la scarti per generare stamina per un **attack**, ne genera 2. |
| 214000 | Haul of Bullets | dodge | 1 | 1 | | Pesca X, dove X e' il livello del tuo tracciato bullet. |
| 214600 | Prompt Reflexes | parry | 1 | 1 | | Pesca 1. |
| 214800 | Ranged | dodge | 0 | 1 | | Assist. Mentre e' in cima ai tuoi scarti conta come un **dodge** nella sequenza per il check di attrition. |
| 214900 | Rapid Ignition | attack | 0 | 1 | | Puoi spendere un bullet per cercare un **attack** negli scarti e metterlo in cima al mazzo. |
| 215000 | Ready to Shine! | parry | 1 | 1 | | Scarta quante carte vuoi dalla mano, poi pesca fino ad averne 3. |
| 215100 | Recharging | maneuver | 1 | 1 | | Assist. Reload 2. |
| 215200 | Repositioning | maneuver | 1 | 1 | | Con la mastery focused: puoi rimescolare tutti gli **attack** dagli scarti nel mazzo. |
| 215300 | Strafing | maneuver | 0 | 1 | | Assist. Puoi spendere un bullet per infliggere 3 danni; se lo fai, puoi muoverti subito senza pagare stamina. |
| 215400 | Strategic Support | dodge | 0 | 1 | | Puoi scegliere un giocatore che scarti un **maneuver** dalla mano. Se lo fa, fai Reload 2. |
| 215500 | Swift Deflection | parry | 0 | 1 | | Quando la scarti dalla mano, pesca 1. |
| 227900 | Barrage of Bullets | attack | 1 | 1 | sì | Spendi quanti bullet vuoi: questo attacco infligge 2 danni per livello weapon in piu' per ognuno. |
| 228000 | Pressing Shot | maneuver | 1 | 1 | | Pesca 1. Se il tracciato bullet e' a 1 o piu', pesca 2. |
| 228100 | Quick Reload | parry | 1 | 2 | | Reload 1. |
| 228200 | Tactical Reload | dodge | 2 | 2 | | Reload 3. |
| 228300 | Diversion | parry | 1 | 1 | | Scegli un altro giocatore che pesca 1. Puoi spendere un bullet: se lo fai, ne pesca 2. |
| 228400 | Prompt Jump | dodge | 0 | 1 | | Quando subiresti danno, puoi scartarla dalla mano per prevenirlo. |
| 228500 | Negation | attack | 0 | 2 | | Quando viene rivelata una carta behavior, puoi scartarla dalla mano e spendere un bullet per annullare gli effetti di quella carta. |
| 228600 | Gunfire | attack | 0 | 1 | sì | Puoi spendere un bullet: questo attacco infligge 3 danni per livello weapon in piu'. |
| 228700 | Cannonball | attack | 4 | 2 | sì | Puoi spendere 3 bullet: se lo fai, stordisci il mostro e questo attacco infligge 4 danni per livello weapon in piu'. Un altro giocatore puo' generare stamina per aiutarti a pagarla. |
| 228900 | Long Range | dodge | 1 | 1 | | Il prossimo **attack** che giochi in questo turno guadagna stealth. Mentre e' in cima ai tuoi scarti, previene il danno da attrition che subiresti. |
| 229000 | Not This Time! | maneuver | 0 | 1 | | Quando riveli una carta attrition, puoi **rivelarla** dalla mano e spendere un bullet per prendere un defense token (max 1 per turno). |

**Gunbow** (livello 1): danno **3**, composizione 6/6/6/6, «Ignite: infliggi 1 danno».
**Precision Reload** (mastery, focus 2): si focalizza facendo Reload; da
focalizzata, quando fai Reload cerchi un **attack** nel mazzo o negli scarti e lo
aggiungi alla mano (se hai cercato nel mazzo, lo rimescoli).

## Cosa e' stato aggiunto al motore

Tre pezzi, e nessuno dei tre e' solo suo:

1. **Bullet**: `PrimalPlayer.bullets` col tetto in `bullet_track`, gli op
   `reload`, `spend_bullets` (opzionale, e con `amount: "any"` a quantita'
   scelta per *Barrage of Bullets*), il conteggio `bullet_track` e le condizioni
   `has_bullets` / `no_bullets`. **Ignite** e' `_ignite()`, chiamato a ogni spesa
   riuscita: risolve `on_ignite` della weapon e le abilita' con
   `trigger: "ignite"` nella sequenza, **una volta sola** per spesa.
2. **Defense token**: `PrimalPlayer.defense_tokens`, contato in
   `defensive_in_sequence()` e scartato alla fine del check di attrition
   (Glossario p.108). Ha sbloccato *Spinning* di Karah.
3. **Stamina generata per tipo**: `Player.stamina_of(card, paying_for)` legge il
   campo `stamina_bonus`, che era gia' scritto sulle carte ma non lo leggeva
   nessuno. Ha sbloccato *Stamina Surge* di Ljonar e fatto funzionare davvero
   *Stamina Boost* di Thoreg.

E tre cose cablate su un id preciso sono diventate generali, perche' Heleren ha
carte con lo **stesso mestiere e id diverso**: `prevents_attrition_on_top`
(*Long Range*), `counts_as_defensive_on_top` (*Ranged* / *Ranged Position*) e
*Cover Fire*, che ora e' una `out_of_turn` dichiarata nei dati come tutte le
altre invece di una funzione che cercava la carta `178403`.

### Un arbitraggio

*Precision Reload* dice «quando fai reload»: il segnalino va sulla carta anche
se il tracciato era gia' pieno e non hai recuperato niente. L'istruzione c'e'
stata. Letta nell'altro modo, un tracciato pieno bloccherebbe di nascosto una
mastery che parla solo di reload.

## I 20 potenziamenti

Estratti aggiungendo `heleren` a `HUNTERS` in `tools/build_loadouts.py`, che ha
prodotto 28 weapon, 6 mastery e le immagini senza una sola ambiguita' di
abbinamento — a differenza di Karah e Dareon, che avevano avuto bisogno di
`MANUAL`. Nel database il suo nome e' scritto giusto (*Heleren*), un caso raro:
Dareon e' *Daeron* e Thoreg *Thoerg*.

Gli id globali usano l'offset **8.000.000** (3 Dareon, 4 Mirah, 6 Karah,
7 Thoreg e Ljonar).

Quattro restano senza effetto, e per quattro motivi diversi:

- *Fire Cascade* ha **Reclaim**, che non e' ancora nel motore (ce l'hanno anche
  tre carte di Karah).
- *Counter Measure* scatta se «hai evitato il danno da attrition», che il
  Glossario definisce a p.108 ma il motore non segnala.
- *Line of Fire* si rivela **all'inizio della fase movimento** con 7 o piu'
  carte in mano: manca quell'innesco.
- *Cycle of Bullets* fa reload quando la scarti per pagare **un attack**: lo
  scarto sa il tipo pagato solo dentro `_pay_stamina`, e l'innesco allo scarto
  vive fuori.
