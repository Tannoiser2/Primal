# Tarragua — trascrizione in corso

Quinto mostro. **Non e' ancora giocabile**: mancano i quattro mazzi behavior e
l'obiettivo. Stance e peril sono letti, e stanno qui perche' quel lavoro non
vada rifatto.

## Non ha sottosistemi suoi

Controllate tutte le sezioni delle regole speciali (p.95-98): Tarragua non
compare in nessuna. Niente charge, dust, swarm, rumble, debility. I **segnalini
Arkeum**, che sulla pagina Expedition sembrano suoi per come e' impaginata,
sono di **Hurom** — il Glossario lo scrive nel titolo della voce.

Usa due cose che il motore ha gia' o ha appena preso:

- **Acceleration**, come Toramat: ogni Stance II e III la aumenta di 1 quando
  viene rivelata.
- **Shield X** (Glossario p.110): la stance toglie X a *ogni* fonte di danno al
  mostro. Nessuno dei quattro mostri precedenti la usava, quindi e' stata
  aggiunta il 6 agosto 2026. Si applica **dopo** il raddoppio di vulnerable: e'
  l'armatura del mostro, non una proprieta' del colpo.

## Le dodici stance

Le quattro caselle di aggression sono stampate nell'angolo in alto a sinistra
come **cifre** (0, 1, 2, 3) dentro il simbolo aggression, non come il set di sei
icone che usa Vyraxen.

| liv | stance | toughness/giocatore | progression | damage | testo |
|---|---|---|---|---|---|
| 0 | I | 2 | 6 | 1 | Resistant. Shield 1. |
| 0 | II | 3 | 3 | 1 | Resistant. Shield 1. When revealed: +1 acceleration. |
| 0 | III | 4 | — | 2 | Shield 2. |
| 1 | I | 6 | 6 | 1 | Resistant. Shield 1. |
| 1 | II | 7 | 3 | 1 | Resistant. Shield 1. When revealed: +1 acceleration. |
| 1 | III | 8 | — | 2 | Shield 2. |
| 2 | I | 10 | 6 | 2 | Resistant. Shield 2. |
| 2 | II | 14 | 3 | 3 | Resistant. Shield 2. When revealed: +1 acceleration. |
| 2 | III | 18 | — | 4 | Shield 3. |
| 3 | I | 16 | 6 | 3 | Resistant. Shield 3. All'inizio del round 1: cerca nel mazzo attrition una carta di valore 0, rimuovila dal gioco, poi rimescola. |
| 3 | II | 18 | 3 | 4 | Resistant. Shield 3. When revealed: +1 acceleration. |
| 3 | III | 22 | — | 5 | Shield 4. When revealed: +1 acceleration. |

## Le tre peril

- **Wailing Roar** (Stance I, *Permanent*): quando il mazzo attrition si
  esaurisce, Tarragua guadagna 1 struggle per giocatore.
- **Slash to the Throat** (Stance II, *Permanent*): quando viene rivelata una
  behavior con quella reazione, il giocatore attivo puo' scartare un dodge dalla
  mano per annullare gli effetti di quella carta **e infliggere vulnerable**. La
  faccia B toglie il vulnerable.
- **Unscratchable** (Stance III): finche' Tarragua ha 1 struggle per giocatore o
  piu', tutte le carte weapon sono **blank** (il testo delle abilita' si ignora).

## Un buco nell'estrattore, trovato qui

`extract_monster.py` salvava il fronte degli *States* TTS ma non il retro. Per i
mostri le cui carte stance sono **stampate fronte-retro con due livelli diversi**
— Tarragua, Jekoros, Kharja, Dygorax — quello significa **quattro facce a testa
mai estratte**: per Tarragua erano proprio Stance II e III del livello 3.

Le facce recuperate di Kharja e Dygorax sono state confrontate con i dati gia'
scritti: **combaciano**. Il buco era nello strumento, non nella trascrizione.

