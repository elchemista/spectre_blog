---
title: "Spectre 0.4: Your Agent Is More Than a Tool Loop"
slug: "spectre-0-4-stack-agent-routes-server-architecture"
lang: "en"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Software Development"
tags: ["Elixir", "OTP", "AI agents", "Spectre", "Spectre 0.4", "AgentServer", "routing", "architecture", "storage"]
seo_title: "Spectre 0.4 Architecture: Stack, Agent, Routes, Server"
seo_description: "Build real Elixir agents with Spectre 0.4: Stack, declarative routes, OTP Server, automatic GAM, RAM-only mode, Ledger and custom storage."
cover_alt: "Spectre 0.4 architecture showing Stack capabilities, Agent routes, Server runtime, GAM admission and pluggable storage"
---

A chatbot answers a question. An agent can act.

Now imagine it has a hundred customers, three different tools, a database outage, a message arriving while it is still thinking, and a manager who wants to know **why it sent an invoice**.

That is where an agent stops being a clever prompt and starts being software.

With **Spectre 0.4**, I changed the architecture rather than adding another abstraction to the old loop. I wanted an agent I could read like an Elixir application: what it knows how to recognize, what it is allowed to use, which process owns its work, and what must happen before it changes the outside world.

The new mental model is:

~~~text
                  Spectre 0.4

   STACK                 AGENT                  SERVER
   Capabilities    →     Routes / intents   →   OTP owner
   Models                 Regex / vectors        Context
   Tools                  Local / LLM            Workers
   Resources              Recognition            Continuations
                                                     |
                                             Consequence proposed
                                                     |
                                                     v
                                              Managed GAM
                                                     |
                                       Authorized registered effect
                                                     |
                                           Observed outcome
~~~

The middle is deliberately called **Agent**, not Route: routes live *inside* the declarative `Spectre.Agent`. In practical terms, you build **Stack → Agent (Routes) → Server**.

This is not just cleaner syntax. It puts the right responsibilities in the right places.

## 1. Stack: install capabilities, not permissions

A Stack declares what an agent's application environment can provide.

~~~elixir
defmodule MyApp.AI do
  use Spectre.Stack

  # Add installable packages here when you need them:
  # install MyApp.Inference
  # install MyApp.InvoiceTools
end
~~~

An installation may provide a model, browser, memory, messaging service or registered tool. Packages declare dependencies, conflicts, ownership and immutable descriptors; Spectre compiles and validates that environment rather than discovering arbitrary helpers at runtime.

But there is a crucial distinction: **installed does not mean authorized**.

An invoice tool may exist in the Stack. That does not entitle an agent to send every invoice it can imagine. The tool's registration, the Server's allowed operations, host policy and GAM admission are separate gates.

This is the difference between giving someone access to a building and giving them the authority to sign a payment.

## 2. Agent: recognize intent without hiding business logic in a prompt

The Agent describes *which requests exist*. It does not own a second conversation loop.

~~~elixir
defmodule MyApp.BillingAgent do
  use Spectre.Agent,
    stack: MyApp.AI,
    server: MyApp.BillingServer

  router strategies: [:regex, :bag, :jaro]

  flow :billing do
    on :invoice_status,
      regex: ~r/\binvoice status\b/i,
      bag: ["check invoice"],
      jaro: ["invoice status"]

    on :help,
      regex: ~r/\bhelp\b/i
  end
end
~~~

This example works without an LLM or embedding model. Regex recognizes an explicit command. Bag and Jaro similarity can handle nearby wording and typos.

When an application needs more flexibility, the same router can combine **reviewed IntentDataset examples, embeddings, a local classifier, an LLM classifier or a custom adapter**. An early deterministic match may avoid the model entirely. Classification chooses among declared routes; it does not invent new business authority.

I like this separation because a developer can answer two different questions:

- *How did the agent understand this message?* Look at routing evidence.
- *Why did the application do that?* Look at the Server handler and its recorded work.

Recognition can be probabilistic. Business behavior should still be inspectable.

## 3. Server: one supervised owner, ordinary Elixir

The Server implements the behavior for routes. `Spectre.Server.Runtime` is the real GenServer; your callback module is **not** a second hidden runtime.

~~~elixir
defmodule MyApp.BillingServer do
  use Spectre.Server, tools: MyApp.AI

  @impl true
  def handle_flow({:billing, :invoice_status}, _input, ctx) do
    respond(ctx, "I can look up an invoice once you provide its number.")
  end

  def handle_flow({:billing, :help}, _input, ctx),
    do: respond(ctx, "Ask me about an invoice.")

  def handle_flow(:unmatched, _input, ctx),
    do: respond(ctx, "I didn't recognize that request.")
end

{:ok, server} =
  Spectre.Server.start_link(
    agent: MyApp.BillingAgent,
    consumer: self()
  )

{:ok, interaction} =
  Spectre.Server.input(server, "invoice status")

receive do
  {Spectre.Server, ^server, {:response, ^interaction, text, _metadata}} ->
    IO.puts(text)
end
~~~

That is an actual model-free AgentServer shape, not a pseudo-agent defined by a system prompt.

When real work starts, Server helpers queue commands in the Context:

~~~elixir
# Fragment from a Server with a configured model service.
def handle_flow({:billing, :explain}, input, ctx),
  do: generate(ctx, :explain_invoice, input: input, on_result: :explained)

def handle_result(:explained, {:generated, response}, ctx),
  do: respond(ctx, response.text)
~~~

The runtime dispatches workers, correlates the result and returns to the named continuation. It owns pending intentions, command acquisition, streams and checkpoints. Native `handle_call`, `handle_cast` and `handle_info` follow ordinary OTP return shapes with Context as state.

