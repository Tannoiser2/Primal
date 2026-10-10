# Dygorax — struttura rilevata

Stessa procedura di Kharja (vedi `kharja_struttura.md`): si legge dalle immagini
estratte, non dall'ordine del salvataggio TTS.

Estrazione: `python3 tools/extract_monster.py Dygorax`
→ 96 immagini in `art/monsters/dygorax/`, provini in `art/_provini/`.
Dati: `data/dygorax.json`, registrato in `Db.monsters`.

## Cosa c'e' nella bag

Quattro mazzi behavior da 9, un mazzo da 3 (le peril, fronte e retro) e cinque
carte sciolte: l'objective *Hit the Tail* e le quattro Stance I, ognuna con le
Stance II e III come *States* e la variante ad aggression alta sul retro.

Le 36 carte behavior sono **18 carte distinte**: nove nomi in due versioni,
verificato sugli hash delle immagini. Qui il mod e' pulito — nessuno slot che
punta all'immagine sbagliata, al contrario di Kharja.

## Le 18 behavior

| nome | versione bassa | versione alta | refresh | reazione |
|------|----------------|---------------|---------|----------|
| Voice of Destruction | ⊕ (liv. 0-1) | M (liv. 2-3) | 4 | attack_played |
| Tail Smash | Ψ (liv. 0-2) | V (liv. 3) | 1 | turn_start_rear / **any_turn_start_rear** |
| Wing Attack | Ψ (liv. 0-2) | V (liv. 3) | 4 | turn_start_flank / **any_turn_start_flank** |
| Dragon Fire | ≢ (liv. 0) | 8 (liv. 1-3) | 4 | rampage |
| Armoring | ≢ (liv. 0) | 8 (liv. 1-3) | 4 | attack_played / **offensive_played** |
| Burning Eye | ⊕ (liv. 0-1) | M (liv. 2-3) | 3 | turn_start_front |
| Dragon's Roar | Ψ (liv. 0-2) | V (liv. 3) | 5 | two_offensive_played |
| Dust Attack | ≢ (liv. 0) | 8 (liv. 1-3) | 6 | end_of_round |
| Pressure | ⊕ (liv. 0-1) | M (liv. 2-3) | 2 | parry_played / **defensive_played** |

Tre nomi cambiano reazione fra le due versioni (in grassetto la versione alta).
*Armoring* e' l'unica carta senza abilita' base: ha solo il testo d'ambientazione
e un boost da 2 struggle.

Le icone di reazione nuove rispetto a Kharja sono le varianti con i chevron
`« »`: la coda da sola vuol dire «quando un giocatore inizia il turno nel settore
rear», la coda fra chevron «all'inizio del turno di un giocatore, se c'e' almeno
un giocatore nel settore rear» (Glossario p.93). Idem per l'artiglio e i flank.

## Le 12 stance

| liv | St.I | St.II | St.III |
|-----|------|-------|--------|
| 0 | 2 / prog 8 / dmg 1 | 3 / prog 4 / dmg 1 | 4 / dmg 2 |
| 1 | 5 / prog 8 / dmg 1 | 7 / prog 4 / dmg 2 | 10 / dmg 3 |
| 2 | 9 / prog 8 / dmg 2 | 14 / prog 4 / dmg 3 | 18 / dmg 4 |
| 3 | 15 / prog 8 / dmg 3 | 20 / prog 4 / dmg 5 | 25 / dmg 6 |

Stance I e II portano **Resistant**. Stance I e' esposta su tutti i lati, Stance
II e III solo su flank e rear.

**I lati esposti sono stati letti campionando i pixel**, non a occhio: il
diagramma e' un cerchio diviso in quattro con un piolo in basso, e il piolo e' il
lato front. La lettura e' stata calibrata sulle stance di Vyraxen, di cui i lati
esposti erano gia' noti: la calibrazione torna esatta su tutti e tre i casi
(front+rear, flank+rear, tutti).