## I quattro mazzi behavior — testi letti

Nove carte per mazzo, e i quattro mazzi sono varianti della stessa dozzina di
carte con numeri diversi. I gruppi sono numerati come li estrae
`extract_monster.py`, che **non** e' l'ordine di livello: quello si ricava dai
glifi aggression, come per Kharja (vedi sotto).

**gruppo 2** — Metal Skin (+1 shield fino a fine turno) · Spidery Grasp (l'attivo
diventa *dazed* e salta il movimento se nessuno nel suo settore o adiacente
scarta un parry; boost: subisce DMG se non rivela tanti dodge quanto il livello
di attrition) · Rumbling Stomp (+1pp struggle e +1 damage fino a fine round) ·
Rampaging Horns (si gira verso l'attivo, che puo' muoversi subito) · Crushing
Horns (se ha subito danno, front e flank subiscono DMG se non rivelano 2 dodge) ·
Indomitable Charge (front DMG×2 se non rivelano 2 dodge; chi li rivela deve
muoversi gratis) · Aggressive Posture (1 struggle per giocatore nel front) ·
Hammer Tail ×2 (rear DMG se non scarta un dodge; threatened nei flank DMG se non
rivela un dodge).

**gruppo 3** — Hammer Tail ×2 (versione dura: threatened in flank e rear DMG+1,
threatened nei flank altro DMG+1 se non rivelano) · Aggressive Posture · Crushing
Horns (**ogni** giocatore, non solo front e flank; boost: scarta le prime 3 carte
attrition) · Rumbling Stomp (+3 damage) · Rampaging Horns (il costo di quel
movimento e' aumentato di 1) · Indomitable Charge · **Arkeum Skin** (+4 shield) ·
Spidery Grasp.

**gruppo 4** — come il 2, ma Rumbling Stomp da +3 e Crushing Horns su front e
flank. Metal Skin +1.

**gruppo 5** — il piu' mite: Hammer Tail ×2 senza i +1, Rumbling Stomp +1,
Aggressive Posture (1pp struggle secco, non per giocatore nel front), Metal Skin
+1, Spidery Grasp senza il *dazed* condizionato.

## Icone aggression — quale mazzo e' quale livello

Letti a occhio su ritagli stretti del solo glifo, come per Kharja. Ordine dei
glifi **identico**: `≢ ⊕ Ψ 8 M V`.

| gruppo estratto | glifi presenti | livello |
|---|---|---|
| 5 | ≢ ⊕ Ψ | **0** |
| 2 | ⊕ Ψ 8 | **1** |
| 4 | Ψ 8 M | **2** |
| 3 | 8 M V | **3** |

Ogni glifo compare esattamente 3 volte per mazzo e la finestra scorrevole di
p.60 combacia su tutti e quattro: e' univoca, non e' una scelta.

Conferma indipendente: l'ordine coincide con la durezza dei testi — il gruppo 5
e' il piu' mite (Rumbling Stomp +1, Aggressive Posture secca) e il gruppo 3 il
piu' duro (Rumbling Stomp +3, Arkeum Skin +4 shield, Crushing Horns su *ogni*
giocatore). Ma la lettura vale per i glifi, non per l'impressione.

## I retri: reazione e refresh

Il retro porta l'icona di reazione al centro e il **refresh** in basso a
sinistra. Per il mazzo del livello 0 (gruppo 5), in ordine di estrazione:
refresh 2, 3, 1, 5, 6, 5, 4, 4, 7.

## Da fare, in ordine

1. Le icone di reazione dei quattro mazzi, tradotte nelle chiavi di
   `data/common.json` (`attack_played`, `threatened`, `end_of_round`, ...).
2. L'**obiettivo**.
3. Il terreno delle due Expedition, dai diagrammi del Regolamento.
4. Il **bonus temporaneo allo shield**: Metal Skin e Arkeum Skin lo alzano fino a
   fine turno, quindi non basta il valore stampato sulla stance.
