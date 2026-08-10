---
title: "Iniziare con Spectre: il tuo primo agente non è un loop"
slug: "iniziare-con-spectre"
lang: "it"
status: published
date: 2026-08-05
updated: 2026-08-05
category: "Sviluppo software"
tags: ["Elixir","OTP","agenti AI","Spectre","runtime per agenti","guida introduttiva"]
seo_title: "Iniziare con Spectre in Elixir"
seo_description: "Un'introduzione a Spectre: come pensare a Subject, Instance, Run e Turn e come costruire il primo agente senza nascondere l'applicazione dietro un modello."
cover_alt: "Un primo agente Spectre: un Subject risolto dall'host, un'Instance OTP proprietaria dello stato e Turn che attraversano un confine visibile"
---

La maggior parte dei tutorial sugli agenti inizia con una chiamata a un modello. Invii un prompt, descrivi due strumenti, stampi la risposta e la demo funziona.

Spectre ti chiede di iniziare da un altro punto.

Prima di scegliere un modello, devi rispondere a una domanda molto meno entusiasmante: **chi possiede lo stato?** Una volta che questa risposta esiste, tutto il resto nel runtime diventa normale Elixir. Se non esiste, ti ritrovi con la trascrizione di una conversazione che finge di essere un'applicazione.

Questa è quindi un'introduzione, ma non del tipo che produce un chatbot in venti righe. È il percorso più breve che conosco verso un agente che potrai ancora sottoporre a debug tra tre mesi.

## L'unica idea che devi capire per prima

Se vuoi conservare una sola frase di questo articolo, conserva questa.

> **Il modulo che usa `Spectre.Agent` non è l'agente vivo. È la definizione compilata dell'agente.
> L'agente vivo è una `Spectre.Instance`, identificata da `AgentRef + Subject`.**

Il modulo dichiara routing, flow, policy, azioni, memoria e persistenza. È una mappa leggibile del comportamento. L'`Instance` è il processo OTP che conserva lo stato ordinato della relazione tra quell'agente e uno specifico Subject.

La tua vera logica continua a vivere in normali moduli Elixir. Spectre non ti chiede di spostare il dominio dentro una DSL; ti chiede di smettere di disperdere al suo interno le decisioni sul ciclo di vita.

Ecco il vocabolario, una volta sola, così il resto dell'articolo si legge rapidamente:

| Oggetto        | Significato                                                                        |
| -------------- | ---------------------------------------------------------------------------------- |
| `Agent`        | La definizione: cosa può fare, come esegue il routing, quali policy si applicano    |
| `Subject`      | La persona o entità canonica con cui lavora l'agente                               |
| `Instance`     | Il proprietario OTP dello stato per `Agent + Subject`                              |
| `Input`        | Un messaggio normalizzato                                                          |
| `Input.Source` | Da dove proviene il messaggio: web, chat, un client MCP                            |
| `State`        | Lo stato autorevole: cursore del flow, dati, policy, effect, cronologia             |
| `Run`          | Una singola esecuzione logica prodotta da un input                                 |
| `Turn`         | Ciò che ricevi quando il Run raggiunge un confine osservabile                      |
| `Effect`       | Un'operazione esterna proposta, non necessariamente eseguita                       |
| `Work`         | Una procedura precisa e durevole, indipendente dalla chat                          |
| `Vigil`        | Un'osservazione ricorrente e durevole                                               |

## Il Subject è la parte che molti sbagliano

Un `Subject` non è l'ID di una chat, un numero di telefono o l'ID di una conversazione. È l'identità applicativa canonica: `{:user, 42}`, `{:company, 18}`, `{:boat, "IT-123"}`.

Il canale non scompare, appartiene semplicemente a un altro posto: dentro `Input.Source`. Questa separazione permette alla stessa persona di parlare con lo stesso agente da un sito web e da un'app di chat mantenendo uno stato continuo, a condizione che l'host abbia autenticato e collegato intenzionalmente quelle identità, non per caso.

La forma completa di un'integrazione è questa:

```text
web / chat / client MCP
          │
          ▼
 autenticazione dell'host
          │
          ▼
 identità esterna → Subject
          │
          ▼
Agent + Subject → Spectre.Instance
          │
          ▼
  Spectre.turn(instance, input)
          │
          ▼
        Run → Turn
          │
 risposta / policy / effect / completamento
```

