---
title: "Spectre 0.4: agenti che lavorano entro un'autorità esplicita"
slug: "spectre-0-4-agenti-autorita-e-controllo-umano"
lang: "it"
status: published
date: 2026-11-17
updated: 2026-11-17
category: "Sviluppo software"
tags: ["Elixir", "OTP", "agenti AI", "Spectre", "GAM", "architettura", "approvazione umana"]
seo_title: "Spectre 0.4: agenti, autorità e controllo umano"
seo_description: "Come Spectre 0.4 separa riconoscimento, conversazione ed esecuzione governata con autorità esplicita, consenso umano, storia persistente e API Elixir."
cover_alt: "Stack, Agent e Server collegano la conversazione ad ammissione GAM, consenso umano, esecuzione e risultato osservato"
translation_of: "content/en/2026-11-17-spectre-0-4-agents-authority-and-human-control.md"
---

Un agente prepara un'email per un cliente. Il testo è buono. Il destinatario è corretto. Il modello è sicuro. Può inviarla?

Non è un altro problema di generazione del testo. Riguarda l'autorità dell'applicazione, il consenso della persona e quello che il servizio email esegue davvero.

Spectre 0.4 rende visibili questi confini nel modo di scrivere un'applicazione Elixir. **Stack seleziona le capacità. Agent riconosce le intenzioni. Server possiede la conversazione. GAM governa le operazioni dichiarate che hanno conseguenze.**

Il core 0.4.0 è disponibile su Hex. Cambia in modo sostanziale struttura e runtime; le applicazioni 0.3 esistenti dovrebbero seguire la [guida di migrazione](/it/docs/migration), invece di trattarlo come un semplice cambio di numero nella dipendenza.

## Parti da tre moduli leggibili

L'architettura segue un ordine semplice:

```text
Stack → Agent → Server
                  │
          worker cognitivi e dei tool
                  │
          proposta concreta di effetto
                  ▼
             Managed GAM
       autorità + prove necessarie
                  │
        consenso umano quando richiesto
                  │
              Act ammesso
                  ▼
          esecutore registrato
                  │
           Outcome osservato
```

Uno **Stack** installa capacità riutilizzabili: modelli, browser, memoria o messaggi. Un **Agent** dichiara route, intenti e strategie di riconoscimento. Un **Server** implementa le callback applicative e possiede stato, attese e continuazioni dentro un processo OTP.

Il riconoscimento può migliorare senza trasferire il comportamento di business in un prompt. Il router combina regex, similarità tra caratteri, esempi verificati, vettori, classificatori locali e classificazione LLM. Può usare un modello quando serve. L'handler scelto resta un handler applicativo dichiarato.

Il Server rimane normale Elixir. Le callback conversazionali restituiscono un Context. `handle_call`, `handle_cast` e `handle_info` conservano le tuple OTP, con Context come stato. Modelli e tool girano in worker e tornano a continuazioni nominate.

La [guida al primo agente](/it/docs/getting-started) parte senza modelli o database. La [guida al routing](/it/docs/routing) aggiunge embedding e classificazione, distinguendo l'encoder che produce i vettori dagli indici Vettore che li cercano.

## GAM significa Governed Act Model

Il [manifesto GAM](/it/governed-act-model) descrive il modello che governa il passaggio da proposta a operazione autorizzata.

Un modello può proporre. Una route può riconoscere. Un package può registrare un esecutore. Nessuno di questi fatti, da solo, concede all'agente il permesso di eseguire l'operazione.

GAM verifica autorità e prove applicabili a una candidate concreta. Quando serve consenso umano, lo lega all'operazione e agli argomenti esatti mostrati. Dopo l'ammissione, l'esecutore registrato effettua un tentativo e il sistema registra ciò che è stato osservato.

Managed GAM collega il modello ad AgentServer: costruisce la presentation, coordina l'attesa, verifica la decisione e consente l'esecuzione dopo un'ammissione valida. L'applicazione configura operazioni e policy di business senza riscrivere tutto il protocollo in ogni callback.

Per un'operazione email Kinetic registrata, l'avvio può richiedere:

```elixir
# Frammento di opzioni AgentServer; richiede registrazione effetto e adapter host.
gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]
```

Il Server propone la bozza invece di chiamare direttamente il client email:

```elixir
# Frammento dentro un Server con effetto email registrato.
propose(ctx, {:kinetic, :send_email},
  %{"to" => recipient, "body" => draft},
  on_result: :sent)
```

Il consumer mostra la presentation esatta, conferma la visualizzazione effettiva e invia la scelta distinta della persona. Cambiare messaggio o destinatario non permette di riutilizzare una decisione presa per una bozza diversa.

