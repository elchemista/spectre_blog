---
title: "Una skill non è un file Markdown: il ragionamento che mi ha portato a Spectre"
slug: "skill-non-e-file-markdown-come-e-nato-spectre"
lang: "it"
status: published
date: 2026-08-19
updated: 2026-08-19
category: "Sviluppo software"
tags: ["AI agents","skill","Spectre","Elixir","pattern recognition","routing","Morph","agent governance"]
seo_title: "Le skill oltre il Markdown: come è nato Spectre"
seo_description: "Le skill non sono solo istruzioni. Ecco come pattern, Flow, Journal, Ledger, Lab e Morph hanno formato il modo in cui Spectre apprende e cambia."
cover_alt: "Un pattern riconosciuto dal runtime Spectre diventa una skill governata attraverso Flow, Journal, Ledger, Lab e Morph"
---

Quando ho iniziato a pensare alla costruzione di un Agent, le skill esistevano
già.

Strumenti come Codex, Claude e altri sistemi agentici utilizzavano skill
costruite intorno a istruzioni in Markdown, a volte accompagnate da script,
tool e altre risorse. Il sistema riconosceva che una determinata skill poteva
essere utile, caricava le sue istruzioni nel contesto e lasciava che il modello
le applicasse.

Era un'idea semplice e potente. Senza addestrare nuovamente il modello, potevi
spiegargli come usare un tool, come seguire una procedura aziendale o come
affrontare una particolare categoria di problemi.

