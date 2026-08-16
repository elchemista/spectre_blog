---
title: "Un Agent enterprise non è un chatbot con le credenziali di produzione"
slug: "agent-enterprise-spectre-controllo-sicurezza"
lang: "it"
status: published
date: 2026-08-16
updated: 2026-08-16
category: "Software Development"
tags: ["Elixir","OTP","AI agents","Spectre","enterprise AI","sicurezza","audit","testing"]
seo_title: "Spectre per Agent AI enterprise controllabili"
seo_description: "Scopri come Spectre 0.3.2 governa Agent enterprise con autorità, Policy, recovery, Ledger e Lab per audit, debugging e test su casi operativi reali."
cover_alt: "Un team operativo controlla un Agent Spectre con Policy, checkpoint, Receipts e strumenti di test prima che agisca sui sistemi aziendali"
---

Un chatbot che sbaglia una risposta crea una conversazione imbarazzante.

Un Agent con credenziali di produzione che sbaglia crea un incidente.

È in quella distanza che nasce il problema enterprise. Non quando aggiungiamo
un logo SSO alla pagina di login, non quando scegliamo un modello più grande e
nemmeno quando rinominiamo una demo in "copilot". Il problema inizia quando il
software può agire per conto di una persona o di un'azienda e noi dobbiamo
rispondere a domande molto meno spettacolari di un benchmark:

- chi ha autorizzato questa operazione?
- quale versione dell'Agent l'ha proposta?
- cosa era già stato salvato prima del crash?
- ripetere l'operazione è sicuro?
- possiamo fermarla, revocarla e ricostruire ciò che è successo?

