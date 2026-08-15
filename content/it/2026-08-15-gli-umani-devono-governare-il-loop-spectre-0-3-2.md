---
title: "Gli umani devono governare il loop, non eseguirlo"
slug: "umani-governano-loop-spectre-streaming-0-3-2"
lang: "it"
status: published
date: 2026-08-15
updated: 2026-08-15
category: "Sviluppo software"
tags: ["Elixir","OTP","agenti AI","Spectre","streaming AI","human in the loop","governance","sistemi distribuiti"]
seo_title: "Governare agenti AI con Spectre 0.3.2"
seo_description: "Scopri come Spectre 0.3.2 governa inferenza e streaming con Instance, steering, budget, recovery, Receipt, Policy e confini umani espliciti in Elixir."
cover_alt: "Un operatore governa un Agent Spectre durante un'analisi di incidente, osservando streaming provvisorio, budget, steering e Result canonico"
---

Abbiamo costruito Agent capaci di lavorare per ore.

Poi abbiamo assunto un umano per premere "Continue" ogni trenta secondi.

Complimenti. Abbiamo automatizzato il lavoro creando un nuovo lavoro.

Una [collection di daily.dev sull'AI engineering nel
2026](https://daily.dev/posts/ai-engineering-in-2026-agents-are-everywhere-but-humans-still-run-the-loops-t8knr6vxz)
riassume bene il paradosso: gli Agent sono ovunque, ma gli umani continuano a
eseguire i loop. Controllano ogni passo, copiano risultati tra sistemi,
riavviano processi bloccati, osservano costi e decidono se una risposta
incompleta sia già abbastanza affidabile da essere usata.

Il problema non è la presenza dell'umano. Il problema è il ruolo che gli
abbiamo assegnato.

Un umano dovrebbe definire intenzione, autorità e limiti. Dovrebbe intervenire
quando cambia il giudizio necessario. Non dovrebbe diventare il scheduler,
il retry manager e il database transazionale di un modello probabilistico.

La release [Spectre `0.3.2`](https://github.com/elchemista/spectre/blob/0.3.2/CHANGELOG.md)
rende questa distinzione concreta. L'inferenza diventa una
`Spectre.Invocation` posseduta dall'Instance. Lo streaming non è più soltanto
testo inoltrato dal provider alla UI. Ha identità, budget, fencing,
cancellazione, steering, recovery e un punto preciso nel quale un risultato
provvisorio diventa canonico.

Questa non è una storia sul far apparire le parole un po' prima sullo schermo.
È una storia su chi possiede il loop.

## Il caso reale: un Incident Analyst che può essere corretto in corsa

Costruiamo un Agent per aiutare durante un incidente di produzione.

Riceve timeline, metriche e note già raccolte dall'applicazione. Analizza le
evidenze, propone un'ipotesi e prepara una spiegazione leggibile. Mentre sta
lavorando, l'operatore può accorgersi che la prima direzione è troppo larga e
scrivere:

> Concentrati soltanto sui timeout del servizio pagamenti dopo il deploy
> `checkout-1842`.

Un'implementazione ingenua concatena questa frase al prompt mentre il provider
sta ancora generando. Ora metà risposta appartiene alla vecchia intenzione e
metà alla nuova. La UI le mostra come se fossero un unico pensiero coerente.
Il sistema non sa più quale istruzione abbia prodotto quale testo.

Spectre sceglie una semantica più severa: lo steering sostituisce il tentativo.
Il vecchio stream termina come `:superseded`. Il nuovo tentativo riceve una
nuova Invocation e un nuovo epoch. L'applicazione deve consumare esplicitamente
il replacement.

Non è spettacolare. È meglio: è falsificabile.

## Preparare l'Agent senza nascondere il comportamento nel prompt

Partiamo dalla dipendenza pubblicata:

~~~elixir
defp deps do
  [
    {:spectre, "~> 0.3.2"}
  ]
end
~~~

Prima di avviare il servizio possiamo controllare il contratto installato e la
Definition dell'Agent:

~~~console
mix spectre.doctor --agent MyApp.IncidentAnalyst --strict
~~~

[`Doctor`](https://github.com/elchemista/spectre/blob/0.3.2/docs/INSTALLATION.md)
è read-only. Verifica versioni, matrice Foundation e forma pubblica
dell'Agent senza avviare risorse dei package o chiamare adapter esterni. Non
prova che il nostro deployment sia sicuro, ma scopre una classe molto meno
romantica di problemi: configurazioni incompatibili e contratti incompleti.

La Definition dell'Agent rimane normale codice Elixir:

~~~elixir
defmodule MyApp.IncidentActions do
  def restart_checkout(args, ctx) do
    key = Keyword.fetch!(ctx.opts, :idempotency_key)
    MyApp.Deployments.restart_checkout(args, idempotency_key: key)
  end
end

defmodule MyApp.IncidentAnalyst do
  use Spectre.Agent,
    id: :incident_analyst,
    prompt_root: "priv/agents/incident_analyst/prompts"

  model(MyApp.LLM)
  router(via: [:regex])

  actions MyApp.IncidentActions do
    protect(:restart_checkout, with: :restart_confirmation)
  end

  policy :restart_confirmation do
    request(:confirm_restart)
    accept(:confirmed_restart, regex: ~r/^confirm restart$/i)
    reject(:cancel_restart, regex: ~r/^(cancel|do not restart)$/i)
    attempts(2, then: :cancel_pending)
  end

  flow :incident_response do
    on :ANALYZE_INCIDENT,
      regex: ~r/\b(analyze|investigate|incident)\b/i,
      via: [:regex] do
      reason(:incident_analysis, temperature: 0.1)
    end

    on :RESTART_CHECKOUT,
      regex: ~r/^restart checkout$/i,
      via: [:regex] do
      action(:restart_checkout)
    end
  end
end
~~~

Qui ci sono già due confini diversi.

`reason/2` permette al modello di analizzare e rispondere, ma disabilita
l'Action planning. `action/1` seleziona invece un'operazione già conosciuta e
protetta da una Policy deterministica. Il testo del prompt aiuta il modello a
ragionare. Non decide se il servizio può essere riavviato.

La differenza sembra pedante soltanto fino al primo incidente reale.

## L'Instance possiede la conversazione, non il processo del provider

Lo streaming di `0.3.2` richiede un Agent Instance. È l'owner locale della
coppia `AgentRef + Subject`, dei Run trattenuti e dello stato canonico.

Per l'esempio abilitiamo anche Receipt osservazionali:

~~~elixir
children = [
  {Spectre.Supervisor, name: MyApp.SpectreSupervisor},
  {Spectre.Receipt.Sink.Memory, name: MyApp.IncidentReceipts}
]

subject = Spectre.Subject.new({:incident, "INC-742"})

{:ok, instance} =
  Spectre.ensure_instance(
    MyApp.SpectreSupervisor,
    MyApp.IncidentAnalyst,
    subject,
    receipt_mode: :observational,
    receipt_sink:
      {Spectre.Receipt.Sink.Memory, server: MyApp.IncidentReceipts},
    max_stream_sessions: 2,
    idle: :timer.minutes(15)
  )
~~~

Il sink in memoria va bene per una demo e per i test. Non è una scelta di
produzione. Più avanti vedremo cosa cambia con Receipt richiesti e storage
durevole.

Quando parte un'inferenza, l'Instance committa selezione del modello e intento
di dispatch. Il tentativo del provider viene eseguito fuori dalla sua mailbox.
Questo evita che la latenza del modello trasformi l'owner dello stato in un
processo incapace di ricevere controlli.

Il provider può essere lento. L'Instance non deve diventare sordo.

## Aprire uno stream con limiti veri

Il trasporto vive in un package o modulo che implementa
[`Spectre.Inference.StreamAdapter`](https://github.com/elchemista/spectre/blob/0.3.2/docs/STREAMING_INFERENCE.md).
Core possiede lifecycle e limiti, non il client HTTP specifico del provider.

~~~elixir
{:ok, stream} =
  Spectre.stream(
    instance,
    "Analyze incident INC-742 and explain the most likely cause.",
    plan_actions?: false,
    stream_adapter: MyApp.StreamAdapter,
    stream_adapter_opts: [profile: :fast],
    inference_budget: [
      input_tokens: 12_000,
      output_tokens: 2_000,
      total_tokens: 14_000,
      attempts: 2,
      duration_ms: 120_000
    ],
    stream_provider_stall_timeout: 15_000,
    stream_max_duration_ms: 120_000,
    stream_result_timeout: 30_000
  )
~~~

In `0.3.2` lo streaming supporta intenzionalmente generazione testuale senza
Action planning o structured output. `plan_actions?: false` non è una formula
magica da copiare. Dichiara che questo percorso sta producendo analisi, non
autorità sul mondo esterno.

Un hard budget di costo richiederebbe anche un pricing ref immutabile e usage
di costo autorevole dichiarato dall'adapter. Spectre non trasforma una stima
ottimista in contabilità soltanto perché il numero sembra preciso.

## Un delta non è ancora la risposta dell'Agent

Lo stream è un Enumerable pull-driven e one-shot. Un consumer può gestirlo
così:

~~~elixir
Enum.each(stream, fn
  %Spectre.Inference.StreamEvent{kind: :delta, payload: text} ->
    MyApp.IncidentUI.render_provisional(text)

  %Spectre.Inference.StreamEvent{kind: :usage, usage: usage} ->
    MyApp.IncidentUI.update_meter(usage)

  %Spectre.Inference.StreamEvent{kind: :inference_completed} ->
    MyApp.IncidentUI.mark_provider_complete()

  %Spectre.Inference.StreamEvent{
    kind: :result,
    payload: %Spectre.Result{} = result
  } ->
    MyApp.IncidentUI.deliver_committed(result)

  %Spectre.Inference.StreamEvent{kind: kind}
  when kind in [
         :failed,
         :cancelled,
         :ambiguous,
         :interrupted,
         :superseded
       ] ->
    MyApp.IncidentUI.mark_terminal(kind)
end)
~~~

La distinzione importante è tra `:delta` e `:result`.

Un delta è testo provvisorio. Ha attraversato lo screening incrementale, ma
non il normale post-processing completo e non il commit finale del Run. Non va
salvato come risposta autorevole, inviato via email o usato per attivare un
Effect.

Il `:result` contiene invece il `%Spectre.Result{}` canonico. Il provider ha
terminato, la risposta completa ha attraversato i controlli e il Run è stato
committato.

Concatenare i delta per ricostruire il risultato è scorretto. Il sanitizer
incrementale può sopprimere più testo del sanitizer terminale, per esempio
quando un marker di controllo attraversa due chunk UTF-8. La relazione di
sicurezza va in una sola direzione: il provvisorio può mostrare meno, mai più
di ciò che il controllo completo permetterebbe.

Se interessa soltanto il risultato canonico, non serve enumerare:

~~~elixir
{:ok, %Spectre.Result{} = result} =
  Spectre.await_result(stream, 60_000)
~~~

Lo streaming rimane utile per la UI. Il risultato rimane utile per il sistema.
Confondere i due è comodo finché non conta.

## Lo steering non modifica il passato

Durante l'analisi l'operatore restringe il problema:

~~~elixir
{:ok, replacement} =
  Spectre.Inference.Stream.steer(
    stream,
    "Focus only on payment timeouts after deploy checkout-1842."
  )
~~~

Il vecchio Enumerable termina con `:superseded`. Non comincia improvvisamente
a emettere eventi appartenenti al replacement. Il nuovo handle ha un altro
stream epoch e un'altra Invocation e deve essere consumato esplicitamente.

Questo dettaglio elimina una bug classica delle interfacce generative: testo
prodotto sotto istruzioni diverse presentato come un'unica risposta.

L'handle contiene inoltre un bearer token vivo. Il suo `Inspect` lo nasconde,
ma questo non lo rende un oggetto durevole. Può rimanere nello stato locale di
un processo autorizzato. Non deve finire in database, log, PubSub o payload
inviati al browser.

L'operatore può cambiare direzione. Non può riscrivere retroattivamente quale
intenzione abbia generato i token già prodotti.

## Backpressure significa prima della mailbox

Molti sistemi dichiarano di avere backpressure perché mantengono una coda
limitata dopo aver ricevuto dati illimitati. È una frase rassicurante, non una
proprietà.

Spectre preferisce adapter pull. Lo StreamSession concede al trasporto al
massimo un credito alla volta. Un adapter push è ammesso soltanto se dichiara
`:bounded_push_transport` e applica un limite reale prima che i messaggi
entrino nella mailbox.

Core limita durata, attach, stall del provider, inattività del consumer,
dimensione dei delta, risposta accumulata, eventi e byte in coda. L'adapter
possiede invece i due limiti che Core non può più vedere dopo il parsing:
dimensione del chunk grezzo e residuo del parser.

Questa separazione è importante. Spectre può verificare il proprio confine.
Non può fingere di controllare il socket di una libreria HTTP che non applica
flow control.

## Il crash non autorizza un retry creativo

Supponiamo che l'Instance cada dopo il dispatch. Il provider potrebbe essere
ancora al lavoro, aver concluso o aver addebitato la richiesta. L'assenza di un
risultato locale non prova che il lavoro esterno non sia avvenuto.

Durante il recovery Spectre osserva ciò che può dimostrare:

| Evidenza disponibile | Comportamento |
| --- | --- |
| Il provider non è ancora partito | Il dispatch può iniziare in sicurezza |
| Esiste un cursore durevole e l'adapter supporta `:resume` | Viene committata una Invocation successiva con nuovo epoch |
| Esiste un request id stabile e l'adapter supporta `:reconcile` | L'adapter classifica il lavoro incerto |
| Non esiste evidenza sufficiente | Il Run termina come `:interrupted` o `:ambiguous` |

Il vecchio handle non cambia in place. Se il recovery ha creato un successore,
l'owner può richiederlo presentando il vecchio handle come prova correlata:

~~~elixir
{:ok, replacement} = Spectre.resume_stream(instance, old_stream)
~~~

Il sistema preferisce un'ambiguità esplicita a un secondo addebito nascosto.
È una scelta meno magica e molto più economica.

## L'umano rientra quando cambia l'autorità

L'analisi può avanzare autonomamente dentro budget e Definition. Il riavvio di
un servizio è diverso.

Quando l'operatore scrive `restart checkout`, la route non usa lo stream
precedente come autorizzazione. Apre un normale Turn, prepara l'Effect
`restart_checkout` e incontra `:restart_confirmation`. Soltanto una risposta
che soddisfa la Policy dichiarata può approvarlo. L'applicazione host deve poi
eseguire separatamente la capability reale e usare l'idempotency key nel
proprio confine durevole.

Questa è la forma utile di human in the loop.

L'umano non convalida ogni token. Decide quando il sistema chiede nuova
autorità. Il codice decide quando quella domanda è obbligatoria.

Per azioni selezionate dal modello, `0.3.2` aggiunge anche validazione di un
sottoinsieme limitato di JSON Schema sia al confine di planning sia a quello di
esecuzione. Un argomento malformato non diventa più credibile dopo
l'approvazione umana.

## Receipt: evidenza, non mitologia exactly-once

I [Receipt di confine](https://github.com/elchemista/spectre/blob/0.3.2/docs/RECEIPTS.md)
sono opzionali. In modalità `:observational` vengono
aggiunti dopo il commit canonico e un guasto del sink non blocca il Run. In
modalità `:required`, Spectre usa un outbox checkpointed e impone una barriera
prima di attraversare il confine configurato.

La modalità richiesta pretende un vero Checkpoint Store durevole e un
`Spectre.Receipt.Sink` capace di conservare payload content-addressed. Il sink
in memoria dell'esempio non soddisfa questa responsabilità operativa.

Un `Spectre.Receipt.Envelope` lega l'evidenza tipizzata a Definition, closure e
radici canoniche pre e post. Redige chiavi costituzionalmente sensibili prima
di calcolare il digest. Non include credenziali, cursori, raw provider error o
request id pubblici.

Ma un Receipt non prova replay deterministico. Non prova exactly-once del
provider. Non prova exactly-once di un Effect esterno. Dimostra che una
specifica evidenza è legata a uno specifico confine e a uno specifico stato.

È già molto. Chiamarlo più di questo lo renderebbe meno utile, non più forte.

## Quali problemi Spectre chiude davvero

Ora possiamo tornare al paradosso iniziale senza trasformarlo in marketing.

| Concern | Confine fornito da Spectre |
| --- | --- |
| L'umano deve sorvegliare ogni iterazione | Policy, budget e controlli nominati spostano l'intervento sui cambi di autorità o intenzione |
| Il modello produce output tardivo o duplicato | Fencing su generation, Run, Invocation, dispatch, epoch e sequence rifiuta eventi stale |
| Una correzione in corsa mescola due richieste | Lo steering sostituisce il tentativo e termina il precedente come `:superseded` |
| La UI tratta i token come verità | Delta provvisori e Result canonico hanno eventi e semantiche diverse |
| Costi e loop crescono senza un tetto | Budget aggregati, deadline, capacità e buffer sono finiti |
| Un crash invita a ripetere lavoro incerto | Resume e reconcile richiedono evidenza del provider, altrimenti l'esito resta esplicito |
| Non sappiamo quale stato abbia attraversato un confine | Receipt opzionali legano evidenza e radici canoniche pre e post |
| Le regole cambiano insieme al prompt | Definition, Action, Policy e authority rimangono strutture di codice e dati verificabili |

Spectre non elimina il giudizio umano. Gli assegna un indirizzo.

## Cosa Spectre non chiude al posto dell'applicazione

Un runtime onesto deve anche dichiarare dove finisce.

Spectre non crea automaticamente credenziali OAuth task-scoped. Non decide il
RBAC del database. Non rende sicuro un token amministrativo troppo largo. Non
trasforma un container ordinario in una sandbox kernel-isolated. Non può
garantire durability di un adapter che mente e non può imporre backpressure a
un client HTTP che ha già riempito una mailbox.

Queste responsabilità appartengono all'host, al deployment o a package
specializzati. Spectre offre punti nei quali applicarle: Authority Envelope,
Action ed Effect boundary, Policy, Checkpoint Store, Receipt Sink,
StreamAdapter e operation registry chiuso.

La differenza è sottile ma decisiva. Un confine esplicito non risolve da solo
la sicurezza. Rende possibile implementarla e testarla senza chiedere al
modello di ricordarsene.

## Il loop appartiene al sistema

L'autonomia non significa assenza di controllo. Significa che il controllo è
stato trasformato da attenzione umana continua a struttura verificabile.

Con Spectre `0.3.2`, un'inferenza ha owner, identità, budget e terminalità. Uno
stream può essere osservato senza essere scambiato per verità. Un operatore può
cambiare direzione senza fondere due tentativi. Un crash conserva l'ambiguità
invece di nasconderla dietro un retry. Un Effect sensibile torna all'umano
perché una Policy lo richiede, non perché qualcuno stava fissando la console.

Il modello può eseguire il lavoro cognitivo.

L'umano governa il cambiamento di intenzione e autorità.

Il runtime possiede il loop.
