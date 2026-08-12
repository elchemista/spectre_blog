---
title: "Spectre Morph: creare un agente che evolve senza riscriversi"
slug: "spectre-morph-creare-un-agente-che-evolve"
lang: "it"
status: published
date: 2026-08-12
updated: 2026-08-12
category: "Sviluppo software"
tags: ["Elixir","OTP","agenti AI","Spectre","Morph","Skill runtime","evoluzione governata"]
seo_title: "Spectre Morph: creare un agente Elixir che evolve"
seo_description: "Scopri come Morph in Spectre 0.3.0 permette a un agente Elixir di proporre, valutare e attivare Skill da chat o admin senza ottenere codice o autorità."
cover_alt: "Un Agent Spectre passa dalla Definition immutabile A alla Definition B valutata attraverso una proposta Morph governata"
---

«Un agente che si modifica da solo» fa venire in mente quasi sempre l'immagine sbagliata.

Sembra un modello che apre i propri file sorgente, riscrive un prompt, aggiunge un tool e si riavvia con più potere di quello che aveva un attimo prima. È certamente una modifica. È anche un sistema difficile da verificare, riprodurre o considerare affidabile.

Spectre 0.3.0 segue una strada diversa. Un Agent può partecipare al cambiamento del proprio comportamento futuro, ma non modifica mai il modulo in esecuzione e non trasforma mai testo generato in codice eseguibile. Produce — o aiuta l'host a produrre — una proposta limitata per una **nuova Definition immutabile**. La proposta viene valutata, revisionata, approvata e attivata attraverso lo stesso percorso di governance applicato a qualsiasi altra modifica.

Questo è il compito di `Spectre.Morph`.

L'idea importante non è semplicemente che un agente possa cambiare. Molti sistemi possono cambiare. L'idea importante è che l'agente possa cambiare **senza diventare l'autorità che decide se la propria modifica è sicura**.

## Installare la versione pubblicata

