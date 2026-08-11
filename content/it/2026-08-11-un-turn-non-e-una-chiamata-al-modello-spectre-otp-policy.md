---
title: "Un Turn non è una chiamata al modello: come Spectre governa gli agenti con OTP"
slug: "un-turn-non-e-una-chiamata-al-modello-spectre-otp-policy"
lang: "it"
status: published
date: 2026-08-11
updated: 2026-08-11
category: "Sviluppo software"
tags: ["Elixir","OTP","Actor Model","agenti AI","Spectre","governance degli agenti","policy"]
seo_title: "Turn, Policy e governance OTP degli agenti Spectre"
seo_description: "Perché Spectre definisce il Turn come confine osservabile, applica Policy deterministiche agli effect protetti e fonda l'ownership su Actor Model e OTP."
cover_alt: "Un actor Spectre legato a un Subject fa avanzare un Run fino a un confine osservabile, mentre una Policy deterministica separa effect proposto, approvato ed eseguito"
---

In molti framework per agenti, un turno inizia quando l'input raggiunge un modello e termina quando il modello ha finito di chiamare tool e ha prodotto una risposta.

Io ho iniziato Spectre partendo da una domanda diversa:

> **In quale punto la responsabilità passa dal runtime dell'agente all'applicazione che possiede il mondo reale?**

Questa domanda ha cambiato il significato del Turn.

In Spectre, un `Turn` non è sinonimo di una richiesta all'LLM, di un passaggio attraverso un grafo o di un intero tool loop. È la proiezione pubblica prodotta quando un `Run` ripristinabile raggiunge il primo confine osservabile. Il confine può essere una risposta, la richiesta di una Policy oppure un'invocazione esterna. Prima di quel punto il modello può aver partecipato, oppure può non essere stato chiamato affatto.

La frase utile è questa:

> **Un Turn di Spectre termina quando cambia il proprietario della prossima decisione.**

Se il runtime ha del testo da esporre, l'host possiede la consegna. Se un effect protetto richiede approvazione, quella decisione appartiene a una persona o a un host fidato. Se una capability approvata deve essere eseguita, il side effect appartiene a un executor esterno al reasoning loop. Spectre non nasconde questi passaggi dietro un'altra iterazione automatica.

È uno dei modi principali in cui Spectre si differenzia dai framework più model-first, e deriva direttamente dall'Actor Model, da OTP e dalle parti meno spettacolari dei sistemi distribuiti.

## L'Actor Model è stato il punto di partenza

Il modulo che usa `Spectre.Agent` non è un actor vivo. È la definizione compilata del comportamento.

L'oggetto vivo del runtime è una `Spectre.Instance` legata a un Subject:

```text
AgentRef + Subject → un'Instance logica
```

Un'Instance possiede lo stato ordinato della relazione tra un agente logico e un Subject canonico. Ha una mailbox, serializza le modifiche di stato accettate e conserva i Run che appartengono a quel Subject. Un PID può scomparire dopo un crash; l'identità logica non deve scomparire insieme a lui.

Questo si collega in modo naturale alle idee che ho imparato dagli actor e da OTP:

| Idea di Actor Model o OTP | Interpretazione in Spectre |
| --- | --- |
| Un processo possiede il proprio stato | Un'Instance possiede lo stato canonico per `AgentRef + Subject` |
| Gli altri partecipanti comunicano tramite messaggi | Move dei Run, risultati dei worker e comandi di controllo tornano all'Instance come messaggi correlati |
| La mailbox stabilisce un ordine | Le modifiche di stato sono accettate in serie, invece di competere su stato mutabile condiviso |
| L'identità del processo non è l'identità di business | Il PID è temporaneo; `AgentRef + Subject` è l'indirizzo stabile |
| Il lavoro lento o fallibile va isolato | I runner di capability e operation lavorano fuori dalla mailbox dell'Instance |
| I Supervisor ricostruiscono i processi | OTP riavvia il processo del runtime; i checkpoint configurati ripristinano lo stato durevole |
| Il fallimento è previsto | Revisioni, fencing e idempotenza decidono se un risultato tardivo è ancora valido |

Non ho copiato l'Actor Model come scelta estetica. L'ho usato per rispondere a domande sull'ownership.

Chi può modificare questo stato? Quale Run possiede questa conferma in sospeso? Che cosa succede se un'azione esterna risponde dopo che l'agente è avanzato? Un secondo processo può applicare la stessa receipt? Queste domande diventano molto più semplici quando esiste un solo proprietario canonico e tutto il resto deve riportargli evidenze.

La supervisione OTP è importante, ma «let it crash» non basta. Un processo riavviato può essere ricostruito. Un pagamento duplicato, un record eliminato o un articolo pubblicato non possono essere annullati da un Supervisor. Spectre combina quindi l'isolamento dei fallimenti con revision fence, identificatori stabili degli effect, chiavi di idempotenza ed esiti ambigui espliciti.

