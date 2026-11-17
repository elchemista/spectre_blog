---
title: "Spectre 0.4: Agents That Work Within Explicit Authority"
slug: "spectre-0-4-agents-authority-and-human-control"
lang: "en"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Software Development"
tags: ["Elixir", "OTP", "AI agents", "Spectre", "GAM", "architecture", "human approval"]
seo_title: "Spectre 0.4: Agents with Authority and Human Control"
seo_description: "How Spectre 0.4 separates recognition, conversation and governed execution, with explicit authority, human approval, durable history and practical Elixir APIs."
cover_alt: "Stack, Agent and Server connect conversation to GAM admission, human approval, execution and an observed result"
---

An agent drafts a customer email. The text is good. The recipient is correct. The model is confident. Can it send?

That question is not another text-generation problem. It concerns the application's authority, the person's consent and what the external mail service actually does.

Spectre 0.4 makes those boundaries visible in the way an Elixir application is written. **Stack selects capabilities. Agent recognizes intentions. Server owns the conversation. GAM governs the declared operations that have consequences.**

The core 0.4.0 release is available on Hex. It brings substantial authoring and runtime changes; existing 0.3 applications should follow the [migration guide](/en/docs/migration), rather than treating the upgrade as a dependency-number change.

## Start with three modules you can read

The architecture follows a simple order:

```text
Stack → Agent → Server
                  │
          cognition and tool workers
                  │
          concrete effect proposal
                  ▼
             Managed GAM
      authority + required evidence
                  │
        human consent when required
                  │
             admitted Act
                  ▼
        registered execution adapter
                  │
            observed Outcome
```

A **Stack** installs reusable capabilities: models, browser tools, memory or messaging. An **Agent** declares routes, intents and recognition strategies. A **Server** implements the application callbacks and owns state, pending work and continuations inside an OTP process.

This gives recognition room to improve without moving business behavior into a prompt. The router can combine regex, character similarity, reviewed intent examples, vector similarity, a local classifier and LLM classification. It can use a model when that helps. The handler it selects remains a declared application handler.

The Server is equally ordinary Elixir. Conversation callbacks return a Context. Native `handle_call`, `handle_cast` and `handle_info` keep their OTP tuple shapes, with that Context as state. Model calls and installed tools run in workers and return to named continuations.

The [first-agent guide](/en/docs/getting-started) starts without a model or database. The [routing guide](/en/docs/routing) then adds embeddings and model classification, including the distinction between an encoder that creates vectors and Vettore's indexes that search them.

## GAM means Governed Act Model

The [GAM manifesto](/en/governed-act-model) describes the model behind the boundary from a proposal to an authorized operation.

A model can propose. A route can recognize. A tool package can register an executor. None of those facts, alone, gives an agent permission to perform the operation.

GAM checks the applicable authority and evidence for a concrete candidate. When human consent is required, it is tied to the exact presented operation and arguments. After admission, the registered executor performs an attempt and the system records what was observed.

Managed GAM connects that model to AgentServer. It constructs the presentation, coordinates the wait, verifies the decision and releases registered execution after valid admission. Applications configure permitted operations and business policy; they do not have to reimplement the protocol in every callback.

For a registered Kinetic mail operation, startup can require:

```elixir
# Fragment of AgentServer options; effect registration and host adapters required.
gam: [operations: %{{:kinetic, :send_email} => [confirm: true]}]
```

The Server proposes the draft instead of invoking the mail client directly:

```elixir
# Callback fragment inside a Server with a registered mail effect.
propose(ctx, {:kinetic, :send_email},
  %{"to" => recipient, "body" => draft},
  on_result: :sent)
```

The consumer shows the exact presentation, acknowledges actual rendering and submits the human's separate choice. Changing the message or recipient is not permission to reuse a decision made for a different draft.

The [architecture guide](/en/docs/architecture-gam) explains the terminology. The [recipes](/en/docs/recipes) connect it to typed Kinetic proposals and installed tools, with the application dependencies called out explicitly.

## Permission and success are different facts

Suppose the person approves. The mail service receives the request, applies it and the connection drops before the reply comes back.

The agent has an admitted operation and an uncertain external result. It does not have evidence that the mail failed. Repeating the send might send it twice.

Spectre keeps admission and execution outcome separate. Application code should report success when the recorded Outcome establishes success, preserve unknown outcomes and reconcile them against the provider's truth before repeating nonrepeatable work.

