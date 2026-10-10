# Da fare

Tutte le **144 carte azione** e tutti i **120 potenziamenti** hanno il loro
effetto: da qui in avanti quello che manca sono regole, non carte.

Elenco unico di quello che manca. Fino a oggi era sparso fra i "Limiti noti" del
README e le sezioni "Da fare" delle singole doc: qui c'e' tutto in un posto, in
ordine di quanto pesa sul gioco.

Stato al 5 agosto 2026: **4 mostri su 4**, **6 cacciatori su 6**, 237 controlli
mirati e 360 partite automatiche senza errori.

## 1. Regole di gioco non ancora coperte

- **Brush e plateau**: gli unici due terreni che riscrivono l'ordine di turno.
  Nascondersi nel brush mette il proprio turno *in pausa* e nomina chi gioca al
  posto tuo; il plateau permette di salirci e annullare le behavior con un
  *riding check*. Il motore non sa mettere un turno in pausa.
- **Keep Your Distance** (objective di Kharja) e' giocabile, ma gli altri
  objective attivabili a scelta seguiranno la stessa strada quando arriveranno.
- **Lo slot Item**: il regolamento prevede di scegliere anche un Item fra gli
  accessori forgiabili. I dati ci sono, lo slot no.

## 2. Interfaccia

- **I tracciati sono sulla plancia mostro, non sul tavolo 3D**: salute,
  hardening e acceleration si leggono nel pannello di sinistra, dove sono
  stampati. Sulla plancia 3D restano invisibili — i dust invece si vedono, come
  foschia bassa sul settore.
- **Hotseat**: le scelte che toccano a un altro giocatore compaiono nello stesso
  schermo. Niente rete, niente schermate separate.

## 3. Piccole cose note

- Tre carte nominavano un trigger fuori turno che il motore non emetteva e non
  venivano mai offerte: *Anticipate* e *Bulwark* di Ljonar, *Disengage* di Karah.
  Corretto il 5 agosto 2026; ora `RulesTest` controlla che ogni trigger scritto
  nei dati abbia qualcuno che lo innesca.

- `why_not_playable` conta la carta che stai giocando fra le fonti di stamina:
  dice "giocabile" anche quando l'unica carta che potrebbe pagarla e' lei stessa.
  Il pagamento poi fallisce e la giocata viene rifiutata, quindi l'esito e'
  giusto ma il messaggio arriva tardi. Stessa famiglia del blocco sul segnalino
  stamina, corretto il 5 agosto.
- Il **plateau di Toramat**: la sua Stance III dice di rimuoverlo, ma nei due
  setup Expedition il plateau non c'e'. Non e' un buco nostro, e' il libro:
  arrivera' dagli scenari di campagna.
- **Il database fan-made** continua a sbagliare nomi (`Daeron`, `Thoerg`) e a
  riusare gli stessi id TTS per carte diverse. Ogni caso risolto e' annotato in
  `MANUAL` / `DB_NAME_FIXES` dentro `tools/build_loadouts.py`.

## Gli ultimi due mostri

**Jekoros** e **Tarragua** sono in perimetro: hanno entrambi le loro pagine
Expedition 1 e 2 nel Regolamento. Le carte sono gia' estratte
(`art/monsters/jekoros/`, `art/monsters/tarragua/`), plance comprese, e i
provini sono in `art/_provini/`. Resta la trascrizione: per ciascuno quattro
mazzi behavior da 9 carte, quattro livelli di stance, peril e obiettivo.

**Tarragua**: stance e peril sono gia' letti e stanno in
[`docs/tarragua_struttura.md`](tarragua_struttura.md); restano i quattro mazzi
behavior e l'obiettivo.

Le meccaniche, che erano l'incognita, sono poca cosa:

- **Tarragua** non ha nessun sottosistema suo — niente charge, dust, swarm,
  rumble, debility o Arkeum. Usa l'**acceleration**, che il motore ha gia' per
  Toramat, e **Shield X**, aggiunto il 6 agosto 2026: la stance toglie X a ogni
  fonte di danno. Nessuno dei quattro mostri attuali lo usava.
- **Jekoros** ha il **tracciato charge** (p.95), che funziona come l'hardening —
  un contatore sulla plancia, e la sua plancia ce l'ha stampato — e le **carte
  attrition speciali**, che il motore gestisce gia' per Toramat.

Le **miniature GLB** ci sono (importate il 6 agosto 2026): Jekoros 18 MB,
Tarragua 84 MB — quest'ultima e' la piu' pesante del progetto, e il grosso e'
geometria, non texture.

Nota di metodo: `extract_monster.py` non salvava il **retro degli States** TTS.
Per i mostri con le stance stampate fronte-retro a due livelli — Tarragua,
Jekoros, Kharja, Dygorax — erano quattro facce a testa mai estratte. Corretto; le
facce recuperate di Kharja e Dygorax combaciano con i dati gia' scritti, quindi
il buco era nello strumento e non nella trascrizione.

## Fuori perimetro

La **modalita' Campagna**: quest, crafting, progressione della forge, scenari
collegati. Il progetto e' esplicitamente limitato a Expedition.
