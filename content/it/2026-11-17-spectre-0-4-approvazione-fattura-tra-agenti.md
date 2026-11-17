---
title: "Un agente vuole inviare una fattura. Un altro chiede il permesso al responsabile."
slug: "spectre-0-4-approvazione-fattura-tra-agenti"
lang: "it"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Sviluppo software"
tags: ["Elixir", "OTP", "agenti AI", "Spectre", "Spectre 0.4", "GAM", "approvazione esterna", "multi-agent", "fatture", "spectre_pulse"]
seo_title: "Spectre 0.4: approvazione GAM tra agenti AI"
seo_description: "Un esempio pratico con Spectre 0.4: l'agente del cliente propone una fattura, l'agente del responsabile chiede il consenso e GAM governa l'invio."
cover_alt: "Un agente propone l'invio di una fattura e l'agente personale di un amministratore raccoglie il consenso umano firmato prima dell'esecuzione"
translation_of: "content/en/2026-11-17-spectre-external-gam-invoice-approval-between-agents.md"
---

Immagina un'azienda in cui un assistente AI svolge il lavoro quotidiano.

Un cliente chiede una fattura. L'agente trova il documento, prepara il messaggio e conosce il tool capace di inviarlo.

È pronto a procedere.

Ma c'è una regola: **non può inviare fatture senza l'autorizzazione di un responsabile**.

La soluzione più ovvia sembra semplice: l'agente chiede «Posso?». Solo che il responsabile ha già **un proprio agente personale**, con la sua chat, magari su un altro server. E l'agente del cliente non può fidarsi di un generico «sì» che arriva dalla rete.

Volevo che Spectre potesse gestire un flusso del genere:

~~~text
 Cliente / dipendente
        |
        v
 AGENTE DEL CLIENTE                 AGENTE DEL RESPONSABILE
 "Invia INV-104"                      "Richiesta di approvazione"
        |                                         |
        v                                         v
 Propone fattura -- approval.request --> Mostra fattura esatta
        |                                         |
        |                              approval.presented (firmato)
        |                                         |
        |                              La persona approva/rifiuta
        |                                         |
        | <----- approval.decision (firmato) -----|
        v
 GAM del cliente verifica:
 - Questa operazione rientra nel Mandate?
 - La richiesta è ancora quella originale?
 - La Presentation è stata mostrata?
 - Il consenso è valido, autentico e non scaduto?
        |
        v
 Act registrato -> esecutore della fattura -> Outcome osservato
~~~

Il dettaglio più importante è questo: **l'agente del responsabile non ottiene il potere di inviare fatture per il cliente**. Trasporta la richiesta a una persona reale e restituisce solo la Evidence di consenso per quella specifica operazione. La decisione di ammissione resta nel GAM Domain dell'agente che ha originato il lavoro.

Non è soltanto una chat tra agenti. È **delega che conserva i confini dell'autorità**.

## Prima di tutto: tre regole

**L'agente propone, non si autorizza da solo.** Un'etichetta come `:send_invoice` significa che una richiesta è stata riconosciuta. Non dimostra un permesso.

**L'assistente del responsabile trasporta la richiesta, ma è la persona a decidere.** Non deve essere un LLM a chiamare le API di approvazione. La UI attendibile mostra il contenuto esatto e una persona autenticata sceglie.

**Consegna, consenso e successo non sono la stessa cosa.** Il trasporto dice «messaggio accodato». La UI dice «ho mostrato la richiesta». La persona dice «approvo». GAM ammette un Act. Il provider comunica un Outcome. Sono eventi differenti.

In Spectre 0.4 questo è un protocollo supportato da [External human approval](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md). Esiste già un esempio eseguibile con **due veri AgentServer e due Domain indipendenti**, senza bisogno di Pulse o di un LLM.

## Registriamo l'operazione: un invio fattura simulato

Per capire il protocollo, **simuleremo** la spedizione della fattura. Non verrà inviata nessuna email reale. In produzione l'adapter dovrà utilizzare un provider autenticato e registrato.

Il contratto Spectre è reale; l'effetto esterno è una fixture di test.

