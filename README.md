# Primal Digital — modalità Expedition

Versione digitale di *Primal: The Awakening* limitata alla **modalità Expedition**:
una singola battaglia contro un mostro, senza campagna.

- **Mostri:** Vyraxen, Kharja, Dygorax e Toramat — tutti e quattro i livelli di aggression (**0-3**), selezionabili in partita
- **Cacciatori:** tutti e sei, con **costruzione del mazzo e forge**
- **Motore:** Godot 4.7, GDScript
- **Plancia:** 3D con camera orbitale (trascina col tasto destro o centrale, rotella per lo zoom)
- **Miniature:** modelli 3D GLB per i cacciatori, per tutti e quattro i mostri e
  per i terreni che sono oggetti; fuoco, dust, acqua e sabbia sono procedurali
- **Colpi:** chi attacca scatta avanti, chi incassa trema, e un anello segna chi
  ha il turno

## Come si avvia

```bash
godot --path PrimalDigital scenes/Main.tscn
```

Collaudo automatico, test mirati sulle regole e strumento di misura:

```bash
godot --headless --path PrimalDigital scenes/SmokeTest.tscn    # 360 partite: 4 mostri x 4 livelli, piu' due giri per cacciatore
godot --headless --path PrimalDigital scenes/RulesTest.tscn    # 237 controlli sulle regole
godot --headless --path PrimalDigital scenes/Diagnostics.tscn  # conta cosa succede in partita
```

`Diagnostics.tscn` non usa sonde nel motore: conta dal registro di gioco, che è
già abbastanza esplicito. Serve a distinguere "il motore sbaglia i numeri" da
"il giocatore automatico gioca male".

Screenshot di sviluppo: `--shot-choice` avanza fino al pannello di pagamento,
`--shot-order` costruisce una sequenza con due abilità simultanee.

```bash
godot --path PrimalDigital scenes/Main.tscn -- --shot
godot --path PrimalDigital scenes/Main.tscn -- --shot-choice
godot --path PrimalDigital scenes/Main.tscn -- --shot-order
godot --path PrimalDigital scenes/Main.tscn -- --shot-turn
godot --path PrimalDigital scenes/Main.tscn -- --shot-reaction
godot --path PrimalDigital scenes/Main.tscn -- --shot-attrition
godot --path PrimalDigital scenes/Main.tscn -- --shot-facing --facing=1 --monster=kharja
godot --path PrimalDigital scenes/Main.tscn -- --shot-terrain --no-windows
godot --path PrimalDigital scenes/Main.tscn -- --shot-blow --no-windows
godot --path PrimalDigital scenes/Main.tscn -- --shot --monster=kharja
godot --path PrimalDigital scenes/Main.tscn -- --shot --no-windows
godot --path PrimalDigital scenes/Main.tscn -- --party=thoreg,dareon --shot
godot --path PrimalDigital scenes/Main.tscn -- --test-pay-token
```

`--shot-turn` porta la partita dentro il turno del primo cacciatore, con carte
già in sequenza: serve a guardare la traccia del round accesa su un turno invece
che sulla fase Consume. `--shot-reaction` mostra la carta reazione del mostro
dove compare in partita. `--shot-attrition` arriva alla fase Attrition restando
fermo, così il cacciatore è threatened e si rivelano due carte invece di una. `--shot-terrain` mette in tavola i quattro terreni senza
miniatura (fuoco acceso, fuoco quasi spento, acqua, sabbia) più i segnalini dust.
`--shot-blow` fotografa un colpo a metà strada: in una posa ferma lo scatto non
si vedrebbe. `--shot-facing` gira il mostro verso un settore e fotografa: serve a
controllare che il modello guardi dove il motore crede — ogni GLB è scolpito
rivolto da una parte diversa e l'angolo di correzione (`art.model_yaw`) era
sbagliato per tre mostri su quattro.

Le prove che fanno avanzare la partita da sole passano tutte da `_advance_until`,
che risponde ai pannelli di scelta **e** salda i pagamenti: la stamina non si
paga in una finestra ma cliccando le carte in mano, e una prova che aspetta il
pannello di scelta resta appesa sulla prima carta che costa qualcosa.

`--test-pay-token` è una prova: gioca l'ultima carta rimasta in mano quando solo
il segnalino stamina può coprirne il costo, e verifica che il pagamento si possa
davvero confermare.

Le prove saltano la schermata iniziale, quindi il mostro si sceglie con
`--monster=<id>`; senza, partono contro Vyraxen. `--no-windows` chiude i pannelli
flottanti prima dello scatto, per fotografare la plancia.

