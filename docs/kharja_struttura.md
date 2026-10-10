# Kharja — struttura rilevata

Ricavata leggendo le immagini estratte, non l'ordine del file di salvataggio
(per Vyraxen quell'ordine si era gia' rivelato sbagliato sui livelli 2 e 3).

Estrazione: `python3 tools/extract_monster.py Kharja`
→ 104 immagini in `art/monsters/kharja/`, provini in `art/_provini/`.

Dati: `data/kharja.json`, registrato in `Db.monsters`. Kharja e' giocabile:
`SmokeTest.tscn` gira 60 partite anche contro di lei, `RulesTest.tscn` ha due
sezioni dedicate (mazzi e stance, poi Keep Your Distance e le facce B).

## Differenze rispetto a Vyraxen

1. **Un'immagine per carta**, non fogli sprite: `NumWidth = NumHeight = 1`.
   Il calcolo dello slot (`CardID % 100`) qui ritaglia fuori dall'immagine e
   produce file neri, senza errori. `extract_monster.py` lo gestisce.
2. **Nessun nickname** su nessuna carta: il ruolo va letto dall'immagine.
3. **CardID che si ripetono** fra carte diverse della stessa bag (le due carte
   Stance I condividono il 14172): i file vanno nominati per posizione, non per
   id. Stesso inciampo gia' visto sulle carte potenziamento.
4. **10 behavior in 4 versioni**, invece del serbatoio unico da 18 di Vyraxen.
   I quattro mazzi da 10 hanno gli stessi 10 nomi, ma **le carte distinte sono
   20, non 40**: la stessa versione ricompare nei mazzi dei livelli coperti
   dalla finestra di aggression. Verificato sugli hash delle immagini estratte,
   non a occhio: i quattro `Flaming Tails Ψ`, per dire, sono lo stesso file.

## Contenuto letto

### Carte sciolte (5)
- **Keep Your Distance** (`sciolta_0`) — objective. Permanente, max 3 segnalini.
  L'icona verde in testa al testo e' il simbolo **dodge**: non e' un'attivazione
  libera, si offre *dopo che giochi un dodge*. Spendendone uno chiudi la action
  phase e previeni il danno da attrition.
- **Stance I** × 4 livelli di aggression: `sciolta_2` = liv.0, `sciolta_1` =
  liv.1, `sciolta_3` = liv.2, `sciolta_4` = liv.3 (letto dall'icona d'angolo).

Ogni carta sciolta e' stampata fronte-retro e porta le **Stance II e III come
*States*** del mod, non come carte separate: `sciolta_N_stato2.jpg` e
`sciolta_N_stato3.jpg`. Sul retro (`sciolta_N_retro.jpg`) c'e' la variante ad
aggression alta.

### Le 12 stance (4 livelli × 3)
`toughness_per_player` = numero rosso, `progression` = numero piccolo sopra
"STANCE ...", `damage` = artigli in basso a destra.

| liv | St.I | St.II | St.III |
|-----|------|-------|--------|
| 0 | 2 / prog 6 / dmg 1 | 3 / prog 2 / dmg 1 | 5 / dmg 1 |
| 1 | 5 / prog 6 / dmg 1 | 7 / prog 2 / dmg 1 | 12 / dmg 1 |
| 2 | 10 / prog 7 / dmg 2 | 16 / prog 2 / dmg 2 | 20 / dmg 3 |
| 3 | 15 / prog 7 / dmg 3 | 25 / prog 2 / dmg 3 | 30 / dmg 5 |

Testi: St.I «All'inizio del round 1, ogni giocatore esaurisce una pozione.»
St.II piazza terreno fuoco nei settori danneggiati (dal liv.2 anche segnalini
su Kharja; al liv.3 due segnalini e burning). St.III porta il segnalino round
a 8 e, se e' gia' a 8+, Kharja guadagna struggle (al liv.3 unleashes).

**Attenzione a `sciolta_2`** (livello 0): i suoi due *States* sono invertiti
rispetto agli altri tre, `stato2` e' la Stance III e `stato3` la Stance II. E'
il mod a essere fatto cosi'; `data/kharja.json` punta ai file giusti.

### I 3 peril (deck 5), fronte e retro
- **I — In the Clutches of Fire** (`g5_02`): a inizio round scarta la prima
  behavior; se ha *claw*, chi e' nel settore front subisce danno.
- **II — Burning Skin** (`g5_01`): immune a blind. Ogni ferita di Kharja piazza
  un segnalino. Il danno da attrition cresce di 1 per segnalino.
- **III — Fireburst** (`g5_00`): immune a blind. Come sopra, e a fine round se
  la salute di Kharja e' 1 tutti subiscono danno +X (X = segnalini).