~~~elixir
defmodule InvoiceDemo.Effect do
  @behaviour Spectre.Server.GAM.EffectAdapter

  def execute_effect(:send, args, _context) do
    send(Process.whereis(InvoiceDemo.Consumer), {:invoice_dispatched, args})
    {:ok, %{simulated: true}}
  end
end

defmodule InvoiceDemo.Package do
  use Spectre.Stack.Installable,
    id: :invoice_demo,
    version: "0.1.0"

  def effects(_installation) do
    %{
      invoice_send: %{
        contract: 1,
        adapter: InvoiceDemo.Effect,
        operation: :send,
        side_effect: :non_idempotent,
        material: :arguments,
        partition: [],
        schema_hash: nil,
        config: %{}
      }
    }
  end
end

defmodule InvoiceDemo.Stack do
  use Spectre.Stack
  install InvoiceDemo.Package
end
~~~

Abbiamo dichiarato `:invoice_send` come operazione governata. Non è il nome di una funzione arbitraria che il modello può invocare senza controlli.

Il descrittore identifica l'adapter e segnala che l'effetto esterno non è idempotente. Questa informazione conta quando il risultato diventa incerto.

## Creiamo l'agente del cliente e il suo Server

Per l'esempio useremo una Route deterministica. Così vediamo bene cosa fa GAM senza chiederci se un modello ha interpretato correttamente la frase. In seguito si possono aggiungere embedding, classificatori locali o LLM.

~~~elixir
defmodule InvoiceDemo.CustomerServer do
  use Spectre.Server

  def handle_flow({:billing, :send}, _input, ctx) do
    propose(ctx, :invoice_send,
      %{
        "invoice_id" => "INV-104",
        "to" => "billing@example.test",
        "amount_cents" => 125_000,
        "currency" => "EUR"
      },
      on_result: :invoice_result)
  end

  def handle_result(:invoice_result, result, ctx) do
    send(Process.whereis(InvoiceDemo.Consumer), {:invoice_result, result})
    no_response(ctx)
  end

  def handle_result(tag, result, ctx), do: super(tag, result, ctx)
end

defmodule InvoiceDemo.CustomerAgent do
  use Spectre.Agent,
    stack: InvoiceDemo.Stack,
    server: InvoiceDemo.CustomerServer

  router strategies: [:regex]

  flow :billing do
    on(:send, regex: ~r/^send invoice INV-104$/i)
  end
end
~~~

Qui l'Agent riconosce l'intenzione. Il Server propone un'operazione **con dati concreti e immutabili**. GAM controlla l'ammissione.

Ora creiamo l'agente personale del responsabile:

~~~elixir
defmodule InvoiceDemo.AdminServer do
  use Spectre.Server

  def handle_flow(:unmatched, _input, ctx),
    do: respond(ctx, "Le richieste di approvazione arrivano nella UI attendibile.")
end

defmodule InvoiceDemo.AdminAgent do
  use Spectre.Agent,
    stack: InvoiceDemo.Stack,
    server: InvoiceDemo.AdminServer
end
~~~

È davvero un secondo AgentServer, non un'altra personalità infilata nello stesso prompt.

## Un trasporto per comunicare tra agenti

Il protocollo di approvazione non richiede obbligatoriamente Spectre Pulse. Basta implementare `Spectre.Server.GAM.Managed.Approval.send_message/2`.

Per un esempio locale possiamo usare la mailbox:

~~~elixir
defmodule InvoiceDemo.Transport do
  @behaviour Spectre.Server.GAM.Managed.Approval

  def send_message(message, opts) do
    send(Keyword.fetch!(opts, :receiver), {:wire, message})
    {:ok, :queued}
  end
end
~~~

Attenzione: `:queued` significa solo che il trasporto ha accodato il messaggio. **Non** significa che la persona lo abbia visto o approvato.

