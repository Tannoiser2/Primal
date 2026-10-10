# Karah — the Dual Blade

Quarto cacciatore giocabile. Tutto quello che fa gira intorno al **passare
attraverso il mostro**: tre carte lo fanno in momenti diversi del turno, la sua
mastery lo premia e una carta aspetta proprio quel momento per colpire.

Dati: `data/hunters.json` (24 carte), `data/loadouts.json` (28 weapon,
6 mastery), `data/upgrades.json` (20 potenziamenti).

## Il vocabolario viene dalla sua carta di riferimento

Il regolamento italiano copre solo Dareon, Mirah e Thoreg: le parole di Karah non
ci sono. Le definisce la sua **Player Reference** (`art/karah/karah_aid_back.jpg`),
che era gia' estratta e non avevo guardato:

- **Chain [colore]**: la carta si gioca **senza pagare la stamina** se segue una
  carta di quel colore nella sequenza.
- **Overrun**: la miniatura va nel settore **opposto** a quello attuale.
- **Battle Dance**: maneuver consecutivi fanno danno da soli. Le soglie stanno
  sulla plancia cacciatore: **3, 5 e 7 per livello weapon** al secondo, quarto e
  sesto maneuver di fila.
- **Reclaim [condizione]**: mentre la carta e' negli scarti, se la condizione e'
  soddisfatta la puoi rimettere in mano.

L'icona a lame incrociate vuol dire **«solo con la mastery focused»**. Su Thoreg
l'avevo letta come *strain*: *Heavy Smash* e' stata corretta.

## Le 24 carte

Sei per colore, come chiede la Dual Blade. Cinque parlano di overrun (*Cut
Through*, *Run Through*, *Piercing Strike* subito; *Cross Over* al posto di un
movimento pagato; *Divert* fuori turno quando si rivela una behavior), e due lo
aspettano per scattare (*Backstab* 4 danni per livello weapon, *Shadowstrike*
pesca 2). Sei portano **Chain**, quattro alzano il limite di sequenza: e' un
mazzo che vuole sequenze lunghe e gratis.

Reazioni fuori turno nuove: *Deny* butta la carta attrition appena rivelata e ne
fa pescare un'altra, *Disengage* fa ripescare la mano piena quando il mostro
cambia orientamento, *Offensive Attitude* cerca un attack quando un altro
giocatore ne gioca uno.

**Dual Blade** (livello 1): danno 2, composizione 6/6/6/6, «quando inneschi la
battle dance, infliggi 1 danno».
**Piercing Dash** (mastery, focus 2): si focalizza facendo overrun; da
focalizzata, ogni overrun infligge il danno base della weapon oppure fa pescare.

## Cosa e' stato aggiunto al motore

Op: `overrun`, `grant_stealth_turn`, `reroll_attrition`.
Funzioni: `_chain_free` (costo azzerato dalla chain, e da `free_if` per *Wall of
Blades*), `_overrun`, `_battle_dance`, `_mastery_focused_trigger` (mastery che
reagiscono a un evento anche da focalizzate).
Trigger fuori turno nuovi: `overrun` e `attrition_revealed`.
Condizione `paid_with_attack`, conteggio `type_in_sequence`.

## Il database, di nuovo

Due tier (B1 e D1) hanno entrambe le carte dello stesso colore, quindi
l'abbinamento automatico non basta: risolti guardando le immagini e messi in
`MANUAL` di `build_loadouts.py` — 205800 e' *Endless Strike*, 205900 e' *Evasive
Dance*.

## Da fare

- **Dodici potenziamenti su venti** non hanno ancora effetto: quasi tutti
  reazioni fuori turno (*Reactive Defense*, *Blade Rush*, *Iron Hedge*) o carte
  che riscrivono la battle dance (*Maelstorm*, *Double Strike*, *Dancing
  Shield*). Sono segnati e la costruzione del mazzo non li usa.
- **Reclaim** e' nei dati (*Shadow Step*, *Returning Blade*, *Unseen*) ma il
  motore non offre ancora il recupero dagli scarti.
