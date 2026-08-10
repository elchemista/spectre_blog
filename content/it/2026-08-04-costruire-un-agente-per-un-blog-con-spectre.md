---
title: "Costruire un agente per un blog con Spectre, non attorno a un loop magico"
slug: "costruire-un-agente-per-un-blog-con-spectre"
lang: "it"
status: published
date: 2026-08-04
updated: 2026-08-04
category: "Sviluppo software"
tags: ["Elixir","OTP","agenti AI","Spectre","runtime per agenti","blog basato su Git"]
seo_title: "Costruire un agente per un blog con Spectre"
seo_description: "Come ho costruito con Spectre un agente per un blog basato su Git, lasciando flessibile il ragionamento del modello e mantenendo espliciti flow, stato, pubblicazione e ripristino."
cover_alt: "Un agente per un blog costruito attorno a un runtime OTP esplicito, collegato a file Markdown, cronologia Git, ragionamento del modello e pubblicazione controllata"
---

Non ho costruito Spectre perché fosse difficile chiamare un LLM da Elixir.

Quella parte è facile. Invii una richiesta, passi alcuni messaggi, descrivi qualche funzione e aspetti che il modello restituisca una tool call.

Il problema inizia dopo la prima demo riuscita.

Dai un obiettivo al modello. Decide cosa fare dopo, chiama uno strumento, legge il risultato e decide di nuovo. Nel terminale sembra fantastico. Poi aggiungi memoria, tentativi, approvazione, lavoro in background e un'altra chiamata a un modello per giudicare se la prima chiamata ha fatto la cosa giusta.

In poco tempo, l'applicazione comincia a sembrare un involucro attorno a un unico grande loop intelligente.

Non ho nulla contro quell'intelligenza. Voglio che il modello comprenda richieste non rigide, legga documentazione, colleghi idee e prenda decisioni che sarebbe doloroso esprimere come regole ordinarie.

Ciò che mi infastidiva era perdere la forma del software attorno al modello.

Quando qualcosa era in esecuzione, volevo sapere che cosa fosse. Quando l'utente cambiava la richiesta, volevo aggiornare il lavoro invece di aggiungere un altro messaggio al contesto. Quando una chiamata esterna andava in timeout, volevo che l'applicazione ammettesse che il risultato era incerto. E quando il processo si riavviava, non volevo che il ripristino significasse chiedere al modello di ricostruire la situazione dalla trascrizione di una conversazione.

Volevo il modello, ma volevo anche il flow.

È per questo che esiste Spectre.

## Il blog che sto davvero costruendo

Il blog è volutamente semplice.

Gli articoli sono file Markdown. Git ne conserva la cronologia. L'applicazione li renderizza e li pubblica. C'è un solo agente editor, non un gruppo di agenti che finge di essere una piccola azienda editoriale.

Posso parlare con quell'agente tramite Telegram o un client MCP. Potrei chiedergli:

> Prepara un articolo sul nuovo runtime di Spectre. Prima leggi il repository, usa lo stesso tono degli altri post e lascialo come bozza.

Sembra una sola richiesta, ma non è un solo tipo di lavoro.

Una parte è conversazionale. L'agente deve capire cosa intendo e decidere come rispondere. Una parte è operativa. Leggere le fonti, raccogliere appunti e preparare una bozza può continuare oltre il messaggio iniziale. Pubblicare è ancora un'altra cosa: modifica il repository e non dovrebbe accadere solo perché il modello ritiene che l'articolo sia pronto.

Molti sistemi per agenti mettono tutto questo dentro lo stesso loop.

Spectre lo separa.

```text
Telegram o MCP
       │
       ▼
  Agente editor
       │
       ├── Flow: comprendere la conversazione
       │
       ├── Work: ricercare e preparare l'articolo
       │
       ├── Policy: richiedere l'approvazione per pubblicare
       │
       └── Vigil: monitorare nel tempo gli articoli pubblicati
```

Il modello può partecipare a ogni parte in cui il ragionamento è utile, ma non possiede l'intera sequenza.

## La conversazione non è lavoro in background

In Spectre, un `Flow` gestisce il lato conversazionale di un agente.

Descrive le route che l'agente comprende e ciò che quelle route possono avviare o proporre. Il routing può essere rigido dove serve rigidità e flessibile dove conta il linguaggio naturale.

Un comando diretto come «pubblica questo articolo» può usare un match deterministico. Una richiesta meno prevedibile può passare attraverso embedding, un classificatore o un LLM che sceglie tra route già esistenti.

Il dettaglio importante è che il modello sceglie all'interno del vocabolario dell'applicazione. Non inventa una nuova parte del sistema ogni volta che gliene serve una.

Una conversazione ha anche una continuazione ripristinabile, rappresentata da un `Run`. Può fermarsi perché l'agente ha risposto, perché servono altre informazioni oppure perché ha raggiunto un confine di approvazione o di esecuzione. Quel confine è visibile all'applicazione host invece di essere nascosto dentro un'altra iterazione del modello.

Ricercare e preparare l'articolo è diverso.

Questo appartiene a un `Work`: un'operazione durevole e finita, con stato, avanzamento, budget e condizione di completamento propri.