Un crash è previsto. Non dimostra che non sia successo nulla.

## Che cosa fa davvero un Turn

L'entry point pubblico è volutamente piccolo:

```elixir
{:ok, turn} = Spectre.turn(instance, input)

case turn.observable do
  {:reply, output, run_ref} ->
    deliver_once(output, Spectre.Run.Ref.token(run_ref))

  {:needs, policy_boundary} ->
    present_policy(policy_boundary)

  {:awaiting, invocation_ref} ->
    dispatch_invocation(turn.boundary, invocation_ref)
end
```

All'interno può accadere molto di più:

```text
normalizza l'input
  → ripristina lo stato e richiama la memoria
  → riprende una Policy aperta oppure esegue il routing di un normale Turn
  → esegue codice deterministico e, se serve, il ragionamento del modello
  → prepara una risposta o un Effect
  → conferma lo stato autorevole
  → si ferma al primo confine osservabile
```

Il vocabolario chiuso degli observable è importante. Un'integrazione browser, un adapter di pagamento o un futuro trasporto agent-to-agent non può inventare un nuovo tipo di Turn. Le estensioni possono aggiungere nuovi tipi di Effect, ma l'host continua a vedere lo stesso confine del lifecycle.

Anche la continuation resta privata. Un `Turn` espone un `Run.Ref` protetto da revisione, non il Run mutabile. L'Instance conserva la continuation e rifiuta un riferimento obsoleto, un'invocazione estranea o una risposta indirizzata alla revisione sbagliata del Run.

È l'incapsulamento degli actor applicato al runtime di un agente: il mondo esterno riceve un indirizzo e una richiesta, non la proprietà della macchina.

## Una Policy è un router deterministico temporaneo

Qui per `Policy` intendo il gate del runtime collegato a un Effect protetto, non un'istruzione vaga nel system prompt e nemmeno le policy di governance più ampie usate per approvare nuove Definition.

Consideriamo un'azione distruttiva:

```elixir
actions MyApp.AccountActions do
  protect(:delete_account, with: :confirm_delete)
end

policy :confirm_delete do
  request(:confirm_delete_request)
  accept(:confirmed, regex: ~r/^yes,?\s+delete$/iu)
  reject(:cancelled, regex: ~r/^(no|cancel)$/iu)
  otherwise(ask: :confirm_delete_retry)
  attempts(3, then: :cancel_pending)
end

flow :account do
  on :DELETE_ACCOUNT, regex: ~r/^delete my account$/iu, cache: false do
    action(:delete_account)
  end
end
```

Il primo input non chiama `delete_account/2`. Prepara un Effect con stato `:waiting_policy` e apre un Awaitable posseduto da quel Run.

Mentre la Policy è aperta, il normale routing non riceve un'altra possibilità di reinterpretare la risposta successiva. La Policy ha precedenza su turn handler, classificatori e routing LLM. Un matcher puro confronta l'input normalizzato con i branch `accept` e `reject` dichiarati. Un testo sconosciuto incrementa il contatore dei tentativi. Il rifiuto o l'esaurimento dei tentativi annulla l'Effect in sospeso.

Questa precedenza è più importante della regex stessa.

Se l'utente scrive «sì, elimina», non voglio che un LLM decida che probabilmente significa approvazione mentre considera anche route non correlate, documenti recuperati e descrizioni dei tool. Voglio che il runtime sappia che un Run preciso sta aspettando una decisione precisa, sotto una Policy compilata precisa.

Un'applicazione fidata può inoltre risolvere la Policy tramite una label dichiarata:

```elixir
{:ok, approved_turn} =
  Spectre.Turn.resolve_policy(turn, {:accept, :confirmed})
```

Non deve costruire un falso messaggio utente come `"yes"`. La sorgente della decisione viene registrata, la label deve esistere nella Policy e una resolution non valida fallisce senza modificare lo stato.

## Proposto, approvato ed eseguito sono fatti diversi

Molte API per agenti permettono già l'approvazione dei tool, ed è un'ottima evoluzione. L'opinione più forte di Spectre è che proposta, approvazione ed esecuzione siano fatti distinti del lifecycle, anche quando il percorso ideale li fa sembrare un'unica operazione.

| Confine | Stato dell'Effect | L'azione è stata eseguita? | Chi possiede il prossimo passo? |
| --- | --- | --- | --- |
| Viene selezionata un'azione protetta | `:waiting_policy` | No | Policy resolver |
| La Policy accetta | `:approved` | No | Host o capability executor |
| La Policy rifiuta o scade | `:cancelled` | No | Nessuno; è terminale |
| Viene confermata la receipt di esecuzione | `:completed` oppure `:failed` | Sì | Il runtime registra l'esito |

