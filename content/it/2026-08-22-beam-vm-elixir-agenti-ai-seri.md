---
title: "BEAM non è nata per l'AI, ma sembra fatta apposta per gli agenti seri"
slug: "beam-vm-elixir-agenti-ai-seri"
lang: "it"
status: published
date: 2026-08-22
updated: 2026-08-22
category: "Sviluppo software"
tags: ["BEAM VM","Elixir","Erlang","OTP","AI agents","fault tolerance","concurrency","Spectre"]
seo_title: "BEAM VM ed Elixir per agenti AI affidabili"
seo_description: "La BEAM non è nata per l'AI, ma processi isolati, supervision, message passing e OTP la rendono una base ideale per agenti e sistemi AI seri."
cover_alt: "Un Agent AI eseguito come insieme di processi Elixir supervisionati sulla BEAM VM"
---

Quando si parla di intelligenza artificiale, la scelta tecnologica sembra quasi
automatica.

Python per il modello. CUDA per la GPU. Un server di inferenza, qualche API e
un framework che mette insieme prompt e tool.

Ha perfettamente senso se il problema che stiamo guardando è addestrare o
servire un modello. Ma un Agent serio non coincide con il modello che utilizza.
Il modello è soltanto uno dei suoi componenti e, spesso, nemmeno quello che
rimane attivo più a lungo.

Un Agent esiste prima della chiamata al modello e deve continuare a esistere
dopo. Riceve messaggi, conserva stato, aspetta risposte dalla rete, avvia
lavori, gestisce timeout, coordina tool, chiede approvazioni, produce effetti e
deve sapere cosa fare quando una di queste operazioni fallisce.

La parte difficile comincia proprio quando la demo del prompt finisce.

Ed è qui che una macchina virtuale nata decenni prima dell'attuale ondata di AI
diventa sorprendentemente moderna.