La [guida all'architettura](/it/docs/architecture-gam) spiega i termini. Le [ricette](/it/docs/recipes) collegano proposte Kinetic tipizzate e tool installati, indicando chiaramente le dipendenze applicative.

## Permesso e successo sono fatti diversi

La persona approva. Il servizio email riceve la richiesta, la applica e la connessione si interrompe prima della risposta.

L'agente ha un'operazione ammessa e un risultato esterno incerto. Non ha la prova che l'invio sia fallito. Ripeterlo potrebbe produrre due email.

Spectre mantiene separate ammissione ed esito dell'esecuzione. Il codice deve dichiarare successo quando l'Outcome registrato lo dimostra, conservare gli esiti incerti e riconciliarli con il provider prima di ripetere lavoro non ripetibile.

Per il business questa distinzione conta più di un “Fatto” ottimista. L'assistenza distingue un rifiuto da un guasto. Un operatore può verificare un pagamento incerto. Il cliente vede quale operazione esatta ha approvato. Servono comunque adapter corretti, idempotenza del provider dove disponibile e una policy operativa di riconciliazione.

## Il tuo agente chiede al mio senza dare autorità all'AI

L'agente di un cliente potrebbe aver bisogno del tuo consenso prima di aprire un sito. Tu hai già una chat con il tuo agente personale. La richiesta deve arrivare lì e devi poter confermare o rifiutare.

Nella 0.4, richiedente e approvatore possono essere due AgentServer con Domain GAM indipendenti. Il cliente congela la richiesta; l'agente personale la mostra al suo consumer umano autenticato; la decisione ritorna come prova firmata e correlata. Il mandato originale del cliente continua a controllare l'ammissione.

Pulse può trasportare i messaggi, ma è opzionale. Il core include un esempio eseguibile con due agenti e adapter mailbox. Un trasporto personalizzato implementa lo stesso contratto. La ricevuta tecnica `accepted` prova l'acquisizione della consegna, non consenso umano o esecuzione conclusa.

Il protocollo gestisce identità delle richieste, vincoli immutabili, conferma della presentazione, scadenza e risposte consumate. Ripetere una scelta salvata reinvia la stessa decisione firmata. Il modello è un intermediario, non l'approvatore. Autenticazione reale e firma fidata restano responsabilità dell'applicazione.

La [guida indipendente dal trasporto](/it/docs/agent-to-agent) descrive flusso e limiti dopo un riavvio.

## Le Skill lavorano indipendentemente nello stesso confine di autorità

Una Skill di ricerca e una di fatturazione possono avere processi Server, stato e worker separati. Una risponde mentre l'altra aspetta consenso. Entrambe condividono il Domain GAM principale, con le restrizioni del mount.

È diverso da due agenti indipendenti che comunicano tra Domain. Una Skill montata non richiede un'altra storia di autorità o un secondo protocollo di consenso. La sua proposta deve comunque soddisfare operazione consentita sul root e riferimento ammesso per il mount.

Le capacità riutilizzabili restano utili senza trasformare ogni package in un altro framework di runtime. Dichiarazioni, callback e confine delle conseguenze rimangono leggibili nell'applicazione.

## La storia persistente non deve diventare memoria permanente del processo

La modalità solo RAM rimane un punto di partenza supportato. Database e Ledger non sono obbligatori.

Per storie crescenti, un provider configurato può conservare batch canonici GAM, coordinamento Server e proiezione storica del Domain nel database. Il Domain attivo mantiene radici di autorità e frontiere attive, carica le righe rilevanti quando servono e le rilascia dopo il comando.

Riduce la residenza storica in RAM. Non promette memoria costante per qualunque lavoro attivo o commit indipendenti dalla latenza del database. Il recovery verifica ancora la storia canonica: la proiezione derivata non sostituisce autorità mancanti.

L'applicazione può implementare un solo provider `Spectre.Server.Store` con i gruppi di callback necessari per storia/proiezione. Ledger offre integrazioni file e PostgreSQL. Proprietà del database, migrazioni e pool restano dell'host.

Corpi email, URL, assigns e ricevute private richiedono una policy di storage. L'adapter opzionale dei payload espone `put` e `fetch`: un database cifrato, object store o servizio può restituire riferimenti opachi portabili. Non è obbligatorio usare indirizzi basati sul contenuto. Installare Ledger non cifra né rimuove i dati inline precedenti.

Il guasto del database è esplicito. L'host può attendere, riprovare il recovery o scegliere un Domain RAM nuovo, che non riutilizza il consenso precedente. Le storie divergenti non vengono unite in silenzio. La [guida storage](/it/docs/storage) spiega queste scelte e distingue recovery da reset completo della sessione.

## Dove serve a un'applicazione reale

| Flusso | Confine utile |
| --- | --- |
| Contatti commerciali | Prepara la bozza; invia solo destinatario/contenuto approvati attraverso l'adapter consentito |
| Assistenza rimborsi | Separa riconoscimento della richiesta e autorità di rimborsare una fattura; riporta il risultato osservato dal provider |
| Ricerca condivisa | Richiede consenso della persona designata per navigazione protetta o divulgazione, anche da un'altra chat/agente |
| Supporto operativo | Distingue lettura/analisi da modifiche distribuite e conserva esiti esterni incerti da verificare |
| Assistenza di lunga durata | Usa identità di sessione, storia su database e query limitate invece di tenere ogni evento nell'heap |

Sono confini di progettazione applicativa. Non stabiliscono conformità legale automatica, protezione completa dei dati o policy aziendali corrette senza implementare tali requisiti nell'host.

## Una versione che cambia la struttura dell'applicazione

Il punto di partenza resta piccolo:

```elixir
{:spectre, "~> 0.4.0"}
```

Genera la struttura corrente con `mix spectre.gen.agent MyApp.SupportAgent --server`, esegui il test e aggiungi una capacità alla volta. Le nove librerie satellite sono opzionali e hanno versioni indipendenti: usa package compatibili pubblicati oppure il [catalogo sorgente testato](/it/docs/ecosystem).

La nuova [documentazione](/it/docs/overview) copre routing, revisione/training dei dataset, task Mix, behaviour, storage, consenso esterno e test di produzione. Le applicazioni 0.3 hanno un percorso dedicato di migrazione.

L'obiettivo è un'applicazione in cui il riconoscimento può essere probabilistico, mentre proprietà, autorità ed effetti osservati restano abbastanza espliciti da comprenderli, testarli e gestirli.