L'approvazione viene confermata prima dell'esecuzione. Il risultato esterno viene confermato dopo. Se il secondo commit ha un esito incerto, Spectre restituisce un'ambiguità invece di decidere silenziosamente che l'azione debba essere eseguita di nuovo.

Assomiglia a un piccolo protocollo transazionale attorno a una capability, anche se Spectre non può rendere transazionale un sistema esterno arbitrario. L'host deve comunque implementare l'azione reale in modo sicuro e persistere la chiave di idempotenza insieme all'operazione di dominio.

Una Policy non sostituisce nemmeno l'autorizzazione. La conferma risponde a «l'actor atteso ha approvato questa operazione preparata?». L'autorizzazione risponde ancora a «questo Subject autenticato può eliminare questo account adesso?». L'host deve imporla al vero confine della capability, usando dati di business correnti.

Questa separazione è intenzionalmente scomoda. Impedisce di scambiare una conversazione gradevole per autorità.

## L'ownership conta quando più cose sono aperte

Un agente longevo non ha sempre una sola richiesta in corso.

Uno stesso Subject può parlare dal sito e da Telegram. Un report può essere in esecuzione mentre un altro Turn chiede conferma. Due azioni protette diverse possono attendere una risposta. Nel frattempo, la Definition dell'agente può essere aggiornata.

Spectre non risolve tutto questo mantenendo vivo un unico enorme model loop.

Normalmente ogni nuovo input crea un nuovo Run sopra lo State condiviso e ordinato dell'Instance. La risposta a una Policy è l'eccezione importante: riprende il Run che possiede l'Awaitable. La source dell'input identifica l'origine della conversazione, così un semplice «sì» può essere correlato al corretto confine sospeso.

Se più Policy potrebbero possedere la risposta e manca l'origine, Spectre restituisce un errore di ambiguità. Non sceglie il Run più recente, il primo elemento di una lista o l'azione che sembra semanticamente più vicina.

Questo diventa ancora più importante quando cambia il comportamento. Nel runtime 0.3, un Run è pinned alla Definition immutabile che lo ha ammesso. Un nuovo input può usare la Definition B, mentre una conferma aperta dalla Definition A continua sotto A. L'authority corrente viene comunque controllata prima del prossimo Effect, quindi un vecchio comportamento riproducibile non diventa un vecchio permesso eterno.

È una combinazione sottile:

- l'Instance conserva una sola identità logica;
- ogni Run conserva il proprio proprietario semantico;
- la Definition attiva possiede il nuovo lavoro;
- l'authority corrente può ancora revocare il vecchio lavoro;
- il modello non decide quale versione debba ricevere un evento.

È qui che l'ownership degli actor cresce e diventa governance dell'agente.

## In che cosa differisce dagli altri framework

Spectre non è l'unico progetto con esecuzione durevole, approvazione umana, stato esplicito o processi OTP. Sostenerlo sarebbe sia sbagliato sia strategicamente inutile.

