# Jekoros — struttura rilevata

Sesto mostro. Dati in `data/jekoros.json`, scritti da
`tools/build_tarragua_jekoros.py`.

## Il tracciato charge

Jekoros non avanza di stance con la salute: **avanza col tracciato charge**
(stampato sulla plancia, da 1 a 3). Quando il charge arriva a 3, la Stance I e la II
lo azzerano e passano alla stance successiva; la Stance III manda **KO tutti i
cacciatori**, cioè la partita è persa. Il charge sale con l'unleash (peril Thunder
Horn) e, ai livelli 2 e 3, di 1 all'inizio del round 1; scende con l'objective
Strike to the Heart.

## I quattro mazzi behavior

36 carte, **18 distinte**. Nel mod il mazzo del livello 1 ha una carta in meno: è
Electric Spark della versione 8, che si ritrova nei mazzi dei livelli 2 e 3 e che la
finestra di p.60 richiede (ogni glifo tre volte per mazzo).

| gruppo estratto | livello |
|---|---|
| 1 | 0 |
| 2 (+ Electric Spark) | 1 |
| 3 | 2 |
| 4 | 3 |

| carta | reazione | refresh |
|---|---|---|
| Unfathomable / Creeping Shadows | inizio turno nel front | 5 |
| Haunting Echoes | carta defensive giocata **oppure** threatened | 3 |
| Electric Spark | threatened | 2 |
| Sting | rampage | 4 |
| Retaliation | inizio turno nei flank | 4 |
| Electrocution | mano vuota | 2 |
| Heart Seeker | carta aggro giocata | 3 |
| Killer Tail | fine round | 5 |
| Insane Buzz | fine round | 5 |

Due reazioni nuove: **mano vuota** (la carta barrata, p.93) e le carte con **due
icone separate da /**, che scattano per l'una o per l'altra.

## Stance

Toughness per giocatore 2/4/5 (liv. 0), 7/8/12 (1), 12/17/22 (2), 20/25/30 (3); danno
1, 1, 2, 3. Stance I esposta su tutti i lati, II e III su front e flank.

## Peril e objective

- **Incessant Echo** (Stance I, permanente): Jekoros è *unstoppable* — ogni behavior
  innescata gli dà 1 struggle.
- **Thunder Horn** (Stance I, permanente): immune a blind; a ogni ferita guadagna
  struggle; l'unleash alza il charge di 1, e chi ha una roccia nel settore può
  consumarla per evitare il danno dell'unleash in quel settore.
- **High Tension** (Stance III): col charge a 2 (livello 3: a 1) il danno da
  attrition raddoppia.
- **Strike to the Heart** (objective, Stance II, permanente): a inizio turno un
  giocatore nel front può scartare un'offensive (livello 3: un attack) per infliggere
  vulnerable o abbassare il charge di 1.

## Attrition

Le cinque carte attrition di Jekoros (valore 1, difensiva qualsiasi) prendono il
posto delle cinque di valore 1 del mazzo comune: quando escono, se il giocatore
attivo è nel front Jekoros guadagna 1 struggle.

## Expedition

Pezzi dal Regolamento: Expedition 1 2 rock, baethanis, 2 water; Expedition 2 2 rock,
2 cyricae, 2 water. Caselle lette dal diagramma del Regolamento (p.76).
