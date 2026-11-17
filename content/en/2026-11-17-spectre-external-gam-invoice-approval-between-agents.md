---
title: "One Agent Wants to Send an Invoice. Another Asks the Boss."
slug: "spectre-external-gam-invoice-approval-between-agents"
lang: "en"
status: draft
date: 2026-11-17
updated: 2026-11-17
category: "Software Development"
tags: ["Elixir", "OTP", "AI agents", "Spectre", "Spectre 0.4", "GAM", "external approval", "multi-agent", "invoices", "spectre_pulse"]
seo_title: "Spectre 0.4: External GAM Approval Between AI Agents"
seo_description: "A practical Spectre 0.4 example: a customer agent proposes an invoice, an admin's personal agent requests consent, and GAM controls execution."
cover_alt: "A customer agent requests invoice delivery and an administrator's personal agent obtains signed human consent before the effect executes"
---

Imagine a company where an AI assistant does the everyday work.

A customer asks for an invoice. The assistant finds the record, prepares the message and knows which tool can send it.

It is ready.

Except it is **not allowed to send invoices without approval**.

The obvious solution sounds simple: the agent asks the administrator “Can I?” But the administrator has their own assistant, their own chat, perhaps even a different server. And the customer agent cannot just trust any incoming “yes.”

Here is the workflow I wanted Spectre to support:

~~~text
 Customer / employee
      |
      v
 CUSTOMER AGENT                      ADMIN'S PERSONAL AGENT
 "Send INV-104"                            "Approval requested"
      |                                           |
      v                                           v
 Propose exact invoice -- approval.request --> Human sees exact invoice
      |                                           |
      |                              approval.presented (signed)
      |                                           |
      |                              Human confirms or rejects
      |                                           |
      | <----- approval.decision (signed) --------|
      v
 Customer's GAM checks:
 - Is this operation in the mandate?
 - Is the request still the exact frozen one?
 - Was the presentation actually shown?
 - Is the authenticated consent valid and unexpired?
      |
      v
 Committed Act -> registered invoice executor -> observed Outcome
~~~

Notice the architecture: **the administrator's agent does not acquire the customer's execution powers**. It carries the request to a human and returns constrained consent Evidence. The customer's original GAM Domain still decides whether the operation may happen.

That is not just “agent-to-agent chat.” It is authority-preserving delegation.

## First, the three rules

Before code, three distinctions prevent most design mistakes.

**The agent proposes; it does not authorize itself.** An intent label such as `:send_invoice` is only recognition.

**The admin's assistant transports the request; the admin decides.** The LLM on the admin side must not call the approval APIs. The trusted consumer/UI renders the exact request and an independently authenticated human chooses.

**Delivery is not consent, and consent is not execution success.** A transport says “message queued.” A UI says “presentation shown.” A human says “approve.” The customer's GAM admits an Act. The invoice provider reports an Outcome. They are five separate events.

Spectre 0.4 models these distinctions through [External human approval](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md). The core example actually runs **two AgentServers with independent Domains**, without requiring Pulse or an LLM.

## Create the operation: a simulated invoice sender

To make the example understandable, we will *simulate* invoice delivery. No real email or invoice is sent. A production integration replaces the effect adapter with a registered, authenticated provider adapter.

The contract is real; the external side effect is a fixture.

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

We have deliberately named the governed operation `:invoice_send`. It is registered through a Stack installation; it is not an arbitrary function name the model can execute.

The effect descriptor identifies its adapter and records that the side effect is non-idempotent. That matters when an external response becomes uncertain.

## Create the customer agent and its Server

This example uses a deterministic route so we can inspect the governance protocol without wondering what a model guessed. Swap in embedding or LLM classification later if you need more flexible language understanding.

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

The code is intentionally small. The customer Agent recognizes the request. The Server proposes the **concrete, fixed** operation. GAM handles admission, not the model.

The recipient's personal Agent can be simple:

~~~elixir
defmodule InvoiceDemo.AdminServer do
  use Spectre.Server

  def handle_flow(:unmatched, _input, ctx),
    do: respond(ctx, "Your approval requests arrive through the trusted UI.")
end

defmodule InvoiceDemo.AdminAgent do
  use Spectre.Agent,
    stack: InvoiceDemo.Stack,
    server: InvoiceDemo.AdminServer
end
~~~

This is a real second AgentServer, not a second personality stuffed into one prompt.

## Connect both agents through a transport

The core approval protocol does **not** depend on Spectre Pulse. A transport must implement `Spectre.Server.GAM.Managed.Approval.send_message/2`.

For a local demo, a mailbox is enough:

~~~elixir
defmodule InvoiceDemo.Transport do
  @behaviour Spectre.Server.GAM.Managed.Approval

  def send_message(message, opts) do
    send(Keyword.fetch!(opts, :receiver), {:wire, message})
    {:ok, :queued}
  end
end
~~~

That `:queued` receipt is technical delivery information. It is *not* evidence that the admin saw the screen or agreed.