Eppure, mentre costruivo [Spectre](https://github.com/elchemista/spectre/tree/0.3.2),
continuavo a farmi una domanda:

> Il file Markdown è davvero la skill oppure è soltanto il manuale che descrive
> la skill?

Per provare a rispondere, sono partito da qualcosa che conosciamo da molto
prima dei Large Language Model: il modo in cui imparano gli esseri viventi.

## Prima dei modelli c'erano i pattern

Il cervello umano, come quello degli altri animali, si è evoluto per
riconoscere pattern.

Un animale non ha bisogno di conoscere scientificamente la forma, la velocità
e la traiettoria di un predatore. Gli basta riconoscere abbastanza segnali
simili a quelli incontrati in precedenza per attivare una risposta.

Anche noi funzioniamo continuamente in questo modo.

Quando impariamo a guidare, all'inizio dobbiamo pensare consapevolmente a ogni
movimento. Controlliamo lo specchietto, premiamo il pedale, cambiamo marcia e
osserviamo la strada come operazioni quasi separate. Dopo molta esperienza,
non ricostruiamo più ogni volta l'intera teoria della guida. Riconosciamo una
situazione e attiviamo una procedura che abbiamo già esercitato.

Succede la stessa cosa a un programmatore esperto. Davanti a un errore
familiare non legge ogni carattere come se fosse la prima volta. Riconosce la
forma del problema e comincia immediatamente a restringere il campo delle
possibili cause.

Il cervello non conserva soltanto una risposta pronta. Impara una relazione
tra una situazione, un possibile comportamento e il risultato ottenuto.

In modo molto semplificato, attraverso l'esperienza e la plasticità neurale
alcune connessioni vengono rafforzate, altre indebolite. La ripetizione,
l'errore e il feedback rendono progressivamente più facile attivare un
comportamento utile quando ricompare una situazione simile.

Per questo una skill umana non è semplicemente una risposta memorizzata. È la
capacità di riconoscere quando una procedura può essere utile, applicarla al
contesto presente e correggerla osservando il risultato.

Prima riconosciamo il pattern. Poi attiviamo il comportamento.

Questa idea è diventata importante per Spectre.

## Come impara un Large Language Model

Anche una rete neurale impara dai pattern, ma lo fa in modo diverso da un
cervello biologico.

Un Large Language Model è una rete neurale basata, nella maggior parte dei
casi moderni, sull'architettura Transformer. Durante l'addestramento riceve
enormi quantità di testo e modifica i propri parametri per diventare sempre
più bravo a prevedere quale token dovrebbe seguire quelli precedenti.

Può sembrare un obiettivo limitato, ma per prevedere bene il linguaggio il
modello deve apprendere una quantità enorme di regolarità. Deve riconoscere
strutture grammaticali, relazioni tra concetti, forme di ragionamento,
convenzioni del codice, stili di scrittura e procedure che ricorrono nei dati
di addestramento.

Queste conoscenze non vengono necessariamente conservate in blocchi separati.
Non esiste una cartella interna chiamata "skill per il meteo" o una singola
parte del modello dedicata a "scrivere codice Elixir". Le rappresentazioni e i
comportamenti emergono in modo distribuito tra moltissimi parametri.

L'attenzione permette al modello di stabilire quali parti dell'input siano
rilevanti rispetto alle altre. Le reti feed-forward presenti nei blocchi del
Transformer trasformano ulteriormente queste rappresentazioni. Non esiste
però un singolo attention head che possiamo accendere per attivare in modo
deterministico una skill.

Quando inseriamo una skill nel prompt, stiamo modificando il contesto che
guiderà l'elaborazione del modello. Le istruzioni influenzano le sue attivazioni
e quindi la distribuzione delle possibili risposte.

Questo significa che una skill in Markdown non insegna normalmente qualcosa
di nuovo ai pesi del modello. Gli mette temporaneamente un manuale sulla
scrivania.

Il modello legge quel manuale, prova a collegarlo alla richiesta e utilizza le
capacità apprese durante l'addestramento per eseguire la procedura descritta.

È un meccanismo estremamente utile. Possiamo cambiare una procedura senza
addestrare nuovamente il modello. Possiamo aggiungere esempi, introdurre nuovi
tool e fornire conoscenza specifica di un'azienda.

Ma rimane un manuale.

Il modello deve interpretarlo correttamente ogni volta.

Ed è proprio qui che il mio ragionamento ha iniziato a prendere una strada
diversa.

## Perché chiedere sempre tutto al modello?

Se un comportamento ricorrente nasce dal riconoscimento di un pattern, perché
lasciare che sia sempre il modello a riconoscere quel pattern?

Immaginiamo che un utente scriva:

> Che tempo fa a Como?

Possiamo inviare la frase a un LLM, chiedergli di capire l'intenzione,
lasciargli scegliere il tool corretto, eseguire una chiamata a un servizio
meteorologico e infine generare una risposta.

Funziona. Ma stiamo utilizzando un modello generale per riscoprire qualcosa
che il sistema potrebbe già sapere.

La richiesta contiene un pattern abbastanza semplice: l'utente vuole
conoscere il meteo in una determinata località.

Una regex può riconoscere alcune forme molto esplicite. Un classificatore può
individuare l'intenzione. La similarità vettoriale può collegare frasi
differenti allo stesso significato. Se la confidenza è sufficiente, il runtime
può chiamare direttamente l'API meteorologica e restituire una risposta
formattata.

Non serve necessariamente un LLM per dirci che 18 gradi sono 18 gradi.

Questa osservazione non nasce soltanto dal desiderio di risparmiare token. Se
eliminiamo una chiamata non necessaria otteniamo anche minore latenza, un
risultato più prevedibile e un comportamento molto più semplice da testare.

Naturalmente la situazione cambia se l'utente domanda:

> Considerando il meteo di Como, Milano e Lugano, quale sarebbe il giorno
> migliore per organizzare un evento all'aperto?

Qui il modello può essere realmente utile. Spectre può raccogliere i dati in
modo deterministico, strutturarli e passare al modello soltanto il compito che
richiede confronto, ragionamento e spiegazione.

Il punto non è scegliere tra codice e intelligenza artificiale.

Il punto è capire quale parte del problema richiede davvero il modello.

Questa riflessione ha portato alla nascita di `on` nei Flow di Spectre e a un
[routing basato prima di tutto sulle evidenze](https://github.com/elchemista/spectre/blob/0.3.2/docs/ROUTING.md).

~~~text
input
  ↓
riconoscimento del pattern
  ↓
Flow.on
  ├── comportamento deterministico
  ├── skill specializzata con un modello
  └── modello generale come fallback
~~~

Prima che tutto venga delegato a un LLM, Spectre può osservare l'input e
provare a riconoscere una situazione già conosciuta. Può farlo attraverso una
regola esplicita, una regex, un classificatore o una ricerca semantica.

Se il pattern è semplice e il comportamento è già definito, può eseguirlo
senza modello. Se serve ragionamento, può preparare una skill e un contesto
molto più precisi. Se la richiesta è nuova o ambigua, può passare il controllo
a un modello generale oppure chiedere un chiarimento.

Il modello non scompare.

Smette semplicemente di essere il componente obbligato a riscoprire tutto da
zero a ogni interazione.

## Le skill in Markdown diventano più forti

Non ho mai pensato che le skill in Markdown dovessero sparire.

Sono molto utili quando dobbiamo descrivere una procedura flessibile, insegnare
al modello come utilizzare uno strumento o fornirgli informazioni che non
erano disponibili durante l'addestramento.

Spectre aggiunge qualcosa attorno a quelle istruzioni.

Il runtime può stabilire quando una skill deve essere utilizzata, quale pattern
l'ha attivata, quale modello può eseguirla, quali tool può usare e quali azioni
richiedono un'autorizzazione.

La skill non viene più semplicemente aggiunta a un prompt sperando che il
modello la interpreti nel modo corretto. Diventa una capacità inserita
all'interno del comportamento dell'Agent.

Il Markdown può continuare a descrivere la parte cognitiva della procedura. Il
Flow ne definisce il momento di attivazione. Le policy ne delimitano
l'autorità. Il runtime ne osserva l'esecuzione.

In questo modo una skill non è più soltanto qualcosa che il modello ha letto.
È qualcosa che l'Agent sa quando e come utilizzare.

## Un sistema che impara dai casi reali

Le regex funzionano bene quando il linguaggio è molto prevedibile. Ma gli
esseri umani possono esprimere la stessa intenzione in modi completamente
diversi.

"Che tempo fa?", "Pioverà oggi?", "Mi serve l'ombrello?" e "Posso uscire senza
giacca?" potrebbero richiedere gli stessi dati, ma non condividono
necessariamente le stesse parole.

Qui la similarità semantica diventa interessante.

Spectre può conservare esempi già riconosciuti e confrontare un nuovo input
con i pattern conosciuti. Un amministratore può osservare come vengono
classificate le richieste, confermare i casi corretti e correggere quelli
sbagliati.

Con il tempo, il sistema raccoglie modi di esprimersi che non erano stati
previsti durante la costruzione iniziale dell'Agent e che potrebbero non essere
nemmeno comparsi nei dati di addestramento del modello.

Questo non richiede necessariamente un nuovo fine-tuning.

Possiamo migliorare il livello di riconoscimento esterno, aggiungere esempi,
correggere le soglie e rendere il routing progressivamente più preciso.

È una forma di apprendimento diversa. I pesi del modello non cambiano, ma
cambia la capacità operativa dell'Agent.

Il sistema impara a riconoscere meglio il proprio ambiente reale.

Ed è particolarmente importante per applicazioni aziendali, perché ogni
azienda sviluppa un proprio linguaggio. I clienti usano nomi interni,
abbreviazioni, modi ricorrenti di formulare problemi e richieste che nessun
modello generale può conoscere completamente in anticipo.

Spectre permette di trasformare questa esperienza locale in comportamento
esplicito.

## Riconoscere un pattern senza perdere il controllo

Naturalmente un classificatore può sbagliare. Una regex può essere troppo
rigida e due richieste semanticamente vicine possono avere intenzioni
operative molto diverse.

Ma questo non è un problema lasciato all'applicazione finale o qualcosa che
chi utilizza Spectre deve risolvere da zero.

Spectre è stato costruito considerando fin dall'inizio che il riconoscimento
di un pattern non è una verità assoluta. È un'evidenza accompagnata da una
determinata confidenza. Il router raccoglie candidati da fonti differenti e
l'arbitrator decide quale evidenza è abbastanza forte da diventare una route.

Per questo il runtime offre soglie di accettazione e di margine, gestione
esplicita dei conflitti e controllo sul percorso scelto. Se il riconoscimento
non è abbastanza sicuro, Spectre può evitare l'esecuzione deterministica,
chiedere un chiarimento oppure utilizzare un modello come arbitro finale tra
route già dichiarate.

Ma la parte più importante arriva dopo la decisione.

Il [Journal](https://github.com/elchemista/spectre/blob/0.3.2/docs/JOURNAL.md)
conserva record strutturati che spiegano ciò che è accaduto nel runtime. Può
registrare le evidenze raccolte, i punteggi, i margini, le soglie configurate,
la route selezionata e il motivo della decisione, mantenendo il contenuto della
conversazione escluso per impostazione predefinita.

[Spectre Ledger](https://github.com/elchemista/spectre_ledger) non duplica il
Journal e non pretende di registrare ogni revisione interna. Conserva in modo
append-only i checkpoint che Spectre persiste realmente e le boundary receipt
emesse quando il runtime attraversa confini non deterministici o di autorità.
Offre quindi una prova durevole di ciò che è stato salvato e dei confini che
sono stati attraversati.

[Spectre Lab](https://github.com/elchemista/spectre_lab) porta questi artefatti
in un ambiente di verifica e test isolato. Può caricare e confrontare
checkpoint e boundary receipt verificati, esercitare lo streaming con fixture
virtuali e iniettare errori controllati nei confini di persistenza e receipt.
Non finge di ricreare deterministicamente una vecchia risposta del modello o
un effetto esterno. Fornisce invece gli strumenti necessari per trasformare un
caso osservato in un test ripetibile senza aprire nuovamente l'I/O reale.

Spectre offre anche una valutazione del solo routing, che esegue la pipeline
senza caricare lo stato dell'Agent e senza eseguire l'handler vincente. Un caso
classificato male può così diventare una fixture di regressione prima che una
nuova configurazione venga promossa.

Quindi Spectre non prova a risolvere il problema fingendo che il
riconoscimento sia infallibile.

Lo risolve rendendo la decisione spiegabile, l'evidenza persistibile e il caso
verificabile.

È una differenza fondamentale. Un errore che possiamo isolare e ripetere può
diventare un test. Un errore nascosto dentro una conversazione rimane soltanto
una conversazione andata male.

## Da molti casi a una nuova capacità

A questo punto è nata una nuova domanda.

Cosa succede quando un pattern continua a ripetersi?

All'inizio un modello generale può gestire una richiesta nuova. Poi Spectre
osserva che casi simili compaiono frequentemente. L'amministratore comincia a
riconoscerli, li corregge e scopre che quasi sempre portano alla stessa
procedura.

A quel punto non stiamo più osservando semplicemente una serie di
conversazioni. Stiamo osservando la nascita di una nuova skill.

È da questo ragionamento che nasce
[Morph](https://github.com/elchemista/spectre/blob/0.3.2/lib/spectre/morph.ex).

Morph può aiutare un host fidato a trasformare un pattern ricorrente in una
capacità candidata. Il pattern, la procedura e il risultato atteso possono
essere analizzati, testati e infine promossi all'interno di una nuova versione
dell'Agent.

Questa idea assomiglia in parte all'evoluzione naturale.

In natura, le caratteristiche che funzionano meglio in un determinato
ambiente hanno maggiori probabilità di essere conservate. Nel caso di Spectre,
però, l'evoluzione non deve essere cieca e incontrollata.

È osservata e guidata.

Il modello o Forge possono individuare una regolarità e produrre una proposta
inerte. Morph può accompagnare quella modifica attraverso valutazione,
revisione, approvazione e attivazione. Ma la promozione rimane un atto
esplicito, autorizzato dall'host.

La nuova capacità entra in una nuova Definition immutabile dell'Agent. La
versione precedente non viene cancellata e rimane disponibile per il confronto
o il rollback.

Questo significa che l'Agent può evolversi senza perdere la propria storia e
senza concedere al modello l'autorità di riscrivere liberamente se stesso.

L'esperienza non diventa semplicemente un prompt sempre più lungo.

Diventa un pattern riconoscibile e un comportamento versionato.

## Cosa sono quindi le skill?

Dopo aver seguito questo percorso, sono arrivato a una definizione diversa da
quella da cui ero partito.

Una skill non è il file Markdown.

Il Markdown è una possibile rappresentazione della procedura, esattamente come
un manuale è una rappresentazione di qualcosa che una persona può imparare a
fare.

La skill completa nasce quando un sistema sa riconoscere la situazione
corretta, attivare la procedura, rispettare i limiti dell'autorità, osservare il
risultato e utilizzare quell'esperienza per migliorare.

Il modello porta la capacità di generalizzare e ragionare. Spectre porta il
lifecycle, il controllo, la memoria operativa e la possibilità di trasformare
casi reali in comportamenti espliciti.

Non voglio costruire un Agent che invia ogni problema a un modello generale e
spera che interpreti correttamente un manuale sempre più grande.

Voglio costruire un Agent che sappia distinguere ciò che conosce già da ciò
che richiede davvero ragionamento.

Quando il pattern è semplice, può rispondere attraverso un comportamento
deterministico. Quando il problema richiede intelligenza, può attivare la skill
e il modello corretti. Quando incontra qualcosa di nuovo, può imparare
dall'esperienza senza modificarsi fuori dal controllo umano.

Per me è questa la direzione più interessante.

Una skill non è ciò che abbiamo scritto per il modello.

È ciò che l'Agent ha imparato a riconoscere, sa eseguire e può continuare a
migliorare senza perdere il controllo.