Portable application state belongs in `ctx.assigns`. Process-local references and handles belong in `ctx.private`, not in persisted state. Shared provider resources belong to the Stack runtime.

You are no longer obliged to invent a fragile, ad hoc loop every time an agent needs to wait, resume or handle two things at once.

## 4. GAM is in the path before an action matters

Suppose the model suggests sending an invoice. A suggestion is not an authorization, and a tool being installed is not a permission.

For a *registered* invoice effect, a Server can propose:

~~~elixir
propose(ctx, :send_invoice,
  %{"invoice_id" => "INV-104", "to" => "client@example.test"},
  on_result: :invoice_sent)
~~~

The application's allowed operations and GAM determine whether that concrete consequence may proceed. If consent is required, Spectre creates a frozen Presentation and checks the exact human response. Only an admitted, committed Act can release the registered executor.

GAM is not something every Server callback must manually rebuild. **Managed GAM** owns the Domain, Scope, ingress, proposal binding, consent protocol and result delivery. You still decide the business rules and who really has authority.

This design matters because the hardest bug is rarely “the model called the wrong function.” It is “the model called a function that should never have been executable under those circumstances.”

The [GAM guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/GAM.md) and [Managed GAM integration](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md) document that boundary.

## 5. No database required. And you are not locked into mine.

One of my favorite properties of Spectre 0.4 is how small it can start.

**Option A — entirely in RAM.** The default AgentServer can run without PostgreSQL, Ledger or any companion package. This is useful for a prototype, a transient assistant or an application that explicitly accepts losing session history on restart.

~~~elixir
gam: [storage: :ephemeral]
~~~

**Option B — durable local history.** Select disk storage when you want continuity without deploying a database server:

~~~elixir
gam: [storage: {:disk, "var/agents/customer-42"}]
~~~

A stable authenticated identity is required for durable storage.

**Option C — PostgreSQL through `spectre_ledger`.** The optional [Ledger package](https://github.com/elchemista/spectre_ledger) integrates coordination, canonical GAM history and a persisted per-record Domain projection. Your application still starts the Repo and applies migrations. Simply installing the package does not magically select a database.

~~~elixir
gam: [storage: :ledger, operations: allowed_operations]
~~~

**Option D — your own store.** Implement `Spectre.Server.Store` and connect your own backend:

~~~elixir
# MyApp.Storage implements @behaviour Spectre.Server.Store.
gam: [storage: {MyApp.Storage, MyApp.Repo}]
~~~

This is more than a “save messages” callback. The unified contract covers atomic coordination (`fetch/2`, `put_new/3`, `compare_and_swap/4`, `delete/3`), canonical GAM history (`ledger_*`), and optionally the complete `projection_*` group for persisted projections. It enforces strict semantics for revisions, ambiguous writes and bounded reads.

You can choose your persistence technology without replacing the AgentServer/GAM protocol.

### What about RAM limits?

A subtle but important change: with a **projection-backed Domain**, Spectre loads the records needed for a command, commits the derived changes and releases historical records instead of retaining the *entire* read model in the Domain heap.

That is a major improvement for long-lived agents. But it is **not** a promise of fixed or zero memory growth: active Duties, authority, relevant evidence groups and full-history diagnostics still consume memory. Without a projection store, the complete projection stays in RAM. Database latency also remains real.

The system provides bounded page reads and worker controls; you choose your workload budgets and storage. Even `hibernate_after` is an optimization for an idle Runtime, not a magical memory quota.

For details, see [Domain storage](https://github.com/elchemista/spectre/blob/0.4.0/docs/DOMAIN_STORAGE.md), [the Store behaviour](https://github.com/elchemista/spectre/blob/0.4.0/lib/spectre/server/store.ex) and [OTP memory profiling](https://github.com/elchemista/spectre/blob/0.4.0/docs/OTP_PROFILE_0_4.md).

## 6. Reset is deliberate; recovery is not wishful thinking

Need to start a new conversation without tearing down the owner?

~~~elixir
:ok = Spectre.Server.reset(server)
~~~

The reset keeps the root PID, identity and configuration, restarts mounted Skills with fresh state and fences old-session replies. It refuses unresolved governed work with `:reset_busy`. Durable reset opens a new session generation without erasing historical audit facts.

A failed database is different. You may wait, retry recovery from verified history, or **explicitly** choose a fresh RAM Domain. That new Domain cannot inherit old authorizations. History is not silently merged back later, and an uncertain external effect still requires reconciliation.

An agent should not “recover” by pretending that missing authority or an unanswered payment never existed.

## 7. Why this is a different kind of developer experience

Spectre still lets you start with a tiny Agent and a regex. Add a model only when it helps. Add a database only when persistence matters. Install Skills, tools and external channels as your application grows.

But crucial boundaries are already part of the framework's vocabulary:

- **Stack:** what exists.
- **Agent/Routes:** what input means.
- **Server:** who owns the work.
- **GAM:** what is authorized.
- **Outcome:** what actually happened.
- **Store:** what remains knowable after restart.

It is not a guarantee of correctness for arbitrary Elixir code, nor automatic legal compliance. The host must authenticate users, register real effects and keep consequential I/O inside the governed path.

What it does give you is the architecture that often gets postponed until *after* the first expensive incident.

Start with `mix spectre.gen.agent MyApp.SupportAgent --server`, the [0.4 getting-started guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/GETTING_STARTED.md), and the [0.3 → 0.4 migration guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/MIGRATING_TO_0_4.md).

**An agent should be easy to start. A serious agent should also be possible to explain. Spectre 0.4 is built for both.**