For production across services or nodes, [spectre_pulse](https://github.com/elchemista/spectre_pulse) can carry the same authenticated protocol. The transport implementation changes; the customer's GAM law does not.

## Start two independent Domains and nominate the real human

Below is the essential startup wiring. The example assumes a host process is acting as the trusted consumer; identities and keys shown here are **test fixtures**, not an authentication solution.

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
          message: "Send invoice INV-104 for EUR 1,250 to billing@example.test?",
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

Even though these agents can use the same transport, they have **different GAM Domains**. The human's public key and approved identity are pinned by the requesting host; a random message from another agent does not count.

The `mandate_ref` here identifies authorization established by the trusted host for approval. It is not a transferable superpower or a remotely imported execution mandate.

## Show, acknowledge and decide — in that order

Now the customer asks to send the invoice:

~~~elixir
{:ok, _interaction} =
  Spectre.Server.input(customer, "send invoice INV-104")
~~~

The transport sends an `approval.request`. In the local fixture we hand the message to the second Server via its authenticated ingress:

~~~elixir
request_id =
  receive do
    {:wire, %{"type" => "approval.request"} = request} ->
      :ok = Spectre.Server.receive_approval(admin, request)
  
      receive do
        {Spectre.Server, ^admin, {:approval_request, ^request}} ->
          # Trusted UI: display the literal frozen request and expiry.
          IO.puts(request["rendered_payload"])
      end
  
      # ONLY after real rendering:
      :ok = Spectre.Server.approval_presented(admin, request["id"])
    request["id"]
  end
~~~

The local demo must now return the signed `approval.presented` acknowledgement to the customer and wait for the customer's consent-pending state:

~~~elixir
receive do
  {:wire, %{"type" => "approval.presented"} = acknowledgement} ->
    :ok = Spectre.Server.receive_approval(customer, acknowledgement)
end

receive do
  {Spectre.Server, ^customer, {:pending, _, _}} -> :ok
end
~~~

**Only after an actual human choice** does the trusted UI call:

~~~elixir
# Called by trusted UI code, never by the model:
:ok = Spectre.Server.approval_decide(admin, request_id, :confirm)
# Or:
# :ok = Spectre.Server.approval_decide(admin, request_id, :reject)
~~~

The signed `approval.decision` is delivered back to the customer via `Spectre.Server.receive_approval/2`:

~~~elixir
receive do
  {:wire, %{"type" => "approval.decision"} = signed_decision} ->
    {:ok, _} = Spectre.Server.receive_approval(customer, signed_decision)
end
~~~

 For an approved request, its Domain verifies authority, request digest, binding, showing, signature and expiry. It admits and commits the Act before the registered invoice effect can run.

For rejection, the original continuation receives `{:consent, :rejected}`; the invoice effect does not run.

The wire protocol has four message kinds: `approval.request`, `approval.presented`, `approval.decision` and `approval.cancelled`. They are not interchangeable. A forged, stale or replayed decision cannot authorize a different invoice.

For a complete **invoice-specific** confirm-and-reject walkthrough, see the [companion demo fixture](https://github.com/elchemista/spectre_blog/blob/master/examples/spectre_0_4_external_invoice_approval.exs). With the Spectre and spectre_blog repositories side by side, run from the Spectre 0.4 checkout:

~~~sh
mix run ../spectre_blog/examples/spectre_0_4_external_invoice_approval.exs
~~~

The fixture simulates invoice delivery and exercises signed consent, refusal and replay checks; it is adapted from the official core example. You can also run the **original, tested core fixture**:

~~~sh
mix run docs/examples/external_approval.exs
~~~

That repository example uses a simulated browser operation rather than an invoice, but its two-AgentServer transport, Ed25519 signatures, separate Domains, rendering acknowledgement and replay checks are exercised together. Our invoice code above adapts that same contract; it is a guided integration example, not a claim that a real billing provider was tested.

## What happens when the administrator is offline?

The requester waits; it does not silently promote itself to approver.

The recipient can keep a durable approval inbox, fetch entries with `Spectre.Server.approval/2` and page them with `approval_inbox/2`. Requests can be delivered again, so the UI deduplicates by full reference. A technical transport acknowledgment does not prove that a person viewed anything.

Expiry is binding. A restart restores the customer's wait **suspended**, requiring a fresh presentation before continuing. A lost delivery or unknown database write remains unknown rather than becoming imaginary consent.

And an approval does not add rights the customer's original Mandate lacked.

That is the property I care about most: **another agent may help you decide, but it cannot quietly rewrite who is allowed to act**.

## Turning this demo into a production workflow

You will need a real authenticated human login, stable signing keys, an authorized approver registry, secure message ingress and a transport appropriate to the deployment. Add durable storage for coordination and GAM history—`spectre_ledger`/PostgreSQL or your own `Spectre.Server.Store`—when restart continuity matters.

The production effect adapter needs actual invoice-provider credentials, a durable invoice identifier, provider-specific deduplication and reconciliation of ambiguous outcomes. Keep credentials out of prompts and model output. Allow only registered operations through the governed path; direct HTTP calls from an ordinary Server callback bypass this guarantee.

The [external approvals guide](https://github.com/elchemista/spectre/blob/0.4.0/docs/EXTERNAL_APPROVALS.md), [source example](https://github.com/elchemista/spectre/blob/0.4.0/docs/examples/external_approval.exs), [Managed GAM](https://github.com/elchemista/spectre/blob/0.4.0/docs/MANAGED_GAM.md), and [Pulse adapter](https://github.com/elchemista/spectre_pulse) describe the contracts and failure cases.

## Why I find this exciting

Picture the same workflow for a refund, production deployment, contract signature, expense, customer-data export or high-value purchase.

The specialist agent can keep working. The manager does not need to stare at its logs. The personal assistant presents the question in the manager's own space. And the originating system keeps the authoritative record of what was actually permitted and what happened.

This is the difference between *agents talking to one another* and *agents cooperating inside a system with accountable authority*.

**Spectre 0.4 is not just about making an agent do more. It is about making delegation something you can finally trust enough to build on.**