## Versione web

Si gioca nel browser su https://tannoiser2.github.io/Primal/ ed è nella
[ludoteca](https://tannoiser2.github.io/). La pubblica l'azione `.github/workflows/pages.yml`
a ogni aggiornamento del ramo `main`.

Gli sculti originali arrivano a due milioni di triangoli e le immagini sono importate senza
perdita: esportati così fanno un pacchetto da 1,2 GB, troppo per un browser. Prima di
esportare, l'azione lancia `tools/alleggerisci_web.py` **solo sulla sua copia**:

- semplifica ogni miniatura a 60.000 triangoli con gltfpack;
- passa le immagini 2D a WebP con perdita e al massimo 2048 pixel di lato;
- non genera LOD e ombre separate per i modelli.

Il pacchetto web scende così a circa 220 MB. Il progetto qui resta a piena qualità per l'app
desktop. Nel browser Godot usa il renderer Compatibility (WebGL 2) al posto di Forward+.

## Esportare l'app macOS

```bash
godot --headless --path PrimalDigital --export-release "macOS" PrimalDigital.app
codesign --force --deep --sign - PrimalDigital.app     # firma locale, basta per uso personale
cp -R PrimalDigital.app "/Applications/Primal Digital.app"
```

Serve che i template di export di Godot 4.7 siano installati (Editor → Gestisci
template di esportazione). Il preset è in `export_presets.cfg`; l'app pesa ~700 MB,
quasi tutti miniature 3D: sono dieci GLB da 35-50 MB l'uno.

## Struttura

```
data/          dati di gioco in JSON (carte, mostro, regole)
scripts/engine Db, Player, Game  — il motore, indipendente dalla UI
scripts/ui     Board3D (plancia 3D), Main (interfaccia)
scripts/tools  SmokeTest (partita automatica)
tools/         pipeline Python di estrazione asset dal mod TTS
art/ models/   immagini carte e mesh estratti (generati, non modificare a mano)
```

Il motore (`scripts/engine/Game.gd`) non conosce la UI: comunica via segnali
(`log_line`, `state_changed`, `scenario_ended`, `choice_required`, `blow`) ed è
pilotabile a comandi (`move`, `play_card`, `assist`, `revive`,
`end_action_phase`, `consume`).

Le **reazioni fuori turno** sono dichiarate nei dati (`out_of_turn`) e il motore
le offre a chi ha la carta in mano. Il nome del trigger deve però essere uno di
quelli che il motore emette davvero: tre carte — *Anticipate*, *Bulwark* e
*Disengage* — ne nominavano uno che non esisteva e non venivano mai offerte. Una
carta che non viene mai offerta non fa rumore, semplicemente non succede: per
questo `RulesTest` legge i dati, raccoglie i trigger e controlla che ognuno
compaia in `Game.gd`.

`blow(attacker_id, target_id, amount)` esiste perché `state_changed` dice che
qualcosa è cambiato, non **chi ha colpito chi**: senza, la plancia non saprebbe
quale miniatura far scattare. Gli id sono quelli dei cacciatori oppure
`"monster"`; quando i due coincidono il danno non viene dal mostro (fatigue,
burning, terreni, carte proprie) e sul tavolo resta solo il tremito.

**I comandi del motore sono coroutine**: quando serve una decisione il motore emette
`choice_required` e *si sospende* finché la UI non chiama `answer()`. Chi lo pilota
deve quindi usare `await`. Con `game.auto_resolve = true` le scelte vengono risolte
da un'euristica senza sospendersi: è così che gira il collaudo headless.

Tipi di richiesta (`request.kind`): `pay` (quali carte scartare per generare
stamina), `cards` (scegli 0..N carte da un elenco), `player`, `sector`, `confirm`,
`order` (quale effetto simultaneo risolvere per primo).

### Effetti simultanei

`_resolve_simultaneous()` è il punto unico in cui si risolve un gruppo di effetti
che scattano insieme. Applica prima la priorità del Regolamento p.35 — stance,
peril, behavior, altre carte — e a parità di priorità chiede l'ordine al giocatore.
Passano di qui: le abilità innescate giocando una carta (propria, delle carte in
sequenza, weapon, mastery, obiettivo), le behavior attivate dallo stesso evento e
le rampage multiple.

Conseguenza importante: l'effetto legato al **colore** della carta (danno per un
attack, rimozione di struggle per un maneuver) si applica *dopo* tutte le abilità,
così i bonus ai danni entrano nell'attacco che li ha generati (p.21 e l'esempio
di p.25).

