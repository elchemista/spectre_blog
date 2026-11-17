---
title: "Spectre 0.4: un agente è molto più di un loop con dei tool"
slug: "spectre-0-4-stack-agent-route-server-architettura"
lang: "it"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Sviluppo software"
tags: ["Elixir", "OTP", "agenti AI", "Spectre", "Spectre 0.4", "AgentServer", "routing", "architettura", "persistenza"]
seo_title: "Spectre 0.4: architettura Stack, Agent, Route e Server"
seo_description: "Come costruire agenti Elixir con Stack, Route, Server OTP, GAM automatico, modalità RAM, Ledger e Store personalizzato nella nuova Spectre 0.4."
cover_alt: "Architettura Spectre 0.4 con capacità Stack, route nell'Agent, Server OTP, autorizzazione GAM e storage configurabile"
translation_of: "content/en/2026-11-17-spectre-0-4-stack-agent-routes-server-architecture.md"
---

Un chatbot risponde a una domanda. Un agente può compiere azioni.

Ora immagina cento clienti, tre tool diversi, un database che smette di rispondere, un nuovo messaggio mentre il modello sta ancora elaborando e un responsabile che chiede: **«Perché ha inviato quella fattura?»**

È qui che un agente smette di essere un prompt intelligente e diventa software.

Con **Spectre 0.4** non volevo semplicemente aggiungere altre funzionalità al vecchio loop. Ho cambiato l'architettura. Volevo poter leggere un agente come una normale applicazione Elixir: come riconosce una richiesta, quali capacità possiede, quale processo è responsabile del lavoro e cosa deve accadere prima di modificare il mondo esterno.

Il nuovo modello è questo:

~~~text
                   Spectre 0.4

   STACK                AGENT                 SERVER
   Capacità       →     Route / intenti   →  Processo OTP
   Modelli               Regex / vettori      Context
   Tool                  Classificatori        Worker
   Risorse               Riconoscimento       Continuazioni
                                                   |
                                          Azione proposta
                                                   |
                                                   v
                                             Managed GAM
                                                   |
                                         Effetto autorizzato
                                                   |
                                         Risultato osservato
~~~

Un dettaglio importante: lo strato centrale si chiama **Agent**, non Route. Le Route sono dichiarate *dentro* `Spectre.Agent`. In pratica: **Stack → Agent (Route) → Server**.

Non è solo una sintassi più elegante. È una separazione delle responsabilità.

## 1. Stack: installare capacità non significa concedere permessi

Lo Stack dichiara quali risorse e strumenti sono disponibili nell'ambiente applicativo.

~~~elixir
defmodule MyApp.AI do
  use Spectre.Stack

  # Installa solo i package che servono:
  # install MyApp.Inference
  # install MyApp.InvoiceTools
end
~~~

Un package può fornire modelli, browser, memoria, messaggistica o tool registrati. I package dichiarano dipendenze, incompatibilità, ownership e descrittori immutabili. Spectre compila e verifica l'ambiente, anziché cercare estensioni implicite durante l'esecuzione.

Ma ecco la distinzione fondamentale: **installato non significa autorizzato**.

Puoi installare un tool per inviare fatture. Questo non significa che ogni agente possa inviare qualsiasi fattura. Registrazione del tool, operazioni consentite al Server, regole dell'applicazione e ammissione GAM sono passaggi distinti.

È la differenza tra poter entrare in un edificio e avere l'autorità per firmare un pagamento.

## 2. Agent: riconoscere l'intenzione senza nascondere il business nel prompt

L'Agent dichiara *quali richieste conosce*. Non ospita un secondo loop nascosto.

~~~elixir
defmodule MyApp.BillingAgent do
  use Spectre.Agent,
    stack: MyApp.AI,
    server: MyApp.BillingServer

  router strategies: [:regex, :bag, :jaro]

  flow :billing do
    on :invoice_status,
      regex: ~r/\bstato fattura\b/i,
      bag: ["controlla fattura"],
      jaro: ["stato fattura"]

    on :help,
      regex: ~r/\baiuto\b/i
  end
end
~~~

Questo Agent funziona **senza un LLM e senza embedding**. Le regex gestiscono comandi espliciti; Bag e Jaro intercettano formulazioni simili ed errori di battitura.

Quando serve qualcosa di più flessibile, lo stesso router può combinare **esempi verificati in IntentDataset, embedding, classificatori locali, classificazione LLM o adapter personalizzati**. Se un riconoscimento deterministico è già sufficiente, una chiamata al modello può essere evitata.

Per me questa separazione è essenziale perché permette di rispondere a due domande diverse:

- *Come ha capito quel messaggio?* Guarda le evidenze del routing.
- *Perché ha eseguito quel comportamento?* Guarda l'handler nel Server e il lavoro registrato.

Il riconoscimento può essere probabilistico. Il comportamento applicativo resta esplicito e ispezionabile.

## 3. Server: un proprietario supervisionato, normale Elixir

Il Server implementa gli handler associati alle Route. Il vero GenServer è `Spectre.Server.Runtime`: il modulo applicativo non è un altro processo con una seconda vita segreta.

~~~elixir
defmodule MyApp.BillingServer do
  use Spectre.Server, tools: MyApp.AI

  @impl true
  def handle_flow({:billing, :invoice_status}, _input, ctx) do
    respond(ctx, "Indicami il numero della fattura da controllare.")
  end

  def handle_flow({:billing, :help}, _input, ctx),
    do: respond(ctx, "Puoi chiedermi informazioni su una fattura.")

  def handle_flow(:unmatched, _input, ctx),
    do: respond(ctx, "Non ho riconosciuto la richiesta.")
end

{:ok, server} =
  Spectre.Server.start_link(
    agent: MyApp.BillingAgent,
    consumer: self()
  )

{:ok, interaction} =
  Spectre.Server.input(server, "stato fattura")

receive do
  {Spectre.Server, ^server, {:response, ^interaction, text, _metadata}} ->
    IO.puts(text)
end
~~~

È la struttura reale di AgentServer, non un finto agente descritto dentro un system prompt.

Per fare lavoro asincrono, gli helper aggiungono comandi al Context:

~~~elixir
# Frammento: richiede il servizio modello e il prompt configurati.
def handle_flow({:billing, :explain}, input, ctx),
  do: generate(ctx, :explain_invoice, input: input, on_result: :explained)

def handle_result(:explained, {:generated, response}, ctx),
  do: respond(ctx, response.text)
~~~

Il runtime avvia i worker, correla il risultato e richiama la continuazione indicata da `on_result:`. Gestisce pending, command outbox, streaming e checkpoint. Le callback OTP native, come `handle_call`, `handle_cast` e `handle_info`, mantengono le normali tuple OTP con il Context come stato.

I dati applicativi portabili vivono in `ctx.assigns`. Riferimenti a processi e handle locali in `ctx.private`, che non viene salvato nei checkpoint. Le connessioni ai provider rimangono nelle risorse supervisionate dello Stack.

Non devi più costruire da zero un loop fragile ogni volta che l'agente deve aspettare, riprendere o coordinare più operazioni.

## 4. GAM entra in gioco prima delle azioni importanti

Supponiamo che il modello voglia inviare una fattura. Un suggerimento non è un'autorizzazione. Nemmeno la disponibilità del tool lo è.

Con un effetto fattura *registrato*, il Server può proporre:

~~~elixir
propose(ctx, :send_invoice,
  %{"invoice_id" => "INV-104", "to" => "client@example.test"},
  on_result: :invoice_sent)
~~~

L'insieme delle operazioni consentite e GAM stabiliscono se quella conseguenza concreta possa essere eseguita. Se serve consenso, Spectre prepara una Presentation immutabile e verifica la risposta riferita proprio a quella richiesta. Solo un Act ammesso e registrato può liberare l'esecutore.

**Managed GAM** integra automaticamente Domain, Scope, ingress, Candidate, consenso e riconsegna del risultato. Non devi riscrivere il protocollo in ogni callback. Le regole di business e l'autenticazione, invece, rimangono responsabilità dell'applicazione.

Il bug più pericoloso non è necessariamente «il modello ha chiamato il tool sbagliato». Spesso è «quel tool non avrebbe mai dovuto poter essere chiamato in quelle condizioni».

Approfondimenti: [GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/GAM.md) e [Managed GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md).

## 5. Nessun database obbligatorio. E nessun lock-in sul mio.

Questa è una delle caratteristiche della 0.4 che preferisco: puoi iniziare davvero in piccolo.

**Opzione A — tutto in RAM.** AgentServer funziona senza PostgreSQL, Ledger o package aggiuntivi. È utile per prototipi, assistenti temporanei o dove perdere la storia al riavvio è una scelta accettabile.

~~~elixir
gam: [storage: :ephemeral]
~~~

**Opzione B — persistenza su disco.** Puoi mantenere una storia durevole senza installare un server database:

~~~elixir
gam: [storage: {:disk, "var/agents/customer-42"}]
~~~

Per la persistenza serve un'identità stabile ed esplicita.