I retri (`g5_NN_retro.jpg`) sono le **varianti ad aggression alta**: portano la
`V` nell'angolo dove il fronte ha `Ψ`, quindi entrano al livello 3 — la stessa
convenzione di Vyraxen. Cambiano cosi': Burning Skin piazza **2** segnalini per
ferita invece di uno; Fireburst, oltre al danno, piazza fuoco **in ogni settore**;
In the Clutches of Fire ha lo stesso identico testo. Anche Keep Your Distance ha
la sua faccia B: in piu' **Kharja guadagna 1 struggle**. In `kharja.json` sono
le peril `401010/401020/401030` e l'objective `402010`, usate dal livello 3.

### Le 20 versioni di behavior
Dieci nomi — Fiery Mane, Ember Dash, Terrifying Gaze, Flaming Tails, Catlike
Spring, Rising Temperature, Hellfire, Onslaught, Spirit of the Woltyar, Fire
Paw — in due versioni ciascuno. Gli id in `kharja.json` (43001-43020) sono
nostri: quelli TTS cambiano da mazzo a mazzo per la stessa carta.

| nome | versione bassa | versione alta | refresh | reazione |
|------|----------------|---------------|---------|----------|
| Fiery Mane | ⊕ (liv. 0-1) | M (liv. 2-3) | 1 | attack_played |
| Ember Dash | ≢ (liv. 0) | 8 (liv. 1-3) | 5 | turn_start_front |
| Terrifying Gaze | ⊕ (liv. 0-1) | M (liv. 2-3) | 4 | turn_start_front |
| Flaming Tails | Ψ (liv. 0-2) | V (liv. 3) | 4 | turn_start_front |
| Catlike Spring | ≢ (liv. 0) | 8 (liv. 1-3) | 2 | turn_start_rear |
| Rising Temperature | ⊕ (liv. 0-1) | M (liv. 2-3) | 5 | rampage |
| Hellfire | Ψ (liv. 0-2) | V (liv. 3) | 4 | due offensive / offensive |
| Onslaught | Ψ (liv. 0-2) | V (liv. 3) | 3 | end_of_round |
| Spirit of the Woltyar | Ψ (liv. 0-2) | V (liv. 3) | 6 | end_of_round |
| Fire Paw | ≢ (liv. 0) | 8 (liv. 1-3) | 6 / 1 | player_moved |

Fire Paw e' l'unica con refresh diverso fra le due versioni (6 → 1) e Hellfire
l'unica che cambia reazione (due carte offensive → una sola).

Portano *claw*: Catlike Spring (entrambe), Onslaught (entrambe), Rising
Temperature M, Hellfire V.

## Icone aggression — quale mazzo e' quale livello

Le 40 behavior portano 6 glifi distinti. Ritagliati e letti a contrasto pieno
(`art/_provini/kharja_icone_aggression.jpg`). Il raggruppamento automatico per
somiglianza e' stato **scartato**: si faceva guidare dal rumore di scansione e
dava cardinalita' assurde (14 e 13 su 40). Lettura a occhio su ritagli stretti.

Ordine dei glifi: `≢ ⊕ Ψ 8 M V`

| mazzo | icone presenti | livello |
|-------|----------------|---------|
| 1 | ≢ ⊕ Ψ   | 0 |
| 2 | ⊕ Ψ 8   | 1 |
| 3 | Ψ 8 M   | 2 |
| 4 | 8 M V   | 3 |

La finestra scorrevole del regolamento (p.60) combacia con tutti e quattro.

## Due carte sbagliate nel salvataggio TTS

Il mod stesso assegna a due carte l'immagine di un'altra: nel mazzo 3 la carta
in posizione 1 (`CardID` 14597) punta all'arte di Fiery Mane M, gia' usata dalla
posizione 0; nel mazzo 4 la posizione 2 (`CardID` 14599) punta a Spirit of the
Woltyar Ψ, che nel mazzo 4 c'e' gia' come versione V. Non e' un errore
dell'estrazione: sono i `FaceURL` del salvataggio a essere identici.

Il risultato e' che al mazzo 3 manca Spirit of the Woltyar e al mazzo 4 manca
Fiery Mane. La ricostruzione, in `kharja.json`:

- mazzo 3 → **Spirit of the Woltyar Ψ** (l'unica versione ammessa dalla finestra
  del livello 2: la V arriva solo al 3);