## Come è disposta la schermata

Tre colonne, e in mezzo non ci va niente che si possa mettere altrove:

- **sinistra** la scheda del mostro — la sua plancia, con il segnalino salute
  dove sta adesso e **le tre carte reazione nei riquadri stampati**, come sul
  tavolo; poi stance, peril e obiettivo una sotto l'altra e della stessa misura — oppure quella
  del cacciatore selezionato: si guarda l'una o l'altra, aprirne una chiude
  l'altra. Nella scheda del cacciatore l'arma sta a sinistra e armor e helm
  impilati alla sua destra, **alti la metà** dell'arma, come sulla plancia vera;
  la larghezza dell'arma si ricava all'indietro dallo spazio disponibile, perché
  armor e helm sono carte coricate e a misura fissa uscivano dalla colonna;
- **centro** il tavolo, la mano a ventaglio in basso e, in basso a sinistra, la
  sequenza del giocatore attivo;
- **destra** il registro.

In alto, tre righe: chi c'è in campo, la **traccia del round**, e cosa tocca fare
adesso.

La traccia è la risposta alla domanda «adesso a chi tocca»: mostra la sequenza
vera del regolamento — Consume, upkeep del mostro, un turno per cacciatore in
ordine di gioco, fine round — con la casella accesa dove siamo. L'ordine parte
dal giocatore **aggro** (p.17), non dal primo posto in tavola; prima dell'upkeep
il primo giocatore è ancora quello del round scorso, quindi lì la traccia mostra
l'ordine che *ci sarà*, che è quello che serve per decidere adesso. Sotto, il
messaggio dice chi deve agire, cosa succede se lo fa e **cosa viene dopo**: senza
l'ultima parte ogni fase sembrava l'ultima.

Le carte si pescano alla fine del proprio turno, quando la mano si ripristina al
limite: il motore lo scrive nel registro, perché a schermo le carte comparivano
in mano e non si capiva da dove.

**Quando si chiede qualcosa, la carta si vede.** Vale per tutte le domande che
nominano una carta — «scarti X?», «riveli X?» — e per la scelta di quale effetto
risolvere per primo, che mostra le carte in causa col loro testo e non un elenco
di nomi: nessuno ricorda a memoria cosa fa *Reactive Guard* mentre decide
l'ordine. Le carte azione non portano il percorso dell'immagine nei dati, si
ricava dall'id con `Db.card_art()`; leggerne il campo `art` restituisce vuoto.

**Le cose da guardare fermano il gioco.** La behavior appena rivelata e l'esito
dell'attrition (con le carte uscite, il conto e cosa ne segue) sono richieste
come tutte le altre — `kind: "notice"` — quindi il motore **si sospende** finché
non si chiude il riquadro. Non è solo comodità: è così che gli effetti restano in
fila. La domanda «scarti questa carta?» che risponde a una reazione arriva
**dopo** che la reazione è stata letta, non sopra, e si capisce a cosa si sta
rispondendo. `RulesTest` lo verifica sull'ordine vero delle richieste.

Il livello di aggression **non si cambia in corsa**: si decide nella schermata
iniziale, quando la partita è ancora da montare.

La **sequenza** è una finestra spostabile che si apre da sola alla prima carta
giocata e si richiude a fine turno; chi la chiude a mano se la riapre dal
pulsante *Sequenza* nella barra. Sul tavolo le carte giocate ci sono comunque,
ma quando il cacciatore è sul lato lontano diventano minuscole e di taglio.

## La plancia 3D

`Board3D` sceglie da sola come disegnare ogni terreno, in quest'ordine: se esiste
`models/terrain/<tipo>.glb` usa la miniatura; se il terreno è uno dei quattro
**procedurali** lo costruisce; altrimenti appoggia il segnalino di cartone con
l'immagine vera in `art/terrain/<tipo>.png`. Aggiungere un GLB basta a far
cambiare il tavolo: non c'è codice da toccare.

I quattro procedurali non hanno miniatura perché non sono oggetti — sono
fenomeni, e una tessera piatta li tradiva:

| | Come |
|---|---|
| **fuoco** | particelle additive che salgono, più una luce che accende il settore; `fire_spent` è la stessa fiamma più bassa e più scura, cioè il segnalino girato sul giallo |
| **dust** | particelle basse e lente su tutto il settore, non su un segnalino: più fitte a due dust |
| **acqua** | piano suddiviso con onde nel vertex shader e riflesso nella normale, bordo sfumato |
| **sabbia** | resta la tessera, ma le creste si muovono con una normale calcolata a schermo |

