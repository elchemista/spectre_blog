---
title: "Quando anche le leggi della fisica sono plugin: DeepSeek Harness vs Spectre"
slug: "deepseek-harness-vs-spectre-plugin-o-kernel"
lang: "it"
status: published
date: 2026-08-16
updated: 2026-08-16
category: "Software Development"
tags: ["AI agents","agent architecture","DeepSeek Harness","Spectre","Elixir","OTP","plugin systems","enterprise AI"]
seo_title: "DeepSeek Harness vs Spectre: plugin o kernel?"
seo_description: "DeepSeek Harness rende tutto sostituibile tramite plugin. Spectre conserva un kernel governato. Un confronto su composizione, autorità, stato e recovery."
cover_alt: "Due architetture di Agent a confronto, una composta interamente da plugin e una costruita intorno a un kernel governato"
---

"Everything is a plugin" è una frase irresistibile per uno sviluppatore.

Promette libertà. Cambia il modello, cambia il registry dei tool, cambia il
database, cambia il loop. Se una scelta non ti piace, la sostituisci da
configurazione e continui a lavorare.

Poi l'Agent riceve accesso alla produzione e la domanda cambia:

> Se tutto è sostituibile, quale parte garantisce che alcune cose restino vere?

È il motivo per cui il nuovo
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) mi
interessa molto, ma la sua tesi architetturale non mi convince fino in fondo.
Non perché i plugin siano sbagliati. DeepSeek li usa in modo molto più serio di
quanto suggerisca lo slogan. Il punto è che un runtime operativo ha bisogno di
distinguere ciò che può variare dalle leggi che definiscono correttezza,
ownership e autorità.

Su questa distinzione, [Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2)
sceglie una strada quasi opposta.

DeepSeek Harness vuole rendere sostituibile il sistema.

Spectre vuole rendere governabile l'Agent.

Entrambe sono idee valide. Non sono però la stessa idea, e per un prodotto
enterprise preferisco nettamente la seconda.

## Una fotografia, non una sentenza definitiva

DeepSeek Harness è appena arrivato pubblicamente. Al momento della scrittura,
il suo [package principale](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/package.json)
dichiara `0.1.0-rc.5`, mentre il
[README](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/README.md)
lo definisce una developer preview e avvisa che arriveranno cambiamenti
incompatibili.

Quindi questo articolo non prova a decretare un vincitore eterno. Confronta due
decisioni architetturali visibili oggi.

Anche i prodotti sono diversi. DeepSeek Harness è un coding harness con profili
Web e headless, pensato per essere ricomposto dall'utente. Spectre è un runtime
Elixir incorporabile in applicazioni dove Agent, Work, Vigil, Policy ed Effect
devono sopravvivere oltre una singola interazione.

Il confronto interessante non è sulla quantità di feature. È sulla domanda:

> Dove deve vivere la costituzione di un sistema agentico?

## Cosa significa davvero "everything is a plugin"

Non è soltanto marketing. La
[documentazione architetturale](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/architecture.md)
afferma che modello, tool registry, session log e agent loop sono plugin
sostituibili da configurazione. Dice anche che non esiste un core privilegiato
da modificare.

Una configurazione DSH nasce come albero di plugin costruito a strati:

~~~text
base bundle
      +
profile bundles
      +
profile patch
      +
home patch
      +
CLI overlay
      |
      v
running Cordis tree
~~~

Ogni strato può sostituire la configurazione completa di una row oppure
inserirne una nuova. Il watcher delle patch può ricomporre l'albero mentre il
sistema gira. Le registrazioni dei plugin sono Effect reversibili, quindi
unload e teardown possono rimuoverle in modo prevedibile.

Questo è potente sul serio. Non è il solito array di callback chiamato
"plugin system" per rendere più elegante un README.

## Cordis è la parte che bisogna prendere sul serio