In Spectre, nulla di questo diagramma è negoziabile e nulla coinvolge ancora un modello.

## Una conversazione è composta da molti Run sopra un unico stato

È la seconda cosa che sorprende le persone.

Una conversazione Spectre non è un unico lungo Run che rimane aperto mentre l'utente scrive. Normalmente ogni messaggio crea un **nuovo** `Run` e tutti questi Run leggono e modificano, in ordine, lo stesso `State` posseduto dall'Instance.

```text
Instance
└── State condiviso
    ├── Run 1
    ├── Run 2
    └── Run 3
```

Un wizard di tre passaggi appare quindi così:

```text
Revisione dello State 0 — current_flow: nil

Utente: "create project"
    └── Run R1 → Turn: "What is it called?"
        Revisione dello State 1 — current_flow: :project_name

Utente: "Spectre Studio"
    └── Run R2 → Turn: "What is the goal?"
        Revisione dello State 2 — current_flow: :project_goal

Utente: "Managing durable agents"
    └── Run R3 → Turn: "Confirm?"
        Revisione dello State 3 — current_flow: :project_review
```

La continuità non deriva dal mantenere vivo R1. Deriva da `state.current_flow`, `state.current_scope` e `state.data`.

C'è una sola eccezione importante. Quando un Run si ferma perché attende la decisione di una policy, l'effect in sospeso appartiene a **quel** Run. Spectre usa l'origine della conversazione in `Input.Source` per correlare la risposta e ricondurla ad esso. Se sono aperte più policy e l'origine è ambigua, ottieni un errore esplicito invece di un'ipotesi fortunata.

> **Wizard normale: nuovi Run che condividono uno stato.
> Policy sospesa: ripresa correlata del Run che la possiede.**

Questa singola regola spiega gran parte del comportamento del runtime.

## Inizia dal core, senza alcun modello

La tentazione è collegare un modello fin dal primo giorno. Io non lo farei.

Aggiungi la dipendenza, fissandola a un commit che hai realmente verificato, dato che l'API è ancora giovane:

```elixir
defp deps do
  [
    {:spectre, github: "elchemista/spectre", ref: "<verified-commit-sha>"}
  ]
end
```

Poi inserisci il supervisor nel tuo supervision tree:

```elixir
def start(_type, _args) do
  children = [
    {Spectre.Supervisor, name: MyApp.SpectreSupervisor},
    MyApp.Repo,
    MyAppWeb.Endpoint
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

`Spectre.Supervisor` avvia e trova l'Instance univoca per una coppia `Agent + Subject`. Due richieste simultanee per la stessa coppia convergono sulla stessa Instance; Subject diversi ricevono stati completamente indipendenti.

Il tuo primo agente dovrebbe essere noioso e deterministico:

```elixir
defmodule MyApp.SupportAgent do
  use Spectre.Agent, history: 30

  router(via: [:regex])

  interrupt :HELP, regex: ~r/^(help|menu)$/iu do
    reply(:help, renderer: {MyApp.AgentReplies, :render})
  end

  flow :main do
    on :HELLO, regex: ~r/^(hi|hello)$/iu do
      reply(:hello, renderer: {MyApp.AgentReplies, :render})
    end

    on :ACCOUNT_STATUS, regex: ~r/^account status$/iu do
      run(:account_status)
    end
  end

  def account_status(input, context) do
    account_id = Keyword.fetch!(context.opts, :account_id)
    account = MyApp.Accounts.fetch!(account_id)

    {:ok,
     %Spectre.Result{
       input: input,
       route: context.route,
       state: context.state,
       reply_text: "Account status: #{account.status}"
     }}
  end
end
```

`reply/2` restituisce qualcosa di fisso. `run/2` chiama normale codice Elixir e `MyApp.Accounts` continua a possedere il dominio. Il modulo dell'agente rimane una mappa del comportamento invece di diventare un posto in cui nascondere le regole di business.

Ciò che stai verificando in questa fase non ha nulla a che fare con l'intelligenza: che il Subject sia corretto, che l'Instance venga riutilizzata, che i Turn vengano prodotti, che lo stato avanzi e che una risposta venga consegnata esattamente una volta.

## Risolvere il Subject e trovare l'Instance

Il gateway decide chi sta parlando:

```elixir
subject = Spectre.Subject.new({:user, user.id}, metadata: %{tenant_id: user.tenant_id})