Due dettagli che è facile sbagliare rifacendoli: le onde dell'acqua vanno tenute
a **bassa frequenza** (alzandola il riflesso si spezza in una griglia di puntini
e la pozza sembra una palla da bowling), e il tavolo va ricostruito **solo quando
il terreno cambia davvero** — `state_changed` arriva a ogni variazione di stato,
e rifare i nodi a ogni giro riavvia le particelle un fotogramma sì e uno no.

I colpi arrivano dal segnale `blow` e passano per una **coda**: il motore ne
emette anche tre di fila (attacco, battle dance, abilità della weapon) e
sovrapporli darebbe solo un tremolio confuso. Chi colpisce scatta verso il
bersaglio e torna, chi incassa trema in proporzione al danno. Lo scatto muove un
nodo interno alla miniatura, non la miniatura: così la posizione sulla casella
resta quella decisa da `set_hunter_position` e l'anello del giocatore attivo non
si sposta insieme al corpo.

## Pipeline degli asset

Gli asset vengono ricostruiti dal mod Tabletop Simulator in `../Mods`:

```bash
python3 tools/extract_assets.py     # ritaglia le carte dagli sprite sheet TTS
python3 tools/build_loadouts.py     # equipaggiamento forgiabile e immagini dei potenziamenti
python3 tools/cutout_standees.py    # scontorna le figurine dei cacciatori (ripiego)
python3 tools/optimize_art.py       # ridimensiona e converte in JPEG dove serve
python3 tools/check_exposure.py     # rilegge i lati esposti dalle carte stance
```

`check_exposure.py` non genera niente: **ricontrolla** una trascrizione fatta a
mano. Il diagramma di esposizione sulla carta stance è il cerchio diviso da una
X — rosso esposto, nero protetto — ed è orientato col **front in basso**, segnato
dal trattino sotto il cerchio (Regolamento p.20). Letto con il front in alto si
scambiano front e rear, e l'errore si vede solo quando provi ad attaccare e la
carta viene rifiutata. La lettura automatica è una prima passata: su qualche
carta non centra il cerchio e va scartata, per questo `--sheet` ritaglia tutti i
diagrammi in una tavola con accanto il valore del JSON. È lì che si decide.

Le **miniature 3D** non vengono dal mod: sono file GLB aggiunti a mano sotto
`Organized_Print_Files/*/Miniatures/`. Si importano a parte:

```bash
python3 tools/import_miniatures.py --shrink        # solo chi è in gioco
python3 tools/import_miniatures.py --shrink --all  # tutti e sei i cacciatori
```

`--shrink` riscrive il GLB ridimensionando le texture incorporate a 1024px
(ricostruendo buffer e offset del contenitore). Se un modello manca, la plancia
ricade da sola sul mesh TTS per il mostro e sulle sagome piatte per i cacciatori.

Note su come sono organizzati i dati nel mod, utili se si estendono i contenuti:

- Le carte vivono in **sprite sheet**: l'indice della carta è `CardID % 100`,
  la griglia è in `CustomDeck.NumWidth/NumHeight`.
- Le **Stance II e III** non sono carte separate: sono *States* TTS della carta Stance I.
- Esistono **quattro mazzi behavior** da 9 carte, uno per livello di aggression,
  ma nel file TTS non sono in ordine di livello. L'ordine si ricava dalla struttura
  descritta a p.60 del Regolamento: ogni livello usa un set di 3 icone aggression
  che scorre su 6 icone totali (L0 = A,B,C; L1 = B,C,D; L2 = C,D,E; L3 = D,E,F),
  quindi livelli adiacenti condividono 6 carte, a distanza 2 ne condividono 3 e a
  distanza 3 nessuna. `_order_behavior_decks()` cerca la permutazione che rispetta
  questa struttura: è univoca. Fidandosi dell'ordine del file si sbagliano i
  livelli 2 e 3, che sono invertiti.
- La stessa carta behavior compare con **CardID diversi** in mazzi diversi: va
  identificata dall'immagine, non dall'id (vedi `behavior_aliases`).
- **Peril e objective sono a doppia faccia**: il fronte porta l'icona C (usata dai
  livelli 0, 1 e 2), il retro l'icona F (solo livello 3). Le tre carte peril
  abbinano stance diverse sulle due facce, così ogni faccia dà comunque un set
  I/II/III completo.
