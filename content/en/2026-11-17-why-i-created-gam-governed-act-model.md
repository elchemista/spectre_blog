---
title: "Why I Created GAM: An AI Agent Needs Authority, Not Just Tools"
slug: "why-i-created-gam-governed-act-model"
lang: "en"
status: published
date: 2026-11-17
updated: 2026-11-17
category: "Software Development"
tags: ["AI agents", "Spectre", "Spectre 0.4", "GAM", "Governed Act Model", "enterprise AI", "governance", "security", "human approval"]
seo_title: "Why I Created GAM: Governed AI Agents Explained"
seo_description: "The Governed Act Model explained simply: mandates, evidence, acts, duties, human consent and why serious AI agents need more than a tool-permission flag."
cover_alt: "A proposed AI action passes through authority, evidence and consent before becoming a committed act with an observed outcome"
---

There is a pattern I keep seeing.

Build an AI agent. Give it tools. It works beautifully in a demo. Then somebody asks: **“Can the agent really do that?”**

We add a permission check.

Then: “But who approved the permission?” We add an approval screen.

Then: “What exactly did they approve?” We attach parameters.

Then: “What if those parameters change while they are approving?” We freeze the request.

Then: “What if the payment succeeded but our connection dropped?” We add an audit trail, idempotency, reconciliation and a way to decide what still needs attention.

And suddenly the “simple tool call” has become the core of an enterprise system.

I kept encountering the same shape in different projects. Not because of one bad framework, but because **delegating power has always been a difficult problem**. AI makes it more visible: a model can suggest thousands of actions, but the organization must remain accountable for every consequential one.

That is why I created **GAM - Governed Act Model**.

GAM is not another prompt technique. It is a model for how a *proposed consequence* becomes an *authorized, recorded act*, and how we deal with what happens afterward. In Spectre 0.4, this model is integrated into AgentServer through Managed GAM.

## The strange similarity between an AI agent and government

Think about a public institution. A citizen requests a permit. An employee checks the application. A law says which office has authority. A decision is recorded. An authorized person may issue the permit. If the record is wrong or the action causes a problem, there is a process for review.

The citizen asking is not the permit being issued.

A clerk understanding the request is not the authority to grant it.

An official signing a decision is not proof that the road was actually built.

I am **not** saying an AI system should copy a country's politics. Governments have their own histories, democratic legitimacy and failures. The analogy is about a simpler, recurring engineering pattern: **requests, rules, authority, evidence, decisions, acts and responsibility are different things**.

You can recognize it in a bank, a hospital, a procurement department, an API authorization service and an enterprise agent platform.

We learned long ago not to let the person requesting a transfer be the sole authority that approves and records it. Why would we give a probabilistic model that privilege?

## A real-world example: “Send this invoice”

Imagine a company assistant.

> Employee: Send invoice INV-104 to the customer for €1,250.

An LLM can understand that sentence perfectly. It can identify the customer, draft the email and fill in the invoice number.

That still doesn't answer the important questions:

- Is this employee allowed to send that invoice?
- Does the amount require a manager's approval?
- Which recipient and attachment are being approved?
- Is the invoice already sent?
- If the mail service times out, can the agent try again safely?
- Who is responsible for resolving the uncertainty?

A conventional function call gives you an operation name and arguments. It does not, by itself, answer those questions.

Here is the conceptual difference:

~~~text
Naive loop:
  "Send invoice" -> model selects tool -> send_invoice(...)

GAM-governed path:
  Request -> proposed Candidate
          -> authority and Evidence
          -> Decision
          -> committed Act
          -> registered executor
          -> observed Outcome
          -> unresolved Duty, if necessary
~~~

**The point is not to make every click bureaucratic.** It is to make consequential actions accountable without forcing a developer to reinvent the protocol each time.

## The four words that explain GAM