Sotto DSH c'è [Cordis](https://github.com/cordiverse/cordis), un meta-framework
per quella che i suoi autori chiamano composabilità spaziotemporale. Il
[paper](https://github.com/cordiverse/paper) separa due problemi:

- composabilità temporale, cioè poter rimuovere un componente e invertire i
  suoi effetti sul contesto;
- composabilità spaziale, cioè dichiarare dipendenze e reagire quando i servizi
  disponibili cambiano.

Nel concreto, un plugin dichiara dipendenze con `inject`, trova servizi tramite
chiavi tipizzate nel `ctx`, registra Effect reversibili e comunica con eventi
tipizzati. Gli eventi possono essere `emit`, `parallel`, `serial` o
`waterfall`.

Il
[primer di Cordis](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/cordis-primer.md)
spiega bene la semantica di una waterfall. Un listener riceve la richiesta e
`next()`. Può modificarla e delegare al listener successivo, oppure non
chiamare `next()` e chiudere la catena con la propria decisione.

Questa non è estensibilità casuale. Ci sono dependency injection dichiarata,
servizi tipizzati, teardown, scoping e contratti di dispatch. DSH usa Cordis
con notevole disciplina.

Ed è proprio per questo che il disaccordo è interessante. Non sto criticando
un'implementazione ingenua. Sto discutendo il limite di un'idea implementata
bene.

## DeepSeek ha già incontrato i problemi degli Agent seri

Appena un Agent può usare tool reali, la sola componibilità non basta. La
documentazione di DSH mostra che il progetto lo sa.

La sua
[pipeline dei tool](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/tool-execution-pipeline.md)
non esegue semplicemente ciò che il modello richiede. Il percorso comprende:

~~~text
persisted tool/call
      |
tools/pre-execute waterfall
      |
approval, when required
      |
monotonic guards
      |
tools/execute waterfall
      |
tool body
      |
tools/post-execute waterfall
      |
finalizeContent
      |
immutable tools/result
      |
persisted tool/result
~~~

Le guard monotone possono negare o astenersi, ma una decisione di deny non
viene trasformata in allow da un listener successivo. Se l'approvazione non è
disponibile, il percorso fallisce chiuso. L'esito finale osservato è congelato
e autorevole per quella pipeline.

Anche la
[Session](https://github.com/deepseek-ai/deepseek-harness/blob/47f943859bef60e4160492346772ded9b24f765a/docs/subsystems/session.md)
è progettata seriamente. È un log append-only di eventi tipizzati e la history
del modello viene derivata dal log, non mantenuta in una seconda copia. Gli
input visibili al modello, i chunk, i messaggi, le chiamate ai tool e i loro
risultati sono ricostruibili. La persistenza aggiunge revisioni, validazione,
riparazione delle code troncate e chiusura esplicita di Turn interrotti.

Quindi no, DeepSeek Harness non è un loop fragile con un marketplace attaccato
sopra. Ha contratti, recovery e mitigazioni che molti framework non hanno.

Ma quelle mitigazioni rendono visibile anche il paradosso.

Per costruire un sistema dove tutto è un plugin, DSH ha dovuto reintrodurre
guard monotone, esiti immutabili, ownership dei servizi, log durevoli e punti
di decisione che si comportano quasi come un kernel.

## Il problema non è il plugin, è il comportamento emergente

Una waterfall isolata è comprensibile. Dieci plugin isolati sono
comprensibili. Il comportamento della composizione completa può esserlo molto
meno.

In DSH il comportamento effettivo deriva da qualcosa di simile a questo:

~~~text
behavior =
    plugin tree
  + layer order
  + rows replaced by patches
  + active Context dependencies
  + listeners and their order
  + waterfall short circuits
  + selected providers
  + runtime state
~~~

L'ordine non è sempre una fragilità. `inject` elimina molta sequenza manuale e
le guard monotone proteggono decisioni locali. Il problema è il carico di
ragionamento globale.

Per sapere perché un tool è stato eseguito, non basta leggere il tool. Bisogna
sapere quale profilo è partito, quali bundle lo compongono, quali patch hanno
sostituito le row, quali listener erano attivi, chi ha chiamato `next()`, chi ha
chiuso la waterfall e quale provider possedeva il servizio in quel momento.

Per un coding harness controllato dal suo utente, questo può essere un prezzo
ragionevole. Anzi, può essere proprio la feature.

Per un runtime incorporato in un prodotto aziendale, la stessa libertà diventa
un costo di verifica.

## Un core di default non è ancora una costituzione

La documentazione DSH usa comunque l'espressione "core packages" per Session,
system prompt, tools, Agent e agent loop. Non è una contraddizione. Sono la
spina dorsale della composizione fornita da DeepSeek.

Ma il documento architetturale precisa che anche questi componenti sono plugin
e che qualunque row mostrata da `--dump-config` può essere sostituita da una
patch.

Quindi "core" indica ciò che la distribuzione monta normalmente. Non indica
necessariamente una costituzione che ogni composizione conforme deve
preservare.

La guard monotona è un ottimo esempio. Dentro la pipeline standard, un deny è
monotono. Ma la promessa più ampia del sistema resta la sostituibilità della
pipeline, del registry e del loop che la usa.

Non sto dicendo che una patch possa segretamente superare ogni controllo. Sto
dicendo che la proprietà di sicurezza dipende dalla composizione effettivamente
avviata. È una scelta legittima, ma obbliga il deployment a dimostrare che la
propria plugin tree conserva le invarianti attese.

In Spectre la domanda è formulata diversamente: quali invarianti non devono
dipendere da quella composizione?

## Spectre mette alcune leggi nel kernel

L'[architettura di Spectre](https://github.com/elchemista/spectre/blob/0.3.2/docs/ARCHITECTURE.md)
separa decisione conversazionale e autorità applicativa. Il modello può
classificare, ragionare e proporre lavoro. Solo lifecycle e Policy
deterministiche possono rendere quel lavoro eseguibile.

Il percorso costituzionale ha questa forma:

~~~text
Definition
    |
    v
Instance, owner of AgentRef + Subject
    |
    v
Run / Lifecycle / Policy
    |
    v
Effect or Invocation
    |
    v
host application authority
~~~

Attorno a questa catena possono cambiare modello, memoria, percezione,
planning, canale, trasporto e mission planner. Non possono però diventare
proprietari alternativi dello stato canonico.

Una Definition è immutabile e content-addressed. L'Instance è l'unico owner
locale dello stato per una coppia `AgentRef + Subject`. I Run conservano
identità e continuità. I Runner temporanei eseguono operazioni lente, ma non
possiedono lo stato canonico e non decidono retry semantici.

Quando un risultato torna, l'Instance controlla loop id, attempt id, epoch,
fencing token, context revision, control generation e trigger generation prima
di applicarlo. Un risultato valido per un mondo ormai superato viene scartato.

Queste non sono feature opzionali. Sono le leggi della fisica di quel runtime.

## Stato canonico: log della sessione e Instance non sono la stessa cosa

DSH fa una scelta molto buona: la Session append-only è la fonte di verità
dell'interazione e la history viene derivata da essa. Per un coding harness è
una base forte. Resume, fork, UI e persistenza possono leggere lo stesso
vocabolario di eventi.

Spectre affronta un dominio differente. Un'Instance può possedere più Run e
sezioni tipizzate per Flow, Work, Vigil, controller, inferenza, controllo e
Receipt outbox. Ogni cambiamento accettato avanza revisioni precise. Un
checkpoint ambiguo blocca ulteriori scritture automatiche finché la
riconciliazione non prova lo stato durevole.

Il suo flusso operativo è quindi:

~~~text
Instance creates a fenced snapshot and Attempt
      |
temporary Runner performs one operation
      |
Progress or Result returns to the Instance
      |
validate -> reduce -> commit
~~~

Non direi che la Session DSH sia debole. Direi che risponde alla domanda
"qual è la storia canonica di questa interazione?".

L'Instance Spectre risponde anche a un'altra domanda: "chi può ancora cambiare
lo stato operativo di questo Agent dopo concorrenza, restart, revoca e update?".

Per Agent long-running, quella domanda diventa decisiva.

## Cognizione non è autorità

Questa è la separazione più importante di Spectre:

~~~text
model proposes an Action
      |
Effect is staged
      |
deterministic Policy requests or denies authority
      |
approval is committed
      |
host rechecks authorization and credentials
      |
Effect is executed
      |
terminal outcome is committed
~~~

Approvazione ed esecuzione sono commit separati. Uno schema valido prova la
forma degli argomenti, non l'autorità. Un idempotency key permette
all'applicazione di deduplicare, ma non finge che un provider esterno sia
exactly-once. Se una scrittura potrebbe essere avvenuta, l'esito può restare
ambiguo invece di autorizzare un retry creativo.

DeepSeek Harness possiede una robusta pipeline di permission e approval. La
differenza non è "DSH esegue alla cieca, Spectre no". Sarebbe falso.

La differenza è ontologica. In Spectre l'autorità appartiene esplicitamente a
Definition, Lifecycle, Policy ed host. Il modello e le estensioni possono
contribuire cognizione senza salire sopra quella catena.

## Lo Stack di Spectre è un compromesso più stretto

Spectre non rifiuta la composizione. Il suo
[Stack](https://github.com/elchemista/spectre/blob/0.3.2/docs/STACK.md)
installa pacchetti, verifica dipendenze, conflitti e ownership, e produce
riferimenti chiusi con digest immutabili.

Puoi integrare Prism, Kinetic, Mnemonic, Lens, Directive, Beam, Pulse, Ledger,
Lab e adapter host. Core non deve conoscere i loro client, processi o
credenziali. Alcuni pacchetti possono consumare contratti di altri pacchetti,
ma non diventano un secondo runtime canonico.

La regola decisiva è:

> installato non significa autorizzato.

Installare una capability dichiara che esiste nell'ambiente. Non la rende
automaticamente visibile al planner, disponibile a ogni Flow o eseguibile senza
Policy. Binding, protezione e autorizzazione restano decisioni separate.

Per me questo è il compromesso corretto:

> Tutto ciò che può variare ha un confine di estensione esplicito. Tutto ciò che
> definisce correttezza resta nel kernel.

Non "everything is a plugin", ma nemmeno "niente è sostituibile".

## Un guasto concreto mostra la differenza

Immaginiamo un Agent che può approvare un rimborso. Il provider accetta
l'operazione, poi la connessione cade prima della risposta.

In entrambi i sistemi possiamo costruire logging, approval e persistenza. La
domanda architetturale è dove vive la regola che impedisce una seconda
esecuzione non provata.

In un harness universalmente componibile, quella proprietà emerge dal registry
attivo, dalla pipeline del tool, dalle guard registrate, dalla persistenza e
dalla configurazione avviata. La composizione deve conservare l'intera catena.

In Spectre, il lifecycle dell'Effect, la separazione tra approval ed execution,
l'esito ambiguo e il fencing del Run appartengono al runtime. L'host deve ancora
implementare vera idempotenza e riconciliazione sul provider di pagamento, ma
un adapter non può semplicemente mutare lo stato canonico e dichiarare il
problema risolto.

Spectre non elimina la responsabilità dell'applicazione. Le dà un punto preciso
in cui esistere.

## Confronto architetturale

| Tema | DeepSeek Harness | Spectre 0.3.2 |
| --- | --- | --- |
| Obiettivo principale | Coding harness ricomponibile | Runtime governato incorporabile in un prodotto |
| Unità di composizione | Albero Cordis di plugin, bundle e patch | Definition e Stack sopra un kernel deterministico |
| Agent loop | Plugin sostituibile | Run e Runtime costituzionali, con extension boundary |
| Stato principale | Session event log append-only | Instance canonica per AgentRef + Subject, con più domini e Run |
| Estensione | Servizi, eventi, waterfall ed Effect reversibili | Callback, provider, Stack Ref e package manifest |
| Ordine | Layer e listener partecipano al comportamento | Ordine limitato ai confini dichiarati, lifecycle centrale |
| Tool safety | Pre, approval, guard monotone, execute, post, final outcome | Action catalog, schema, Policy, Effect lifecycle, host authority |
| Recovery | Persistenza e riparazione della Session | Revisioni, CAS, ambiguity fence, Attempt ed epoch fencing |
| Hot replacement | Obiettivo centrale di Cordis | Deliberatamente limitato da Definition, generazioni e digest |
| Installazione | Una row può cambiare la composizione | Installazione non concede autorità |
| Punto forte | Massima adattabilità dell'harness | Ragionabilità del runtime sotto concorrenza e failure |

La tabella non dice che una colonna sia universalmente migliore. Dice che le
due architetture ottimizzano costi diversi.

## Dove DeepSeek Harness è probabilmente migliore

Se voglio costruire un laboratorio per Agent di coding, DSH è estremamente
attraente.

Posso sostituire il loop, cambiare session implementation, montare un provider
di filesystem remoto, cambiare sandbox, aggiungere una UI, creare un profilo
headless e sperimentare con middleware che intercettano ogni fase. Cordis rende
reload e teardown parte del modello invece di lasciarli a convenzioni sparse.

Per ricerca, hacker tool, shell personalizzabile e piattaforme dove l'utente
deve poter ricomporre quasi tutto, DeepSeek Harness può essere superiore a
Spectre.

Non copierei però quella priorità dentro Spectre. Rendere sostituibile il Run
reducer o l'ownership dell'Instance non aggiungerebbe libertà utile al suo
obiettivo. Renderebbe la correttezza una proprietà emergente della
configurazione.

## Composable harness e governed runtime

La distinzione di posizionamento può essere semplice:

~~~text
DeepSeek Harness
Composable agent harness

Spectre
Governed agent runtime
~~~

DeepSeek Harness dice: sostituisci tutto.

Spectre dovrebbe dire: estendi tutto ciò che può cambiare, proteggi ciò che
deve restare vero.

Il primo messaggio è ideale quando chi usa il sistema è anche chi ne ricompone
l'architettura. Il secondo è più interessante quando l'Agent entra in una
banca, un SaaS, un ERP, un sistema industriale, un workflow finanziario o un
customer operation center.

In quei contesti non basta sapere che esiste un plugin di approval. Bisogna
sapere chi possiede l'autorità quando quel plugin, il provider, il Runner, il
database o la rete falliscono.

## La parte più interessante del nuovo Harness

DeepSeek ha involontariamente rafforzato una tesi centrale di Spectre.

Per costruire Agent seri, anche un progetto fondato sulla sostituibilità totale
ha dovuto introdurre esiti immutabili, log durevoli, guard monotone, recovery,
eventi tipizzati, ownership e approval esplicita.

Non è una sconfitta di DSH. È la prova che il problema reale non è collegare un
modello a un tool. Il problema è mantenere proprietà verificabili mentre
componenti probabilistici e sistemi esterni falliscono.

DeepSeek prova a ottenere quelle proprietà dentro una composizione
universalmente modificabile.

Spectre dice che alcune di quelle proprietà sono il kernel.

Per un coding harness scelgo volentieri la libertà di smontare la macchina.

Per un Agent operativo scelgo un sistema dove posso cambiare muscoli, sensi e
memoria, ma non sostituire per errore le leggi della fisica.

È per questo che "everything is a plugin" non mi convince come costituzione di
un runtime enterprise. Non perché offre troppa estensibilità, ma perché tratta
la sostituibilità come valore superiore alla permanenza di alcune invarianti.

La domanda finale non è quanti plugin posso installare.

È molto più semplice:

> Chi possiede l'autorità quando tutto il resto può fallire?

In Spectre la risposta è deliberatamente difficile da sostituire.