- Nel mod le **miniature 3D esistono solo per i mostri**. I sei cacciatori sono
  `Figurine_Custom`, cioè immagini piatte. Il gioco usa quindi i modelli GLB
  esterni; le sagome scontornate restano come ripiego se i GLB non ci sono.

### Le carte potenziamento

`data/upgrades.json` è **scritto a mano** trascrivendo le 40 carte dalle immagini:
è lì, non nel database fan-made, che sta la verità su nomi, costi e testi. Due
motivi concreti: il database ha errori accertati (*Sentinel* / *Exhausting
Defense* scambiati, *Arrow Snatch* chiamato "Arrow Switch", *Momentum Strike* che
conta la sequenza invece degli scarti) e comprime le icone in abbreviazioni che
perdono informazione.

Attenzione a un dettaglio: **gli id TTS si ripetono fra i cacciatori** — 212900 è
sia *Blade Surge* di Dareon che *Double Shot* di Mirah. Le carte portano quindi un
id globale (3.000.000 + id per Dareon, 4.000.000 + id per Mirah); l'id TTS resta
solo per ritrovare l'immagine.

### Abbinare immagini e statistiche

`build_loadouts.py` deve unire due sorgenti che non si conoscono: il database ha
nomi e statistiche, il mod TTS ha le immagini identificate solo da un `CardID`.
Per le carte potenziamento l'abbinamento è automatico: ogni track dell'albero
delle abilità contiene due mazzetti da 2 carte, il database dice quali sottotipi
stanno in ciascun tier, e il sottotipo si legge **dal colore della fascia in alto**
della carta (rosso attack, blu maneuver, giallo parry, verde dodge — i valori di
riferimento sono misurati sulle carte starter, di cui il tipo è noto). Dove una
coppia ha due carte dello stesso colore l'abbinamento resta ambiguo: quelle sono
elencate in `MANUAL` e risolte leggendo le carte una per una. Lo script fallisce
rumorosamente se resta un'ambiguità non risolta.

## Fonti dei dati

| Dato | Fonte |
|---|---|
| 144 carte azione (nome, tipo, costo, stamina, aggro, tratti, testo) | trascritte dalle immagini carta del mod |
| Icone aggro | campionate a livello di pixel dalle immagini, non a occhio |
| Stance, behavior, peril, objective di Vyraxen | trascritti dalle immagini carta |
| Stance, behavior, peril, objective di Kharja | trascritti dalle immagini carta, vedi `docs/kharja_struttura.md` |
| Stance, behavior, peril, objective di Dygorax | trascritti dalle immagini carta, vedi `docs/dygorax_struttura.md` |
| Stance, behavior, peril, objective di Toramat | trascritti dalle immagini carta, vedi `docs/toramat_struttura.md` |
| Tracciato hardening e segnalini dust | Regolamento p.95 e Glossario p.109 |
| Acceleration e carte attrition speciali | Glossario p.106 e Regolamento p.98 |
| Terreno iniziale di ogni expedition | letto dai diagrammi di setup, Regolamento p.67-70 |
| Regole dei terreni | Regolamento p.89-90 |
| Strain, confuse, stealth, Impetus | Glossario p.107, p.113 e p.110 |
| Icone di reazione e loro significato | Regolamento p.31 e p.103 |
| Struttura di round e turno, struggle/unleash, attrition, KO | Regolamento p.17-30 |
| Regole Expedition e livelli di aggression | Regolamento p.65-66 e p.60 |
| Stance, behavior, peril e objective dei livelli 1-3 | trascritti dalle immagini carta |
| Plance dei quattro mostri e posizione dei tracciati | estratte dal mod, frazioni misurate una volta sull'immagine |
| Salute del mostro (10 a ogni livello) | Glossario, voce *Health (mostro)* |
| Infuriate X/Y/Z e Burning | Glossario p.107 |
| Valori del mazzo attrition | letti dalle 10 carte: 2,1,3,1,2,1,0,1,1,2 |
| Equipaggiamento forgiabile | `primal_database.xlsm`, con le immagini dal mod |
| 120 carte potenziamento | nomi e statistiche dal database, testi ed effetti dalle immagini, in `data/upgrades.json` |
| 24 carte azione di Heleren, Gunbow e Precision Reload | trascritte dalle immagini, vedi `docs/heleren_struttura.md` |
| Bullet, Ignite, Reload, defense token | Player Reference di Heleren e Glossario p.108 |
| 20 potenziamenti di Heleren | testi ed effetti dalle immagini, statistiche dal database |
| Finestra dei ritratti su plance e carte stance | misurata a mano, in `art.portrait` |