- mazzo 4 → **Fiery Mane M** (la piu' alta che esista per quel nome).

Due segnali indipendenti la sostengono: ogni mazzo torna a dieci nomi diversi, e
sparisce l'anomalia notata prima — la carta del mazzo 4 con l'icona Ψ dove la
finestra prevedeva 8, M o V era proprio quella. Con la ricostruzione il mazzo 4
resta `8 M V`, senza eccezioni.

Se un giorno saltassero fuori una Fiery Mane V o una Spirit M, basta aggiungerle
a `behaviors` e cambiare l'id nel `behavior_deck` del livello.

## Reazioni sui retri

Ricavate confrontando i retri di Kharja con quelli di Vyraxen, di cui la
reazione e' gia' nota (`art/_provini/reazioni.jpg`), e confermate sul glossario
del regolamento italiano (p.93, "Icone di reazione behavior").

| icona | reazione | carte |
|-------|----------|-------|
| fauci | `turn_start_front` | Ember Dash, Terrifying Gaze, Flaming Tails |
| spira | `turn_start_rear` | Catlike Spring |
| drago | `rampage` | Rising Temperature |
| clessidra | `end_of_round` | Onslaught, Spirit of the Woltyar |
| rombo arancio | `attack_played` | Fiery Mane |
| due glifi offensive | `two_offensive_played` | Hellfire Ψ |
| un glifo offensive | `offensive_played` | Hellfire V |
| figura in corsa | `player_moved` | Fire Paw |

Le ultime tre non c'erano nel vocabolario del motore e sono state aggiunte.
Il glifo bianco senza rombo colorato e' il simbolo generico di "carta
offensive": il rombo colorato indica il tipo preciso (rosso attack, blu
maneuver, giallo parry, verde dodge — verificato sulle carte azione di Dareon).

## Il modello 3D

Kharja **ha** un `Custom_Model` nel mod, dentro il *Book of Monsters*: mesh e
texture sono nella cache locale del mod, quindi non serve generare niente. Basta
la riga in `SCENE_OBJECTS` di `extract_assets.py`, che li copia in
`models/kharja.obj` e `art/models/kharja_diffuse.jpg`.

Board3D sceglie da solo: se il mostro ha una miniatura GLB usa quella, altrimenti
il mesh; se manca anche quello, una capsula. Il flag `"triplanar"` nei dati del
mostro decide come applicare la texture — serve a Vyraxen, non a Kharja.

## Cosa e' stato aggiunto al motore

Reazioni: `offensive_played`, `two_offensive_played`, `player_moved`.
Trigger delle peril: `round_start`, `monster_wound`, `attrition_damage`.
Nuovi op: `suffer`, `suffer_unless_reveal`, `force_discard`,
`discard_all_of_type`, `no_assist`, `skip_movement`, `skip_turn`,
`movement_payment_type`, `place_sector_damage`, `clear_sector_damage`,
`exhaust_potion`, `exhaust_potion_or_discard`, `discard_top_behavior`,
`advance_round_marker`, `unleash`, `end_action_phase` (che non chiude la fase a
meta' risoluzione: segna e lascia finire la carta). `add_counter` accetta ora un
tetto `max`, e `place_terrain` conosce `each_damaged_sector` e `each_sector`.
Bersagli: `players_in_front_and_flank`, `threatened_players`,
`players_in_damaged_sectors`, `aggro`. Condizioni: `stance_1`, `stance_2`,
`stance_3`, `stance_2_or_3`, `monster_health_1`.
`damage_bonus` accetta ora anche `"monster_counters"`, cioe' il DMG+X di quasi
tutte le carte di Kharja.

I segnalini damage sui settori (`sector_damage`) sono nuovi: servono alle stance
II, che piazzano fuoco "in ogni settore danneggiato", e li piazza Rising
Temperature.

## Scelte dichiarate

- **«Skips their turn»** e' stato inteso come turno intero saltato: niente
  movimento, niente azione, niente attrition. La carta non lo dettaglia.
- **«Reveal»** non toglie nulla dalla mano, quindi il motore non chiede niente:
  guarda la mano e, se la carta c'e', l'effetto non si applica.
- L'**Enhancement di Onslaught** (il giocatore aggro deve rivelare 2 parry)
  passa dai `flags` del boost, come gia' facevano le carte di Vyraxen.

## Da fare

- La plancia mostro non e' stata estratta: nel pannello c'e' la carta stance.
  La miniatura 3D e' un GLB Meshy, importato con `tools/import_miniatures.py`.
- Il giocatore automatico del collaudo **declina sempre** Keep Your Distance: le
  opzioni sono ordinate con "continua il turno" per prima e l'euristica prende la
  prima. Le partite headless quindi non lo esercitano — lo copre `RulesTest`.
- Nessuna faccia B di Kharja porta *Infuriate*, che su Vyraxen compare invece
  sulle peril II e III ad aggression alta.

## I lati esposti erano sbagliati

Sette carte stance su dodici avevano il campo `exposed` sbagliato: le Stance II e
III di ogni livello risultavano **scambiate fra loro** ai livelli 0, 1 e 2 (la II
è flank+rear, la III solo flank), e la Stance I del livello 2 era front+flank e
non flank+rear.

Il diagramma di esposizione ha il **front in basso**, segnato dal trattino sotto
il cerchio (Regolamento p.20). Le Stance II e III non sono carte a sé ma *States*
TTS della Stance I, ed è lì che si sono scambiate: sono due immagini che si
somigliano molto, e lette di fila una vale l'altra.

Corretto rileggendo le immagini con `tools/check_exposure.py --sheet`, che
ritaglia i dodici diagrammi in una tavola sola: appaiati, gli scambi si vedono
subito. I valori sono ora fissati in `RulesTest`.