This separation matters to the business more than an optimistic “Done” message. Support can distinguish a refusal from a service failure. An operator can investigate an uncertain payment. A customer can see which exact operation they approved. The host still needs correct adapters, provider idempotency where available and an operational reconciliation policy.

## Your agent can ask my agent, without giving AI the authority

A customer agent may need your approval before opening a website. You already have a personal chat with your own agent. The request should reach that chat, and you should confirm or reject it there.

In 0.4, the requester and approver can run as two AgentServers with independent GAM Domains. The customer freezes the request; the personal agent delivers it to its authenticated human consumer; the human decision returns as signed, correlated evidence. The customer's original mandate still controls admission.

Pulse can transport the messages, but it is optional. The core contains a runnable two-agent example using a mailbox adapter. A custom transport implements the same approval contract. A technical `accepted` receipt means delivery acquisition, not human consent or completed execution.

The protocol handles request identities, immutable bindings, presentation acknowledgement, expiry and consumed replies. Retrying a stored choice resends the same signed decision. A model is an intermediary, not the approver. Real human authentication and trusted signing remain responsibilities of the application.

See the [transport-independent approval guide](/en/docs/agent-to-agent) for the flow and its restart limits.

## Skills can work independently within one authority boundary

A research Skill and a billing Skill can have separate Server processes, local state and workers. One can answer while another awaits consent. Both share the root agent's GAM Domain, with the mount's restrictions.

That is different from two independent agents communicating across Domains. A Skill mount does not need a new authority history or another consent protocol. Its proposal still needs both the root's permitted operation and the mount's allowed operation reference.

This keeps reusable capabilities useful without turning every package into another runtime framework. The application can read the declarations, callbacks and consequence boundary in one place.

## Durable history should not become permanent process memory

RAM-only operation remains a supported starting point. No database or Ledger package is required.

For growing histories, a configured storage provider can keep canonical GAM batches, Server coordination and the Domain's historical projection in a database. The live Domain retains its authority roots and active frontiers, loading relevant historical rows when needed and releasing them after the command.

That reduces historical RAM residency. It does not promise constant memory for arbitrary active work, or commits independent of database latency. Cold recovery still verifies canonical history; the derived projection cannot replace missing authority facts.

Applications can implement one `Spectre.Server.Store` provider with the relevant history/projection callback groups. Ledger supplies file and PostgreSQL integrations. Database ownership, migrations and connection pools stay with the host.

Private email bodies, URLs, assigns and receipts need their own storage policy. The optional payload adapter exposes `put` and `fetch`, allowing an encrypted database, object store or another service to return opaque portable references. There is no mandatory content-addressing scheme. Ledger installation alone does not encrypt or remove existing inline data.

A database outage is explicit. The host can wait, retry recovery or deliberately select a fresh RAM Domain, which cannot reuse previous consent. Divergent histories are not silently merged. The [storage guide](/en/docs/storage) explains these choices and distinguishes recovery from a complete session reset.

## Where this helps a real application

| Workflow | The useful boundary |
| --- | --- |
| Customer outreach | Prepare a draft freely; send only the exact approved recipient/content through the permitted adapter |
| Refund assistance | Recognize the request separately from authority to refund a particular invoice; report the provider's observed result |
| Shared research | Require the designated person's consent for protected navigation or disclosure, even when their chat uses another agent |
| Operations assistance | Keep read/analysis tools distinct from deployed changes, and preserve uncertain external outcomes for review |
| Long-lived support | Use explicit session identity, database history and bounded historical queries instead of keeping every event in a process heap |

These are application-design boundaries. They do not establish automatic legal compliance, complete privacy protection or correct business policy without the host implementing those requirements.

## A release that changes how you structure the application

The practical starting point is still small:

```elixir
{:spectre, "~> 0.4.0"}
```

Generate the current Agent/Server shape with `mix spectre.gen.agent MyApp.SupportAgent --server`, run its test, then add capabilities one at a time. The nine satellite libraries are optional and have independent release versions; use compatible published packages or the [tested source catalogue](/en/docs/ecosystem).

The new [documentation](/en/docs/overview) covers routing, dataset review/training, all core Mix tasks, extension behaviours, storage, external approval and production testing. Existing 0.3 applications have a dedicated migration path.

The goal is an agent application whose recognition can be probabilistic while its ownership, authority and observed effects remain explicit enough to understand, test and operate.