**Opzione C — PostgreSQL con `spectre_ledger`.** Il package opzionale [Ledger](https://github.com/elchemista/spectre_ledger) fornisce coordinamento, storia canonica GAM e una proiezione persistente per-record del Domain. L'applicazione avvia Repo e applica le migrazioni: installare Ledger, da solo, non attiva automaticamente il database.

~~~elixir
gam: [storage: :ledger, operations: allowed_operations]
~~~

**Opzione D — il tuo Store.** Puoi implementare `Spectre.Server.Store` e collegare un backend proprietario:

~~~elixir
# MyApp.Storage implementa @behaviour Spectre.Server.Store.
gam: [storage: {MyApp.Storage, MyApp.Repo}]
~~~

Non è il classico callback «salva messaggi». Il behaviour unificato comprende il coordinamento atomico (`fetch/2`, `put_new/3`, `compare_and_swap/4`, `delete/3`), la storia canonica GAM (`ledger_*`) e, opzionalmente, l'intero gruppo `projection_*`.

I contratti specificano revisioni, scritture ambigue, idempotenza e letture indicizzate e limitate. Puoi cambiare tecnologia di persistenza senza sostituire il protocollo AgentServer/GAM.

### E i limiti della RAM?

Qui c'è un miglioramento importante: con un **Domain dotato di proiezione persistente**, Spectre carica i record necessari al comando, salva le modifiche derivate e rilascia i record storici, invece di mantenere *tutta* la proiezione nella memoria del processo.

È molto utile per agenti longevi, ma **non significa memoria costante garantita**: Duty attivi, autorità, prove pertinenti e diagnostica completa possono comunque consumare RAM. Senza projection store, l'intera proiezione rimane in RAM. Anche la latenza del database rimane un costo reale.

Letture paginate e controlli sui worker aiutano a contenere il lavoro; i budget effettivi dipendono dall'applicazione. `hibernate_after` può ridurre la memoria di un Runtime inattivo, ma non rappresenta una quota globale.

Leggi [Domain storage](https://github.com/elchemista/spectre/blob/0.4.0/docs/DOMAIN_STORAGE.md), il [behaviour Store](https://github.com/elchemista/spectre/blob/0.4.0/lib/spectre/server/store.ex) e i [profili RAM/OTP](https://github.com/elchemista/spectre/blob/0.4.0/docs/OTP_PROFILE_0_4.md).

## 6. Reset consapevole, recovery senza finzioni

Vuoi ripartire con una nuova conversazione mantenendo il processo?

~~~elixir
:ok = Spectre.Server.reset(server)
~~~

Il reset mantiene PID, identità e configurazione del root, riavvia le Skill con stato nuovo e rende obsolete le risposte della sessione precedente. Rifiuta il reset se esiste lavoro governato irrisolto (`:reset_busy`). Un reset durevole apre una nuova generazione senza cancellare l'audit precedente.

Un database non disponibile è un altro problema. Il sistema può aspettare, tentare il recupero dalla storia verificata o scegliere **esplicitamente** un Domain RAM nuovo. Quest'ultimo non eredita vecchie autorizzazioni. Le storie divergenti non vengono unite in automatico e un effetto esterno incerto richiede comunque una verifica.

Un agente non dovrebbe «riprendersi» fingendo che un pagamento o un consenso scomparso non siano mai esistiti.

## 7. L'ergonomia di Spectre 0.4 nasce dalle responsabilità chiare

Puoi cominciare con una regex e un Server minuscolo. Aggiungi un modello quando serve. Un database quando serve persistenza. Skill, tool e canali esterni quando crescono i requisiti.

Ma alcuni confini importanti esistono già nel linguaggio del framework:

- **Stack:** cosa è disponibile.
- **Agent/Route:** cosa significa l'input.
- **Server:** chi possiede il lavoro.
- **GAM:** cosa è autorizzato.
- **Outcome:** cosa è realmente accaduto.
- **Store:** cosa resta ricostruibile dopo il riavvio.

Non è un sandbox magico per codice Elixir arbitrario, né una certificazione legale automatica. Il sistema host deve autenticare le persone, registrare gli effetti reali e mantenere le conseguenze dentro il percorso governato.

Però evita di rimandare queste domande al giorno dopo il primo incidente serio.

Parti da `mix spectre.gen.agent MyApp.SupportAgent --server`, dalla [guida 0.4](https://github.com/elchemista/spectre/blob/0.4.0/docs/GETTING_STARTED.md) e dalla [migrazione 0.3 → 0.4](https://github.com/elchemista/spectre/blob/0.4.0/docs/MIGRATING_TO_0_4.md).

**Un agente deve essere facile da creare. Un agente serio deve anche essere possibile da spiegare. Spectre 0.4 nasce per entrambe le cose.**