Scritta così, la distinzione sembra ovvia, ma cambia il modo in cui si percepisce l'applicazione. La chat non deve restare aperta mentre l'articolo viene preparato e il Work non deve fingere che ogni passaggio operativo sia un altro turno della conversazione.

Significa anche che posso chiedere all'agente cosa sta succedendo senza affidarmi al modello perché racconti il proprio processo nascosto.

> **Io:** Come procede l'articolo su Spectre?

> **Agente:** Ho letto la documentazione sull'architettura del core e sulle operazioni. Manca ancora la sezione di confronto.

Quella risposta può provenire dallo stato confermato del Work: la sua fase, il suo avanzamento e i risultati parziali pubblicati. Non deve essere una spiegazione improvvisata, generata da ciò che entra ancora nella finestra di contesto del modello.

## Cambiare la richiesta senza ricominciare

La parte utile arriva quando interrompo il lavoro.

Supponiamo che la ricerca sia già iniziata e che io invii un altro messaggio:

> Includi il motivo per cui ho separato Work da Directive. Usa anche il nuovo documento sul runtime, non il vecchio file del concept.

L'implementazione più semplice consiste nell'aggiungere quella frase alla conversazione e sperare che la chiamata successiva al modello la noti.

Spectre la tratta come una modifica all'operazione in esecuzione.

L'agente può determinare a quale Work mi riferisco, metterlo in pausa in un punto sicuro, applicare un aggiornamento e riprenderlo con una nuova revisione del contesto. L'aggiornamento è limitato ai campi che il Work consente esplicitamente di modificare e conserva la provenienza del messaggio che lo ha causato.

Questo è importante perché il tentativo precedente potrebbe terminare più tardi.

Senza un confine di revisione, un vecchio risultato può arrivare dopo l'aggiornamento e riportare silenziosamente l'articolo verso i vecchi requisiti. In Spectre quel risultato appartiene a una vista precedente del Work e può essere rifiutato.

Il modello continua a svolgere la parte interessante. Capisce che il mio messaggio cambia la direzione editoriale e lo trasforma in informazioni utili per l'operazione.

Ma «i requisiti sono cambiati» non è più soltanto una frase in un prompt. Diventa una vera transizione dell'applicazione.

È l'equilibrio che non trovavo altrove.

## Il modello è libero di pensare

Spectre non è un tentativo di trasformare un agente AI in un workflow engine tradizionale.

Non voglio descrivere in anticipo ogni possibile pensiero. Se potessi farlo, probabilmente non mi servirebbe il modello.

Mentre prepara l'articolo, il modello può decidere quali parti di una fonte siano rilevanti, confrontare spiegazioni diverse, estrarre affermazioni o scegliere la struttura migliore per la bozza. Spectre Prism può selezionare un modello più economico per la classificazione e uno più potente per la scrittura o il ragionamento approfondito. Spectre Lens può fornire capacità di navigazione senza rendere il browser parte dello stato canonico dell'agente.

L'obiettivo non è rendere deterministica ogni decisione.

L'obiettivo è stabilire con precisione quali decisioni sono probabilistiche.

Il modello può decidere che una sezione è debole e richiede altra ricerca. Può proporre un'altra operazione dichiarata. Può produrre una scaletta rivista. Quello che non può fare è ridefinire silenziosamente il ciclo di vita attorno al lavoro, concedersi una nuova capacità o trasformare un suggerimento in un effetto collaterale esterno.

Spectre non cerca di controllare il ragionamento del modello.

Controlla ciò che quel ragionamento può diventare.

## È nella pubblicazione che la differenza diventa visibile

Scrivere una bozza è relativamente sicuro. Pubblicarla non è la stessa cosa.

La pubblicazione modifica il repository Git e rende visibile l'articolo. A seconda dell'applicazione, può anche avviare un deploy, avvisare gli iscritti o inviare il contenuto ad altri canali.

Non voglio che «il modello ha chiamato lo strumento di pubblicazione» costituisca l'intero modello di sicurezza.

In Spectre, l'agente può proporre la pubblicazione, ma un'azione protetta entra in un ciclo di vita esplicito della policy. L'applicazione può richiedere conferma, accettare o rifiutare una risposta dichiarata, limitare il numero di tentativi e annullare l'azione in sospeso.

Approvazione ed esecuzione sono separate.

Questa separazione è importante. Confermare un'azione ne modifica lo stato; non la esegue di nascosto nello stesso callback. L'applicazione host attraversa ancora il vero confine ed esegue l'operazione Git usando le proprie credenziali e regole di autorizzazione.

Così l'interazione può rimanere naturale:

> **Agente:** La bozza è pronta. Vuoi che la pubblichi?

> **Io:** Pubblicala.

Ma sotto questo breve scambio il modello non ha semplicemente deciso che le parole «pubblicala» siano sufficienti per eseguire codice arbitrario. La risposta risolve una specifica policy in sospeso per uno specifico Effect. Soltanto allora l'host può eseguire la capacità registrata.

È questo che dovrebbe significare per me «human in the loop».

