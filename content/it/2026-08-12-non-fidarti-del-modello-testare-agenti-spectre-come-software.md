---
title: "Non fidarti del modello: testare un agente Spectre come software"
slug: "non-fidarti-del-modello-testare-agenti-spectre-come-software"
lang: "it"
status: published
date: 2026-08-12
updated: 2026-08-12
category: "Sviluppo software"
tags: ["Elixir","ExUnit","agenti AI","Spectre","testing","OTP","Policy","idempotenza"]
seo_title: "Testare agenti Spectre senza fidarsi del modello"
seo_description: "Scopri come testare routing, Policy, Effect, crash, retry e Candidate Morph in Spectre 0.3.0 separando invarianti deterministiche ed eval del modello."
cover_alt: "Una suite ExUnit circonda un modello probabilistico e verifica i confini deterministici di un agente Spectre"
---

Un agente ha prodotto la risposta corretta. Il test passa.

Ma ha chiamato il modello tre volte quando non serviva? Ha preparato un'azione
distruttiva prima dell'approvazione? Ha eseguito due volte la stessa operazione
dopo un timeout? Ha modificato lo stato durevole prima che il commit riuscisse?

Se il test controlla soltanto il testo finale, non conosce nessuna di queste
risposte.

È uno dei problemi più strani del software agentico: un risultato corretto può
nascondere un percorso sbagliato, costoso o pericoloso. Un modello può arrivare
alla frase desiderata dopo aver ignorato una Policy. Un router può scegliere la
route giusta usando inutilmente un LLM. Un executor può restituire un errore
dopo aver già creato il record nel sistema esterno.

La filosofia di Spectre parte da qui:

> **Non devi dimostrare che il modello sarà sempre affidabile. Devi dimostrare
> che il runtime non gli permetterà di oltrepassare confini verificabili.**

In Spectre 0.3.0 il modello rimane probabilistico, ma ownership, lifecycle,
Policy, Effect, revisioni e commit sono software. Possono essere testati come
software.

## Un test e una eval rispondono a domande diverse

La prima distinzione importante è tra **contratto** e **qualità
probabilistica**.

Un test ExUnit dovrebbe rispondere a domande come:

- un Effect protetto rimane ineseguibile prima dell'approvazione?
- un rifiuto impedisce davvero la chiamata dell'Action?
- una label host sconosciuta lascia lo stato invariato?
- un crash dopo il commit viene classificato come ambiguo?
- un retry conserva la stessa chiave di idempotenza?
- una Session ripristina il lavoro pendente dopo il riavvio?

Una eval del router risponde invece a domande come:

- questi ottanta modi di chiedere assistenza arrivano alla route corretta?
- quali input ambigui richiedono davvero il modello?
- una route deterministica ha iniziato a chiamare inutilmente l'LLM?
- il cambiamento di prompt o modello ha ridotto il pass rate?

Sono entrambe necessarie, ma non sono intercambiabili.

| Livello | Che cosa verifica | Deve essere deterministico? |
| --- | --- | --- |
| Unit e contract test | Transizioni, callback, stato e confini di autorità | Sì |
| Lifecycle test OTP | Crash, restart, recovery, fencing e replay | Sì |
| Routing eval | Comportamento sopra un corpus e uso consentito dell'LLM | Il corpus e le soglie sì; il provider può essere simulato o reale |
| Morph evaluation | Regressioni tra Definition parent e Candidate | Gate e receipt sì; eventuali provider live vanno separati |
| Test con provider reale | Compatibilità, latenza e comportamento del modello o embedding reale | No; deve vivere in una suite separata |

Se mescoli tutto in una sola suite online, ogni fallimento diventa ambiguo. Non
sai più se hai rotto una transizione del runtime, modificato un prompt o
ricevuto una risposta diversa dal provider.

## Costruiamo il più piccolo Agent interessante

Usiamo un Agent che può creare un progetto soltanto dopo l'accettazione di una
Policy. L'Action è normale codice Elixir e invia un messaggio al processo di
test quando viene realmente invocata:

```elixir
defmodule MyApp.ProjectActions do
  def create_project(args, ctx) do
    if pid = Keyword.get(ctx.opts, :test_pid) do
      send(pid, {:project_created, args})
    end

    {:ok, %{id: "project-123", args: args}}
  end
end

defmodule MyApp.ProjectAgent do
  use Spectre.Agent

  router(via: [:regex])

  input_pipeline do
    plug(Spectre.Input.Plugs.NormalizeText,
      trim?: true,
      case: :downcase
    )
  end

  actions MyApp.ProjectActions do
    protect(:create_project, with: :terms)
  end

  policy :terms do
    accept(:accepted_terms, regex: ~r/^yes$/i)
    reject(:rejected_terms, regex: ~r/^(no|cancel)$/i)
    attempts(2, then: :cancel_pending)
  end

  flow :projects do
    on :START_PROJECT,
      regex: ~r/^start project$/i,
      via: [:regex],
      cache: false do
      action(:create_project, args: %{source: "chat"})
    end
  end
end
```

Questo Agent non ha bisogno di un modello per il test. Non stiamo simulando
l'intelligenza; stiamo isolando il contratto che deve rimanere vero qualunque
modello venga montato in futuro.

## Il test più importante controlla ciò che non accade

Il primo Turn prepara l'intenzione, ma deve fermarsi alla Policy:

```elixir
defmodule MyApp.ProjectAgentTest do
  use ExUnit.Case, async: true

  alias MyApp.ProjectAgent
  alias Spectre.Awaitable
  alias Spectre.Effect
  alias Spectre.Result

  test "un'Action protetta non viene eseguita prima dell'approvazione" do
    assert {:ok, turn} =
             Spectre.turn(
               ProjectAgent,
               "  START PROJECT  ",
               test_pid: self()
             )

    assert {:awaiting, %Awaitable{name: :terms, status: :open}, result} =
             turn.decision

    assert [%Effect{status: :waiting_policy} = waiting] =
             result.state.pending_effects

    waiting_id = waiting.id

    assert {:error, {:effect_not_approved, ^waiting_id}} =
             execute(result)

    refute_received {:project_created, _args}
  end

  defp execute(%Result{} = result) do
    Spectre.execute(result.state, %{
      agent: ProjectAgent,
      input: result.input,
      state: result.state,
      opts: [test_pid: self()]
    })
  end
end
```

Il valore restituito è soltanto una parte della prova. La riga decisiva è:

```elixir
refute_received {:project_created, _args}
```

Dimostra che la capability non è stata invocata. Un'asserzione sul testo
«Please confirm» non lo dimostrerebbe: l'Agent potrebbe aver creato il progetto
e poi chiesto conferma troppo tardi.

Un buon contract test osserva sempre entrambe le metà del confine:

1. il valore restituito o l'esito del processo;
2. le callback chiamate, nel numero e nell'ordine corretti;
3. le callback che non devono essere chiamate;
4. lo stato in memoria e quello durevole prima e dopo il commit;
5. il comportamento dopo retry, replay o restart.

La coverage dice quali righe sono state attraversate. Non dice che un Effect è
stato eseguito una sola volta.

## Approvazione ed esecuzione devono restare due prove separate

Ora possiamo continuare lo stesso stato con `yes`. La Policy possiede questa
risposta, quindi il normale router non deve reinterpretarla:

```elixir
test "l'approvazione rende l'Effect eseguibile ma non lo esegue da sola" do
  assert {:ok, awaiting_turn} =
           Spectre.turn(
             ProjectAgent,
             "start project",
             test_pid: self()
           )

  assert {:awaiting, _awaitable, awaiting_result} =
           awaiting_turn.decision

  assert {:ok, approved_turn} =
           Spectre.turn(
             ProjectAgent,
             "yes",
             state: awaiting_result.state,
             test_pid: self()
           )

  assert {:needs, %Effect{status: :approved}, approved_result} =
           approved_turn.decision

  refute_received {:project_created, _args}

  assert {:ok, execution} = execute(approved_result)
  assert_receive {:project_created, %{source: "chat"}}
end
```

Questo test prova tre fatti distinti:

```text
proposta dell'Action != approvazione != esecuzione
```

Se un refactoring fa partire automaticamente l'Action durante la risoluzione
della Policy, `refute_received/1` lo rileva anche quando l'output finale sembra
corretto.

Un host fidato può risolvere la stessa Policy usando una label dichiarata:

```elixir
{:ok, approved_turn} =
  Spectre.Turn.resolve_policy(
    awaiting_turn,
    {:accept, :accepted_terms}
  )
```

Vale la pena testare anche una label inesistente. La chiamata deve restituire
errore e lo stato della Session non deve cambiare. Non basta controllare che
l'Action non sia partita: anche un tentativo fallito di approvazione non deve
consumare o corrompere l'Awaitable.

## Il percorso negativo è comportamento di prima classe

Il rifiuto non è un'eccezione intorno all'happy path. È una transizione
terminale del lifecycle:

```elixir
test "il rifiuto cancella l'Effect senza invocare l'Action" do
  assert {:ok, awaiting_turn} =
           Spectre.turn(
             ProjectAgent,
             "start project",
             test_pid: self()
           )

  assert {:awaiting, _awaitable, awaiting_result} =
           awaiting_turn.decision

  assert {:ok, rejected_turn} =
           Spectre.turn(
             ProjectAgent,
             "no",
             state: awaiting_result.state,
             test_pid: self()
           )

  assert {:completed, %Effect{status: :cancelled} = cancelled, result} =
           rejected_turn.decision

  assert Effect.outcome(cancelled) ==
           {:cancelled, {:policy_rejected, :rejected_terms}}

  assert result.state.pending_effects == []
  refute_received {:project_created, _args}
end
```

La matrice completa della Policy dovrebbe includere almeno:

- accept;
- reject;
- risposta sconosciuta;
- esaurimento dei tentativi;
- scadenza;
- label host inesistente;
- seconda risoluzione dello stesso Awaitable; e
- più Awaitable candidati senza una source sufficiente a disambiguarli.

Il caso «maybe» è particolarmente utile. Deve incrementare i tentativi e
rimanere nella Policy senza richiamare classifier o LLM. Una risposta breve a
una conferma aperta non deve tornare nel normale reasoning loop.

## Un LLM finto è uno strumento, non il giudice del test

Quando una route richiede un modello, usa un adapter deterministico nella suite
normale. Un test double può registrare ogni invocazione e restituire una label
controllata:

```elixir
defmodule MyApp.TestLLM do
  @behaviour Spectre.LLM

  @impl Spectre.LLM
  def complete(prompt, opts) do
    send(Keyword.fetch!(opts, :test_pid), {:llm_called, prompt})
    {:ok, "PROJECT_SUPPORT"}
  end
end
```

Ora puoi distinguere due invarianti:

```elixir
assert_receive {:llm_called, prompt}
assert prompt =~ "PROJECT_SUPPORT"
```

oppure:

```elixir
refute_received {:llm_called, _prompt}
```

La seconda asserzione è spesso più importante. Se una regex o un classifier
locale possiede già evidenza sufficiente, raggiungere la route corretta dopo
una chiamata LLM è comunque una regressione di costo, latenza e privacy.

Non usare un secondo modello per decidere se il contract test è passato. Il
modello può aiutare una eval semantica; non deve giudicare se una callback
vietata è stata invocata.

## Il corpus di routing misura anche l'uso del modello

Per un Agent che combina route regex, classifier locale e fallback LLM,
Spectre include `mix spectre.eval` per eseguire un corpus JSONL attraverso le
vere pipeline di input e routing:

```json
{"id":"start-project-exact","input":"start project","expected_route":"START_PROJECT","expected_strategy":"regex","llm":"forbidden","tags":["deterministic"]}
{"id":"project-support-local","input":"I need help with my project","expected_route":"PROJECT_SUPPORT","llm":"forbidden","tags":["local"]}
{"id":"ambiguous-project-request","input":"something is wrong with the setup","allowed_routes":["PROJECT_SUPPORT","ACCOUNT_SUPPORT"],"llm":"required","tags":["ambiguous"]}
```

Puoi usarlo come gate riproducibile:

```bash
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/spectre-routing.json
```

Il report misura pass rate, accuratezza delle route, strategie usate,
violazioni della policy LLM e latenza p50/p95. Il comando fallisce quando le
soglie dichiarate non vengono rispettate.

La proprietà interessante è `llm`: `forbidden`, `allowed` oppure `required`.
Una route può essere corretta e il caso può fallire ugualmente perché il
modello è stato chiamato quando non serviva.

Per ispezionare un solo caso senza eseguire handler, Action o persistenza:

```elixir
{:ok, receipt} =
  Spectre.Router.evaluate(
    MyApp.ProjectAgent,
    "start project",
    state: %Spectre.State{current_flow: :projects}
  )

assert receipt.label == :START_PROJECT
assert receipt.strategy == :regex
refute receipt.llm_called?
```

La receipt conserva metadati operativi sanitizzati, non prompt, input o output
grezzi del provider. La routing evaluation non esegue l'handler selezionato,
non carica memoria, non persiste stato e non esegue Action: misura il router,
non finge di essere un test end-to-end.

## Uccidere il processo è diverso dal simulare `{:error, reason}`