La BEAM non è stata progettata per i Large Language Model. Erlang nacque in
Ericsson e [Erlang/OTP fu costruito e collaudato per applicazioni distribuite e
tolleranti ai guasti](https://www.erlang.org/about), in un mondo dove una parte
del sistema poteva cadere senza interrompere tutto il servizio.

Non era intelligenza artificiale. Erano telecomunicazioni.

Ma il problema aveva già una forma familiare: moltissime attività concorrenti,
stato che vive nel tempo, comunicazione asincrona, rete inaffidabile, errori
parziali e necessità di recuperare senza spegnere l'intero sistema.

È difficile immaginare una descrizione più vicina a un runtime moderno per
agenti.

## Un Agent non è una funzione

Molti esempi di agenti iniziano con una funzione che riceve una stringa, chiama
un modello e restituisce una risposta.

È un ottimo modo per spiegare il primo esempio. Diventa però un modello mentale
pericoloso quando il sistema cresce.

Immaginiamo un Agent che sta analizzando documenti per un cliente. Nel
frattempo riceve una nuova istruzione, una chiamata al modello comincia a
produrre token in streaming, un tool esterno va in timeout e una policy richiede
l'approvazione di una persona. Un altro lavoro pianificato deve partire tra
dieci minuti, mentre quello precedente deve poter essere sospeso o annullato.

Questa non è più una funzione. È un piccolo sistema concorrente.

~~~text
Agent Instance
  ├── conversazione e stato
  ├── Run attivo
  ├── Work o Vigil in background
  ├── Invocation verso un modello
  ├── Effect in attesa di policy
  └── timer, messaggi e notifiche
~~~

Non significa che ogni voce debba sempre corrispondere a un processo distinto.
Significa che esistono proprietari, lifecycle e failure domain differenti.

La BEAM ci offre un modo naturale per rappresentarli senza trasformare tutto in
callback annidate, thread condivisi o una collezione di record in un database
che qualche worker deve continuamente interpretare.

## I processi BEAM sono confini di ownership

Un processo Erlang non è un processo del sistema operativo. È un'entità molto
più leggera, gestita direttamente dalla VM. La documentazione ufficiale
descrive i [processi Erlang come leggeri e adatti a sistemi con quantità molto
elevate di processi concorrenti](https://www.erlang.org/doc/system/eff_guide_processes.html).

Ogni processo possiede il proprio stato e la propria mailbox. A livello del
modello di programmazione, comunica con gli altri attraverso messaggi invece
di modificare direttamente la loro memoria.

Questo cambia profondamente il modo in cui possiamo costruire un Agent.

Un'istanza può possedere lo stato canonico di uno specifico Agent e di uno
specifico Subject. Le richieste arrivano come messaggi. Un lavoro temporaneo
può essere avviato sotto un altro processo. Il proprietario riceve il risultato
e decide se è ancora valido prima di applicarlo.

Non abbiamo soltanto concorrenza. Abbiamo un confine chiaro intorno alla
domanda più importante di un sistema stateful:

> Chi possiede questo stato e chi può modificarlo?

In Elixir, [`GenServer`](https://hexdocs.pm/elixir/GenServer.html) fornisce una
forma standard per costruire questi proprietari. Può mantenere stato, ricevere
chiamate sincrone e messaggi asincroni, gestire timeout, partecipare a una
supervision tree ed essere osservato con strumenti comuni.

Naturalmente non bisogna mettere qualsiasi funzione dentro un GenServer. La
stessa documentazione di Elixir avverte che un processo deve modellare una
proprietà runtime, come stato mutabile, concorrenza o fallimento, non essere
usato soltanto per organizzare codice.

Un Agent long-running possiede esattamente queste proprietà. Non stiamo
inventando processi perché ci piace OTP. Stiamo dando una forma esplicita a
qualcosa che nel sistema esiste già.

## La supervision cambia il modo di pensare agli errori

Un provider LLM può andare in timeout. Un parser può ricevere una risposta
incompleta. Un'integrazione può restituire dati non validi. Un processo che
gestisce uno stream può terminare mentre l'utente sta inviando una nuova
istruzione.

In molti runtime, la gestione di questi casi viene dispersa tra `try`, retry,
callback e code di messaggi. Con OTP, il fallimento è una parte dichiarata
dell'architettura.

Un [Supervisor](https://hexdocs.pm/elixir/Supervisor.html) sa quali processi
deve avviare, fermare e riavviare. Una supervision tree descrive quali
componenti dipendono dagli altri e quale parte deve essere ricostruita quando
qualcosa termina in modo anomalo. Un
[`DynamicSupervisor`](https://hexdocs.pm/elixir/DynamicSupervisor.html) può
gestire figli creati su richiesta, mentre un
[`Task.Supervisor`](https://hexdocs.pm/elixir/Task.Supervisor.html) permette di
isolare lavori temporanei senza lasciarli fuori dal lifecycle
dell'applicazione.

Questo non significa che "let it crash" voglia dire ignorare gli errori.
Significa separare il codice che svolge il lavoro dal codice che decide come il
sistema deve recuperare. Il componente può fallire in modo chiaro. Il suo
supervisore contiene il danno e applica una strategia conosciuta.

Per gli agenti questa separazione è preziosa. Una chiamata difettosa al modello
non dovrebbe abbattere tutte le conversazioni. Un Work fallito non dovrebbe
corrompere l'Instance che lo ha avviato. Un adapter esterno instabile non
dovrebbe diventare il proprietario implicito del lifecycle dell'Agent.

Ma anche qui bisogna essere precisi: riavvio non significa recovery.

Un Supervisor può far ripartire un processo, ma non può inventare lo stato che
non abbiamo salvato. Durabilità, checkpoint, idempotenza e riconciliazione
rimangono responsabilità dell'architettura applicativa.

La BEAM fornisce il meccanismo per contenere il guasto. Un runtime serio deve
anche sapere da quale verità durevole ripartire.

## Scheduling e garbage collection adatti alla concorrenza

Gli agenti passano moltissimo tempo ad aspettare.

Aspettano il provider del modello, il database, un'API, l'approvazione di una
persona, un messaggio dell'utente o il prossimo intervallo di un'attività
periodica. Il problema non è soltanto eseguire rapidamente una funzione. È
mantenere molte attività vive senza permettere a una di bloccare tutte le
altre.

La BEAM distribuisce i processi eseguibili tra più scheduler e usa un budget di
riduzioni per forzare il cambio di contesto dopo una quantità limitata di
lavoro. La VM è progettata affinché moltissimi processi possano avanzare senza
dipendere da un singolo event loop applicativo.

Anche la memoria segue la stessa filosofia. Erlang utilizza un
[garbage collector generazionale per processo](https://www.erlang.org/doc/apps/erts/garbagecollection.html).
Una raccolta della memoria riguarda normalmente il processo proprietario di
quell'heap, invece di imporre ogni volta una pausa globale a tutte le attività
dell'applicazione.

Per un runtime che ospita molte conversazioni e lavori indipendenti, questo è
un vantaggio strutturale. Un'Instance che crea molti dati temporanei non deve
necessariamente trascinare tutte le altre nella propria raccolta della memoria.

Non significa che la BEAM renda qualsiasi carico automaticamente veloce.
Significa che è stata ottimizzata per mantenere reattivo un sistema composto da
molte attività concorrenti, che è una descrizione molto più vicina a un sistema
di agenti che a un singolo benchmark numerico.

## Message passing come interfaccia di controllo

La comunicazione tra processi Erlang avviene tramite
[segnali e messaggi asincroni](https://www.erlang.org/doc/system/ref_man_processes.html).
Ogni processo riceve i messaggi nella propria mailbox e decide come
interpretarli.

Per un Agent questa non è soltanto un'implementazione interna. Può diventare il
linguaggio naturale del controllo operativo.

Un utente può inviare nuove informazioni mentre un Work è in esecuzione. Il
runtime può chiedere al lavoro di sospendersi, aggiornare il contesto e
riprendere. Un processo può monitorare un worker e ricevere un segnale quando
termina. Un timer può generare il prossimo passo di un Vigil. Un riferimento
unico può distinguere il risultato valido da una risposta tardiva appartenente
a un tentativo ormai sostituito.

La BEAM offre già mailbox, monitor, link, timer e identità di processo. Non
risolve automaticamente il protocollo, ma ci permette di costruirlo con
primitive che condividono la stessa semantica runtime.

Questa distinzione è importante. Una risposta tardiva di un modello non deve
essere applicata soltanto perché è finalmente arrivata. Deve appartenere
ancora al Run corretto, al tentativo corretto e alla revisione corretta.

La VM ci dà il trasporto e l'isolamento. Il runtime dell'Agent aggiunge fencing,
revisioni e regole di commit.

## Elixir rende questa macchina utilizzabile

La BEAM è la fondazione, ma Elixir rende piacevole costruirci sopra sistemi
complessi.

Pattern matching, dati immutabili, protocolli e pipeline permettono di
descrivere transizioni senza nascondere continuamente lo stato dentro oggetti
mutabili. Le macro consentono di creare DSL leggibili che a compile time
diventano strutture verificabili, invece di lasciare che il comportamento
esista soltanto dentro stringhe e configurazioni informali.

Questo è particolarmente utile per un Agent. Flow, policy, action e skill
possono essere letti come una mappa del comportamento, ma compilati in una
forma precisa che il runtime può ispezionare.

Elixir porta inoltre un ecosistema maturo per HTTP, database, telemetry,
streaming e interfacce realtime. Phoenix e LiveView possono mostrare lo stato
di un Agent mentre i processi che lo possiedono continuano a vivere fuori dal
ciclo di rendering della pagina.

E non è vero che Elixir debba rimanere completamente fuori dalla parte
numerica. [Nx](https://hexdocs.pm/nx/Nx.html) offre tensori e calcolo numerico,
mentre [`Nx.Serving`](https://hexdocs.pm/nx/Nx.Serving.html) permette di
organizzare inferenza e batching. EXLA, Axon e Bumblebee possono portare
classificatori, embedding e alcuni modelli direttamente nell'ecosistema BEAM.

Il punto, però, non è dimostrare che ogni modello debba essere eseguito in
Elixir.

Il punto è che Elixir può essere il control plane che coordina modelli locali,
GPU, servizi Python e provider remoti senza cedere a questi componenti la
proprietà dell'Agent.

## Dove la BEAM non è magia

Python e l'ecosistema CUDA rimangono la scelta dominante per addestrare grandi
modelli e sviluppare nuove architetture numeriche. Un calcolo pesante non
diventa improvvisamente economico perché viene avviato da un processo Elixir.

Lavoro CPU-bound prolungato, NIF scritte male e chiamate native bloccanti
possono danneggiare la reattività della VM. Questi carichi devono essere
spostati su dirty scheduler, porte, librerie native progettate con attenzione o
servizi separati. Anche una mailbox può crescere senza limite se il protocollo
non introduce backpressure e limiti.

La distribuzione tra nodi BEAM è potente, ma non sostituisce una strategia per
partizioni di rete, sicurezza, consistenza e deployment. E, come abbiamo visto,
una supervision tree non sostituisce un database o un checkpoint durevole.

Questi non sono argomenti contro la BEAM. Sono il motivo per cui è importante
distinguere la VM dall'architettura costruita sopra di essa.

La BEAM offre primitive straordinariamente adatte. Non prende al posto nostro
le decisioni di ownership, autorità, persistenza e recovery.

## Perché ho scelto Elixir per Spectre

È esattamente per questo che ho scelto Elixir per costruire
[Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2).

Non perché Elixir fosse il linguaggio più popolare nel mondo AI e nemmeno
perché volessi riscrivere in Elixir ciò che Python sa già fare bene.

L'ho scelto perché un modello è probabilistico, mentre il sistema che gli
concede stato e autorità non può essere soltanto probabilistico.

In Spectre, un'Instance possiede lo stato canonico. Run, Work, Vigil e
Invocation hanno lifecycle espliciti. Un Effect descrive un'azione, ma il
modello non la esegue. Una Policy decide deterministicamente quali passaggi
sono necessari e l'host conserva l'autorità finale.

Queste idee non sono state aggiunte nonostante OTP. Sono diventate naturali
proprio perché OTP spinge a chiedere chi possiede un processo, chi lo
supervisiona, come comunica e cosa succede quando fallisce.

La BEAM fornisce la fisica del sistema. Spectre prova a costruirci sopra le
leggi costituzionali di un Agent.

## La VM sotto il modello conta

La BEAM non è un framework AI. Ed è proprio questo a renderla così interessante
per l'AI.

Non prova a essere il modello, il database vettoriale, il provider o il tool.
Offre un ambiente in cui tutti questi componenti possono essere coordinati
senza diventare il centro incontrollato del sistema.

Il modello può cambiare. Il provider può fallire. Un tool può andare in
timeout. Un lavoro può essere annullato. L'Agent deve comunque conservare
identità, stato, lifecycle e autorità.

Python risponde molto bene alla domanda: come addestro ed eseguo questo
modello?

Elixir e la BEAM rispondono a un'altra domanda:

> Come faccio a tenere vivi molti sistemi intelligenti, concorrenti e
> imperfetti, lasciandoli fallire senza perdere il controllo dell'applicazione?

La BEAM non è nata per gli agenti AI.

Ma più seri diventano gli agenti, più sembra che li stesse aspettando da
sempre.
