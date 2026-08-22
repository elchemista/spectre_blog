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
seo_description: "La BEAM non è nata per l'AI, ma processi isolati, supervision, messaggi e OTP la rendono una base ideale per agenti e sistemi AI seri."
cover_alt: "Un Agent AI eseguito attraverso processi Elixir supervisionati sulla BEAM VM"
---

Quando ho iniziato a costruire Spectre, scegliere Elixir per un progetto legato
all'intelligenza artificiale sembrava quasi una provocazione.

Nel mondo AI il percorso più comune è già tracciato. Si parte da Python, si
arriva a CUDA quando serve una GPU e si aggiunge un server per esporre il
modello. Elixir compare raramente in questa conversazione. Quando compare, di
solito qualcuno domanda perché complicarsi la vita usando un linguaggio che
non si trova al centro dell'ecosistema del machine learning.

All'inizio è una domanda legittima. Se dovessi addestrare un nuovo Large
Language Model, probabilmente non sceglierei Elixir come primo strumento. Ma
mentre lavoravo a Spectre mi sono accorto che il modello era soltanto una parte
del problema. Era la parte più visibile, non necessariamente la più difficile.

Un Agent reale deve continuare a esistere quando la chiamata al modello è
finita. Deve ricordare in quale stato si trova, ricevere nuove istruzioni,
aspettare servizi esterni, fermare un lavoro, riprenderlo e capire se una
risposta arrivata in ritardo è ancora valida. Se può compiere azioni, deve
anche sapere chi ha il diritto di autorizzarle e cosa fare quando qualcosa
fallisce a metà.

A quel punto la domanda non è più soltanto quale modello usare. La domanda
diventa quale tipo di sistema vogliamo costruire intorno al modello.

Ed è proprio lì che Elixir e la BEAM hanno cominciato a sembrarmi non una
scelta insolita, ma una scelta quasi ovvia.

## Il momento in cui un Agent smette di essere una funzione

Immaginiamo un Agent che sta analizzando alcuni documenti per un cliente. Ha
già avviato una ricerca, il modello sta producendo una risposta e un servizio
esterno impiega più tempo del previsto. Nel frattempo il cliente invia un
nuovo messaggio e aggiunge un dettaglio importante che cambia il senso del
lavoro.

L'Agent dovrebbe poter ricevere quel messaggio senza aspettare che tutto il
resto finisca. Potrebbe dover sospendere la ricerca, aggiornare il contesto e
riprendere da un punto coerente. Se nel frattempo arriva la vecchia risposta
del servizio esterno, non dovrebbe applicarla ciecamente soltanto perché è
arrivata.

In una demo possiamo rappresentare tutto con una funzione che riceve una
stringa e restituisce una risposta. In un prodotto vero quella funzione si
trasforma presto in un insieme di attività che vivono nello stesso momento.
Alcune durano pochi secondi, altre possono rimanere attive per ore. Alcune
aspettano la rete, altre aspettano una persona. Ognuna può fallire senza che
per questo debba sparire l'intero Agent.

Questa forma del problema mi ricordava molto meno una semplice applicazione AI
e molto più un sistema concorrente.

