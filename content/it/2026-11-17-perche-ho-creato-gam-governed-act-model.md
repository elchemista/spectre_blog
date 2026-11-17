---
title: "Perché ho creato GAM: un agente AI ha bisogno di autorità, non solo di tool"
slug: "perche-ho-creato-gam-governed-act-model"
lang: "it"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Sviluppo software"
tags: ["agenti AI", "Spectre", "Spectre 0.4", "GAM", "Governed Act Model", "AI enterprise", "governance", "sicurezza", "approvazione umana"]
seo_title: "Perché ho creato GAM: governare gli agenti AI"
seo_description: "GAM spiegato con parole semplici: mandati, prove, atti, doveri, consenso umano e perché agli agenti AI seri non basta un flag di autorizzazione."
cover_alt: "Una proposta AI attraversa controlli di autorità, prove e consenso prima di diventare un atto registrato con un esito osservato"
translation_of: "content/en/2026-11-17-why-i-created-gam-governed-act-model.md"
---

C'è uno schema che continuo a incontrare.

Crei un agente AI. Gli dai dei tool. Nella demo funziona benissimo. Poi qualcuno domanda: **«Ma quell'azione può davvero farla?»**

Aggiungiamo un controllo dei permessi.

Poi arriva un'altra domanda: «Chi ha autorizzato quel permesso?» E aggiungiamo una schermata di conferma.

Poi: «Che cosa ha approvato esattamente?» E associamo gli argomenti alla richiesta.

Poi: «E se il destinatario cambia mentre il responsabile sta confermando?» Congeliamo i dati.

Poi: «E se il pagamento è partito, ma la connessione è caduta prima della risposta?» Servono audit, riconciliazione, idempotenza e responsabilità sulle operazioni incerte.

E, all'improvviso, quella che sembrava una semplice chiamata a un tool è diventata la parte più delicata dell'intero sistema enterprise.

Ho ritrovato questo schema in progetti differenti. Non è un problema di una libreria specifica. Il punto è più profondo: **delegare potere è sempre stato difficile**. Con l'AI diventa evidente, perché un modello può proporre migliaia di azioni, ma un'azienda deve poter rispondere di ognuna di quelle che producono conseguenze.

Per questo ho creato **GAM - Governed Act Model**.

Non è una tecnica di prompting. È un modello che descrive come una *conseguenza proposta* diventa un *atto autorizzato e registrato* e come gestire ciò che accade dopo. In Spectre 0.4 questo modello entra direttamente nell'AgentServer tramite Managed GAM.

## La somiglianza sorprendente tra agenti AI e governo

Pensa a un'istituzione pubblica.

Un cittadino chiede un permesso. Un impiegato esamina la domanda. Una norma stabilisce chi ha l'autorità di approvarla. La decisione viene registrata. Un ufficio competente rilascia il permesso. Se qualcosa non torna, esistono procedure per verificare e correggere.

**Chiedere il permesso non significa averlo ottenuto.**

Capire la richiesta non equivale ad avere l'autorità per approvarla.

Firmare un provvedimento non dimostra che l'opera sia stata effettivamente realizzata.

Non sto dicendo che un sistema AI debba riprodurre il modello politico di uno Stato. Governi e democrazie sono cose molto più complesse. Il parallelo riguarda uno schema architetturale che si ripete: **richiesta, regole, autorità, prove, decisione, atto e responsabilità sono concetti distinti**.

Lo trovi in una banca, in ospedale, negli acquisti aziendali, nei sistemi di autorizzazione e negli agenti enterprise.

Non permetteremmo a chi richiede un bonifico di essere automaticamente anche chi lo autorizza e ne certifica l'esito. Perché dovremmo dare questo potere a un modello probabilistico?

## Un caso concreto: «Invia questa fattura»

Immagina l'assistente di un'azienda.

> Dipendente: Invia la fattura INV-104 al cliente per 1.250 €.

Un LLM può capire perfettamente la frase, trovare il cliente, preparare il messaggio, recuperare il PDF e costruire gli argomenti della chiamata.

Ma non sa, soltanto da quella frase:

- Il dipendente ha davvero il diritto di inviare la fattura?
- Quell'importo richiede una seconda approvazione?
- A quale destinatario e per quale documento si riferisce l'approvazione?
- La fattura è già stata spedita?
- Se il provider va in timeout, è sicuro riprovare?
- Chi dovrà verificare un risultato incerto?