{:ok, instance} =
  Spectre.ensure_instance(
    MyApp.SpectreSupervisor,
    MyApp.SupportAgent,
    subject,
    idle: :timer.minutes(30)
  )
```

Chiama `ensure_instance/4` a ogni messaggio. Non devi conservare un PID in un socket o in una LiveView, perché l'identità del runtime è la coppia logica, non il processo:

```text
MyApp.SupportAgent + Subject(user:42)
```

Il PID cambia dopo un riavvio. La coppia no.

Poi costruisci un vero input, con la sua origine allegata:

```elixir
input =
  Spectre.Input.new(%{
    text: message.text,
    meta: %{locale: user.locale},
    source: %{
      kind: :web,
      mount: :support_chat,
      conversation_id: message.thread_id,
      actor_id: user.id,
      reply_to: message.id,
      metadata: %{}
    }
  })

{:ok, turn} = Spectre.turn(instance, input, account_id: user.account_id, user_id: user.id)
```

Durante gli esperimenti puoi passare una semplice stringa, ma è la source che in seguito consente al runtime di associare un semplice «sì» alla policy in sospeso corretta, nella conversazione corretta. Aggiungerla ora costa poco; introdurla in seguito è doloroso.

Internamente il ciclo non ha nulla di straordinario, ed è proprio questo il punto:

```text
normalizza l'input → carica lo stato → eventualmente riprendi una policy
→ raccogli le evidenze di routing → scegli una route → esegui l'handler
→ aggiorna la cronologia → conferma lo stato → restituisci il Turn
```

Il Run si ferma al primo confine osservabile invece di nascondere routing, approvazione ed esecuzione dentro una sola chiamata.

## Il Turn è l'intera superficie API che consumi

Per il codice dell'applicazione, `turn.decision` è quasi tutto:

```elixir
case turn.decision do
  {:reply, result} ->
    MyApp.Chat.send(thread_id, result.reply_text)

  {:awaiting, _awaitable, result} ->
    MyApp.Chat.send(thread_id, result.reply_text)

  {:needs, effect, result} ->
    MyApp.Effects.enqueue(effect, result)

  {:completed, completion, result} ->
    MyApp.Audit.record(completion, result)

  {:no_response, result} ->
    MyApp.Audit.record_silent_turn(result)
end
```

| Decisione                            | Significato                                            |
| ------------------------------------ | ------------------------------------------------------ |
| `{:reply, result}`                   | Hai del testo da consegnare                            |
| `{:awaiting, awaitable, result}`     | Serve un input o la decisione di una policy            |
| `{:needs, effect, result}`           | L'effect è autorizzato e può essere eseguito           |
| `{:completed, completion, result}`   | L'operazione è terminata                               |
| `{:no_response, result}`             | Il Turn termina senza output visibile                  |

Invece di ripetere quel `case` in ogni canale, implementa una volta sola un dispatcher:

```elixir
defmodule MyApp.AgentDelivery do
  @behaviour Spectre.Turn.Dispatcher

  @impl true
  def deliver_reply(text, _result, opts) do
    MyApp.Chat.deliver(Keyword.fetch!(opts, :conversation_id), text)
  end

  @impl true
  def execute?(effect, _result, opts) do
    MyApp.Authorization.allow_effect?(Keyword.fetch!(opts, :user_id), effect)
  end

  @impl true
  def suppressed(_effect, _result, opts) do
    deliver_reply("You are not authorised to perform this operation.", nil, opts)
  end