Per comunicare tra nodi o servizi puoi usare [spectre_pulse](https://github.com/elchemista/spectre_pulse): cambia il trasporto, non il modello di autorità sul lato richiedente.

## Avviamo due Domain separati e identifichiamo chi può approvare

Questa è la configurazione essenziale. Nel nostro esempio un processo host funge da consumer attendibile. Identità e chiavi sono **fixture di test**, non sostituiscono l'autenticazione reale.

~~~elixir
{public, private} = :crypto.generate_key(:eddsa, :ed25519)

human = %{
  kind: :human,
  attributes: %{"subject" => "billing-admin"}
}

mandate_ref = "admin:billing-approval"
expires_at = System.system_time(:millisecond) + 60_000
transport = {InvoiceDemo.Transport, [receiver: self()]}

{:ok, customer} =
  Spectre.Server.start_link(
    agent: InvoiceDemo.CustomerAgent,
    consumer: self(),
    identity: %{subject: "customer-42"},
    gam: [
      operations: %{
        invoice_send: [
          confirm: true,
          message: "Inviare INV-104, EUR 1.250, a billing@example.test?",
          approver: {:external, "spectre://admin/billing"}
        ]
      },
      approvals: [
        address: "spectre://customer/billing",
        transport: transport,
        approvers: %{
          "spectre://admin/billing" => [
            principal: human,
            public_key: public,
            mandate_ref: mandate_ref,
            expires_at: expires_at
          ]
        }
      ]
    ]
  )

{:ok, admin} =
  Spectre.Server.start_link(
    agent: InvoiceDemo.AdminAgent,
    consumer: self(),
    identity: %{subject: "billing-admin"},
    gam: [
      approvals: [
        address: "spectre://admin/billing",
        transport: transport,
        signer: [
          principal: human,
          private_key: private,
          mandate_ref: mandate_ref,
          expires_at: expires_at
        ]
      ]
    ]
  )
~~~

Anche se utilizzano lo stesso trasporto, i due agenti hanno **GAM Domain diversi**. L'host richiedente conosce l'identità del responsabile e la sua chiave pubblica: un messaggio qualsiasi proveniente dalla rete non può creare un consenso valido.

Il `mandate_ref` qui indica un'autorizzazione stabilita dal sistema host per la conferma. **Non** trasferisce all'agente dell'amministratore il Mandate esecutivo dell'agente cliente.

## Mostrare, confermare la visualizzazione, decidere

Il cliente invia la richiesta:

~~~elixir
{:ok, _interaction} =
  Spectre.Server.input(customer, "send invoice INV-104")
~~~

Il trasporto produce un messaggio `approval.request`. Nella fixture locale lo consegniamo al secondo Server tramite il suo ingresso attendibile:

~~~elixir
request_id =
  receive do
    {:wire, %{"type" => "approval.request"} = request} ->
      :ok = Spectre.Server.receive_approval(admin, request)
  
      receive do
        {Spectre.Server, ^admin, {:approval_request, ^request}} ->
          # UI attendibile: mostra testo originale e scadenza.
          IO.puts(request["rendered_payload"])
      end
  
      # Soltanto dopo la visualizzazione reale:
      :ok = Spectre.Server.approval_presented(admin, request["id"])
    request["id"]
  end
~~~

Il test locale deve ora inoltrare il messaggio firmato `approval.presented` al cliente e aspettare che la sua richiesta risulti effettivamente in attesa di consenso:

~~~elixir
receive do
  {:wire, %{"type" => "approval.presented"} = acknowledgement} ->
    :ok = Spectre.Server.receive_approval(customer, acknowledgement)
end

receive do
  {Spectre.Server, ^customer, {:pending, _, _}} -> :ok
end
~~~

**Solo dopo una decisione umana reale**, la UI attendibile invoca:

~~~elixir
# Chiamata della UI autenticata, mai del modello:
:ok = Spectre.Server.approval_decide(admin, request_id, :confirm)
# Oppure:
# :ok = Spectre.Server.approval_decide(admin, request_id, :reject)
~~~

Il messaggio firmato `approval.decision` viene consegnato al cliente con `Spectre.Server.receive_approval/2`:

~~~elixir
receive do
  {:wire, %{"type" => "approval.decision"} = signed_decision} ->
    {:ok, _} = Spectre.Server.receive_approval(customer, signed_decision)
end
~~~

 In caso di conferma, il Domain del cliente verifica autorità, digest, dati congelati, visualizzazione, firma e scadenza. Solo dopo l'ammissione e il commit dell'Act può partire l'esecutore registrato.

Se la persona rifiuta, la continuazione riceve `{:consent, :rejected}` e la fattura non viene spedita.

Il protocollo comprende `approval.request`, `approval.presented`, `approval.decision` e `approval.cancelled`. Non sono messaggi intercambiabili. Una firma falsa, una decisione scaduta o riutilizzata non possono autorizzare un'altra fattura.

Per un esempio **specifico della fattura**, con conferma e rifiuto, ho aggiunto uno [script completo nel repository del blog](https://github.com/elchemista/spectre_blog/blob/master/examples/spectre_0_4_external_invoice_approval.exs). Con i repository Spectre e spectre_blog affiancati, esegui dal checkout Spectre 0.4:

~~~sh
mix run ../spectre_blog/examples/spectre_0_4_external_invoice_approval.exs
~~~

Lo script simula l'invio e riproduce il flusso di consenso firmato, rifiuto e controllo anti-replay; deriva dalla fixture ufficiale. Puoi anche eseguire il **test originale del core**:

~~~sh
mix run docs/examples/external_approval.exs
~~~

L'esempio ufficiale usa un'apertura browser simulata, anziché una fattura, ma esercita davvero due AgentServer, Domain separati, firma Ed25519, conferma della visualizzazione, approvazione/rifiuto e controllo del replay. I frammenti qui sopra adattano lo stesso protocollo al caso fattura: non pretendono di essere un'integrazione già testata con un provider contabile.

## E se il responsabile non è online?

L'agente del cliente aspetta. Non diventa automaticamente il proprio approvatore.

L'agente del responsabile può usare una inbox persistente: `Spectre.Server.approval/2` per leggere una richiesta e `approval_inbox/2` per paginare quelle ricevute. Le notifiche possono ripetersi: la UI deve deduplicarle per riferimento completo. Una ricevuta di trasporto non equivale alla visualizzazione.

La scadenza rimane vincolante. Dopo un riavvio, l'attesa dell'agente cliente torna **sospesa**: prima di proseguire serve una nuova Presentation. Una consegna persa o una scrittura incerta nel database non diventano consenso immaginario.

E, soprattutto, l'approvazione non aggiunge diritti che il Mandate originale del cliente non prevedeva.

**Un altro agente può aiutarti a prendere una decisione, ma non può riscrivere di nascosto chi ha il potere di agire.**

## Come trasformare questa demo in un sistema reale

In produzione servono login umano autenticato, chiavi di firma persistenti, registro attendibile degli approvatori, ingress sicuro e un trasporto adatto al deployment. Se serve continuità al riavvio, configura persistenza per coordinamento e storia GAM: `spectre_ledger` con PostgreSQL oppure un tuo `Spectre.Server.Store`.

L'effetto che invia davvero fatture dovrà usare credenziali protette, identificativo durevole, deduplicazione sul provider e procedure di riconciliazione degli esiti ambigui. Mai mettere credenziali nel prompt. E le chiamate HTTP dirette dentro callback ordinarie non ricevono automaticamente le garanzie del percorso governato.

Sono tutte responsabilità concrete, non dettagli da nascondere sotto una demo.

Riferimenti tecnici: [approvazioni esterne](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md), [esempio eseguibile](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs), [Managed GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md) e [Pulse](https://github.com/elchemista/spectre_pulse).

## La parte che trovo davvero interessante

Ora immagina lo stesso schema per un rimborso, un deploy in produzione, una firma contrattuale, una spesa, un export di dati personali o un acquisto importante.

L'agente specializzato continua a lavorare. Il responsabile non deve osservare continuamente i suoi log. Il suo assistente personale porta la richiesta nella sua chat. E il sistema che ha originato il lavoro conserva la responsabilità di verificare cosa era autorizzato e cosa è successo davvero.

Questa è la differenza tra *agenti che si scambiano messaggi* e *agenti che collaborano all'interno di un sistema con autorità verificabile*.

**Spectre 0.4 non serve soltanto a far fare più cose agli agenti. Serve a rendere la delega abbastanza affidabile da poterci costruire sopra un'applicazione seria.**