## Le peril e l'objective

| | fronte (liv. 0-2) | retro (liv. 3) |
|---|---|---|
| I *Hardening* | il danno da attrition alza l'hardening di 1 | ... e se e' hardened, Dygorax guadagna 1 struggle |
| II *Unbreakable* | a inizio round hardening +1 | ... e se e' hardened, DMG+1 per il round |
| III *Dragon Scales* | mentre e' hardened resta esposto solo il rear | ... piu' *Infuriate 2/6/9* |

*Hit the Tail* (objective, Stance I) qui non e' quello di Vyraxen: l'icona in
testa al testo e' il rombo rosso dell'**attack**, quindi si attiva giocando un
attacco. «Se sei nel settore rear, riduci l'hardening di 1»; la faccia B aggiunge
1 struggle a Dygorax.

## Hardening e dust: le due regole nuove

**Tracciato hardening** (Regolamento p.95, vale anche per Toramat). Sale e scende
per effetto delle carte; a 3 il mostro e' **hardened** (Glossario p.109) e allora:
niente stun, niente confuse, niente vulnerable, e il damage in eccesso non si
riporta mai — sparisce a ogni ferita.

**Segnalini dust** (p.95). Le carte li piazzano nei settori, massimo 2 per
settore. All'inizio della fase Attrition ogni dust nel proprio settore mette un
*disrupt* su una carta difensiva della sequenza, che per quel check non conta.
A fine round il dust si toglie tutto.

Da qui i due tratti del mostro: le behavior seminano dust per svuotare le
difese sull'attrition, e l'hardening lo rende sempre piu' difficile da ferire —
mentre l'objective, colpendo da dietro, lo riporta giu'.

## Cosa e' stato aggiunto al motore

Stato: `hardening`, `hardened()`, `dust` per settore.
Reazioni: `defensive_played`, `any_turn_start_rear`, `any_turn_start_flank`.
Op: `hardening`, `place_dust`, `suffer_unless_next_card`,
`suffer_halved_on_discard`; `suffer_unless_discard` accetta ora anche
`discard_kind` (una categoria invece di un tipo preciso).
Bersagli: `players_in_dust_sectors`, `players_in_flank`, `players_in_aggro_sector`;
`place_terrain` conosce `aggro_sector`. Condizione: `monster_hardened`.
Stance: il campo `resistant`.

`Pressure` chiede una carta che deve ancora essere giocata: il motore segna
l'obbligo sul giocatore (`pending_next_card`) e lo verifica alla carta dopo, o
alla chiusura della fase azione se quella carta non arriva.

## Da fare

- La plancia mostro non e' stata estratta: nel pannello c'e' la carta stance.
  La miniatura 3D e' un GLB Meshy, importato con `tools/import_miniatures.py`.
- La UI non mostra ancora ne' il tracciato hardening ne' i segnalini dust: sono
  nel registro di gioco, non sul tavolo.
- Toramat usa gli stessi due sistemi (hardening e dust) piu' le carte attrition
  speciali: dopo questo lavoro gli manca solo la trascrizione.

## La plancia

Estratta il 5 agosto 2026 insieme a quelle di Kharja e Toramat. Non era mai
uscita perche' `extract_monster.py` guardava mazzi e carte sciolte ma **non le
tessere**, e la plancia e' un `Custom_Tile`. Nella borsa di un mostro le tessere
sono piu' d'una — ci sono anche i segnalini — quindi si sceglie quella giusta
dalla forma: la piu' grande e coricata.

Le quattro plance hanno lo stesso stampo, quindi le posizioni dei tracciati sono
frazioni misurate una volta sola e valide per tutte: la traccia salute parte a
0.418 con passo 0.0588, la seconda traccia (hardening qui, acceleration su
Toramat) parte a 0.831. Il segnalino nel pannello sta su **ancore**, non su
pixel, cosi' resta al suo posto quando la finestra cambia misura.