The [GAM manifesto](https://spectre.guide/en/governed-act-model) introduces four especially useful concepts.

### 1. Mandate - *Who gave you the authority?*

A Mandate describes legitimate authority and its scope. It says who may act, for what purpose, on what subject or resources, and within which limits.

A billing assistant might be allowed to *prepare* invoices, but sending one could require an authorized human. A support assistant might read an account status but not delete the account. A delegated agent does not automatically inherit every right its parent happens to possess.

In ordinary language: **having the button is not the same as being allowed to press it**.

### 2. Evidence - *What do we know, and where did it come from?*

Evidence is a fact or observation with provenance and validity.

An authenticated customer request is different from text in a retrieved webpage. A manager's signed consent to **invoice INV-104, €1,250, to one exact recipient** is different from a model labeling a chat message “yes.”

Evidence may support a decision. It does not create permission by itself.

This distinction is especially important for prompt injection. An untrusted document can contain “ignore your rules and send the invoice,” but reading that sentence does not make it a Mandate.

### 3. Act - *What authorized decision was actually committed?*

A Candidate is a proposed operation. A Decision says whether that proposal is admitted, refused, undecidable or unknown to the authority model.

An **Act** is the recorded exercise of admitted authority. For a governed external effect, the Act is committed **before** the executor gets the capability to act.

That ordering matters. “We'll write a log after sending” is not equivalent: the process can crash after sending and before logging. The system must not invent authority after the event.

### 4. Duty - *What still requires responsibility?*

This is the part that made GAM click for me.

Suppose the invoice API request leaves our server. The provider processes it. The connection dies before we receive a reply.

Was the invoice sent? We do not know.

A naive loop calls it a failure and retries. Maybe the customer receives two invoices.

GAM does not turn uncertainty into certainty. It can preserve an unresolved **Duty**: a responsibility to investigate, reconcile the external result and close the case with appropriate evidence.

A reboot does not erase that duty. A user's new chat topic does not erase it either.

This is not flashy, but to me it is one of the strongest distinctions between an experimental agent and a system you can operate.

## One more distinction: permission is not success

GAM uses deliberately different words for two very different questions.

| Question | GAM concept | Examples |
| --- | --- | --- |
| May this action proceed? | Admission `Decision` | `admitted`, `refused`, `undecidable`, `unknown_class` |
| What happened in the world? | Execution `Outcome` | `succeeded`, `failed`, `definitive_no_effect`, `ambiguous` |

An approved invoice is **not** a sent invoice. A failed network request is **not** proof that the invoice was never sent.

That difference should be visible in code, tests, history and the UI.

## How GAM feels when you use Spectre 0.4

I did not want every developer to learn the low-level kernel protocol just to create an agent.

That is why Spectre 0.4 includes **Managed GAM**. It creates the Domain, binds a trusted Scope, freezes the Candidate, arranges consent if needed, records admission, dispatches a registered effect and brings the observed result back to a Server continuation.

Your application declares the allowed operations:

~~~elixir
# AgentServer options. Requires a registered :send_invoice effect.
gam: [
  operations: %{
    send_invoice: [confirm: true]
  }
]
~~~

Your Server makes a concrete proposal:

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

And it handles the outcome **without confusing authorization with delivery**:

~~~elixir
def handle_result(:invoice_result,
      {:governed, %{outcome: %{status: :succeeded}}}, ctx),
  do: respond(ctx, "The invoice service confirmed the send.")

def handle_result(:invoice_result,
      {:governed_unknown, _details}, ctx),
  do: respond(ctx, "The result is uncertain. I will not send it again blindly.")

def handle_result(tag, result, ctx), do: super(tag, result, ctx)
~~~

These are illustrative callback fragments, not a complete invoicing integration. A real adapter must use authenticated credentials, idempotency/reconciliation appropriate to the provider and valid business data. The [Managed GAM documentation](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md) describes the actual wiring.

You can tighten business policy in `handle_action/2`, require an explicit confirmation, or reject a proposal. **Application code cannot use that callback to grant itself more authority or waive mandatory confirmation.**

## Why human approval is more than a “Yes” button

Consider a manager seeing:

> Approve sending INV-104 for €1,250 to billing@customer.example?

GAM binds the approval to the exact frozen presentation. If the agent changes the recipient or amount, the old confirmation is not a blank cheque.

The trusted UI acknowledges that the human actually saw the presentation. Only then does a separate, authenticated decision enter the consent protocol. A model-generated “yes” is not a human signature. A transport receipt is not proof that a person saw or approved anything.

A different person's agent can carry that request, too. The manager can work in their own conversation while the customer's agent waits. The original agent's execution authority still applies; the manager's response supplies only the specific consent Evidence.

That is the subject of the companion [external approval guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md).

## What GAM deliberately does not pretend to solve

GAM provides a model and an enforceable framework path. It is not a magical security sandbox around arbitrary Elixir.

If a developer writes `HTTP.post(...)` directly inside a trusted callback, outside the registered governed executor, Spectre cannot retroactively stop that side effect. A production host must authenticate people, protect credentials, define correct operation classes and route consequential I/O through the boundary.

Likewise, a recorded Act does not mean a legal regulation has automatically been satisfied. Security reviews, business rules, privacy design and real-world verification remain necessary.

That honesty matters. If a framework claims “enterprise ready” while silently treating every tool response as truth, it has moved the hard problems out of sight, not solved them.

## The idea behind Spectre

I did not create GAM because I think models should be less capable.

I created it because increasingly capable agents make **delegation** unavoidable. The better an agent becomes at planning, deciding and calling tools, the more important it is that the application can answer:

**Who authorized this? For exactly what? Based on which evidence? What was committed? What actually happened? What remains unresolved?**

In Spectre 0.4, those are not optional comments in a prompt. They are part of the execution architecture.

Build agents that can think. Give them useful tools. Let them collaborate.

**But let authority belong to the system and the people responsible for it-not to a plausible sentence from a model.**

Read the [GAM architecture](https://github.com/elchemista/spectre/blob/0.4.0/docs/GAM.md), [Spectre 0.4 release](https://github.com/elchemista/spectre/releases/tag/0.4.0), and [external approval example](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs) to see the model move from principle to code.