## Cosa è implementato

**Tutte le carte hanno il loro effetto**: 144 azione e 120 potenziamento. Non
c'è più niente in catalogo segnato in rosso — quello che manca da qui in avanti
sono regole, non carte, ed è tutto in [`docs/da_fare.md`](docs/da_fare.md).

Struttura del round (Consume → Upkeep → turni → fine round) e del turno
(Movimento → Azione → Attrition → Fine turno); costi in stamina pagati scartando
carte; sequenza con limite 5 e abilità combo; carte aggro e rotazione del mostro;
danni, toughness, ferite e progressione delle stance; struggle, unleash ed
escalation; le tre carte behavior in gioco con icone di reazione, refresh, effetti
boost e rampage; carte peril e objective; check di attrition con threatened;
KO, depleted, revive, carte Wound e fatigue damage; assist; mastery con focus;
pozioni; terreni piazzati dalle carte; condizioni di vittoria e sconfitta.

**Costruzione del mazzo e forge** (Regolamento p.66), per i livelli 1-3: scelta di
weapon (che detta danno base e composizione del mazzo), armor e helm del livello
corrispondente, mastery, fino a 3 pozioni senza doppioni, e i potenziamenti
dell'albero delle abilità (2, 4 o 6 secondo il livello). Il mazzo va composto
rispettando esattamente i conteggi di attack/maneuver/parry/dodge della weapon:
la schermata non lascia iniziare finché non torna.

**Stati del mostro**: *vulnerable* (raddoppia una singola fonte di danno, poi si
consuma; decade a fine round), *stun* (il segnalino va su una carta behavior, che
non si innesca per il resto del round; poi un giocatore rivela fino a 2 attack e
infligge il proprio weapon damage per ognuna) e *blind* (rende *blank* una carta
peril fino all'inizio del turno di chi l'ha inflitto). Non sono status generici:
ognuno colpisce un componente diverso del tavolo.

**Decisioni del giocatore** (pannello modale): quali carte scartare per pagare la
stamina, chi bersagliare con "choose another player" e con le cure, se pagare i
costi opzionali (Heavy Arrow), se scartare una carta per evitare il danno di una
behavior, se muoversi o incassare quando Aggression lo impone, quale carta prendere
cercando nel mazzo o negli scarti, quali carte riciclare. Sono gestite anche le tre
reazioni fuori turno: **Cover Fire** (previene il danno da attrition di un altro
giocatore), **Thwart** (raddoppia lo struggle rimosso) e **Intuition** (ricicla sé
stessa quando giochi una parry).

**Collaudo:** 240 partite automatiche complete senza errori. Con un'IA volutamente
banale (nessuna combo, niente pozioni né assist) i quattro mostri chiudono in
media così (salute residua su 10):

| Livello | Dotazione | Vyraxen | Kharja | Dygorax | Toramat |
|---|---|---|---|---|---|
| 0 | mazzo starter | 6.3 | 5.6 | 5.4 | 7.1 |
| 1 | forge + potenziamenti liv. 1 | 7.5 | 6.5 | 7.1 | 6.7 |
| 2 | forge + potenziamenti liv. 2 | 8.1 | 7.4 | 6.9 | 7.7 |
| 3 | forge + potenziamenti liv. 3 | 8.9 | 8.5 | 7.7 | 7.9 |

I numeri si sono alzati da quando il terreno ha effetto: il fuoco blocca le
carte, la sabbia costa stamina, l'acqua accorcia la sequenza — e il giocatore
automatico non ne sa niente, non scappa dal fuoco e non spende le rocce.

La curva è coerente su tutti e quattro: ogni livello è più duro ma resta aggredibile.
Senza forge i livelli 2 e 3 restavano a 10 su 10, cioè il mostro non veniva mai
ferito. Kharja è un filo più difficile da ferire a parità di livello, il che
torna: la sua Stance I ha toughness più alta e i segnalini che accumula fanno
crescere il danno che i cacciatori incassano. Dygorax è la più ostica al livello
0 — *Resistant* sulle prime due stance butta via ogni danno in eccesso, e il
giocatore automatico non sa che dovrebbe abbassarle l'hardening colpendo da
dietro.