end
```

Vale la pena ripetere un avvertimento: il valore predefinito di `execute?/3` è `true`. Per ogni agente che possiede un'azione sensibile, implementa il veto e ricontrolla l'autorizzazione al vero confine dell'applicazione.

## L'approvazione non è l'esecuzione

È qui che Spectre smette di sembrare una libreria per chat.

Un handler `run/2` può leggere dati e comporre una risposta. Quando vuoi attraversare un confine esterno — eliminare, pubblicare, inviare, pagare — dichiari un'azione e la proteggi:

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

Il primo messaggio produce `{:awaiting, awaitable, result}`. L'effect esiste, è in attesa della policy e `delete_account/2` non è stata chiamata.

La conferma produce `{:needs, effect, result}`. L'effect è ora approvato, ma non è ancora stato eseguito. Soltanto il dispatcher o l'host attraversa quel confine.

L'azione riceve un `effect_id` e un `idempotency_key`, e quella chiave deve essere scritta nella stessa transazione dell'operazione reale. Un controllo in ETS non protegge da un crash.

Tre stati che la maggior parte dei framework per agenti comprime in uno solo — proposto, approvato, eseguito — qui rimangono visibilmente distinti. È il motivo fondamentale per cui affiderei a questo runtime qualcosa di più serio della scrittura di una bozza.

## Dove guardare davvero quando si comporta male

Non nella cronologia della chat. La cronologia è contesto conversazionale; non è lo stato della macchina.

Quando un agente fa la cosa sbagliata, leggi in questo ordine:

```text
turn.result.input.text
turn.result.route.label
turn.result.state.revision
turn.result.state.current_flow
turn.result.state.current_scope
turn.result.state.awaitables
turn.result.state.pending_effects
turn.result.state.trace
turn.ref
Spectre.Instance.info(instance)
```

`Instance.info/1` fornisce una vista operativa rispettosa della privacy e `Instance.run/2` restituisce una vista compatta di un Run o della sua tombstone. Il token `Run.Ref` è anche la chiave di idempotenza naturale per la consegna:

```elixir
delivery_key = Spectre.Run.Ref.token(turn.ref)

MyApp.Deliveries.deliver_once(delivery_key, fn ->
  MyApp.Chat.send(conversation_id, turn.result.reply_text)
end)
```

Per ogni Turn registra nei log il token del Run, il tipo di decisione, l'etichetta della route e la revisione dello stato. Questi quattro campi rispondono alla maggior parte delle domande di produzione senza aprire un debugger.

## Un wizard richiede un elemento in più di quanto immagini

Impostare `current_flow` non fa arrivare magicamente un testo arbitrario nel passaggio corretto. Quando l'utente risponde `Spectre Cloud`, quella stringa non contiene alcun intento classificabile.

Una corretta conversazione a più passaggi è quindi composta da:

```text
una normale route iniziale
+ State.current_flow e State.current_scope
+ State.data che contiene la bozza
+ un plug deterministico di continuation routing che legge il cursore
+ un interrupt globale per annullamento/aiuto
+ una cancellazione esplicita quando il workflow termina
```

Il plug di continuazione legge il cursore, trova la regola esatta corrispondente, conserva gli interrupt globali e i comandi espliciti, rimuove i normali candidati che altrimenti sottrarrebbero la risposta e aggiunge un candidato deterministico. Le route di cattura rimangono invisibili al routing ordinario, perciò un messaggio casuale non può mai essere classificato come «nome del progetto».

E quando il workflow termina, cancella tu stesso il cursore:

```elixir
%{context.state | current_flow: nil, current_scope: nil,
                  data: Map.delete(context.state.data, :project_draft)}
```

Dimenticare quella riga è, nella mia esperienza, il modo più comune di costruire un agente che sembra infestato.

## Persistenza e differenza tra due livelli

Lo stato conversazionale è uno `%Spectre.State{}`: cursore del flow, dati del wizard, policy aperte, effect, cronologia, revisione. Salvalo con compare-and-swap, mai con una scrittura cieca:

```sql
UPDATE spectre_agent_states
SET payload = ..., revision = revision + 1
WHERE agent_id = ... AND subject_id = ... AND revision = expected_revision
```

Se nessuna riga è stata modificata, esiste un conflitto e un Turn precedente non deve sovrascrivere uno stato più recente.

Il secondo livello è il checkpoint dell'Instance, necessario quando esistono Run conservati, `Work`, `Vigil` e pianificazione. Un commit ambiguo a quel livello crea un persistence fence e non viene ritentato automaticamente, perché non è mai sicuro presumere che la scrittura precedente non sia avvenuta.

Questa riluttanza a tirare a indovinare è deliberata. Un crash non dimostra che non sia successo nulla.

## Conversazione, lavoro e osservazione sono cose diverse

Un flow risponde alla conversazione corrente. Un `Work` esegue una procedura finita che sopravvive al Turn che l'ha avviata:

```elixir
on :START_RESEARCH, regex: ~r/^research\s+.+$/iu do
  work(MyApp.ResearchWork, input: :text, origin: :chat, reply_text: "Research started.")