La cosa interessante è che la BEAM è nata per affrontare un problema simile
molto prima che parlassimo di agenti. Erlang fu sviluppato in Ericsson per
costruire sistemi che dovevano rimanere disponibili anche quando una loro
parte smetteva di funzionare. In seguito Erlang e OTP sono stati usati per
applicazioni distribuite e tolleranti ai guasti in cui fermare tutto non era
una soluzione accettabile. La [storia ufficiale di Erlang](https://www.erlang.org/about)
nasce dalle telecomunicazioni, non dall'intelligenza artificiale.

Eppure le telecomunicazioni avevano già molte delle difficoltà che oggi
ritroviamo negli agenti. Esistevano tante attività contemporanee, messaggi che
potevano arrivare in momenti diversi, stato che doveva vivere nel tempo e
guasti che non potevano propagarsi ovunque.

Il nome del problema è cambiato. La sua forma, molto meno.

## Un processo piccolo può dare un confine enorme

La prima cosa che colpisce della BEAM è il suo modo di trattare i processi.

Un processo Erlang non è un pesante processo del sistema operativo. È una
piccola unità gestita dalla macchina virtuale, con una propria identità, uno
stato e una casella in cui riceve messaggi. La documentazione di Erlang spiega
che questi [processi sono leggeri e pensati per esistere in grandi quantità](https://www.erlang.org/doc/system/eff_guide_processes.html).

La parte importante, almeno per me, non è soltanto quante migliaia di processi
possiamo avviare. È il confine che ogni processo crea.

Se un processo possiede lo stato di un Agent, gli altri componenti non entrano
dentro quello stato per modificarlo quando vogliono. Gli inviano un messaggio.
Il proprietario riceve la richiesta, controlla se ha ancora senso e decide
come cambiare lo stato.

Questo rende molto concreta una domanda che in tanti sistemi rimane nascosta:
chi possiede davvero lo stato?

Con [`GenServer`](https://hexdocs.pm/elixir/GenServer.html), Elixir offre una
forma comune per costruire questo tipo di proprietario. Non serve trasformare
ogni funzione in un processo. Ha senso farlo quando qualcosa deve vivere nel
tempo, ricevere eventi, proteggere uno stato o rappresentare un confine di
fallimento. Un Agent che può essere interrotto, aggiornato e ripreso possiede
esattamente queste caratteristiche.

Un lavoro temporaneo può vivere in un altro processo. Se quel lavoro fallisce,
il processo che possiede l'Agent non deve perdere il proprio stato. Se il
lavoro termina correttamente, invia il risultato al proprietario, che può
ancora decidere se accettarlo. Questa separazione sembra un dettaglio tecnico,
ma cambia completamente il modo in cui si ragiona sul sistema.

Non stiamo più sperando che tutte le operazioni finiscano nel giusto ordine.
Stiamo assegnando a ogni parte una responsabilità chiara.

## Fallire senza trascinare tutto con sé

Prima o poi un provider del modello va in timeout. Una connessione si chiude
durante lo streaming. Un parser incontra una risposta che non si aspettava.
Non sono casi eccezionali. Sono il normale ambiente in cui vive un Agent.

OTP porta il fallimento dentro il disegno dell'applicazione. Un
[`Supervisor`](https://hexdocs.pm/elixir/Supervisor.html) conosce i processi
che gli sono affidati e sa come reagire quando uno di essi termina. Non siamo
costretti a spargere la stessa logica di recupero in ogni funzione. Possiamo
decidere in un punto chi deve essere riavviato e quale parte del sistema deve
rimanere intatta.

La famosa idea di lasciare che un processo fallisca viene spesso raccontata
male. Non significa ignorare gli errori. Significa evitare che un componente
mezzo rotto continui a nascondere uno stato incoerente. Il processo termina in
modo chiaro e il livello che lo supervisiona decide come ricostruirlo.

Naturalmente riavviare non significa recuperare tutto per magia. Se uno stato
importante non è mai stato salvato, un Supervisor non può inventarlo. Un
sistema serio ha ancora bisogno di checkpoint, operazioni che possano essere
ripetute senza produrre danni e una verità durevole da cui ripartire.

Però la BEAM ci dà qualcosa di prezioso ancora prima della persistenza. Ci
permette di contenere il guasto. Una chiamata al modello che fallisce non deve
abbattere tutte le conversazioni. Un'integrazione instabile non deve diventare
il centro da cui dipende la vita dell'Agent.

Quando molti agenti lavorano nello stesso sistema, questa proprietà smette di
essere elegante teoria e diventa sopravvivenza operativa.

## La concorrenza che serve davvero agli agenti

Gran parte della vita di un Agent viene trascorsa aspettando. Aspetta il
modello, una ricerca nel database, un'API, un nuovo messaggio o
l'approvazione di una persona. Mentre un Agent aspetta, gli altri devono poter
continuare a lavorare.

La BEAM distribuisce i processi pronti tra i suoi scheduler e misura il lavoro
attraverso le riduzioni. Dopo una quantità limitata di lavoro, un processo
lascia spazio agli altri. Non dobbiamo costruire manualmente un unico ciclo
applicativo dal quale dipende la reattività di tutto il sistema.

Anche la memoria segue un'idea simile. Erlang usa un
[garbage collector generazionale per ogni processo](https://www.erlang.org/doc/apps/erts/garbagecollection.html).
Quando un processo deve ripulire il proprio spazio, normalmente non impone la
stessa pausa a tutte le altre attività. Un Agent che ha creato molti dati
temporanei non deve necessariamente bloccare migliaia di conversazioni che non
c'entrano nulla.

Questo non rende la BEAM la macchina più veloce per ogni tipo di calcolo. Non è
quello il punto. Il suo talento è mantenere vivo e reattivo un sistema composto
da tantissime attività indipendenti. Per gli agenti è spesso molto più utile
di vincere un confronto su una singola funzione eseguita in isolamento.

Il passaggio di messaggi completa questa idea. Se un utente aggiunge una nuova
informazione mentre un lavoro è ancora attivo, il messaggio può raggiungere il
processo che possiede l'Agent. Un monitor può accorgersi che un lavoro è
terminato. Un timer può risvegliare un'attività periodica. Una risposta
arrivata tardi può essere confrontata con il tentativo che l'aveva generata e
scartata se quel tentativo non è più valido.

La BEAM non decide da sola le regole del nostro Agent. Ci offre però un
linguaggio runtime coerente per esprimerle. Stato, messaggi, tempo e fallimenti
non sembrano pezzi provenienti da sistemi differenti che dobbiamo incollare a
forza.

## Elixir rende questa macchina comprensibile

La BEAM è la base, ma Elixir è ciò che mi ha fatto desiderare di costruirci
sopra.

Il pattern matching rende leggibili molti passaggi che altrimenti diventano
una successione di controlli. I dati immutabili aiutano a vedere una
transizione come il passaggio da uno stato a un altro, invece di nascondere
modifiche in oggetti condivisi. Le macro permettono di creare un linguaggio
specifico per il problema senza ridurre tutto a stringhe dentro un prompt.

Per un Agent questa leggibilità conta molto. Un comportamento dovrebbe poter
essere letto dal programmatore. Dovrebbe essere chiaro quale evento lo attiva,
quale lavoro avvia e quale azione richiede autorità. Elixir consente di
scrivere codice che rimane vicino all'idea che descrive, ma continua a essere
codice verificabile dal runtime.

Poi c'è l'ecosistema. Elixir è già molto forte quando servono connessioni HTTP,
database, streaming, telemetria e interfacce in tempo reale. Con
[Nx](https://hexdocs.pm/nx/Nx.html) e
[`Nx.Serving`](https://hexdocs.pm/nx/Nx.Serving.html) può occuparsi anche di
tensori, inferenza e richieste raggruppate. Alcuni classificatori, embedding e
modelli possono quindi vivere direttamente nella BEAM.

Non credo però che il valore di Elixir dipenda dal sostituire Python. Python e
CUDA rimangono strumenti eccellenti per addestrare modelli ed eseguire calcoli
numerici pesanti. Elixir può coordinare un servizio Python, una GPU locale o
un provider remoto senza consegnare a nessuno di questi la proprietà
dell'Agent.

Anche la BEAM ha limiti reali. Un calcolo lungo che occupa la CPU può ridurre
la reattività. Una funzione nativa scritta male può bloccare scheduler che
dovrebbero servire altri processi. Una casella di messaggi può crescere troppo
se nessuno limita il ritmo dei messaggi in arrivo. La distribuzione tra
nodi non risolve automaticamente sicurezza, consistenza o problemi di rete.

Questi limiti non indeboliscono la scelta. La rendono più chiara. La BEAM è un
ambiente eccellente per gestire il lifecycle e coordinare il lavoro. Il calcolo
specializzato può rimanere dove viene eseguito meglio.

## Il motivo per cui Spectre è scritto in Elixir

È esattamente questo il ragionamento che mi ha portato a scegliere Elixir per
[Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2).

Non volevo costruire un altro contenitore intorno a un prompt. Volevo un
runtime in cui un Agent avesse un'identità, uno stato e un lifecycle che non
dipendessero dall'umore del modello. In Spectre una Instance possiede lo stato
canonico. I lavori possono essere avviati e osservati senza diventare i
proprietari dell'Agent. Un Effect può descrivere un'azione, ma è la Policy,
insieme all'host, a decidere se quella azione può davvero attraversare il
confine verso il mondo esterno.

Molte di queste idee sono nate pensando al controllo e alla sicurezza, ma OTP
ha dato loro una forma naturale. Continuava a riportarmi alle domande giuste.
Chi possiede questo stato? Chi supervisiona questo processo? Cosa succede se
il risultato arriva troppo tardi? Quale parte può fallire senza corrompere il
resto?

Quando penso oggi alla scelta di Elixir, non penso prima di tutto alla sintassi
o alle prestazioni. Penso al modo in cui la BEAM obbliga il sistema ad avere
confini visibili.

La BEAM non è nata per l'intelligenza artificiale. Non conosce prompt, modelli
o agenti. È nata per tenere vivi sistemi concorrenti mentre alcune loro parti
falliscono.

Ma appena un Agent smette di essere una demo e deve restare vivo davvero,
inizia ad avere esattamente quel problema.

Per questo Elixir, nel mondo degli agenti seri, mi sembra ogni giorno meno una
scelta strana e sempre più la scelta giusta.