**Cosa dice la diagnostica.** Ai livelli alti le partite non arrivano al round 10:
finiscono al 5°-6° perché i cacciatori vengono annientati. Non è un problema di
danno — il danno inflitto *cresce* col livello (13.6 al livello 0, 55.9 al livello 3)
e il rapporto danno/ferite torna con la toughness dichiarata. Il limite è la
sopravvivenza. La prova: dando al giocatore automatico una regola difensiva
(muoversi quasi sempre, perché restare fermi rende *threatened* e da threatened
l'attrition pesca due carte e prende la peggiore) i round sopravvissuti al livello 3
sono passati da 3.1 a 4.8, e al livello 2 da 4.6 a 6.6.

Resta zero vittorie: il divario che rimane è **qualità di gioco** — combo, mastery
focalizzate, uso di vulnerable e stun al momento giusto, costruzione del mazzo — cioè
esattamente ciò che rende interessante il gioco vero. I numeri del motore sono
internamente coerenti.

`SmokeTest.tscn` gira 15 partite per ciascuno dei quattro livelli, contro tutti
e quattro i mostri. In coda fa due giri di 15 partite **per ogni cacciatore fuori
dal gruppo di misura** — uno col mazzo starter e uno con la forge: senza, le
carte di Thoreg, Karah, Ljonar e Heleren non verrebbero mai eseguite, perché il
gruppo di misura è sempre Dareon e Mirah, e i potenziamenti si giocano solo dal
livello 1 in su.

`RulesTest.tscn` verifica in modo mirato: che il bonus di Counterstrike entri
nell'attacco che segue (2 + 3 = 5 danni), che l'abilità della Great Sword si
applichi al secondo attacco della coppia (6 danni totali e 1 struggle rimosso),
che con due abilità simultanee il motore chieda davvero l'ordine, e che la
priorità fra categorie preceda la scelta del giocatore. E per i livelli alti: le
statistiche della Stance I di livello 3 con la sua apertura del round 1, le soglie
di *Infuriate 2/6/9*, e il *burning* che si consuma quando il mazzo si esaurisce.
Su Kharja: che i quattro mazzi behavior abbiano dieci carte e dieci nomi diversi,
che il fuoco delle Stance II vada solo nei settori con un segnalino damage, che la
Stance III sposti il segnalino round a 8 (e dia struggle se ci è già), che ogni
ferita lasci un segnalino e che quel segnalino pesi sull'attrition, che *reveal*
non tolga la carta dalla mano, e che *Fire Paw* colpisca solo se la carta scartata
dal mazzo behavior ha *claw*. Su Dygorax: il tracciato hardening che si ferma a 3,
*hardened* che blocca vulnerable e stun e cancella il danno in eccesso, *Resistant*
che non riporta l'eccesso alla stance seguente, il tetto di 2 dust per settore col
*disrupt* sull'attrition, *Dragon Scales* che lascia esposto solo il rear, *Pressure*
che colpisce solo se la carta dopo non è difensiva, e *Hit the Tail* che abbassa
l'hardening attaccando dal rear. Su Toramat: il tetto dell'acceleration a 1 per
giocatore e lo struggle che ne deriva nell'upkeep, l'escalation che la fa salire,
le due carte attrition speciali che pretendono un dodge, *Out of Control* che si
risolve appena entra in gioco, e *Crash on the Rocks* che a quota segnalini mette
*Crashing Charge* in cima al mazzo. E su *Keep Your Distance*: che si offra dopo un
dodge, che declinare non faccia nulla, che accettare metta il segnalino, prevenga
l'attrition e chiuda la fase azione, che a 3 segnalini non venga più offerto, e
che al livello 3 entrino le facce B (Burning Skin che lascia 2 segnalini per
ferita).

### Una scelta di arbitraggio

*Vulnerable* si può spendere sull'attacco che lo ha appena inflitto (Precise
Strike, Lacerate). Il Regolamento (p.21) fa risolvere il testo dell'abilità
**prima** dell'effetto di colore, quindi quando il danno arriva il segnalino è già
sulla plancia del mostro, e il glossario non prevede eccezioni. È una lettura
letterale: se al tavolo lo giocate diversamente, il punto da cambiare è il
controllo `monster_vulnerable` in `deal_damage_to_monster()`.

## Traduzioni

