# Ljonar — the Sword and Shield

Quinto cacciatore giocabile, e il primo che gioca **per gli altri**: si prende
addosso il mostro, para i colpi dei compagni e trasforma quelli che incassa in
danno.

Dati: `data/hunters.json` (24 carte), `data/loadouts.json` (28 weapon,
6 mastery), `data/upgrades.json` (20 potenziamenti).

## Vocabolario

La sua Player Reference non inventa parole: usa Assist, Confuse, Opening,
Resilience, Taunt, Vulnerable. Due mancavano al motore e **valgono per tutti**:

- **Taunt**: durante il turno di un altro giocatore scarti la carta. Il giocatore
  attivo pesca 1, **tu prendi il segnalino aggro** e il mostro si gira subito
  verso il tuo settore. Cinque delle sue carte ce l'hanno.
- **Resilience**: dopo che subisci danno puoi **rivelare** (non scartare) una
  carta con Resilience per pescare 1. Era gia' scritta su *Battle Cry* di Dareon
  dal primo giorno, senza effetto: ora funziona anche li'.

## Le 24 carte

Sei per colore, come chiede la Sword and Shield. Il tema e' il tank:

- *Bulwark* e *Anticipate* **prevengono il danno**, il primo anche a un compagno.
- *Counterattack* e *Last Breath* rendono il danno incassato: la seconda infligge
  al mostro esattamente quanto damage hai addosso.
- *Attack Plan* mentre e' in cima ai tuoi scarti fa **crescere di 1 per livello
  weapon ogni danno inflitto al mostro da chiunque**.
- *Immolate* e *Beyond Limits* comprano vantaggio per gli altri col proprio sangue.

**Sword and Shield** (livello 1): danno 2, composizione 6/6/6/6, «dopo un parry:
rimuovi 1 struggle». **Shield Master** (mastery, **focus 3** — la prima cosi'):
si focalizza con parry→attack, e da focalizzata da' 2 per livello weapon dopo un
parry e +3 per livello all'attacco che segue un parry.

## Cosa e' stato aggiunto al motore

`_taunt_offered` (offerta a inizio turno altrui), `_resilience_offered` (dopo
ogni danno subito), l'op `prevent_damage` con l'intercettazione dentro `_suffer`,
e `_discard_top_aura`, il bonus che una carta in cima agli scarti concede a
tutti. Piu' i conteggi `occupied_sectors` e `aggro_in_discard`, il valore
`own_damage`, l'op `suffer_self` e `free_if: mastery_focused`.

## Da fare

Tre carte su 24 restano senza effetto, e sono tre cose diverse:
- *Concentrated Attack* conta gli attack negli scarti di **un altro** giocatore;
- *Rapid Dash* da' +1 per livello alle weapon **altrui** dagli scarti (l'aura c'e'
  gia' per i danni al mostro, non per le weapon);
- *Stamina Surge* genera 2 stamina invece di 1 quando la scarti per un attack
  (stesso impianto che manca a *Stamina Boost* di Thoreg).

I 20 potenziamenti sono in catalogo con nome, colore, costo e testo, ma gli
effetti non sono ancora trascritti: la costruzione del mazzo li segna in rosso.

## I venti potenziamenti

Erano tutti e venti in catalogo col loro testo ma **senza effetto**: nessuno
entrava nei mazzi. Ora ci sono tutti. Quattro hanno richiesto altrettanti pezzi
di motore, e nessuno dei quattro serve solo a lui:

- **Aure sui costi e sulle armi degli altri.** *Assistance* sconta gli attack che
  giocano i compagni, *Rapid Dash* rinforza le loro weapon. `Player.cost_of` e
  `base_weapon_damage` non possono saperlo — vedono solo se stessi — quindi il
  conto passa da `Game.cost_of()` e `Game.weapon_damage_of()`, che guardano anche
  la cima degli scarti altrui.
- **Momenti nuovi in cui chiedere**: `monster_would_gain_struggle` (*Sacrifice*
  paga col proprio sangue perche' quello struggle non arrivi), `would_unleash`
  (*Guardian Shield* lo para per tutti dal front), `other_turn_start`
  (*Outflank*) e `attrition_avoided` (*Snare*), che il Glossario definisce a
  p.108 e che serve anche a *Counter Measure* di Heleren.
- **Incassare al posto di un altro.** *Shield Wall* non si scarta dalla mano:
  sta gia' in cima ai propri scarti, e chi la ha si prende il colpo di un
  compagno del suo settore.
- **Una carta che vale due difensive.** *Mettle* conta doppio nel check di
  attrition, ma solo con la salute critica.

Sulle icone il database sbagliava, come al solito: la carta si chiama
**Assistance**, non *Assistence*.

Anche le tre carte azione rimaste sono chiuse: *Stamina Surge* ha trovato il suo
impianto con Heleren, *Rapid Dash* con l'aura sulle weapon, *Concentrated Attack*
con il conteggio negli scarti di un altro e l'innesco `on_wound` — «se questo
attacco infligge una ferita», che si sa solo dopo aver colpito.