[LangGraph](https://github.com/langchain-ai/langgraph) offre durable execution, interrupt, memoria e un'ottima osservabilità a livello di grafo. [Mastra](https://github.com/mastra-ai/mastra) può sospendere e riprendere agenti e workflow. [OpenAI Agents SDK](https://github.com/openai/openai-agents-python) offre tool, guardrail, sessioni, tracing e flussi human-in-the-loop. [PydanticAI](https://github.com/pydantic/pydantic-ai) offre output type-safe, approvazione dei tool ed esecuzione durevole. [Jido](https://github.com/agentjido/jido) è già un framework Elixir OTP-native con stato esplicito, Action, Signal e Directive.

La differenza non è una voce in una checklist. È l'oggetto collocato al centro del runtime.

| Approccio | Centro di gravità | Che cosa fa particolarmente bene | La scommessa diversa di Spectre |
| --- | --- | --- | --- |
| SDK model-first come OpenAI Agents SDK e PydanticAI | Agent run, modello, tool e output finale | Costruzione rapida, integrazioni con provider, risultati tipizzati, guardrail e approval | Una chiamata al modello è opzionale dentro un Turn; l'host riceve il primo confine di ownership invece di cedere il lifecycle a un tool loop |
| Sistemi a grafo come LangGraph e i workflow di Mastra | Stato del grafo, nodi, archi, checkpoint e interrupt | Orchestrazione esplicita, workflow durevoli e percorsi di esecuzione visibili | Il proprietario principale è un actor legato al Subject con più Run; ownership di Policy ed Effect resta un'invariante del runtime, non soltanto una convenzione del grafo |
| Jido | Stato immutabile dell'agente, comandi, Action, Signal e Directive del runtime | Composizione Elixir nativa, supervisione e workflow autonomi distribuiti | Spectre applica un lifecycle più stretto agli Effect protetti e un confine Turn protetto da revisione, separando approval ed execution per impostazione predefinita |
| Spectre | Identità, ownership, authority e confini osservabili | Continuation governate, precedenza deterministica delle Policy ed Effect consapevoli dei fallimenti | Accetta più cerimonia e un ecosistema più piccolo per rendere esplicito il control plane |

Per un prototipo che deve chiamare tre tool e restituire una risposta, non direi che Spectre sia automaticamente la scelta migliore. Spesso il percorso più leggero è quello corretto.

Spectre diventa interessante quando l'agente sopravvive più a lungo della richiesta, cambia comportamento mentre rimane del lavoro aperto, opera attraverso più canali oppure tocca operazioni per le quali «il modello probabilmente ha fatto la cosa giusta» non è un audit record accettabile.

## Le altre idee nascoste dentro Spectre

Actor Model e OTP sono la base più visibile, ma il runtime è modellato anche da altre idee del software.

### State machine invece di implicazioni conversazionali

Un Effect non può saltare direttamente da `:waiting_policy` a `:completed`. Le transizioni del lifecycle sono esplicite e quelle non valide vengono rifiutate. La trascrizione della chat può spiegare perché è successo qualcosa; non definisce quali stati siano legali.

### Capability security invece di tool universali

Il modello non riceve un'autorità applicativa arbitraria. Può selezionare operation registrate o prepararne i dati. Un Effect descrive il lavoro richiesto, ma non è la capability per eseguirlo. L'executor e l'host continuano a possedere le credenziali e la decisione finale di autorizzazione.

### Projection invece di continuation esposte

Un `Turn` è la proiezione di un Run presso un confine. Un `Result` è la receipt di una transizione. La continuation completa rimane dietro il suo proprietario. È simile al modo in cui i sistemi maturi espongono viste e comandi senza consegnare ai client la propria state machine interna.

### Il pessimismo dei sistemi distribuiti

Un timeout non significa fallimento. Un crash non significa rollback. Un messaggio ripetuto non è necessariamente una nuova intenzione. Per questo Spectre usa identificatori stabili, controlli di revisione, compare-and-swap, chiavi di idempotenza ed esiti ambigui espliciti.

### Supervisione senza ripristino magico

OTP può riavviare un'Instance o un runner fallito, ma il ripristino durevole richiede un checkpoint validato e una nuova risoluzione delle dipendenze del runtime. PID, client, funzioni e secret non appartengono alla continuation. Vengono risolti nuovamente dall'applicazione distribuita.

Queste idee non sono feature agentiche alla moda. Sono vecchie lezioni del software applicate a un nuovo partecipante inaffidabile: un modello probabilistico che opera dentro un'applicazione stateful.

## Che cosa penso faccia bene Spectre

La parte più forte di Spectre non è l'uso di Elixir o la presenza di una DSL. È il rifiuto di lasciare che un'unica astrazione possieda tutto.

- Il modello possiede l'interpretazione probabilistica e il ragionamento.
- Il router possiede la selezione tra i comportamenti dichiarati.
- La Policy possiede un confine deterministico di approvazione.
- Il Lifecycle possiede le transizioni di stato legali.
- L'Instance possiede lo stato canonico del Subject e lo scheduling dei Run.
- L'executor possiede il tentativo esterno.
- L'host possiede identità, autorizzazione, credenziali, storage e consegna.

Poiché questi proprietari sono espliciti, il runtime può spiegare dove si è fermato e quali evidenze servono per continuare.

Questo non rende Spectre automaticamente sicuro. Una Policy sbagliata può approvare la cosa sbagliata. Un'Action troppo ampia può esporre troppa autorità. Uno Store difettoso può perdere stato. Un executor può ignorare l'idempotenza. Un modello può ancora produrre un ragionamento pessimo.

Ciò che Spectre fa bene è assegnare questi fallimenti a componenti visibili, invece di dissolverli dentro un unico loop intelligente.

È anche il motivo per cui non voglio che Spectre diventi un framework generalista copiando tutte le integrazioni degli ecosistemi più grandi. LangGraph, Mastra, OpenAI Agents SDK, PydanticAI e Jido risolvono già molti problemi estremamente bene.

Spectre dovrebbe possedere una domanda più stretta:

> **Come può un agente ricevere input, fermarsi, agire, fallire, ripartire ed evolvere senza perdere l'identità e l'autorità dell'operazione esatta in corso?**

Il `Turn` e la `Policy` sono piccole risposte a questa domanda. OTP è ciò che le fa sembrare meno una convenzione da chatbot e più un runtime.