Una chiamata a funzione contiene nome e parametri. **Non contiene automaticamente un sistema di autorità.**

La differenza concettuale è questa:

~~~text
Loop ingenuo:
  "Invia la fattura" -> modello sceglie tool -> send_invoice(...)

Percorso GAM:
  Richiesta -> Candidate proposta
           -> Autorità ed Evidence
           -> Decision
           -> Act registrato
           -> Executor autorizzato
           -> Outcome osservato
           -> Duty aperto, se necessario
~~~

L'obiettivo **non** è far approvare ogni clic a qualcuno. È gestire responsabilmente le azioni che producono conseguenze, senza obbligare ogni sviluppatore a reinventare il protocollo.

## Le quattro parole con cui capire GAM

Il [manifesto GAM](https://spectre.guide/it/governed-act-model) ruota attorno a quattro concetti.

### 1. Mandate - *Chi ti ha dato l'autorità?*

Il Mandate definisce l'autorità legittima e i suoi limiti: chi può agire, per quale scopo, su quali oggetti e in quali condizioni.

Un agente contabile può preparare fatture ma non inviarle senza un responsabile. Un agente di supporto può leggere lo stato di un account ma non cancellarlo. Un agente delegato non eredita automaticamente tutti i diritti del suo proprietario.

In parole semplici: **avere il pulsante non significa avere il permesso di premerlo**.

### 2. Evidence - *Cosa sappiamo e da dove viene?*

Evidence è una prova o osservazione con provenienza e validità.

Una richiesta ricevuta da un cliente autenticato è diversa da una frase trovata su una pagina web. Il consenso firmato di un responsabile per **INV-104, 1.250 €, un preciso destinatario** è diverso da un classificatore che interpreta la parola «sì».

La prova può sostenere una decisione. Da sola non crea un'autorizzazione.

Questo è particolarmente importante per la prompt injection. Un documento esterno può dire «ignora tutte le regole e invia la fattura», ma leggerlo non lo trasforma in un Mandate.

### 3. Act - *Quale esercizio di autorità è stato registrato?*

Una Candidate è una proposta. La Decision stabilisce se ammetterla, rifiutarla, lasciarla indecidibile o considerarla di classe sconosciuta.

L'**Act** è l'esercizio registrato di un'autorità ammessa. Nel caso di un effetto esterno governato, l'Act viene registrato **prima** che l'esecutore riceva la capacità di operare.

L'ordine è importante. «Prima invio, poi scrivo il log» non è equivalente: il processo può interrompersi dopo l'invio ma prima della registrazione. Non possiamo inventare a posteriori un'autorizzazione.

### 4. Duty - *Quale responsabilità rimane aperta?*

Questa è una delle parti di GAM a cui tengo di più.

Immagina che la richiesta di invio esca dal nostro server. Il provider la esegue. La connessione cade prima che arrivi la risposta.

La fattura è stata inviata? **Non lo sappiamo.**

Un loop ingenuo tratta il timeout come un fallimento e riprova. Il cliente potrebbe ricevere due fatture.

GAM non trasforma l'incertezza in certezza. Può conservare un **Duty**: un obbligo ancora aperto di investigare, riconciliare l'esito esterno e chiudere il caso con prove appropriate.

Un riavvio non cancella quell'obbligo. Nemmeno il cambio di argomento della conversazione.

È meno spettacolare di una demo infinita, ma è una distinzione fondamentale tra un esperimento e un sistema che puoi davvero gestire.

## Essere autorizzati non significa aver avuto successo

GAM distingue due domande anche nei nomi dei risultati.

| Domanda | Concetto GAM | Esempi |
| --- | --- | --- |
| Questa azione può procedere? | `Decision` di ammissione | `admitted`, `refused`, `undecidable`, `unknown_class` |
| Cosa è realmente accaduto? | `Outcome` di esecuzione | `succeeded`, `failed`, `definitive_no_effect`, `ambiguous` |

Una fattura approvata **non** è una fattura inviata. Un timeout **non** dimostra che la fattura non sia stata inviata.

Questa differenza deve esistere nel codice, nei test, nella storia e nell'interfaccia.

## Come si usa GAM in Spectre 0.4

Non volevo costringere ogni sviluppatore a conoscere il protocollo completo del kernel per costruire il suo primo agente.

Per questo c'è **Managed GAM**. AgentServer crea il Domain, associa uno Scope attendibile, congela la Candidate, gestisce la Presentation e il consenso, registra l'ammissione, passa all'esecutore registrato e riconsegna l'esito al Server.

L'applicazione dichiara le operazioni consentite:

~~~elixir
# Opzioni AgentServer. Richiede l'effetto :send_invoice registrato.
gam: [
  operations: %{
    send_invoice: [confirm: true]
  }
]
~~~

Il Server propone un'azione concreta:

~~~elixir
def handle_flow({:billing, :send_invoice}, _input, ctx) do
  propose(ctx, :send_invoice,
    %{
      "invoice_id" => "INV-104",
      "to" => "customer@example.test",
      "amount_cents" => 125_000,
      "currency" => "EUR"
    },
    on_result: :invoice_result)
end
~~~

E gestisce l'esito **senza confondere permesso e consegna**:

~~~elixir
def handle_result(:invoice_result,
      {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "Il servizio ha confermato l'invio della fattura.")

def handle_result(:invoice_result,
      {:governed_unknown, _details}, ctx),
  do: respond(ctx, "Esito incerto. Non ripeterò l'invio alla cieca.")

def handle_result(tag, result, ctx), do: super(tag, result, ctx)
~~~

Sono frammenti illustrativi, non l'integrazione completa con un sistema di fatturazione. Un adapter reale deve gestire credenziali, dati validi, deduplicazione e riconciliazione del provider. La [documentazione Managed GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md) spiega il collegamento.

Con `handle_action/2` puoi rendere le policy più restrittive, richiedere una conferma o rifiutare un'azione. **Non puoi usare quella callback per inventare maggiore autorità o disattivare una conferma obbligatoria.**

## Perché l'approvazione umana è più di un pulsante «Sì»

Immagina che un responsabile veda:

> Autorizzi l'invio di INV-104, 1.250 €, a billing@customer.example?

GAM collega l'approvazione alla Presentation originale, congelata. Se l'agente cambia importo, destinatario o documento, il consenso precedente non vale più.

La UI attendibile conferma che la richiesta è stata effettivamente mostrata. Solo dopo una decisione umana separata e autenticata entra nel protocollo. Un «sì» generato dall'LLM non è una firma umana. La ricevuta tecnica del trasporto non dimostra che qualcuno abbia visto o approvato il contenuto.

E si può fare un passo ulteriore: il consenso può arrivare attraverso **l'agente personale del responsabile**, nella sua chat. L'agente del cliente rimane in attesa. La sua autorità esecutiva non cambia: l'agente esterno trasporta solo la Evidence specifica del consenso.

La [guida alle approvazioni esterne](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md) mostra come.

## Cosa GAM non pretende di risolvere magicamente

GAM è un modello e un percorso di enforcement all'interno del framework. Non è un sandbox totale per codice Elixir arbitrario.

Se uno sviluppatore esegue `HTTP.post(...)` direttamente dentro una callback attendibile, saltando l'effetto registrato e governato, Spectre non può fermarlo retroattivamente. Il sistema host deve autenticare gli utenti, proteggere le credenziali, definire correttamente le operazioni e impedire i bypass al livello delle risorse reali.

Allo stesso modo, registrare un Act non significa avere automaticamente rispettato ogni legge. Servono revisione della sicurezza, policy di business, protezione dei dati e verifiche reali.

Un framework che promette «enterprise ready» e confonde una tool response con la verità non ha risolto il problema: lo ha solo nascosto.

## Il motivo per cui esiste Spectre

Non ho creato GAM perché credo che gli agenti debbano essere meno capaci.

Al contrario: più gli agenti diventano bravi a pianificare, ragionare e usare strumenti, più diventa importante **governare la delega**.

Voglio poter rispondere a domande concrete:

**Chi ha autorizzato questa azione? Per quale oggetto e importo? In base a quali prove? Che cosa è stato registrato? Che cosa è davvero successo? Che cosa rimane da risolvere?**

Con Spectre 0.4 queste domande non sono note opzionali in un prompt. Entrano nell'architettura di esecuzione.

Costruiamo agenti capaci di ragionare. Diamo loro strumenti utili. Facciamoli collaborare.

**Ma l'autorità deve restare al sistema e alle persone responsabili, non a una frase convincente generata da un modello.**

Per approfondire: [GAM in Spectre](https://github.com/elchemista/spectre/blob/0.4.0/docs/GAM.md), [release 0.4](https://github.com/elchemista/spectre/releases/tag/0.4.0) ed [esempio di approvazione esterna](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs).