Spectre vive sopra OTP. Controllare soltanto il valore restituito da un adapter
non prova cosa succede quando un processo esce, viene ucciso o scade durante un
confine.

Un lifecycle test serio deve avviare i processi supervisionati reali e
iniettare il fallimento in punti differenti:

```text
input
  -> load dello stato
  -> recall della memoria
  -> handler e routing
  -> journal di arbitration
  -> rendering
  -> compare-and-set dello stato
  -> journal di persistenza
  -> persist della memoria
```

Per ogni interruzione bisogna verificare che:

- nessuna callback successiva venga chiamata;
- la revisione durevole cambi soltanto dopo il commit;
- non rimanga un processo zombie registrato;
- il Supervisor ricrei soltanto i child che devono essere ricreati;
- il Turn successivo recuperi dallo stato autorevole; e
- un risultato tardivo con fencing obsoleto venga rifiutato.

Questo è il motivo per cui un test del child specification non basta. Dimostra
che il Supervisor *potrebbe* avviare il processo, non che pending Effect e
Awaitable sopravvivano a un crash reale.

La suite `0.3.0` di Spectre usa processi supervisionati reali proprio per
distinguere shutdown normale, crash anomalo, stato ripristinabile e risorse ETS
orfane.

## Un timeout non prova che l'Action sia fallita

Consideriamo questo ordine:

```text
Action esterna crea il progetto
  -> il database applicativo esegue commit
  -> il worker crasha prima della receipt Spectre
```

Dal punto di vista del runtime, l'esito è ambiguo. Ripetere l'Action con una
nuova identità potrebbe creare due progetti.

Per questo `Spectre.execute` inserisce `:effect_id` e
`:idempotency_key` in `ctx.opts`. L'applicazione deve usare quella chiave nello
stesso confine durevole del side effect:

```elixir
def create_project(args, ctx) do
  idempotency_key = Keyword.fetch!(ctx.opts, :idempotency_key)
  MyApp.Projects.create_once(idempotency_key, args)
end
```

`create_once/2` deve essere una vera operazione applicativa idempotente, per
esempio protetta da un vincolo univoco persistito insieme al progetto. Una ETS
temporanea o un flag nel processo non basta dopo un restart.

Il relativo contract test deve provocare un crash **dopo** il business commit,
far ripartire la Session e osservare:

- più tentativi esterni;
- la stessa chiave di idempotenza in ogni tentativo;
- un solo progetto o pagamento nel sistema di dominio; e
- un unico esito terminale accettato dal Run.

OTP può riavviare il worker. Non può annullare un bonifico o eliminare il
secondo ordine creato per errore.

## Morph aggiunge test di regressione prima dell'attivazione

ExUnit verifica il programma e i confini dell'applicazione. Morph deve inoltre
verificare che una nuova Definition non rompa il comportamento già protetto.

Un corpus minimo può dichiarare un comportamento che deve rimanere invariato:

```elixir
protected_cases = [
  %{
    "id" => "weather-stays-unhandled",
    "input" => "weather",
    "expected_outcome" => "clarify",
    "context" => %{"scope" => "support"},
    "llm" => "forbidden"
  }
]

change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Teach the Agent about refunds"
  )
  |> Spectre.Morph.mount_skill("refunds",
    match: {:exact, "refund"},
    reply: "Refund policy applies to: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Morph confronta parent e Candidate sullo stesso corpus e deriva ulteriori
obblighi dal diff reale. Il caso creato dalla Candidate per dimostrare la nuova
Skill deve passare, ma non aumenta il punteggio protetto: una modifica non può
scrivere test facili per se stessa e usarli per nascondere una regressione.

La prova completa non termina con `evaluate/2`. Prima e dopo l'attivazione
esegui anche un vero `Spectre.turn/3` e verifica che:

- prima la nuova route non esista;
- una Candidate non approvata non cambi il comportamento vivo;
- dopo l'attivazione un nuovo Run usi la nuova Definition;
- un Run già aperto rimanga pinned alla Definition precedente; e
- una Candidate obsoleta richieda un rebase esplicito.

L'evoluzione senza regression test non è apprendimento: è deriva.

## I provider reali appartengono a una suite separata

La suite normale deve essere veloce, offline e deterministica. Questo significa
usare fake LLM, fixture di embedding, clock controllati e adapter strumentati.

Ma una fixture non dimostra che il modello reale venga caricato, che un NIF
funzioni o che il provider rispetti ancora il contratto. Servono anche pochi
test opt-in con integrazioni reali.

La separazione è importante:

- i test deterministici vengono eseguiti continuamente;
- le eval con provider reale possono costare e produrre variazioni;
- i test nativi o di rete possono avere un job dedicato;
- una fixture congelata non viene presentata come prova dell'inferenza reale;
- un fallimento del provider non rende rosso ogni contract test del runtime.

La suite di Spectre applica già questa distinzione al semantic cache: il
contratto offline controlla cardinalità delle chiamate e vettori persistiti;
il test ExFastembed reale viene eseguito separatamente e in modo esplicito.

## La matrice minima per un Agent di produzione

Prima di affidare a un Agent un side effect reale, io pretenderei almeno questi
casi:

| Caso | Prova richiesta |
| --- | --- |
| Route deterministica | Route corretta e zero chiamate LLM |
| Route ambigua | Modello chiamato soltanto quando consentito o richiesto |
| Action protetta | Nessuna invocazione prima della Policy |
| Policy rifiutata | Effect cancellato, pending svuotato, zero invocazioni |
| Risoluzione host non valida | Errore e stato invariato |
| Retry dell'Action | Stessa idempotency key e un solo business effect |
| Store prima del commit | Fallimento definito e revisione durevole invariata |
| Store dopo il commit | Esito ambiguo, recovery e nessun retry cieco |
| Crash della Session | Stato pendente ripristinato senza zombie |
| Candidate Morph | Corpus protetto invariato prima dell'attivazione |
| Provider reale | Piccola suite opt-in distinta dai contratti offline |

Non è necessario scrivere tutto il primo giorno. È necessario sapere quale
affermazione ogni test sta realmente dimostrando.

## Che cosa Spectre non può provare al posto della tua applicazione

La suite del framework può provare il lifecycle del framework. Non può provare
automaticamente che il tuo confine di dominio sia corretto.

L'applicazione host deve aggiungere test end-to-end per:

- autorizzazione usando dati di business correnti;
- idempotenza durevole delle proprie Action;
- adapter dello State Store e loro reali semantiche di commit;
- deduplicazione della consegna di messaggi e notifiche;
- gestione di secret e dati sensibili;
- prompt, modelli e corpus specifici del prodotto;
- rollback applicativo quando il mondo esterno lo consente; e
- procedure operative di recovery quando l'esito rimane ambiguo.

Una Policy conferma un'intenzione. Non sostituisce un controllo di
autorizzazione al confine della capability. Una chiave di idempotenza fornita
da Spectre non deduplica nulla se l'Action non la persiste. Un Supervisor non
rende transazionale un'API esterna.

Questi limiti non indeboliscono il modello. Rendono visibile chi possiede ogni
prova.

## Una pipeline pratica

Per la maggior parte dei progetti partirei da questa pipeline:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test --cover
mix spectre.eval MyApp.SupportAgent test/fixtures/routing.jsonl \
  --json tmp/spectre-routing.json
```

Poi terrei separati i job opt-in per provider, modelli, embedding o servizi
esterni reali.

La documentazione di Spectre 0.3.0 dedica una [guida completa ai contratti di
testing](https://github.com/elchemista/spectre/blob/0.3.0/docs/TESTING.md),
mentre la [suite end-to-end dei
Turn](https://github.com/elchemista/spectre/blob/0.3.0/test/full_agent_turn_test.exs)
mostra gli stessi confini con adapter strumentati. I test di
[lifecycle supervisionato](https://github.com/elchemista/spectre/blob/0.3.0/test/system_lifecycle_contract_test.exs)
coprono crash, restore e idempotenza dopo il business commit.

## Il modello può sbagliare senza possedere il sistema

Un agente utile non diventa deterministico soltanto perché lo desideriamo. Il
modello continuerà a interpretare male alcuni input, cambierà comportamento tra
versioni e produrrà risposte che nessun corpus aveva previsto.

Il compito del runtime non è fingere di eliminare questa incertezza. È
circondarla con componenti per i quali possiamo scrivere affermazioni precise:

- questa route non deve chiamare il modello;
- questo Effect non può essere eseguito adesso;
- questo rifiuto è terminale;
- questo commit è ambiguo e non va ripetuto ciecamente;
- questa Candidate non può essere attivata;
- questo risultato tardivo non appartiene più alla revisione corrente.

È la differenza tra testare una conversazione e testare un sistema.

Spectre non chiede di fidarsi meno dell'intelligenza del modello. Chiede di non
confondere mai l'intelligenza con l'autorità. **Il modello può rimanere
probabilistico; i confini entro cui opera devono essere falsificabili.**