end
```

Il Turn della chat termina immediatamente. Il Work continua e puoi ispezionarlo, metterlo in pausa, aggiornarlo oppure esprimere aggiornamento e ripresa come un'unica intenzione durevole:

```elixir
{:ok, resumed} =
  Spectre.Instance.update_and_resume_loop(instance, work_ref, %{extra_urls: urls})
```

È così che «ho cambiato idea mentre era in esecuzione» diventa una vera transizione invece di un'altra frase aggiunta a un prompt. Un `Vigil` copre il terzo caso: un'osservazione ricorrente che si risveglia, controlla, conferma e torna in attesa.

La conversazione, l'operazione finita e l'osservazione durevole condividono un'Instance senza fondersi in un solo loop.

## L'ordine che seguirei davvero

Costruisci l'agente minimo: un Subject, un'Instance, tre route regex, un gateway, un dispatcher. Verifica che cinque messaggi dello stesso Subject raggiungano la stessa Instance.

Poi osserva i Turn e verifica che due messaggi normali producano due Run con revisioni consecutive dello stesso stato.

Poi aggiungi esattamente un'azione protetta e verifica che il primo Turn sia `:awaiting`, che l'azione non sia stata chiamata, che «no» annulli, che «yes» produca `:needs` e che l'azione venga eseguita una sola volta conservando la sua chiave di idempotenza.

Poi aggiungi il wizard, con il plug di continuazione e l'interrupt di annullamento. Poi la persistenza con compare-and-swap e un test di riavvio.

Soltanto dopo tutto questo introdurrei un modello, e anche allora per una singola route di ragionamento, non ancora per scegliere le azioni.

Prima di considerare terminato il primo agente, queste condizioni dovrebbero essere vere:

| Scenario                              | Risultato atteso                         |
| ------------------------------------- | ---------------------------------------- |
| Stesso Agent + stesso Subject         | Stessa Instance                          |
| Stesso Agent + Subject diverso        | Stato isolato                            |
| Due messaggi normali                  | Due Run, revisioni ordinate              |
| Wizard al secondo messaggio           | Route determinata da `current_flow`      |
| Interrupt di annullamento nel wizard  | Workflow cancellato                      |
| Policy risolta dalla stessa chat      | Ripresa del Run corretto                 |
| Policy risolta da un'altra chat       | Nessuna approvazione accidentale         |
| Due policy aperte, origine ambigua     | Errore esplicito                         |
| Webhook duplicato                     | Risposta consegnata una sola volta       |
| Effect ritentato                      | Operazione eseguita una sola volta       |
| Riavvio durante il wizard             | Stato ripristinato                       |
| Vecchio risultato dopo una revisione  | Risultato rifiutato                      |

## Che cosa stai imparando davvero

Iniziare con Spectre non significa vedere comparire la prima risposta in un terminale. Significa saper rispondere in ogni momento a sei domande:

```text
Chi è il Subject?
Chi possiede lo stato?
Da quale source proviene il messaggio?
Quale Run ha prodotto questo Turn?
Il risultato è una risposta, una policy o un effect?
Chi è autorizzato a eseguire l'effect?
```

Un primo agente che risponde a tutte e sei è piccolo: un Agent, un Subject per utente, un'Instance per coppia, tre route, un wizard, un'azione protetta, un dispatcher, uno state store con CAS. Nella mia esperienza è anche sufficiente per comprendere quasi tutto il runtime, perché ogni sistema più grande si appoggia allo stesso ciclo:

```text
Input → Instance → Run → State → Turn → confine dell'host
```

Il modello può unirsi in seguito e sarà davvero utile quando lo farà. Ma entra in un'applicazione che possiede già una forma, l'opposto di come viene costruita la maggior parte degli agenti.

Spectre è disponibile su GitHub all'indirizzo [github.com/elchemista/spectre](https://github.com/elchemista/spectre).