Tutti i testi carta sono in italiano, con l'inglese come ripiego automatico.
Il criterio segue il regolamento italiano, che **non traduce i termini di gioco**:
restano in inglese *struggle*, *stamina*, *aggro*, *threatened*, *vulnerable*,
*blind*, *stun*, *burning*, *slash*, *aim*, *DMG*, le keyword (*Assist*,
*Berserker*, *Resilience*, *Finisher*, *Stealth*, *Consume*, *Recycle*, *Volley*,
*Opening*, *Action*) e i quattro tipi di carta. Le icone di innesco diventano
parole («Dopo due attack di fila:», «Con la mastery focalizzata:») perché a
schermo il simbolo non si distingue.

| Dove | Cosa |
|---|---|
| `data/hunters.json` | campo `it` sulle 48 carte starter, weapon base, mastery, pozione |
| `data/upgrades.json` | campo `it` sulle 40 carte potenziamento |
| `data/vyraxen.json` | campo `it` su behavior, boost, peril, objective e stance |
| `data/equipment_it.json` | equipaggiamento forgiabile, **indicizzato per testo inglese** |

L'equipaggiamento sta a parte perché `loadouts.json` è generato dal database e le
traduzioni verrebbero sovrascritte a ogni rigenerazione. La chiave è il testo
inglese, così una frase tradotta una volta vale per tutte le carte che la usano —
128 carte coprono 170 varianti di frase, perché lo stesso testo compare anche con
gli a capo del database.

`tools/translate_equipment.py` tenta una traduzione automatica a regole: copre
solo il 3% e serve ormai solo da rete. Emette una traduzione **solo se copre
l'intera frase**, così non produce ibridi: su un motore che applica le regole,
una frase tradotta male è peggio di una in inglese.

## Limiti noti

L'elenco completo di quello che manca, in ordine di peso, sta in
[`docs/da_fare.md`](docs/da_fare.md). Qui restano i limiti strutturali.

- **Hotseat.** Le scelte che toccano a un altro giocatore compaiono nello stesso
  schermo, indicando di chi è la decisione. Non c'è ancora rete né schermate separate.
- **Il mesh TTS del mostro è solo un ripiego.** Resta nei dati come riserva
  (`mesh` + `texture`, con `triplanar` dove le UV non corrispondono), ma con le
  miniature GLB non viene più usato: Board3D preferisce sempre il GLB.

- **Hardening e acceleration non si vedono sul tavolo.** Sono gestiti dal motore
  e finiscono nel registro, ma la plancia 3D non li mostra. I segnalini dust ora
  sì: sono una foschia bassa sul settore, più densa a due segnalini.
- **Brush e plateau non si possono usare.** Sono gli unici due terreni con una
  regola che riscrive l'ordine di turno — nascondersi nel brush mette in pausa il
  proprio turno, salire sul plateau permette di annullare le behavior con un
  *riding check* — e il motore non sa ancora mettere un turno in pausa. Gli altri
  nove terreni funzionano.
- **Lo slot Item non c'è.** Il regolamento prevede di scegliere anche un Item fra
  gli accessori forgiabili: i dati ci sono, ma offrire uno slot che non fa nulla
  sarebbe peggio che ometterlo.
- **Il database fan-made ha errori.** Dove immagini e database divergono, valgono
  le immagini. Corretti finora: i nomi *Sentinel* ed *Exhausting Defense* (Dareon,
  track C2) risultano scambiati, e la salute di *Totemic Plate* livello 2 manca —
  quella carta resta visibile ma non selezionabile invece di mostrare uno 0 falso.

## Come estendere

- **Nuovo cacciatore:** aggiungerlo a `data/hunters.json` con le sue 24 carte,
  metterlo in `HUNTERS` dentro `tools/build_loadouts.py` (chiave = id di gioco,
  valore = come lo scrive il database) ed eseguirlo: genera weapon, mastery e le
  immagini dei potenziamenti. La miniatura arriva da `import_miniatures.py`, e un
  GLB appena aggiunto va importato una volta con `godot --headless --import`,
  altrimenti la plancia non lo trova.
- **Nuovo mostro:** un file `data/<nome>.json` con la stessa forma di
  `vyraxen.json` o `kharja.json`, più una riga nel registro `Db.monsters` e l'id
  in `SplashScreen.MONSTERS`. Il motore legge stance, behavior, peril e objective
  del mostro selezionato con `Db.select_monster()`, quindi non c'è altro da
  toccare; finché mancano le behavior il mostro resta visibile ma non
  selezionabile.
- **Nuovo effetto di carta:** aggiungere un caso in `_run_effect()` in `Game.gd`.
  Gli effetti non implementati emettono un warning invece di rompere la partita.