Ho costruito [Spectre 0.3.2](https://github.com/elchemista/spectre/tree/0.3.2)
partendo da domande come queste. Non per rendere il modello più intelligente,
ma per rendere la delega governabile.

Per questo, quando dico che Spectre può essere la scelta migliore per un Agent
enterprise, non intendo "migliore per qualunque chatbot". Intendo migliore
quando controllo, durata, recovery, audit e autorità sono requisiti del
sistema, non note da aggiungere alla fine del progetto.

## Enterprise comincia dove finisce la demo

La demo tipica di un Agent ha una forma rassicurante:

1. costruisci un prompt;
2. chiama un modello;
3. lascia che scelga un tool;
4. esegui il tool;
5. ripeti finché il modello dice di aver finito.

È un ottimo modo per capire un'idea. È anche una descrizione incompleta di un
sistema operativo reale.

Quel loop non dice chi possiede lo stato quando arrivano due richieste
contemporaneamente. Non dice se un'azione approvata ieri è ancora autorizzata
dopo una revoca. Non distingue il testo provvisorio di uno stream da un
risultato canonico. Non sa se il provider esterno ha eseguito un rimborso prima
che la connessione cadesse. Non spiega cosa accade quando il processo riparte
con una Definition diversa.

Molti framework sono eccellenti nel ridurre il tempo necessario per arrivare
al primo tool call. È un obiettivo legittimo. Il problema è che diverse
astrazioni lasciano fuori dal proprio modello proprio le questioni che
un'azienda incontra dopo il primo successo: ownership, fencing, revoca,
persistenza ambigua, idempotenza, privacy, audit e test dei guasti.

Spectre comincia da lì.

## Un caso vero: l'Agent che gestisce una contestazione

Immaginiamo un Account Operations Agent usato da un'azienda SaaS.

Un cliente apre una contestazione dal portale. Più tardi risponde su WhatsApp,
poi un operatore continua il caso dalla console interna. L'Agent deve vedere un
unico Subject aziendale, non tre conversazioni scollegate. Deve raccogliere gli
eventi dell'account, analizzare la cronologia, proporre una soluzione e, se
autorizzato, emettere un rimborso o sospendere temporaneamente un servizio.

La ricerca può durare minuti. Un Vigil può controllare se il pagamento è stato
riconciliato. Un Work può proseguire dopo la fine del Turn che lo ha avviato.
Nel frattempo un operatore può correggere l'obiettivo, mettere in pausa il
lavoro o revocare l'autorità dell'Agent.

Ora arriva il caso interessante: il provider di pagamento accetta il rimborso,
ma il processo muore prima di ricevere la conferma. Al riavvio abbiamo due
possibilità spiacevoli.

Se ripetiamo alla cieca, possiamo rimborsare due volte. Se non facciamo nulla,
possiamo lasciare il cliente senza rimborso. La risposta corretta non è
"chiediamo al modello cosa pensa". La risposta corretta è mantenere l'esito
ambiguo, riconciliare usando prove esterne e impedire che un nuovo Runner agisca
con autorità obsoleta.

Questo non è un caso esotico. È il genere di problema che compare appena un
Agent smette di scrivere testo e comincia a toccare il mondo.

## Il punto non è il loop, è chi lo possiede

Spectre separa concetti che in una demo sembrano la stessa cosa:

| Concetto | Responsabilità |
| --- | --- |
| Definition | La forma immutabile dell'Agent, con Flow, Policy, Skill e Action disponibili |
| Instance | L'unico proprietario locale della coppia AgentRef e Subject |
| Turn | Una decisione conversazionale con un solo esito |
| Run | La continuazione governata di un lavoro, con generazioni e fencing |
| Invocation | Una chiamata nondeterministica identificata, inclusa l'inferenza |
| Policy | La macchina deterministica che decide quando serve nuova autorità |
| Effect | L'operazione approvata che il sistema host può eseguire separatamente |
| Receipt | Evidenza legata a un confine e allo stato canonico, non una promessa magica di exactly-once |

Questa separazione cambia il modo in cui si ragiona sul sistema.

Il modello può proporre. La Policy può richiedere approvazione. L'Instance può
commettere lo stato canonico. L'applicazione host può controllare RBAC,
credenziali e transazioni prima di eseguire l'Effect. Nessuno di questi passaggi
deve essere nascosto in una frase del system prompt.

## L'Agent esiste in codice verificabile

La forma minima del nostro Account Operations Agent potrebbe essere questa:

~~~elixir
defmodule MyApp.AccountOpsActions do
  def issue_refund(args, ctx) do
    idempotency_key = Keyword.fetch!(ctx.opts, :idempotency_key)

    MyApp.Billing.issue_refund(
      ctx.assigns.case_id,
      args,
      idempotency_key: idempotency_key
    )
  end
end

defmodule MyApp.AccountOpsAgent do
  use Spectre.Agent,
    id: :account_operations,
    prompt_root: "priv/agents/account_operations/prompts"

  model(MyApp.LLM)
  router(via: [:regex, :embedding, :classifier])

  actions MyApp.AccountOpsActions do
    protect(:issue_refund, with: :refund_confirmation)
  end

  before_action(:issue_refund,
    run: {MyApp.AccountOpsGuards, :refund_authorized}
  )

  policy :refund_confirmation do
    request(:confirm_refund)
    accept(:refund_approved, regex: ~r/^approve refund$/i)
    reject(:refund_rejected, regex: ~r/^(reject|cancel) refund$/i)
    otherwise(ask: :confirm_refund_retry)
    attempts(3, then: :cancel_pending)
  end

  interrupt :STOP, regex: ~r/^(stop|cancel)$/i do
    run(:cancel_current)
  end

  flow :account_operations do
    on :INVESTIGATE,
      regex: ~r/\b(investigate|analyze)\b/i do
      reason(:investigate_case, temperature: 0.1)
    end

    on :PROPOSE_RESOLUTION,
      regex: ~r/\b(propose|resolve)\b/i do
      act(:propose_resolution, temperature: 0.1)
    end

    on :ISSUE_REFUND,
      regex: ~r/^issue refund$/i do
      action(:issue_refund, args: %{source: "operator"})
    end
  end
end
~~~

Qui `reason/2` permette analisi senza Action planning. `act/2` permette al
planner montato di scegliere soltanto nel catalogo chiuso di Action. La route
deterministica usa `action/2` per preparare un'operazione conosciuta. In ogni
caso, `protect/2` impedisce che il rimborso diventi eseguibile prima della
Policy.

L'approvazione non esegue ancora il rimborso. Produce un Effect approvato e
persistito. Il callback riceve un'idempotency key, ma spetta a
`MyApp.Billing` applicarla al proprio confine durevole. Anche il guard legge
l'autorizzazione corrente dal sistema aziendale immediatamente prima
dell'esecuzione.

È una distinzione essenziale: la validità dello schema degli argomenti non è
autorizzazione, e una risposta convincente del modello non è un ruolo RBAC.

## L'autorità ha una versione e può essere revocata

In Spectre una Definition attiva appartiene a una generazione. I Run vengono
vincolati all'identità, alla Definition e all'autorità che li ha prodotti. Un
Runner temporaneo non diventa un secondo proprietario dello stato. Se arriva un
controllo più recente, gli eventi tardivi della generazione precedente vengono
rifiutati tramite fencing.

Questo risolve una classe di bug che spesso appare solo sotto carico:

- un task vecchio termina dopo che l'operatore ha cambiato obiettivo;
- un retry consegna due volte lo stesso risultato;
- un provider risponde dopo la cancellazione;
- un Worker ripartito prova a scrivere su uno stato più recente;
- un'Action resta tecnicamente disponibile dopo che l'autorità è stata revocata.

Il BEAM è particolarmente adatto a questo modello. Processi supervisionati,
mailbox, isolamento e restart sono strumenti magnifici, ma da soli non
definiscono la verità applicativa. Spectre aggiunge ownership canonica,
generazioni, commit e protocolli di recovery sopra quelle primitive.

OTP ti aiuta a far ripartire un processo. Spectre deve anche decidere se quel
processo può ancora parlare a nome dell'Agent.

## Spectre Ledger: il debugging comincia dalle prove

[Spectre Ledger 0.1.0](https://github.com/elchemista/spectre_ledger) implementa
due confini pubblici già presenti in Core:
`Spectre.Instance.CheckpointStore` e `Spectre.Receipt.Sink`.

Non sostituisce l'Instance, non aggiunge un secondo scheduler e non prova a
registrare ogni movimento interno del runtime. Conserva in modo append-only i
checkpoint che Spectre persiste davvero e i Boundary Receipts che Spectre
emette ai confini nondeterministici o di autorità.

Le dipendenze hanno versioni proprie. Ledger `0.1.0` e Lab `0.1.0` non sono
copie "più vecchie" di Spectre: quei numeri descrivono pacchetti distinti e le
release correnti dichiarano compatibilità con Core `0.3.2`.

~~~elixir
defp deps do
  [
    {:spectre, "~> 0.3.2"},
    {:spectre_ledger,
     github: "elchemista/spectre_ledger",
     branch: "main"},
    {:spectre_lab,
     github: "elchemista/spectre_lab",
     branch: "main",
     only: [:dev, :test]}
  ]
end
~~~

In produzione Ledger usa un Ecto Repo posseduto e supervisionato
dall'applicazione. Non prende il controllo del database e non nasconde la
topologia al team operativo.

~~~console
mix spectre_ledger.gen.migration
mix ecto.migrate
mix spectre_ledger.doctor --backend postgres --repo MyApp.Repo --strict
~~~

~~~elixir
ledger_opts = [
  backend: :postgres,
  repo: MyApp.Repo,
  namespace: "account-operations"
]

checkpoint_store = Spectre.Ledger.checkpoint_store(ledger_opts)
receipt_sink = Spectre.Ledger.receipt_sink(ledger_opts)

subject = Spectre.Subject.new({:support_case, "CASE-4821"})

{:ok, instance} =
  Spectre.summon(
    agent: MyApp.AccountOpsAgent,
    subject: subject,
    checkpoint_store: checkpoint_store,
    receipt_mode: :required,
    receipt_sink: receipt_sink
  )
~~~

Con `receipt_mode: :required`, Spectre prepara il payload, commette l'outbox
canonica, attraversa la barriera di durabilità del checkpoint e usa un append
idempotente prima di completare il confine. Con `:observational`, invece, un
problema del sink non blocca il Run.

Questa scelta è esplicita perché le due modalità rispondono a esigenze diverse.
La telemetria di un suggerimento può essere osservazionale. La prova che un
Effect protetto ha attraversato un confine può essere richiesta.

Per un'indagine operativa possiamo leggere e verificare la catena:

~~~elixir
{:ok, envelopes} = Spectre.Ledger.receipts(instance_ref, ledger_opts)
{:ok, report} = Spectre.Ledger.verify_receipts(instance_ref, ledger_opts)
{:ok, entries} = Spectre.Ledger.receipt_entries(instance_ref, ledger_opts)
~~~

Il report conserva la differenza tra ordine fisico di append e revisione
canonica. Non riordina la storia per farla sembrare più pulita.

Questo è debugging utile in un'azienda: non "mostrami tutto quello che il
processo ha pensato", ma "verifica quale evidenza è legata a quale stato e a
quale confine".

## Spectre Lab: riprodurre condizioni, non raccontare favole sul replay

[Spectre Lab 0.1.0](https://github.com/elchemista/spectre_lab) porta quelle
prove in un ambiente offline e aggiunge strumenti isolati per i test. Può
caricare un Bundle di checkpoint verificato, confrontare due playback per
identità, verificare una catena staccata di Receipts e guidare il vero runtime
di streaming con fixture deterministiche.

Può, per esempio, testare l'inferenza senza aprire una connessione di rete:

~~~elixir
script =
  Spectre.Lab.Inference.StreamScript.text!(
    "Refund requires manual approval.",
    chunk_size: 4
  )

{:ok, stream} =
  Spectre.stream(instance, "Analyze case CASE-4821",
    model: MyApp.TestModel,
    plan_actions?: false,
    stream_adapter: Spectre.Lab.Inference.StreamAdapter,
    stream_adapter_opts: [script: script, observer: self()]
  )

events = Enum.to_list(stream)
~~~

Questa è consegna deterministica di una fixture attraverso il runtime reale.
Non è la riproduzione deterministica di una precedente chiamata al modello.
La differenza sembra prudenza terminologica, ma è esattamente il tipo di
precisione che evita una falsa garanzia nei test.

Lab permette anche di iniettare il guasto che ci interessa davvero, non solo
un generico `{:error, :boom}`:

~~~elixir
{:ok, controller} =
  Spectre.Lab.Fault.Controller.start_link(
    script: %{
      compare_and_swap: [
        {:commit_then_return,
         {:error, {:ambiguous, :lost_ack}}}
      ]
    }
  )

faulty_store =
  {Spectre.Lab.Fault.CheckpointStore,
   controller: controller,
   delegate: checkpoint_store}
~~~

`commit_then_return` significa che il delegate ha commesso la scrittura, ma il
chiamante riceve un esito ambiguo, come quando l'acknowledgement si perde. Il
test può quindi verificare il percorso di recovery e riconciliazione usato in
produzione. Non una scorciatoia speciale di Lab.

Lo stesso meccanismo esiste per `ReceiptSink`, inclusi append e staging del
payload. `Spectre.Lab.TestCase` fornisce inoltre una sandbox posseduta dal test
e un `IOFuse` chiuso. Il fuse blocca solo l'I/O instradato esplicitamente
attraverso di esso, quindi Lab non finge di essere un sandbox universale del
sistema operativo.

Questa onestà nei confini è una funzione di sicurezza, non una limitazione da
nascondere.

## Cosa Spectre risolve che spesso resta fuori dal framework

Torniamo al nostro Account Operations Agent.

| Problema operativo | Confine Spectre |
| --- | --- |
| Web, WhatsApp e console aprono tre sessioni sullo stesso cliente | Subject e Instance definiscono una sola ownership canonica |
| Due richieste concorrenti aggiornano lo stesso Agent | L'Instance sequenzia lo stato e il Checkpoint Store usa CAS |
| Un risultato vecchio arriva dopo stop o update | Generazioni, Run ed epoch applicano fencing |
| Il modello propone un rimborso con argomenti non validi | Catalogo chiuso e JSON Schema limitato vengono validati in planning ed execution |
| Un operatore deve approvare un'azione sensibile | La Policy è deterministica e l'approvazione è un commit separato dall'esecuzione |
| Il processo cade dopo una possibile scrittura | L'esito resta ambiguo finché le prove non consentono la riconciliazione |
| Serve capire cosa ha attraversato un confine | I Receipts legano evidenza, Definition e radici canoniche |
| Serve provare recovery, backpressure e provider failure | Lab usa streaming virtuale e fault injection sulle interfacce pubbliche |
| Un lavoro dura oltre il messaggio che lo ha iniziato | Work e Vigil condividono il runtime operativo governato |

Questi non sono accessori per una dashboard. Sono proprietà del sistema.

## Sicurezza significa anche dichiarare dove Spectre finisce

Spectre è un runtime boundary, non un sistema di autorizzazione aziendale
completo. È scritto chiaramente nel suo
[modello di sicurezza](https://github.com/elchemista/spectre/blob/0.3.2/SECURITY.md).

L'applicazione host deve ancora:

- autenticare utenti e operatori;
- autorizzare la vera risorsa e il tenant;
- proteggere e ruotare le credenziali;
- applicare RBAC e policy di database;
- rendere gli Effect idempotenti al confine esterno;
- cifrare checkpoint e Receipts quando necessario;
- definire retention, backup e isolamento di rete;
- eseguire codice rischioso in un sandbox appropriato.

Spectre non promette immunità alla prompt injection. Segna il contenuto
dinamico come dati nel `Prompt.Plan`, limita ciò che il planner può selezionare,
valida gli argomenti e mantiene l'autorità fuori dal testo generato. Sono
difese strutturali, ma non trasformano input ostile in input fidato.

Anche Ledger è preciso sul proprio limite: il content addressing prova
integrità, non confidenzialità o autorizzazione. Un Bundle esterno non fidato va
verificato in un nodo isolato e ristretto, perché la decodifica Foundation può
caricare moduli BEAM già presenti, inclusi moduli con `@on_load`.

Una piattaforma enterprise non è credibile perché dice "sicuro". È credibile
quando consente di identificare il confine, il proprietario e la prova.

## Ledger e Lab non sono una macchina del tempo

È importante anche dire cosa questi strumenti non promettono.

Ledger registra i checkpoint che Core decide di persistere. Spectre può
coalescere scritture, quindi un Bundle non contiene necessariamente ogni
revisione interna. Lab riproduce quei checkpoint verificati, non l'intera
esecuzione causale. Nessuno dei due ripete una chiamata al modello o un Effect
esterno come se il mondo fosse deterministico.

I Receipts non rendono exactly-once un provider remoto. L'idempotency key non
rende idempotente un'API che la ignora. Un esito ambiguo non diventa fallito
solo perché sarebbe più comodo fare retry.

Queste frasi possono sembrare meno attraenti in una landing page. In
produzione sono molto più utili di una garanzia impossibile.

## Quando Spectre è davvero la scelta migliore

Spectre è un forte candidato quando l'azienda:

- usa Elixir e vuole che gli Agent abbiano semantiche native del BEAM;
- deve mantenere Agent durevoli oltre una singola request HTTP;
- ha Action sensibili che richiedono Policy e approvazioni verificabili;
- deve gestire concorrenza, cancellazione, revoca e restart senza stato fantasma;
- vuole osservare confini nondeterministici con evidenza verificabile;
- deve testare fault ambigui, streaming e recovery prima della produzione;
- preferisce contratti espliciti a comportamento critico nascosto nei prompt.

Se serve un chatbot promozionale per un weekend, Spectre può essere più
struttura del necessario. Se il team non usa il BEAM e vuole soltanto provare
un tool loop, esistono percorsi più brevi.

Ma quando un Agent deve lavorare per ore, sopravvivere ai crash, condividere un
Subject tra canali, attraversare confini aziendali e spiegare ciò che ha fatto,
la struttura non è burocrazia. È il prodotto.

## Costruito pensando a casi reali

Spectre non è nato dall'idea che un prompt sufficientemente lungo possa
descrivere un sistema distribuito.

È nato pensando all'Agent che invia davvero un messaggio. A quello che può
cancellare un account o riavviare un servizio. Al Work di ricerca che continua
dopo la risposta HTTP. Al Vigil che si risveglia domani. All'operatore che
cambia obiettivo mentre un provider sta ancora generando. Al checkpoint che
potrebbe essere stato scritto prima di perdere l'ack. Alla Policy rifiutata.
Alla Definition aggiornata mentre esistono ancora Run della versione
precedente.

È per questo che nell'ecosistema le responsabilità restano separate. Core
governa. Ledger conserva evidenza durevole. Lab verifica playback e guasti.
Altri pacchetti possono aggiungere percezione, memoria, planning, canali o
missioni senza diventare un secondo runtime proprietario.

Non voglio che l'Agent sembri autonomo durante la demo. Voglio che resti
controllabile quando la demo è finita e comincia il lavoro vero.

## La vera feature enterprise è poter dire no

Un Agent enterprise non è un modello con più permessi. È un sistema capace di
dire:

"Questa operazione non appartiene alla tua autorità corrente."

"Questa approvazione è scaduta."

"La scrittura potrebbe essere avvenuta, quindi non la ripeterò alla cieca."

"Questo testo è provvisorio, il Result non è ancora canonico."

"Questa prova è integra, ma contiene dati che il tuo ruolo non può leggere."

È meno magico di un loop infinito con accesso a tutto. È anche molto più vicino
a ciò che un'azienda può mettere in produzione con responsabilità.

Spectre non rende il modello più intelligente. Rende la delega governabile.