Non una nota nel system prompt che dice al modello di fare attenzione. Non un secondo modello che revisiona il primo. Un vero confine nel runtime.

## Un timeout non equivale a una pubblicazione fallita

È nelle operazioni esterne che le demo di agenti diventano normali sistemi distribuiti.

Immagina che l'applicazione invii il commit Git o la richiesta di pubblicazione e che la connessione cada prima che arrivi la risposta.

Forse non è successo nulla.

Forse l'articolo è stato pubblicato correttamente ed è andata persa soltanto la risposta.

Riprovare automaticamente potrebbe essere corretto oppure potrebbe creare un'operazione duplicata. Anche segnalare un errore potrebbe essere sbagliato.

Spectre non presume che un crash dimostri che l'azione esterna non sia avvenuta. Le operazioni descrivono il tipo di confine degli effetti collaterali che attraversano. Quando un esito può essere riconciliato, il runtime può chiedere all'applicazione di verificare cosa sia realmente accaduto prima di riprovare.

Non è una funzionalità particolarmente spettacolare. Non produrrà un video impressionante di cinque secondi.

È uno dei motivi per cui riesco a immaginare di usare lo stesso runtime per azioni più serie della preparazione di una bozza.

## Perché OTP conta qui

Spectre è OTP-native perché l'actor model ci offre già una buona risposta a una delle domande più difficili in un sistema di agenti: chi possiede lo stato?

Per un agente in esecuzione, Spectre usa un'`Instance` legata al Subject come proprietario locale canonico. Il Subject è l'identità applicativa servita: un account, un workspace, un cliente o un'altra reale entità del dominio. È distinto dall'ID di una chat Telegram, da una connessione MCP o da qualsiasi altra identità di canale.

L'Instance possiede lo stato conversazionale e operativo ordinato per quel Subject.

Il lavoro lento non avviene dentro la sua mailbox. Un Runner temporaneo riceve uno snapshot delimitato, esegue un tentativo registrato, restituisce dati e termina. Il Runner non può confermare autonomamente lo stato canonico. L'Instance convalida il risultato e decide se appartiene ancora alla revisione corrente.

Questo mantiene semplice la proprietà dello stato senza costringere ogni chiamata al modello, richiesta del browser o operazione esterna a bloccare il processo dell'agente.

Dà inoltre al fallimento un significato chiaro.

Se un Runner va in crash, è fallito un tentativo. Il Work continua a esistere.

Se l'applicazione si riavvia, il checkpoint contiene stato portabile e identificatori stabili, non vecchi PID o client del modello ancora attivi. Le dipendenze del runtime vengono risolte di nuovo e i risultati obsoleti precedenti al riavvio non possono essere confermati con leggerezza nell'agente ripristinato.

È molto più vicino al comportamento che mi aspetto da un sistema Elixir.

## Monitorare l'articolo dopo la pubblicazione

Una volta pubblicato l'articolo, il Work originale è completo.

Ma il blog potrebbe avere ancora bisogno di monitorarlo.

Una nuova release di Spectre potrebbe rendere obsoleto un paragrafo. Una fonte potrebbe sparire. Un link potrebbe iniziare a restituire un errore.

Questo non è un altro Work che finge di non finire mai. Spectre rappresenta l'osservazione ricorrente con un `Vigil`.

Un Vigil si risveglia in base a un timer o a un evento, esegue un'osservazione, conferma il risultato e torna in attesa. Non deve mantenere attivo un worker tra un controllo e l'altro. Se trova qualcosa di significativo, quell'evento può rientrare nel normale Flow dell'agente e infine raggiungermi attraverso il canale appropriato.

La distinzione resta la stessa: un'astrazione per un'operazione finita, un'altra per l'osservazione durevole, mentre la conversazione rimane qualcosa di distinto.

Condividono lo stesso runtime senza diventare un unico loop gigantesco.

## Che cosa si percepisce di diverso

L'agente per il blog completato non è meno intelligente di uno costruito attorno a un loop interamente guidato dal modello.

Può ancora comprendere una richiesta libera, cercare nella documentazione, revisionare un articolo e adattarsi quando cambio direzione. Nei punti in cui un modello più potente produce un lavoro migliore, posso usarne uno.

Ciò che si percepisce di diverso è che riesco ancora a vedere l'applicazione attorno al modello.

So quale stato è canonico. So se sto osservando una conversazione, un Work finito o un Vigil ricorrente. So quando sceglie il modello e quando subentra una policy deterministica. Posso mettere in pausa un'operazione, aggiornarla, riprenderla e ispezionarne l'avanzamento confermato. So che l'approvazione non esegue un effetto collaterale e che un timeout non significa automaticamente che sia sicuro ripeterlo.

Spectre non è progettato per far scomparire il modello dietro codice rigido.

È progettato per impedire che il resto del software scompaia dietro il modello.

È ciò che volevo da un runtime per agenti: sufficiente libertà perché il modello sia davvero utile e sufficiente struttura perché costruire l'agente continui a sembrare costruire un sistema.

Spectre è disponibile su GitHub all'indirizzo [github.com/elchemista/spectre](https://github.com/elchemista/spectre).