Spectre 0.3.0 è disponibile su [Hex](https://hex.pm/packages/spectre/0.3.0), con l'API pubblica di Morph su [HexDocs](https://hexdocs.pm/spectre/0.3.0/Spectre.Morph.html):

```elixir
def deps do
  [
    {:spectre, "~> 0.3.0"}
  ]
end
```

Morph fa parte del pacchetto core. Non è un plugin separato e non introduce un secondo runtime accanto a Spectre.

## Che cosa cambia davvero?

Il modulo scritto con `use Spectre.Agent` è la definizione compilata dalla quale viene pubblicata la prima Definition canonica. Una `Spectre.Instance` viva possiede lo stato runtime ordinato per uno specifico Agent e uno specifico Subject.

Morph non modifica nessuno dei due sul posto.

Il lifecycle ha invece questa forma:

```text
Definition A attiva
        │
        ▼
      proposta
        │
        ▼
valutazione Candidate B
        │
        ▼
 revisione e approvazione
        │
        ▼
attivazione Definition B
```

La Definition A rimane nel Definition Store. La Definition B possiede un'identità di contenuto diversa e registra la propria lineage. I Run già ammessi sotto A rimangono fissati ad A; i nuovi Turn ammessi dopo l'attivazione possono usare B. Dopo un riavvio, Spectre ricarica e verifica l'Activation durevole invece di fidarsi della memoria transitoria.

È un modello più vicino al deploy di una nuova release immutabile che alla modifica di alcuni campi dentro un oggetto chatbot.

Ecco il vocabolario necessario per leggere più facilmente il resto dell'articolo:

| Concetto | Significato |
| --- | --- |
| Modulo `Agent` | La dichiarazione compilata e leggibile posseduta dallo sviluppatore |
| `Definition` | La descrizione canonica e content-addressed del comportamento |
| `Surface` di Morph | Il limite immutabile che descrive quali modifiche possono essere proposte |
| `Change` | Una bozza ispezionabile che attraversa il lifecycle di Morph |
| `Candidate` | Una possibile Definition successiva, salvata con evidenze e lineage |
| `Activation` | La selezione esplicita, protetta dalla generation, di una Candidate per il lavoro futuro |
| `Skill` runtime | Comportamento data-only montato dentro una nuova Definition |

## L'Agent dichiara come gli è consentito evolvere

Morph è opt-in. Un Agent senza una dichiarazione `morph` non possiede alcuna porta Morph.

Costruiamo un piccolo Agent per il supporto:

```elixir
defmodule MyApp.SupportReplies do
  def render(:help, _input, _context) do
    "I can answer support questions. Type the exact topic you need."
  end
end

defmodule MyApp.SupportAgent do
  use Spectre.Agent, id: :support_agent, history: 30

  router(via: [:regex], semantic_cache?: false, classification_log?: false)

  morph(
    may_propose: [:mount_skill, :replace_skill, :disable_skill],
    within: [scopes: [:support], prompt_tokens: 512],
    approval: :human
  )

  flow :compiled do
    on :HELP, regex: ~r/^help$/i do
      reply(:help, renderer: {MyApp.SupportReplies, :render})
    end
  end
end
```

Il blocco `morph` non è un permesso assegnato al modello. Diventa un componente must-understand della Definition canonica dell'Agent.

Ogni opzione ha un ruolo preciso:

- `may_propose` è un vocabolario chiuso. Nella 0.3.0 Morph accetta mount, replace e disable delle Skill runtime.
- `within.scopes` è lo scope più ampio che una proposta può usare. Il chiamante può selezionarne meno, mai di più.
- `within.prompt_tokens` è il budget massimo di prompt disponibile alle Skill proposte.
- `approval: :human` richiede che una persona identificata approvi la Candidate valutata.

Questa dichiarazione è un **limite**, non una concessione di autorità. Il risultato effettivo viene comunque intersecato con Manifest, Authority Envelope, capability registrate, budget del prompt e policy di governance dell'host. Se uno strato è più stretto, vince il limite più stretto.

L'Agent compilato rimane quindi la costituzione del sistema che evolve. Il comportamento runtime può occupare uno spazio aperto intenzionalmente dal codice; i dati runtime non possono allargare quello spazio.

## Come funziona l'«autoevoluzione» nella DSL

`use Spectre.Agent` importa la macro `morph/1`. La macro viene eseguita quando il modulo dell'Agent viene compilato; non avvia un loop autonomo di apprendimento.

La dichiarazione può apparire una sola volta. `within:` deve contenere almeno uno scope e un limite positivo di token del prompt; `approval:` accetta soltanto `:human` o `:host_policy`; chiavi sconosciute e tipi di mutazione non supportati fanno fallire la compilazione dell'Agent. Il runtime non può quindi reinterpretare più tardi una configurazione vaga.

Il suo compito è trasformare la dichiarazione della DSL in un componente canonico `change_surface`, simile a questi dati di trasporto:

```elixir
%{
  "operation_types" => ["disable_skill", "mount_skill", "replace_skill"],
  "scope_ceiling" => ["support"],
  "prompt_token_ceiling" => 512,
  "approval_requirement" => "human"
}
```

Il componente è marcato `must_understand` e sigillato nell'identità di contenuto della Definition. Cambiare la DSL produce una Definition differente. Un input runtime non può riscrivere la Surface, aggiungere una quarta operazione, aumentare il tetto dei token o trasformare l'approvazione umana in automatica.

La DSL definisce quindi **come è consentito all'Agent di evolvere**, mentre un workflow runtime decide **quando proporre un'evoluzione**.

È utile separare i diversi livelli:

| Livello | Può essere automatizzato? | Proprietario |
| --- | --- | --- |
| Osservare un problema | Sì, tramite Experience esplicita, metriche o eventi host | Host e adapter di osservazione |
| Produrre una proposta | Sì, tramite estrazione dalla chat, logica applicativa o Forge | Agent/modello possono proporre dati limitati |
| Valutare la Candidate | Sì, con corpus protetto e checker registrati | Governance Spectre più evidenze dell'host |
| Approvare la Candidate | Solo nei limiti consentiti dalla Surface e da una risk policy più severa | Persona o policy host fidata, mai l'Agent |
| Attivare la Candidate | Può essere orchestrato da codice host fidato, ma rimane un commit esplicito separato | Host attraverso il confine dell'Instance |

Per un Agent addestrato via chat o gestito da admin, usa il limite umano mostrato sopra:

```elixir
morph(
  may_propose: [:mount_skill, :replace_skill, :disable_skill],
  within: [scopes: [:support], prompt_tokens: 512],
  approval: :human
)
```

In un sistema strettamente controllato, la DSL può invece permettere a una policy host fidata di approvare le modifiche che le sue regole di rischio indipendenti considerano idonee:

```elixir
morph(
  may_propose: [:mount_skill],
  within: [scopes: [:support], prompt_tokens: 128],
  approval: :host_policy
)
```

`approval: :host_policy` **non** significa «l'Agent approva se stesso». Significa che la Definition dell'Agent non impone una persona per ogni proposta, quindi una policy host fidata può scegliere approvazione umana o automatica. La risk policy indipendente della governance rimane autorevole e può comunque richiedere una persona. L'approvazione continua a non attivare la Candidate.

Di conseguenza, l'«evoluzione automatica» in Spectre non è un unico interruttore magico. È una pipeline applicativa composta da piani espliciti:

```text
Experience o chat
        │
        ▼
Reflection / ispezione host
        │
        ▼
proposta Morph o Forge limitata
        │
        ▼
valutazione del comportamento protetto
        │
        ▼
approvazione umana o tramite host policy
        │
        ▼
attivazione esplicita dell'host
```

Puoi automatizzare molto la prima metà. I confini costituzionali rimangono visibili e posseduti in modo indipendente. È questo che rende il processo un'evoluzione, invece di una deriva nascosta del prompt.

## Quale tipo di Skill può creare Morph nella 0.3.0?

La comoda API `Spectre.Morph.mount_skill/3` crea intenzionalmente una piccola Skill runtime reply-only.

Accetta:

- un mount id stabile;
- un solo match esatto e non vuoto;
- un frammento di risposta;
- esempi negativi opzionali tramite `never:`;
- una versione opzionale;
- un limite di token; e
- un sottoinsieme esplicito degli scope della Surface.

L'unico placeholder supportato nella risposta è `{{input.text}}`.

Questa limitazione è importante. Questo codice è valido:

```elixir
Spectre.Morph.mount_skill(change, "refunds",
  match: {:exact, "refund"},
  reply: "Refund policy applies to: {{input.text}}",
  scopes: [:support],
  token_cap: 128
)
```

Non è un modo per iniettare una callback Elixir, un template EEx, il nome di un modulo, credenziali o codice arbitrario. Questa facade non consente inoltre a Morph di sostituire una Skill compilata. `replace_skill/3` e `disable_skill/2` si applicano soltanto alle Skill di origine runtime già presenti nella Definition attiva.

Le Definition governate di livello più basso possono riferirsi a operation già registrate da codice host fidato, ma i dati runtime continuano a non poter inventare un executor. La facade Morph della 0.3.0 rimane più stretta: è un percorso ergonomico e reply-only sopra il motore di governance esistente.

## Il lifecycle di Morph, un confine alla volta

Una modifica completa attraversa fasi separate:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "actor:author",
    reason: "Teach the support Agent about refunds"
  )
  |> Spectre.Morph.mount_skill("refunds",
    match: {:exact, "refund"},
    reply: "Refund policy applies to: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)

{:ok, report} = Spectre.Morph.explain(change)

approved =
  Spectre.Morph.approve(change,
    by: "actor:reviewer",
    mode: :human
  )

{:ok, activation} = Spectre.Morph.activate(approved)
```

Queste chiamate non sono state unite intenzionalmente in un ipotetico `learn_and_restart/1`.

### 1. `change`

`change/2` apre una bozza contro l'esatta Definition attiva dell'Instance. Autore, motivazione ed eventuali evidenze vengono legati alla proposta. La Surface canonica viene riletta dal Definition Store e non accettata dallo stato transitorio del chiamante.

### 2. `mount_skill`, `replace_skill` o `disable_skill`

Queste funzioni aggiungono alla bozza operation tipizzate e inerti. Non modificano l'Agent in esecuzione. Le opzioni non valide fanno fallire il `Change` senza applicare parzialmente il comportamento.

### 3. `evaluate`

La valutazione compone una Candidate ed esegue controlli reali sul comportamento. Confronta parent e Candidate sullo stesso corpus protetto e aggiunge obblighi derivati dal diff effettivo tra le Definition.

Per una nuova Skill con risposta esatta, Morph crea un caso posseduto dalla Candidate che dimostra come il nuovo input produca esattamente l'output promesso. Il caso deve passare, ma pesa zero nel punteggio protetto. Una Candidate non può scrivere test facili per se stessa e usarli per nascondere una regressione: il classico fallimento di Goodhart.

### 4. `explain`

`explain/1` restituisce un report umano deterministico. Puoi mostrarlo in una pagina admin, conservarlo nell'audit log o renderlo come card nella chat. Il report descrive evidenze verificate; non chiede a un altro modello un'opinione priva di fondamento.

### 5. `approve` o `reject`

L'approvazione è un commit separato dell'host. Registra che un attore autorizzato ha accettato la Candidate valutata. Non rende attiva la Candidate.

### 6. `activate`

L'attivazione rilegge gli artefatti durevoli, ripete la verifica costituzionale e usa la generation di attivazione dell'Instance come fence compare-and-swap. Una proposta obsoleta non sovrascrive silenziosamente una Definition più recente.

Questo conserva una delle regole centrali di Spectre:

> **L'approvazione non è esecuzione e una proposta non è autorità.**

## Il corpus protetto è la memoria di ciò che non deve rompersi

Prima di abilitare Morph, definisci casi comportamentali per l'Agent di cui già ti fidi:

```elixir
protected_cases = [
  %{
    "id" => "unrelated-input-stays-unhandled",
    "input" => "weather",
    "expected_outcome" => "clarify",
    "context" => %{"scope" => "support"},
    "llm" => "forbidden"
  }
]
```

In un'applicazione reale, il corpus dovrebbe coprire route compilate importanti, confini delle policy, casi negativi di routing e comportamenti che devono rimanere indisponibili. L'intero contenuto canonico — non soltanto gli id dei casi — viene legato alla valutazione e all'identità della closure.

Se la nuova Skill `refund` cattura per errore `weather`, collide con una route esistente, supera il proprio budget di prompt o modifica un comportamento protetto, la Candidate viene rifiutata prima dell'attivazione.

Un agente capace di evolvere senza test di regressione è semplicemente un agente capace di andare alla deriva.

## Chat e admin sono due interfacce, non due modalità di sicurezza

Dentro Morph non esiste `mode: :chat` o `mode: :admin`. È una scelta intenzionale.

Chat e pannello admin sono punti d'ingresso dell'applicazione. Possono raccogliere la stessa proposta in modo diverso, ma devono entrambi attraversare la stessa pipeline Morph posseduta dall'host.

| Domanda | Interfaccia chat | Interfaccia admin |
| --- | --- | --- |
| Come viene raccolto l'intento? | Una conversazione, eventualmente strutturata da un modello | Un form tipizzato o un'API interna |
| Chi autentica l'attore? | L'host dietro il canale | L'host dietro la sessione admin |
| Chi fornisce `by:` e la modalità di approvazione? | Codice host fidato | Codice host fidato |
| L'input può allargare la Surface? | No | No |
| Può attivare senza valutazione? | No | No |
| Produce la stessa lineage della Candidate? | Sì | Sì |

Questa distinzione permette di costruire due esperienze piacevoli senza creare due sistemi di governance.

## Mettere la logica Morph condivisa in normale Elixir

L'applicazione dovrebbe possedere un solo servizio chiamato da entrambe le interfacce:

```elixir
defmodule MyApp.AgentEvolution do
  alias Spectre.Morph

  def propose(instance, actor_ref, reason, skill, protected_cases) do
    change =
      instance
      |> Morph.change(
        by: actor_ref,
        reason: reason,
        evidence: Map.get(skill, :evidence, %{})
      )
      |> Morph.mount_skill(skill.mount_id,
        match: {:exact, skill.match},
        reply: skill.reply,
        scopes: skill.scopes,
        token_cap: skill.token_cap
      )
      |> Morph.evaluate(cases: protected_cases)

    case Morph.status(change) do
      %{state: :evaluated, error: nil, candidate_ref: candidate_ref} ->
        with {:ok, report} <- Morph.explain(change) do
          {:ok, %{candidate_ref: candidate_ref, report: report}}
        end

      status ->
        {:error, status}
    end
  end

  def approve_and_activate(instance, candidate_ref, reviewer_ref) do
    approved =
      instance
      |> Morph.resume(candidate_ref, by: reviewer_ref)
      |> Morph.approve(by: reviewer_ref, mode: :human)

    case Morph.status(approved) do
      %{state: :approved, error: nil} -> Morph.activate(approved)
      status -> {:error, status}
    end
  end
end
```

Il codice di produzione dovrebbe registrare la proiezione dello status, conservare report ed evidenze e gestire esplicitamente Candidate rifiutate o obsolete. L'esempio mantiene visibile l'happy path senza spostare la policy dentro un controller o un prompt.

L'`instance` di questo esempio deve avere già una Definition canonica attiva e un Definition Store configurato. Il suo Manifest deve concedere le corrispondenti capability delle Skill runtime e il budget del prompt. Per un deploy durevole, l'Instance richiede anche la normale configurazione di checkpoint e ownership descritta nella documentazione operativa di Spectre.

## Modalità 1: proporre una nuova Skill attraverso la chat

Immagina che un operatore autenticato dica all'Agent:

> Quando qualcuno scrive esattamente “refund”, rispondi che la policy di rimborso si applica alla sua richiesta.

Un modello può aiutare a tradurre la frase in un intento chiuso:

```elixir
skill_intent = %{
  mount_id: "refunds",
  match: "refund",
  reply: "Refund policy applies to: {{input.text}}",
  scopes: [:support],
  token_cap: 128,
  evidence: %{
    "source" => "chat",
    "conversation_id" => conversation.id
  }
}
```

L'output del modello non viene passato come insieme arbitrario di opzioni. L'host valida questo schema fisso, ricava autonomamente l'attore autenticato e chiama il servizio condiviso:

```elixir
{:ok, pending} =
  MyApp.AgentEvolution.propose(
    instance,
    "operator:#{current_user.id}",
    "New support behaviour requested in chat",
    skill_intent,
    protected_cases
  )

send_review_card(pending.candidate_ref, pending.report)
```

A questo punto l'Agent ha **proposto** una nuova Skill. Non ne ha installata una.

Un reviewer autenticato può approvare dalla stessa esperienza chat, ma l'applicazione deve risolverne l'identità e mostrare una conferma esplicita. Non bisogna mai permettere al modello di emettere il proprio `by:`, scegliere `mode: :human` o chiamare l'attivazione perché ha scritto la parola «approved».

```elixir
{:ok, activation} =
  MyApp.AgentEvolution.approve_and_activate(
    instance,
    pending.candidate_ref,
    "reviewer:#{current_admin.id}"
  )
```

La chat è quindi una UI conversazionale per proposta e revisione. Non è il confine di sicurezza.

## Modalità 2: creare e approvare una Skill dal pannello admin

Il percorso admin non richiede affatto un modello. Un form LiveView può raccogliere:

- mount id;
- trigger esatto;
- testo della risposta;
- scope consentito; e
- limite di token.

Il form invia la stessa struttura `skill_intent` a `MyApp.AgentEvolution.propose/5`. La pagina admin mostra `pending.report`, i Ref del parent e della Candidate e due azioni separate: **Reject** e **Approve and activate**.

```elixir
{:ok, pending} =
  MyApp.AgentEvolution.propose(
    instance,
    "admin:#{author.id}",
    "Add the refund answer from the support console",
    skill_intent,
    protected_cases
  )

# Mostra pending.report e richiedi una seconda azione esplicita.

{:ok, activation} =
  MyApp.AgentEvolution.approve_and_activate(
    instance,
    pending.candidate_ref,
    "reviewer:#{reviewer.id}"
  )
```

Spectre richiede una persona identificata per una Surface dichiarata con `approval: :human`; l'eventuale obbligo di usare persone diverse come autore e reviewer è invece una scelta della policy host. Per Agent importanti, vale la pena imporre la separazione dei ruoli.

## Dimostrare che l'Agent è davvero cambiato

Prima dell'attivazione, la nuova route non è attiva:

```elixir
{:ok, before_turn} =
  Spectre.turn(instance, "refund",
    skill_context: %{"scope" => "support"}
  )

{:no_response, _result} = before_turn.decision
```

Dopo approvazione e attivazione, un Turn nuovo viene risolto attraverso la Skill runtime:

```elixir
{:ok, after_turn} =
  Spectre.turn(instance, "refund",
    skill_context: %{"scope" => "support"}
  )

{:reply, "Refund policy applies to: refund", _turn_ref} =
  after_turn.observable
```

`skill_context` deve provenire da un contesto host fidato. Non ricavare uno scope privilegiato da testo arbitrario dell'utente. Quando una Surface possiede più scope, Morph richiede inoltre che ogni Skill proposta selezioni un sottoinsieme esplicito e non vuoto, invece di ereditare accesso ampio per omissione.

## Sostituire o disabilitare ciò che Morph ha creato

Lo stesso lifecycle può migliorare una Skill runtime:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Clarify the refund answer"
  )
  |> Spectre.Morph.replace_skill("refunds",
    match: "refund",
    reply: "A support specialist will review: {{input.text}}",
    scopes: [:support],
    token_cap: 128
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Oppure ritirarla:

```elixir
change =
  instance
  |> Spectre.Morph.change(
    by: "operator:author",
    reason: "Withdraw the obsolete refund answer"
  )
  |> Spectre.Morph.disable_skill("refunds")
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Entrambi i percorsi richiedono ancora revisione, approvazione e attivazione. La valutazione del disable verifica inoltre che la rimozione della Skill non faccia catturare inaspettatamente il suo input da uno scope fratello.

## Proposte obsolete e rollback sono espliciti

Immagina di aprire due proposte partendo dalla Definition A. La prima attiva la Definition B. La seconda proposta continua a puntare ad A ed è ora obsoleta.

Spectre non la riapplica silenziosamente su B. Devi scegliere di eseguire il rebase del suo intento tipizzato:

```elixir
rebased =
  stale_change
  |> Spectre.Morph.rebase(
    by: "operator:author",
    reason: "Rebase the proposal on the current Definition"
  )
  |> Spectre.Morph.evaluate(cases: protected_cases)
```

Il rebase crea una nuova identità e ripete i controlli.

Anche il rollback è esplicito e procede in avanti. Spectre attiva un antenato immutabile come una nuova generation di Activation; non cancella la Definition B e non finge di annullare gli Effect esterni già eseguiti mentre B era attiva.

È una verità sottile ma importante dei sistemi distribuiti: lo stato del codice può tornare indietro, mentre il mondo esterno potrebbe non farlo.

## Morph, Reflection e Forge sono cose diverse

Spectre 0.3.0 introduce anche Reflection, Experience e Forge. Completano Morph, ma non sono suoi sinonimi.

| Piano | Scopo | Che cosa non può fare |
| --- | --- | --- |
| Experience | Registrare osservazioni esplicite e redatte | Diventare da sola autorità o stato canonico |
| Reflection | Ispezionare meccanicamente fatti dichiarati, effettivi e osservati | Eseguire istruzioni ispezionate o chiamare un modello |
| Forge | Produrre una proposta inerte da Reflection ed Experience verificate | Pubblicare, approvare, attivare o registrare codice |
| Morph | Offrire all'host una piccola API per modifiche governate alle Skill | Allargare la Surface dell'Agent o saltare la governance |

Una futura esperienza chat può usare Reflection e un critic Forge basato su modello per suggerire che manca una Skill. Il suggerimento finale rimane comunque una proposta. La stessa catena basata sullo Store — valutazione, approvazione e attivazione — conserva il controllo.

## Ciò che Morph rifiuta intenzionalmente di essere

Morph non è:

- un prompt che dice al modello di migliorarsi;
- un compilatore Elixir dinamico;
- un meccanismo per scaricare ed eseguire Skill generate;
- un registro illimitato di tool;
- memoria travestita da comportamento;
- una prova che la proposta di un modello sia corretta; o
- un permesso con cui l'Agent approva la propria modifica.

Questi rifiuti sono la funzionalità.

Conservano la filosofia più ampia di Spectre:

1. **Il modello propone; l'host esegue.**
2. **I dati runtime non diventano mai codice.**
3. **Le Definition sono immutabili e content-addressed.**
4. **Una sola Instance OTP possiede la mutazione canonica ordinata.**
5. **I Run conservano la Definition che li ha ammessi.**
6. **Approvazione e attivazione sono fatti separati.**
7. **Evidenza assente, ambiguità e stato obsoleto falliscono in modo chiuso.**

## Checklist per la produzione

Prima di esporre Morph attraverso una chat o un pannello admin, assicurati che l'applicazione possieda:

- un'identità dell'attore autenticata e ricavata dall'host;
- un Definition Store durevole e il normale confine di persistenza dell'Instance;
- la Surface Morph più stretta possibile;
- un corpus protetto che copra comportamento positivo e negativo esistente;
- capability esplicite per le Skill runtime nell'autorità del Manifest;
- budget del prompt inferiori alla riserva kernel dell'Agent;
- una UI di revisione basata su `Morph.explain/1` e `Morph.status/1`;
- gestione separata di rifiuto, approvazione e attivazione;
- rebase esplicito delle proposte obsolete;
- lineage ed evidenze di audit conservate; e
- un piano di rollback che non prometta di invertire side effect esterni.

Testa inoltre un Turn reale prima e dopo l'attivazione. Costruire un `Change` valido dimostra soltanto che la proposta ha una forma corretta; non dimostra che l'Agent vivo si comporti come previsto.

## Il vero significato di un Agent Spectre che si modifica da solo

Un Agent Spectre non diventa un piccolo sviluppatore con accesso alla shell.

Diventa un sistema capace di proporre una nuova versione del proprio comportamento dichiarato, restando dentro limiti scelti dal codice, autorità scelta dall'host, evidenze scelte dalla valutazione e ownership imposta da un processo OTP.

La chat può rendere conversazionale questa evoluzione. Un pannello admin può renderla operativa. Reflection e Forge possono rendere le proposte più informate. Nessuna di queste interfacce modifica il percorso costituzionale.

È per questo che Morph si integra in Spectre invece di indebolirne la filosofia: **l'Agent può evolvere, ma le regole con cui evolve non appartengono all'Agent.**
